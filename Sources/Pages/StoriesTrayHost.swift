import UIKit
import WebKit

/// Events from the Stories tray web view to the Home page.
@MainActor
protocol StoriesTrayHostDelegate: AnyObject {
    func trayDidMeasure(height: CGFloat, items: Int)
    func trayStoryViewer(open: Bool)
    func trayNavigate(to url: URL)
    func trayDidCapture(wordmark: WordmarkShape)
}

/// Hosts the dedicated Stories web view as a native component of the Home layout. The web
/// view keeps a full viewport (stable Instagram layout) and the host clips it to the tray's
/// measured height; it lives inside the feed's scroll view so it scrolls with the posts.
@MainActor
final class StoriesTrayHost: UIView, WebBridgeReceiver, WKNavigationDelegate {
    static let defaultHeight: CGFloat = 106
    private static let homeURL = URL(string: "https://www.instagram.com/")

    let webView: WKWebView
    private let placeholder = TrayPlaceholderView()
    private weak var delegate: StoriesTrayHostDelegate?
    private let environment: AppEnvironment
    /// Height given to the tray web view (the feed's viewport height).
    var viewportHeight: CGFloat = 800 { didSet { setNeedsLayout() } }
    private(set) var isMeasured = false

    init(environment: AppEnvironment, delegate: StoriesTrayHostDelegate) {
        self.environment = environment
        self.delegate = delegate
        webView = environment.webFactory.makeWebView(boot: UserScripts.Boot(role: .tray), receiver: nil)
        super.init(frame: .zero)
        environment.webFactory.bridge.register(self, for: webView)
        clipsToBounds = true
        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        addSubview(webView)
        addSubview(placeholder)
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func load() {
        isMeasured = false
        placeholder.isHidden = false
        if let url = Self.homeURL { webView.load(URLRequest(url: url)) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if webView.superview === self { webView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(viewportHeight, bounds.height)) }
        placeholder.frame = bounds
    }

    /// Returns the web view to the tray after the story viewer closes.
    func reattach() {
        guard webView.superview !== self else { return }
        insertSubview(webView, belowSubview: placeholder)
        setNeedsLayout()
    }

    func applyTheme(_ background: UIColor) {
        backgroundColor = background
        placeholder.backgroundColor = background
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
    }

    func bridge(didReceive message: BridgeMessage) {
        switch message {
        case .storiesTray(let height, let items):
            isMeasured = true
            placeholder.isHidden = items > 0
            delegate?.trayDidMeasure(height: CGFloat(height), items: items)
        case .storyViewer(let open):
            delegate?.trayStoryViewer(open: open)
        case .navigate(let url):
            delegate?.trayNavigate(to: url)
        case .wordmark(let shape):
            delegate?.trayDidCapture(wordmark: shape)
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let target = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        switch RouteDecision.decide(current: webView.url, target: target, role: .tray) {
        case .stay: decisionHandler(.allow)
        case .native: decisionHandler(.cancel); delegate?.trayNavigate(to: target)
        case .block, .pass: decisionHandler(.cancel)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { load() }
}

/// Static story-ring placeholders shown until the tray reports its items.
private final class TrayPlaceholderView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ rect: CGRect) {
        let fill = UIColor.label.withAlphaComponent(0.09)
        fill.setFill()
        var x: CGFloat = 12
        while x < bounds.width {
            UIBezierPath(ovalIn: CGRect(x: x, y: 10, width: 66, height: 66)).fill()
            UIBezierPath(roundedRect: CGRect(x: x + 10, y: 84, width: 46, height: 8), cornerRadius: 4).fill()
            x += 80
        }
    }
}
