import WebKit

/// Creates every WKWebView with the shared configuration (default persistent data store,
/// inline media, no link previews or back/forward gestures), installs its user scripts and
/// registers it with the bridge. Keeps a weak registry so policy changes reach live pages.
@MainActor
final class WebPageFactory {
    let bridge = WebBridge()
    private let following: FollowingStore
    private let theme: Theme
    private let boots = NSMapTable<WKWebView, BootBox>.weakToStrongObjects()

    private final class BootBox { var boot: UserScripts.Boot; init(_ boot: UserScripts.Boot) { self.boot = boot } }

    init(following: FollowingStore, theme: Theme) {
        self.following = following
        self.theme = theme
    }

    /// Creates a web view; a receiver that cannot exist yet (during its owner's init) registers later via `bridge.register`.
    func makeWebView(boot: UserScripts.Boot, receiver: WebBridgeReceiver?) -> WKWebView {
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
}
