import UIKit
import WebKit

/// Full-screen native modal that hosts the Stories tray web view while Instagram's story
/// viewer is open, so opening a story is instant (same document) yet presented natively.
final class StoryViewerController: UIViewController {
    private let webView: WKWebView
    /// Asks the page to close the viewer (left-edge swipe); the page reports `storyViewer` closed.
    var onCloseRequest: (() -> Void)?

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
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if webView.superview === view { webView.frame = view.bounds }
    }

    override var prefersStatusBarHidden: Bool { true }

    @objc private func edgeClose(_ gesture: UIScreenEdgePanGestureRecognizer) {
        if gesture.state == .recognized { onCloseRequest?() }
    }
}
