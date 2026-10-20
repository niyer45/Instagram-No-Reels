import UIKit

/// A tab's navigation stack. The system bar stays hidden (pages draw native headers) while
/// the interactive swipe-back gesture keeps working.
final class PageNavigationController: UINavigationController, UIGestureRecognizerDelegate {
    let tabItem: TabItem

    init(tab: TabItem, root: UIViewController) {
        self.tabItem = tab
        super.init(rootViewController: root)
        setNavigationBarHidden(true, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    override var childForStatusBarStyle: UIViewController? { topViewController }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1 && transitionCoordinator == nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        // The edge swipe wins over the web view's own pans.
        gestureRecognizer === interactivePopGestureRecognizer
    }
}
