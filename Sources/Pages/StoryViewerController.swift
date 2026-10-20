import UIKit
import WebKit

/// Content of the full-screen story viewer: hosts the Stories tray web view while Instagram's
/// story viewer is open, so opening a story is instant (same document). Home presents it inside
/// `ModalContainerController`, which hides the status bar and home indicator and owns the
/// downward swipe; its dismissal handler calls `requestClose()`. Instagram's own close control
/// and a left-edge swipe close it too; the page then reports `storyViewer` closed and Home
/// dismisses the container.
final class StoryViewerController: UIViewController {
    private let webView: WKWebView
    /// Asks the page to close the viewer; the page reports `storyViewer` closed.
    var onCloseRequest: (() -> Void)?
    private var closeRequested = false

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
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
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if webView.superview === view { webView.frame = view.bounds }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    /// Closes Instagram's viewer once (the downward swipe, the edge swipe).
    func requestClose() {
        guard !closeRequested else { return }
        closeRequested = true
        onCloseRequest?()
    }

    @objc private func edgeClose(_ gesture: UIScreenEdgePanGestureRecognizer) {
        if gesture.state == .recognized { requestClose() }
    }
}
