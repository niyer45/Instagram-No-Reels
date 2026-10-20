import UIKit
import SwiftUI
import Combine
import SafariServices

/// Performs navigations natively: URL -> Route -> Presentation (push, full-screen modal,
/// tab switch, root replacement for login, or block). Every page hands off here when
/// Bridge.js or the navigation delegate decides a navigation leaves the current page.
/// Links outside Instagram open in Safari View Controller; Reels and app redirects are dropped silently.
@MainActor
final class Router {
    weak var environment: AppEnvironment? { didSet { observeSession() } }
    weak var shell: RootTabBarController?
    private var sessionObservation: AnyCancellable?
    private var lastSession: AccountStore.Session?

    func open(_ url: URL, from page: WebPageViewController?) {
        guard RouteDecision.isOfficial(url) else { openExternal(url, userInitiated: false, from: page); return }
        let policy = InstagramNavigation.decision(for: url, following: [])
        guard policy == .allow else { report(policy); return }
        guard let shell, let environment else { return }
        let route = Route(url: url)
        let presentation = Presentation(kind: route.kind)
        if presentation == .block { report(.blockReels); return }

        // A tab root on Instagram's login page opens where Instagram goes after signing in in place. Whether that
        // means a session is decided by what the page then shows (SessionEvidence), never by this navigation; legal
        // and help links from the login page push normally.
        if let page, case .tabRoot = page.placement, page.route.kind == .login, SessionEvidence.opensInPlaceFromLogin(route) {
            page.load(url)
            return
        }
        // From a full-screen page: Home (closing a viewer) just dismisses; anything else
        // dismisses and continues from the selected tab.
        if let page, page.placement == .modal, presentation != .fullScreen {
            page.dismiss(animated: true) { [weak self] in
                if route.kind != .home { self?.open(url, from: nil) }
            }
            return
        }
        switch presentation {
        case .block:
            report(.blockReels)
        case .homeTab:
            shell.select(.home, popToRoot: true)
        case .searchTab:
            shell.select(.search, popToRoot: true)
        case .push:
            let navigation = (page?.navigationController as? PageNavigationController) ?? shell.selectedNavigation
            navigation.pushViewController(makePage(url, placement: .pushed, environment: environment), animated: true)
            Haptics.push()
        case .fullScreen:
            let modal = ModalContainerController(content: makePage(url, placement: .modal, environment: environment))
            shell.topmostPresenter.present(modal, animated: true)
        case .replaceRoot:
            environment.account.markSignedOut()
            let navigation = (page?.navigationController as? PageNavigationController) ?? shell.selectedNavigation
            navigation.setViewControllers([makePage(url, placement: .tabRoot(navigation.tabItem), environment: environment)], animated: false)
        }
    }

    /// Builds the page for `url`. Callers pass the environment they already hold, so there is no
    /// state in which a page cannot be made (the Router's own reference is weak).
    /// Tab roots get their tab's page class (Home only for the feed itself), also when a root is replaced
    /// (login) or rebuilt after signing in, so Search and Profile keep their own behaviour and header.
    func makePage(_ url: URL?, placement: WebPageViewController.Placement, environment: AppEnvironment) -> WebPageViewController {
        switch placement {
        case .tabRoot(.home) where url.map({ Route(url: $0).kind }) == .home:
            return HomePageViewController(environment: environment, url: url)
        case .tabRoot(.search):
            return SearchPageViewController(environment: environment, url: url, placement: placement)
        case .tabRoot(.profile):
            return ProfilePageViewController(environment: environment, url: url, placement: placement)
        default:
            return WebPageViewController(environment: environment, url: url, placement: placement)
        }
    }

    // MARK: External links

    /// Opens a non-Instagram URL like the native app: tapped web links in Safari View Controller over the current
    /// page, mail and phone links in the system, Instagram's link shim unwrapped; everything else is dropped silently.
    func openExternal(_ url: URL, userInitiated: Bool, from page: WebPageViewController?) {
        switch ExternalLink.decide(url, userInitiated: userInitiated) {
        case .safari(let target):
            guard let shell else { return }
            let presenter = shell.topmostPresenter
            if presenter is SFSafariViewController { return }
            if page?.isLoginContent == true, let host = target.host?.lowercased(), ["facebook.com", "fb.com", "meta.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                // A Facebook sign-in in Safari would not sign this app in.
                alert("Log in with your Instagram username and password here. Signing in with Facebook isn’t available in this app.")
                return
            }
            let configuration = SFSafariViewController.Configuration()
            configuration.entersReaderIfAvailable = false
            let safari = SFSafariViewController(url: target, configuration: configuration)
            safari.dismissButtonStyle = .close
            presenter.present(safari, animated: true)
        case .system(let target):
            UIApplication.shared.open(target)
        case .instagram(let target):
            open(target, from: page)
        case .ignore:
            dropped("external")
        }
    }

    // MARK: Session

    /// A page reported `ready`; a ready signed-in kind is evidence of a session (legal/about/lite pages never are).
    func page(_ page: WebPageViewController, didBecomeReady kind: RouteKind) {
        guard let environment, SessionEvidence.signsIn(ready: kind, route: page.route), !page.isLoginContent else { return }
        environment.account.markSignedIn()
    }

    private func observeSession() {
        sessionObservation = environment?.account.$session.sink { [weak self] session in
            // Use the emitted value: @Published fires before the store's property changes.
            guard let self else { return }
            let previous = self.lastSession
            self.lastSession = session
            guard previous == .signedOut, session == .signedIn else { return }
            // Not from inside the bridge callback that produced the evidence: that page may be rebuilt.
            DispatchQueue.main.async { [weak self] in self?.rebuildTabsAfterSignIn() }
        }
    }

    /// Replaces the roots of tabs still showing a login page (or another tab's page) with their own root pages.
    /// Tabs already showing their own content keep their stacks, so a stray signed-out signal costs nothing.
    private func rebuildTabsAfterSignIn() {
        guard let shell, let environment else { return }
        for (tab, navigation) in shell.navigations {
            guard let root = navigation.viewControllers.first as? WebPageViewController else { continue }
            let homeIsPlain = tab == .home && !(root is HomePageViewController)
            guard homeIsPlain || SessionEvidence.rebuildsAfterSignIn(root: root.route, isLoginContent: root.isLoginContent, tabKind: Self.rootKind(of: tab)) else { continue }
            navigation.setViewControllers([makePage(tab.rootURL(account: environment.account), placement: .tabRoot(tab), environment: environment)], animated: false)
        }
    }

    private static func rootKind(of tab: TabItem) -> RouteKind {
        switch tab {
        case .home: return .home
        case .search: return .search
        case .activity: return .activity
        case .profile: return .profile
        }
    }

    // MARK: Content filters

    /// Shows the Content filters sheet.
    func presentSettings() {
        guard let environment, let shell else { return }
        let presenter = shell.topmostPresenter
        if presenter is UIHostingController<ContentFilterSettingsView> { return }
        weak var sheet: UIViewController?
        let actions = ContentFilterSettingsView.Actions(
            reload: { [weak shell] in sheet?.dismiss(animated: true); shell?.reloadHome() },
            importFile: { [weak self] url in
                do { try environment.importFollowing(from: url) } catch { self?.alert(error.localizedDescription) }
            },
            clearImport: { environment.clearFollowing() },
            signIn: { [weak self] in
                sheet?.dismiss(animated: true)
                if let url = URL(string: "https://www.instagram.com/accounts/login/") {
                    self?.shell?.select(.home, popToRoot: true)
                    self?.open(url, from: nil)
                }
            },
            signOut: { [weak shell] in
                sheet?.dismiss(animated: true)
                environment.signOut { shell?.resetTabs() }
            },
            dismiss: { sheet?.dismiss(animated: true) })
        let controller = UIHostingController(rootView: ContentFilterSettingsView(status: environment.filterStatus, following: environment.following, actions: actions))
        sheet = controller
        presenter.present(controller, animated: true)
    }

    /// Blocked destinations are dropped silently, like the native app (which never shows Reels or app redirects).
    func report(_ decision: NavigationDecision) {
        switch decision {
        case .allow: return
        case .blockReels: dropped("reels")
        case .blockExternal, .blockUnknown: dropped("external")
        }
    }

    /// DEBUG event log only: an enumerated reason, never the URL.
    private func dropped(_ reason: String) {
        #if DEBUG
        Diagnostics.record("navigation-dropped", labels: ["reason": reason])
        #endif
    }

    func alert(_ message: String) {
        guard let shell else { return }
        let controller = UIAlertController(title: "Instagram", message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "OK", style: .default))
        shell.topmostPresenter.present(controller, animated: true)
    }
}
