import UIKit

/// Full-screen modal container for Instagram's full-screen pages (stories, create, any future ones) and for native
/// full-screen content such as the story viewer. Presented over the current page (the page stays in the hierarchy,
/// so dismissing returns to it exactly as it was, without reloading), hides the status bar, and dismisses with a
/// downward swipe that follows the finger like the native app. Instagram's own close control dismisses through the
/// Router or the page (its route leaves the full-screen kind).
@MainActor
final class ModalContainerController: UIViewController, UIGestureRecognizerDelegate {
    let content: UIViewController
    /// Replaces the plain dismissal at the end of a downward swipe (e.g. to let the page close its viewer first).
    /// The container has already animated away when this runs; call `dismiss(animated: false)` when done.
    var dismissalHandler: ((ModalContainerController) -> Void)?

    private let backdrop = UIView()
    private let stage = UIView()
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
    private static let distanceToDismiss: CGFloat = 120
    private static let velocityToDismiss: CGFloat = 900

    init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        modalPresentationCapturesStatusBarAppearance = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        backdrop.backgroundColor = .black
        view.addSubview(backdrop)
        stage.clipsToBounds = true
        view.addSubview(stage)
        addChild(content)
        stage.addSubview(content.view)
        content.didMove(toParent: self)
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
        if stage.transform == .identity { stage.frame = view.bounds }
        content.view.frame = stage.bounds
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: Swipe down to dismiss

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan else { return true }
        let velocity = pan.velocity(in: view)
        // Downward and mostly vertical, and only when the content is not scrolled (it scrolls up first).
        return velocity.y > 0 && velocity.y > abs(velocity.x) * 1.5 && contentIsAtTop
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // The web view still sees the touch until the swipe is recognised; then its scrolling is cancelled.
        gestureRecognizer === pan && other is UIPanGestureRecognizer
    }

    private var contentIsAtTop: Bool {
        guard let scrollView = Self.firstScrollView(in: content.view) else { return true }
        return scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 1
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView, scrollView.isScrollEnabled { return scrollView }
        for child in view.subviews { if let found = firstScrollView(in: child) { return found } }
        return nil
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        let height = max(view.bounds.height, 1)
        let distance = max(gesture.translation(in: view).y, 0)
        switch gesture.state {
        case .began:
            if let scrollView = Self.firstScrollView(in: content.view) {
                scrollView.panGestureRecognizer.isEnabled = false
                scrollView.panGestureRecognizer.isEnabled = true
            }
        case .changed:
            let progress = min(distance / height, 1)
            stage.transform = CGAffineTransform(translationX: 0, y: distance).scaledBy(x: 1 - progress * 0.12, y: 1 - progress * 0.12)
            backdrop.alpha = 1 - progress
        case .ended:
            if distance > Self.distanceToDismiss || gesture.velocity(in: view).y > Self.velocityToDismiss {
                finishDismissal(from: distance, height: height)
            } else {
                restore()
            }
        case .cancelled, .failed:
            restore()
        default:
            break
        }
    }

    private func restore() {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            self.stage.transform = .identity
            self.backdrop.alpha = 1
        }
    }

    private func finishDismissal(from distance: CGFloat, height: CGFloat) {
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            self.stage.transform = CGAffineTransform(translationX: 0, y: height).scaledBy(x: 0.88, y: 0.88)
            self.stage.alpha = 0
            self.backdrop.alpha = 0
        } completion: { _ in
            if let handler = self.dismissalHandler { handler(self) } else { self.dismiss(animated: false) }
        }
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) {
            // Focus returns to the page underneath, which never left the hierarchy.
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            completion?()
        }
    }
}
