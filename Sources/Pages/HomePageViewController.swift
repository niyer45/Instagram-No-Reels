import UIKit
import WebKit

/// The Following feed: native Home header that collapses on scroll, the Stories tray hosted
/// in the feed's scroll view over FeedFilter's `[data-instagram-stories-slot]` spacer, the
/// story viewer presented full-screen, and refresh that settles header, tray and posts together.
@MainActor
final class HomePageViewController: WebPageViewController, StoriesTrayHostDelegate {
    private let homeHeader = HomeHeaderView()
    private lazy var tray = StoriesTrayHost(environment: environment, delegate: self)
    private var trayHeight = StoriesTrayHost.defaultHeight
    private var slotTop: CGFloat?
    private var collapse: CGFloat = 0
    private var lastOffset: CGFloat = 0
    private var heldPull: CGFloat?
    private var offsetObservation: NSKeyValueObservation?
    private weak var viewer: StoryViewerController?
    private var trayWait: Timer?
    private var launchReported = false
    /// Fires once when the feed and its tray (or the login page) are ready to be revealed.
    var onLaunchReady: (() -> Void)?

    init(environment: AppEnvironment, url: URL?) {
        super.init(environment: environment, url: url, placement: .tabRoot(.home))
    }

    override var headerHeight: CGFloat { isLoginContent ? 0 : HomeHeaderView.height }
    override var headerOverlaysContent: Bool { true }
    override var storiesSlot: Bool { true }
    override var currentBoot: UserScripts.Boot {
        var boot = super.currentBoot
        boot.storiesHeight = trayHeight
        return boot
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.scrollView.addSubview(tray)
        tray.load()
        offsetObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            MainActor.assumeIsolated { self?.scrolled(scrollView) }
        }
        onReady = { [weak self] in self?.feedReady() }
        applyHomeTheme()
    }

    override func installHeader() {
        homeHeader.onActivity = { [weak self] in self?.openPath("/accounts/activity/") }
        homeHeader.onMessages = { [weak self] in self?.openPath("/direct/inbox/") }
        homeHeader.setWordmark(WordmarkShape.cached())
        view.addSubview(homeHeader)
    }

    private func openPath(_ path: String) {
        guard let url = URL(string: "https://www.instagram.com" + path) else { return }
        environment.router.open(url, from: self)
    }

    override func layoutPage() {
        super.layoutPage()
        let top = view.safeAreaInsets.top
        homeHeader.bounds = CGRect(x: 0, y: 0, width: view.bounds.width, height: HomeHeaderView.height)
        homeHeader.center = CGPoint(x: view.bounds.midX, y: top + HomeHeaderView.height / 2)
        homeHeader.isHidden = isLoginContent
        view.bringSubviewToFront(homeHeader)
        view.bringSubviewToFront(statusBarBackdrop)
        layoutTray()
    }

    private func layoutTray() {
        let zoom = max(webView.scrollView.zoomScale, 0.01)
        let y = (slotTop ?? headerHeight) * zoom
        tray.frame = CGRect(x: 0, y: y, width: webView.bounds.width, height: isLoginContent ? 0 : trayHeight * zoom)
        tray.isHidden = isLoginContent || trayHeight == 0
        tray.viewportHeight = webView.bounds.height
    }

    override func applyTheme() {
        super.applyTheme()
        applyHomeTheme()
    }

    private func applyHomeTheme() {
        homeHeader.backgroundColor = environment.theme.background
        tray.applyTheme(environment.theme.background)
    }

    override func chromeDidChange() {
        super.chromeDidChange()
        view.setNeedsLayout()
    }

    // MARK: Header collapse

    private func scrolled(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y
        defer { lastOffset = y }
        if let held = heldPull {
            homeHeader.transform = CGAffineTransform(translationX: 0, y: held)
            return
        }
        if y <= 0 {
            // At the top the header follows the pull, so the refresh spinner shows above it.
            collapse = 0
            homeHeader.transform = CGAffineTransform(translationX: 0, y: -y)
            homeHeader.setCollapse(0)
            return
        }
        let height = HomeHeaderView.height
        collapse = min(max(collapse + (y - lastOffset), 0), height)
        homeHeader.transform = CGAffineTransform(translationX: 0, y: -collapse)
        homeHeader.setCollapse(collapse / height)
    }

    // MARK: Refresh hold

    override func refreshWillBegin(hold: CGFloat) {
        heldPull = hold
        homeHeader.transform = CGAffineTransform(translationX: 0, y: hold)
        tray.load()
    }

    override func refreshSettle() {
        homeHeader.transform = .identity
        homeHeader.setCollapse(0)
        collapse = 0
    }

    override func refreshDidFinish() {
        heldPull = nil
        homeHeader.transform = .identity
    }

    // MARK: Bridge

    override func statusDidChange(_ status: FilterStatusPayload) {
        environment.filterStatus.apply(status)
        if status.state != .login, status.feedReady { environment.account.markSignedIn() }
        #if DEBUG
        webView.evaluateJavaScript("typeof window.__instagramFilterDiagnostics === 'function' ? window.__instagramFilterDiagnostics() : null") { result, _ in
            guard let structure = result as? [String: Any] else { return }
            Task { @MainActor in Diagnostics.recordStructure(structure) }
        }
        #endif
    }

    override func pageMessage(_ message: BridgeMessage) {
        if case .storiesSlot(let top) = message {
            slotTop = CGFloat(top)
            layoutTray()
        }
    }

    // MARK: Launch readiness (splash)

    private func feedReady() {
        if isLoginContent || tray.isMeasured { reportLaunchReady(); return }
        trayWait?.invalidate()
        trayWait = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.reportLaunchReady() }
        }
    }

    private func reportLaunchReady() {
        trayWait?.invalidate()
        guard !launchReported else { return }
        launchReported = true
        onLaunchReady?()
    }

    // MARK: StoriesTrayHostDelegate

    func trayDidMeasure(height: CGFloat, items: Int) {
        let next = items > 0 ? min(max(height, 40), 190) : 0
        if next != trayHeight {
            trayHeight = next
            environment.webFactory.update(currentBoot, for: webView)
            webView.evaluateJavaScript("window.__instagram&&window.__instagram.layout({storiesHeight:\(Double(next))})", completionHandler: nil)
            layoutTray()
        }
        if isReady { reportLaunchReady() }
    }

    func trayStoryViewer(open: Bool) {
        if open {
            guard viewer == nil else { return }
            let controller = StoryViewerController(webView: tray.webView)
            controller.onCloseRequest = { [weak self] in
                self?.tray.webView.evaluateJavaScript("history.back()", completionHandler: nil)
            }
            viewer = controller
            present(controller, animated: true)
        } else {
            closeViewer(completion: nil)
            // The feed re-scans once the viewer closes (story views can change the page).
            webView.evaluateJavaScript("window.__instagram&&window.__instagram.refresh()", completionHandler: nil)
        }
    }

    func trayNavigate(to url: URL) {
        if viewer != nil {
            closeViewer { [weak self] in
                guard let self else { return }
                self.tray.load()
                self.environment.router.open(url, from: self)
            }
        } else {
            environment.router.open(url, from: self)
        }
    }

    func trayDidCapture(wordmark: WordmarkShape) {
        wordmark.cache()
        homeHeader.setWordmark(wordmark)
    }

    private func closeViewer(completion: (() -> Void)?) {
        guard let viewer else { completion?(); return }
        self.viewer = nil
        viewer.dismiss(animated: true) { [weak self] in
            self?.tray.reattach()
            completion?()
        }
    }
}
