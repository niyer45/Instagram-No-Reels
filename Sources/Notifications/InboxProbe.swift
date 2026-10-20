import UIKit
import WebKit

/// One hidden, offscreen web view that loads `/direct/inbox/` (the page's own navigation, in the shared
/// signed-in data store), waits for Bridge.js's `inboxState` (or 20 s), and is torn down afterwards.
/// Makes no requests of its own and never reads cookies. Single use: create, `run()`, discard.
@MainActor
final class InboxProbe: NSObject, WebBridgeReceiver, WKNavigationDelegate {
    enum Result: Equatable {
        case threads([InboxThread])
        case signedOut, failed, timedOut, cancelled
    }

    static let timeout: TimeInterval = 20
    /// After the first report, later changes within this window replace it (rows can fill in).
    static let settle: TimeInterval = 1.5
    private static let inboxURL = URL(string: "https://www.instagram.com/direct/inbox/")

    private let factory: WebPageFactory
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Result, Never>?
    private var latest: [InboxThread]?
    private var timeoutTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var finished = false

    init(factory: WebPageFactory) { self.factory = factory }

    /// Loads the inbox and returns what the page reports. Cancelling the calling task finishes with `.cancelled`.
    func run() async -> Result {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Result, Never>) in
                if Task.isCancelled || self.finished { continuation.resume(returning: .cancelled); return }
                self.continuation = continuation
                self.start()
            }
        } onCancel: {
            Task { @MainActor in self.finish(.cancelled) }
        }
    }

    private func start() {
        guard let url = Self.inboxURL else { finish(.failed); return }
        let boot = UserScripts.Boot(role: .page, headerHeight: 0, hideChrome: true, storiesSlot: false, storiesHeight: 0)
        let webView = factory.makeWebView(boot: boot, receiver: self)
        self.webView = webView
        webView.navigationDelegate = self
        webView.isUserInteractionEnabled = false
        webView.accessibilityElementsHidden = true
        webView.frame = CGRect(x: -2000, y: 0, width: 390, height: 844)
        // Attached (far offscreen) when a window exists, so WebKit treats it as a live view.
        Self.hostWindow()?.addSubview(webView)
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finish(.timedOut)
        }
        webView.load(URLRequest(url: url))
    }

    private static func hostWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
    }

    private func finish(_ result: Result) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        settleTask?.cancel()
        let continuation = self.continuation
        self.continuation = nil
        #if DEBUG
        // The real signed-in inbox markup has never been observed: keep its structure when detection ran.
        if case .threads = result, let webView {
            // Resume once, at the latest after 2 s: a suspended web process may never answer, and the task
            // expiration handler cannot end a probe that has already finished.
            var resumed = false
            let resume: @MainActor () -> Void = { [weak self] in
                guard !resumed else { return }
                resumed = true
                self?.teardown()
                continuation?.resume(returning: result)
            }
            MessageWatcher.captureOutline(of: webView, source: "watcher", completion: resume)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                resume()
            }
            return
        }
        #endif
        teardown()
        continuation?.resume(returning: result)
    }

    /// Releases the web view: no navigation, scripts, message handler or delegate left behind.
    private func teardown() {
        guard let webView else { return }
        webView.stopLoading()
        webView.navigationDelegate = nil
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.removeScriptMessageHandler(forName: WebBridge.handlerName)
        webView.removeFromSuperview()
        self.webView = nil
    }

    // MARK: WebBridgeReceiver

    func bridge(didReceive message: BridgeMessage) {
        guard !finished else { return }
        switch message {
        case .inboxState(let threads):
            latest = threads
            guard settleTask == nil else { return }
            settleTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.settle * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.finish(self.latest.map(Result.threads) ?? .failed)
            }
        case .ready(let kind) where kind == .login:
            finish(.signedOut)
        case .route(let path, _, _) where Route(path: path).kind == .login:
            finish(.signedOut)
        default:
            break
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard action.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
        guard let target = action.request.url, InstagramNavigation.decision(for: target, following: []) == .allow else { decisionHandler(.cancel); return }
        switch Route(url: target).kind {
        case .inbox:
            decisionHandler(.allow)
        case .login:
            decisionHandler(.cancel)
            finish(.signedOut)
        default:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failed) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failed) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failed) }
}
