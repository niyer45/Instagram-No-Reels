import UIKit
import Combine

/// The shell's root: one PageNavigationController per tab, retained for the whole session so
/// every tab keeps its page and scroll position, plus the native Instagram tab bar.
///
/// It is a custom container rather than UITabBarController: since iOS 26 the system tab bar is a
/// floating Liquid Glass bar that cannot be made opaque with a hairline, and hiding it changes
/// child safe areas differently across iOS 17–27 (docs/DIRECTION.md §3.1).
@MainActor
final class RootTabBarController: UIViewController {
    private let environment: AppEnvironment
    private let tabBar = InstagramTabBar()
    private(set) var navigations: [TabItem: PageNavigationController] = [:]
    private(set) var selectedTab: TabItem = .home
    private var cancellables = Set<AnyCancellable>()
    /// Fires once when Home (or the login page) is ready to reveal behind the splash.
    var onLaunchReady: (() -> Void)?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
        environment.router.shell = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var selectedNavigation: PageNavigationController {
        if let navigation = navigations[selectedTab] { return navigation }
        let navigation = makeNavigation(selectedTab)
        navigations[selectedTab] = navigation
        return navigation
    }

    var homePage: HomePageViewController? { navigations[.home]?.viewControllers.first as? HomePageViewController }

    /// The view controller new modals present from.
    var topmostPresenter: UIViewController {
        var top: UIViewController = self
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabBar.onTap = { [weak self] tab in self?.tapped(tab) }
        view.addSubview(tabBar)
        environment.theme.changes.sink { [weak self] in self?.applyTheme() }.store(in: &cancellables)
        environment.account.$avatar.sink { [weak self] image in self?.tabBar.setAvatar(image) }.store(in: &cancellables)
        show(.home)
        #if DEBUG
        if let tab = DebugLaunchOptions.tab { show(tab) }
        if let url = DebugLaunchOptions.openURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.environment.router.open(url, from: nil) }
        }
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bottom = view.safeAreaInsets.bottom
        tabBar.frame = CGRect(x: 0, y: view.bounds.height - InstagramTabBar.height - bottom, width: view.bounds.width, height: InstagramTabBar.height + bottom)
        navigations[selectedTab]?.view.frame = view.bounds
    }

    override var childForStatusBarStyle: UIViewController? { navigations[selectedTab] }
    override var childForStatusBarHidden: UIViewController? { navigations[selectedTab] }

    private func applyTheme() {
        tabBar.apply(background: environment.theme.background, hairline: environment.theme.hairline)
        view.backgroundColor = environment.theme.background
        view.window?.overrideUserInterfaceStyle = environment.theme.interfaceStyle
    }

    // MARK: Selection

    private func tapped(_ tab: TabItem) {
        if tab == selectedTab { reselect(tab); return }
        Haptics.selection()
        show(tab)
    }

    func select(_ tab: TabItem, popToRoot: Bool) {
        if tab != selectedTab { show(tab) }
        if popToRoot { navigations[tab]?.popToRootViewController(animated: true) }
    }

    private func show(_ tab: TabItem) {
        let previous = navigations[selectedTab]
        selectedTab = tab
        let next = selectedNavigation
        if previous !== next {
            previous?.willMove(toParent: nil)
            previous?.view.removeFromSuperview()
            previous?.removeFromParent()
        }
        if next.parent !== self {
            addChild(next)
            next.additionalSafeAreaInsets.bottom = InstagramTabBar.height
            next.view.frame = view.bounds
            view.insertSubview(next.view, belowSubview: tabBar)
            next.didMove(toParent: self)
        }
        tabBar.select(tab)
        setNeedsStatusBarAppearanceUpdate()
    }

    /// Tapping the selected tab: scroll to top; at the top, pop to root; at the root's top,
    /// Home, Notifications and Profile reload (Search does nothing more).
    private func reselect(_ tab: TabItem) {
        let navigation = selectedNavigation
        if let page = navigation.topViewController as? WebPageViewController, page.scrollToTop() { return }
        if navigation.viewControllers.count > 1 { navigation.popToRootViewController(animated: true); return }
        guard tab != .search, let root = navigation.viewControllers.first as? WebPageViewController else { return }
        Haptics.selection()
        root.reload()
    }

    // MARK: Session changes

    private func makeNavigation(_ tab: TabItem) -> PageNavigationController {
        let root = environment.router.makePage(tab.rootURL(account: environment.account), placement: .tabRoot(tab))
        if let home = root as? HomePageViewController {
            home.onLaunchReady = { [weak self] in self?.launchReady() }
        }
        return PageNavigationController(tab: tab, root: root)
    }

    /// A Home-tab root that is not the feed (e.g. the login page that replaced it) also ends the splash.
    func pageDidBecomeReady(_ page: WebPageViewController) {
        guard !(page is HomePageViewController), page.placement == .tabRoot(.home) else { return }
        launchReady()
    }

    private func launchReady() {
        onLaunchReady?()
        onLaunchReady = nil
    }

    /// Rebuilds every tab from its root route (after signing in or out).
    func resetTabs() {
        presentedViewController?.dismiss(animated: false)
        for navigation in navigations.values {
            navigation.willMove(toParent: nil)
            navigation.view.removeFromSuperview()
            navigation.removeFromParent()
        }
        navigations = [:]
        environment.filterStatus.reset()
        show(.home)
    }

    func reloadHome() {
        select(.home, popToRoot: true)
        homePage?.reload()
    }
}
