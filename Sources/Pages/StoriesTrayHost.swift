import UIKit
import WebKit

/// Events from the Stories tray web view to the Home page.
@MainActor
protocol StoriesTrayHostDelegate: AnyObject {
    /// The tray's measured height and item count; `items == 0` hides the tray.
    func trayDidMeasure(height: CGFloat, items: Int)
    func trayStoryViewer(open: Bool)
    func trayNavigate(to url: URL)
    func trayDidCapture(wordmark: WordmarkShape)
}

/// Hosts the dedicated Stories web view as a native component of the Home layout. The web
/// view keeps a full viewport (stable Instagram layout) and the host clips it to the tray's
/// measured height; it lives inside the feed's scroll view so it scrolls with the posts.
///
/// The tray never replaces or navigates the Home page: if its document lands on a login-kind
/// route (a redirect to `/accounts/login/` or `/accounts/onetap/`), the tray reports itself
/// empty and stays hidden until the next `load()`.
@MainActor
final class StoriesTrayHost: UIView, WebBridgeReceiver, WKNavigationDelegate {
    static let defaultHeight: CGFloat = 106
    private static let homeURL = URL(string: "https://www.instagram.com/")
    /// How long a reload keeps the previous tray on screen while the new one measures.
    private static let reloadCoverLimit: TimeInterval = 4

    let webView: WKWebView
    private let placeholder = TrayPlaceholderView()
    /// Snapshot of the previous tray kept over a reload so refreshing never flashes placeholders.
    private var reloadCover: UIView?
    private var reloadCoverTimer: Timer?
    private weak var delegate: StoriesTrayHostDelegate?
    private let environment: AppEnvironment
    /// Height given to the tray web view (the feed's viewport height).
    var viewportHeight: CGFloat = 800 { didSet { if viewportHeight != oldValue { setNeedsLayout() } } }
    private(set) var isMeasured = false
    private var hasItems = false
    /// The tray's document reached a login-kind route; the tray stays hidden until reloaded.
    private(set) var landedOnLogin = false

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

    /// Loads (or reloads) the tray. A tray that already shows stories stays on screen, as a
    /// snapshot, until the new document measures, so refresh does not flash placeholders.
    func load() {
        if hasItems, webView.superview === self, reloadCover == nil, let cover = snapshotView(afterScreenUpdates: false) {
            cover.frame = bounds
            cover.isUserInteractionEnabled = false
            addSubview(cover)
            reloadCover = cover
            reloadCoverTimer?.invalidate()
            reloadCoverTimer = Timer.scheduledTimer(withTimeInterval: Self.reloadCoverLimit, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.removeReloadCover() }
            }
        } else if reloadCover == nil {
            placeholder.isHidden = false
        }
        isMeasured = false
        landedOnLogin = false
        if let url = Self.homeURL { webView.load(URLRequest(url: url)) }
    }

    private func removeReloadCover() {
        reloadCoverTimer?.invalidate()
        reloadCoverTimer = nil
        guard let cover = reloadCover else { return }
        reloadCover = nil
        UIView.animate(withDuration: 0.15, animations: { cover.alpha = 0 }) { _ in cover.removeFromSuperview() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if webView.superview === self { webView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(viewportHeight, bounds.height)) }
        placeholder.frame = bounds
        reloadCover?.frame.size.width = bounds.width
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

    // MARK: Login guard

    /// The tray landed on Instagram's login flow: hide it and do nothing else (never navigate Home).
    private func landOnLogin() {
        guard !landedOnLogin else { return }
        landedOnLogin = true
        isMeasured = true
        hasItems = false
        placeholder.isHidden = true
        removeReloadCover()
        webView.stopLoading()
        delegate?.trayDidMeasure(height: 0, items: 0)
    }

    private static func isLogin(_ url: URL) -> Bool { RouteDecision.isOfficial(url) && Route(url: url).kind == .login }

    // MARK: WebBridgeReceiver

    func bridge(didReceive message: BridgeMessage) {
        switch message {
        case .storiesTray(let height, let items):
            guard !landedOnLogin else { return }
            isMeasured = true
            hasItems = items > 0
            placeholder.isHidden = items > 0
            if items > 0 { removeReloadCover(); configureNestedScrolling() }
            delegate?.trayDidMeasure(height: CGFloat(height), items: items)
        case .storyViewer(let open):
            guard !landedOnLogin else { return }
            delegate?.trayStoryViewer(open: open)
        case .navigate(let url):
            if Self.isLogin(url) { landOnLogin(); return }
            delegate?.trayNavigate(to: url)
        case .route(let path, _, _):
            if Route(path: path).kind == .login { landOnLogin() }
        case .wordmark(let shape):
            delegate?.trayDidCapture(wordmark: shape)
        default:
            break
        }
    }

    /// Instagram's tray scrolls horizontally in a WebKit child scroll view. Without vertical
    /// bounce it declines vertical pans, so a vertical drag that starts on the tray is taken by
    /// the feed's scroll view (the tray's ancestor) and scrolls the feed.
    private func configureNestedScrolling() {
        var stack: [UIView] = [webView]
        while let view = stack.popLast() {
            if let scroll = view as? UIScrollView, scroll !== webView.scrollView {
                scroll.alwaysBounceVertical = false
                scroll.isDirectionalLockEnabled = true
                scroll.showsVerticalScrollIndicator = false
            }
            stack.append(contentsOf: view.subviews)
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let target = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        // Server redirects to login (e.g. /accounts/onetap/) arrive here too: hide the tray, never navigate Home.
        if Self.isLogin(target) { decisionHandler(.cancel); landOnLogin(); return }
        switch RouteDecision.decide(current: webView.url, target: target, role: .tray) {
        case .stay: decisionHandler(.allow)
        case .native: decisionHandler(.cancel); delegate?.trayNavigate(to: target)
        case .block, .pass: decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url, Self.isLogin(url) { landOnLogin() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { load() }
}

/// Static story-ring placeholders shown until the tray reports its items.
private final class TrayPlaceholderView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        contentMode = .redraw
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TrayPlaceholderView, _: UITraitCollection) in view.setNeedsDisplay() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ rect: CGRect) {
        let fill = UIColor.label.resolvedColor(with: traitCollection).withAlphaComponent(0.09)
        fill.setFill()
        var x: CGFloat = 12
        while x < bounds.width {
            UIBezierPath(ovalIn: CGRect(x: x, y: 10, width: 66, height: 66)).fill()
            UIBezierPath(roundedRect: CGRect(x: x + 10, y: 84, width: 46, height: 8), cornerRadius: 4).fill()
            x += 80
        }
    }
}
