import UIKit

/// A tab's navigation stack. The system bar stays hidden (pages draw native headers). Back is the interactive
/// screen-edge pop only: iOS 26's full-width content swipe is turned off because it would fight horizontal carousels
/// and the Stories tray inside web pages. Pages that are full-height (message threads) hide the shell's tab bar while
/// they are in the stack, and the bar leaves and returns with the page that slides, like `hidesBottomBarWhenPushed`.
final class PageNavigationController: UINavigationController, UIGestureRecognizerDelegate, UINavigationControllerDelegate {
    let tabItem: TabItem
    private var tabBarHidden = false
    /// The tab bar as it looked when it was hidden, carried in by the page it returns with.
    private var tabBarSnapshot: UIView?

    init(tab: TabItem, root: UIViewController) {
        self.tabItem = tab
        super.init(rootViewController: root)
        setNavigationBarHidden(true, animated: false)
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        if #available(iOS 26.0, *) { interactiveContentPopGestureRecognizer?.isEnabled = false }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The tab bar is shared by every tab; this stack decides it while it is the visible one.
        setTabBar(hidden: hidesTabBar(through: topViewController))
    }

    override var childForStatusBarStyle: UIViewController? { topViewController }
    override var childForStatusBarHidden: UIViewController? { topViewController }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        // Pages shown while the tab bar is hidden lay out without its space from their first frame.
        if Self.hidesTabBar(viewController) || hidesTabBar(through: topViewController) {
            viewController.additionalSafeAreaInsets.bottom = -additionalSafeAreaInsets.bottom
        }
        super.pushViewController(viewController, animated: animated)
    }

    // MARK: Gestures

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1 && transitionCoordinator == nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        // The edge swipe wins over the web view's own pans (it fails at once for touches away from the edge).
        gestureRecognizer === interactivePopGestureRecognizer
    }

    // MARK: Tab bar visibility

    static func hidesTabBar(_ controller: UIViewController) -> Bool {
        guard let page = controller as? WebPageViewController, page.placement == .pushed else { return false }
        return page.route.hidesTabBar
    }

    private func hidesTabBar(through controller: UIViewController?) -> Bool {
        guard let controller, let index = viewControllers.firstIndex(of: controller) else { return false }
        return viewControllers[...index].contains(where: Self.hidesTabBar)
    }

    /// The shell's tab bar (drawn by the root container above every tab).
    private var tabBar: InstagramTabBar? {
        parent?.view.subviews.lazy.compactMap { $0 as? InstagramTabBar }.first
    }

    private func setTabBar(hidden: Bool) {
        tabBarHidden = hidden
        guard let bar = tabBar else { return }
        bar.alpha = hidden ? 0 : 1
        bar.isUserInteractionEnabled = !hidden
        bar.accessibilityElementsHidden = hidden
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        let hide = hidesTabBar(through: viewController)
        guard hide != tabBarHidden, let bar = tabBar else { return }
        guard animated, let coordinator = transitionCoordinator,
              let from = coordinator.viewController(forKey: .from), let to = coordinator.viewController(forKey: .to) else {
            setTabBar(hidden: hide)
            return
        }
        // The bar travels inside the page that slides: out with the page being covered (push), back in with the page
        // being uncovered (pop). The real bar switches when the transition completes, or stays if a swipe is cancelled.
        let carrier = hide ? from : to
        let snapshot = hide ? bar.snapshotView(afterScreenUpdates: false) : tabBarSnapshot
        if hide { tabBarSnapshot = snapshot }
        if let snapshot {
            snapshot.frame = bar.frame
            carrier.view.addSubview(snapshot)
        }
        if hide { setTabBar(hidden: true) }
        coordinator.animate(alongsideTransition: { _ in
            if snapshot == nil, !hide { bar.alpha = 1 }
        }, completion: { [weak self] context in
            snapshot?.removeFromSuperview()
            guard let self else { return }
            self.setTabBar(hidden: context.isCancelled ? !hide : hide)
        })
    }
}
