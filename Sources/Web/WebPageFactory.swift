import WebKit
import Combine

/// Creates every WKWebView with the shared configuration (default persistent data store,
/// inline media, no link previews or back/forward gestures), installs its user scripts and
/// registers it with the bridge. Keeps a weak registry so policy changes reach live pages.
/// At launch it also pre-warms Home's web view (`prewarm`), which Home's page then adopts.
@MainActor
final class WebPageFactory {
    let bridge = WebBridge()
    private let following: FollowingStore
    private let theme: Theme
    private let boots = NSMapTable<WKWebView, BootBox>.weakToStrongObjects()
    /// The launch pre-warmed web view, until a page adopts it and claims its load.
    private var warm: Warm?
    private var themeObservation: AnyCancellable?

    private final class BootBox { var boot: UserScripts.Boot; init(_ boot: UserScripts.Boot) { self.boot = boot } }

    init(following: FollowingStore, theme: Theme) {
        self.following = following
        self.theme = theme
        // Web content follows the system appearance (Theme.webStyle), not the window's sampled style.
        themeObservation = theme.changes.sink { [weak self] in self?.applyWebStyle() }
    }

    /// Live web views (pages, tray), for DEBUG memory diagnostics.
    var liveWebViewCount: Int { boots.keyEnumerator().allObjects.count }

    /// Creates a web view; a receiver that cannot exist yet (during its owner's init) registers later via `bridge.register`.
    /// A page whose boot has the pre-warmed web view's role and stories slot (Home) adopts that web view instead.
    func makeWebView(boot: UserScripts.Boot, receiver: WebBridgeReceiver?) -> WKWebView {
        if let warm, !warm.adopted, warm.boot.role == boot.role, warm.boot.storiesSlot == boot.storiesSlot {
            warm.adopted = true
            let webView = warm.webView
            if warm.boot != boot {
                update(boot, for: webView)
                webView.evaluateJavaScript("window.__instagram&&window.__instagram.layout({headerHeight:\(Double(boot.headerHeight)),storiesHeight:\(Double(boot.storiesHeight)),hideChrome:\(boot.hideChrome)})", completionHandler: nil)
            }
            if let receiver { bridge.register(receiver, for: webView) }
            return webView
        }
        #if DEBUG
        Diagnostics.launchMark("first-webview")
        #endif
        let controller = WKUserContentController()
        controller.add(bridge, name: WebBridge.handlerName)
        for script in UserScripts.scripts(boot: boot, policy: following.policy) { controller.addUserScript(script) }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = controller
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.dataDetectorTypes = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.isOpaque = false
        webView.overrideUserInterfaceStyle = theme.webStyle
        webView.backgroundColor = theme.background
        webView.underPageBackgroundColor = theme.background
        webView.scrollView.backgroundColor = theme.background
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        #if DEBUG
        webView.isInspectable = true
        #endif
        if let receiver { bridge.register(receiver, for: webView) }
        boots.setObject(BootBox(boot), forKey: webView)
        return webView
    }

    private func applyWebStyle() {
        for webView in boots.keyEnumerator().allObjects.compactMap({ $0 as? WKWebView })
        where webView.overrideUserInterfaceStyle != theme.webStyle {
            webView.overrideUserInterfaceStyle = theme.webStyle
        }
    }

    /// Updates the boot values used by the web view's next documents (e.g. after its page kind changes).
    func update(_ boot: UserScripts.Boot, for webView: WKWebView) {
        guard let box = boots.object(forKey: webView), box.boot != boot else { return }
        box.boot = boot
        install(boot, in: webView)
    }

    /// Re-installs scripts with the new policy and hands it to every live document.
    func policyDidChange() {
        let json = following.policyJSON
        for webView in boots.keyEnumerator().allObjects.compactMap({ $0 as? WKWebView }) {
            if let boot = boots.object(forKey: webView)?.boot { install(boot, in: webView) }
            webView.evaluateJavaScript("window.__instagram&&window.__instagram.policy(\(json))", completionHandler: nil)
        }
    }

    private func install(_ boot: UserScripts.Boot, in webView: WKWebView) {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        for script in UserScripts.scripts(boot: boot, policy: following.policy) { controller.addUserScript(script) }
    }

    // MARK: Launch pre-warm

    /// Creates a page web view and starts loading `url` now, before any page exists, so WebKit's
    /// processes and the first request overlap the shell's construction. One at a time.
    func prewarm(url: URL, boot: UserScripts.Boot) {
        guard warm == nil else { return }
        let webView = makeWebView(boot: boot, receiver: nil)
        let warm = Warm(webView: webView, url: url, boot: boot)
        webView.navigationDelegate = warm
        webView.load(URLRequest(url: url))
        self.warm = warm
        #if DEBUG
        Diagnostics.launchMark("home-prewarm")
        #endif
    }

    /// Called by the page that adopted the pre-warmed web view when it loads `url`: returns whether
    /// that load is already under way (so the page must not start it again) and whether its document
    /// has committed. Ends the pre-warm either way.
    func claimPrewarmedLoad(of webView: WKWebView, url: URL) -> (inProgress: Bool, committed: Bool) {
        guard let warm, warm.adopted, warm.webView === webView else { return (false, false) }
        self.warm = nil
        if webView.navigationDelegate === warm { webView.navigationDelegate = nil }
        return warm.url == url ? (true, warm.committed) : (false, false)
    }

    /// Navigation delegate of the pre-warmed web view until its page adopts it: keeps main-frame
    /// navigations on Instagram (the page re-checks everything afterwards) and notes the commit.
    private final class Warm: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        let url: URL
        let boot: UserScripts.Boot
        var adopted = false
        var committed = false

        init(webView: WKWebView, url: URL, boot: UserScripts.Boot) {
            self.webView = webView
            self.url = url
            self.boot = boot
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard action.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
            guard let target = action.request.url, InstagramNavigation.decision(for: target, following: []) == .allow,
                  Route(url: target).kind != .blocked else { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { committed = true }
    }
}
