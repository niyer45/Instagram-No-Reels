import UIKit
import SwiftUI

/// Performs navigations natively: URL -> Route -> Presentation (push, full-screen modal,
/// tab switch, root replacement for login, or block). Every page hands off here when
/// Bridge.js or the navigation delegate decides a navigation leaves the current page.
@MainActor
final class Router {
    weak var environment: AppEnvironment?
    weak var shell: RootTabBarController?

    func open(_ url: URL, from page: WebPageViewController?) {
        let policy = InstagramNavigation.decision(for: url, following: [])
        guard policy == .allow else { report(policy); return }
        guard let shell, let environment else { return }
        let route = Route(url: url)
        let presentation = Presentation(kind: route.kind)

        // Leaving Instagram's login flow means the web session is now signed in.
        if let page, page.route.kind == .login, route.kind != .login, presentation != .block {
            environment.account.markSignedIn()
            shell.resetTabs()
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
            navigation.pushViewController(makePage(url, placement: .pushed), animated: true)
            Haptics.push()
        case .fullScreen:
            let modal = makePage(url, placement: .modal)
            modal.modalPresentationStyle = .fullScreen
            modal.modalTransitionStyle = .crossDissolve
            shell.topmostPresenter.present(modal, animated: true)
        case .replaceRoot:
            environment.account.markSignedOut()
            let navigation = (page?.navigationController as? PageNavigationController) ?? shell.selectedNavigation
            navigation.setViewControllers([makePage(url, placement: .tabRoot(navigation.tabItem))], animated: false)
        }
    }

    func makePage(_ url: URL?, placement: WebPageViewController.Placement) -> WebPageViewController {
        guard let environment else { fatalError("Router used without an environment") }
        if case .tabRoot(.home) = placement, url.map({ Route(url: $0).kind }) == .home {
            return HomePageViewController(environment: environment, url: url)
        }
        return WebPageViewController(environment: environment, url: url, placement: placement)
    }

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

    func report(_ decision: NavigationDecision) {
        switch decision {
        case .allow: return
        case .blockReels: alert("Reels are disabled.")
        case .blockExternal: alert("External links and app redirects are disabled. Sign in directly on Instagram’s login page.")
        case .blockUnknown: alert("This destination is not supported.")
        }
    }

    func alert(_ message: String) {
        guard let shell else { return }
        let controller = UIAlertController(title: "Instagram", message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "OK", style: .default))
        shell.topmostPresenter.present(controller, animated: true)
    }
}
