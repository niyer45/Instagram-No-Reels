import UIKit
import WebKit

/// Full-screen native modal that hosts the Stories tray web view while Instagram's story
/// viewer is open, so opening a story is instant (same document) yet presented natively with
/// the status bar hidden. Instagram's own close control, a downward swipe and a left-edge swipe
/// close it; the page then reports `storyViewer` closed and Home dismisses this controller.
final class StoryViewerController: UIViewController, UIGestureRecognizerDelegate {
    private let webView: WKWebView
    /// Asks the page to close the viewer; the page reports `storyViewer` closed.
    var onCloseRequest: (() -> Void)?
    private var closeRequested = false

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addSubview(webView)
        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeClose(_:)))
        edge.edges = .left
        view.addGestureRecognizer(edge)
        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swipeDown(_:)))
        swipe.delegate = self
        swipe.cancelsTouchesInView = false
        view.addGestureRecognizer(swipe)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if webView.superview === view {
            webView.bounds = CGRect(origin: .zero, size: view.bounds.size)
            webView.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // The web view returns to the tray, which lays it out by frame.
        webView.transform = .identity
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    private func requestClose() {
        guard !closeRequested else { return }
        closeRequested = true
        onCloseRequest?()
    }

    @objc private func edgeClose(_ gesture: UIScreenEdgePanGestureRecognizer) {
        if gesture.state == .recognized { requestClose() }
    }

    // MARK: Swipe down to close

    /// The viewer follows the finger down (alpha and transform only) and closes past a distance
    /// or a fling; otherwise it springs back. Instagram's own taps and horizontal swipes still work.
    @objc private func swipeDown(_ pan: UIPanGestureRecognizer) {
        guard webView.superview === view else { return }
        let dy = max(pan.translation(in: view).y, 0)
        switch pan.state {
        case .changed:
            let progress = min(dy / max(view.bounds.height, 1), 1)
            webView.transform = CGAffineTransform(translationX: 0, y: dy).scaledBy(x: 1 - progress * 0.15, y: 1 - progress * 0.15)
        case .ended:
            if dy > 120 || pan.velocity(in: view).y > 900 {
                requestClose()
            } else {
                springBack()
            }
        case .cancelled, .failed:
            springBack()
        default:
            break
        }
    }

    private func springBack() {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            self.webView.transform = .identity
        }
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let pan = gesture as? UIPanGestureRecognizer, !(gesture is UIScreenEdgePanGestureRecognizer) else { return true }
        let velocity = pan.velocity(in: view)
        return velocity.y > 0 && velocity.y > abs(velocity.x) * 1.5
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
