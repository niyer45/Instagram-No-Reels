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
    private var offsetObservation: NSKeyValueObservation?
    /// The presented story viewer (`StoryViewerController` inside the shared full-screen modal container).
    private weak var viewer: ModalContainerController?
    private var trayWait: Timer?
    private var launchReported = false
    /// Fires once when the feed and its tray (or the login page) are ready to be revealed.
    var onLaunchReady: (() -> Void)?

    // Header collapse state (§3.3): `collapse` is how far the header has slid up, 0...height.
    private var collapse: CGFloat = 0
    private var lastOffset: CGFloat = 0
    /// Scroll travelled in the current direction; hiding or revealing from rest starts past `collapseThreshold`.
    private var travel: CGFloat = 0
    private var heldPull: CGFloat?
    private static let collapseThreshold: CGFloat = 8
    #if DEBUG
    /// Outline capture state: bumped at each ready and refresh start so delayed captures of an older page are skipped.
    private var outlineGeneration = 0
    private var scrolledCaptured = false
    #endif

    init(environment: AppEnvironment, url: URL?) {
        super.init(environment: environment, url: url, placement: .tabRoot(.home))
    }

    deinit {
        // The splash's tray wait must not outlive Home (e.g. a Home root replaced after sign-in).
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated { trayWait?.invalidate() }
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
        webView.scrollView.panGestureRecognizer.addTarget(self, action: #selector(homePanChanged(_:)))
        onReady = { [weak self] in self?.feedReady() }
        applyHomeTheme()
        #if DEBUG
        HomeDemo.start(on: self)
        #endif
    }

    /// Tab re-tap and Content filters reload refresh the tray with the feed.
    override func reload() {
        super.reload()
        tray.load()
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
        placeRefreshSpinner()
        layoutTray()
    }

    private func layoutTray() {
        let zoom = max(webView.scrollView.zoomScale, 0.01)
        let y = (slotTop ?? headerHeight) * zoom
        tray.frame = CGRect(x: 0, y: y, width: webView.bounds.width, height: isLoginContent ? 0 : trayHeight * zoom)
        tray.isHidden = isLoginContent || trayHeight == 0
        tray.viewportHeight = webView.bounds.height
    }

    /// The header stays put while pulling, so the spinner belongs in the gap that opens below it.
    /// The refresh control centres its spinner in the pulled distance from the web view's top,
    /// which the header covers; shifting its bounds by the header height moves the spinner into
    /// the gap above the page's (empty) header reservation, as on native Instagram.
    private func placeRefreshSpinner() {
        guard let refresh = webView.scrollView.refreshControl else { return }
        let shift = -headerHeight
        if refresh.bounds.origin.y != shift { refresh.bounds.origin.y = shift }
    }

    override func applyTheme() {
        super.applyTheme()
        applyHomeTheme()
    }

    /// Light pages: the header, glyphs and wordmark follow the window's interface style, which
    /// Theme derives from the page colour; only the surface colour is set here.
    private func applyHomeTheme() {
        homeHeader.backgroundColor = environment.theme.background
        tray.applyTheme(environment.theme.background)
    }

    override func chromeDidChange() {
        super.chromeDidChange()
        view.setNeedsLayout()
    }

    // MARK: Header collapse

    /// Called for every content offset change (KVO); sets only the header's transform and alpha.
    private func scrolled(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y
        let dy = y - lastOffset
        lastOffset = y
        placeRefreshSpinner()
        if heldPull != nil || y <= 0 {
            // At the top (and while a refresh holds the pull) the header is fully shown and fixed;
            // the refresh spinner shows in the gap below it.
            travel = 0
            setCollapse(0)
            return
        }
        if dy == 0 { return }
        if (dy > 0) != (travel > 0) { travel = 0 }
        travel += dy
        let height = HomeHeaderView.height
        let atRest = collapse == 0 || collapse == height
        if !atRest || abs(travel) >= Self.collapseThreshold {
            collapse = min(max(collapse + dy, 0), height)
        }
        // Near the top the header can only be pushed up as far as the content has moved.
        setCollapse(min(collapse, y))
        #if DEBUG
        if !scrolledCaptured, collapse >= height, y > 300 {
            scrolledCaptured = true
            captureOutline("scrolled")
        }
        #endif
    }

    private func setCollapse(_ value: CGFloat) {
        collapse = value
        homeHeader.transform = CGAffineTransform(translationX: 0, y: -value)
        homeHeader.setCollapse(value / HomeHeaderView.height)
    }

    /// At drag end the header snaps fully shown or fully hidden (by fling direction, else by
    /// how far it is collapsed). It cannot hide while the content is less than its height from the top.
    @objc private func homePanChanged(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended || pan.state == .cancelled, heldPull == nil else { return }
        let height = HomeHeaderView.height
        let y = webView.scrollView.contentOffset.y
        guard collapse > 0, collapse < height else { return }
        let velocity = pan.velocity(in: webView.scrollView).y
        var hide = abs(velocity) > 300 ? velocity < 0 : collapse > height / 2
        if y < height { hide = false }
        snapHeader(hidden: hide)
    }

    private func snapHeader(hidden: Bool) {
        let target: CGFloat = hidden ? HomeHeaderView.height : 0
        travel = 0
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
            self.setCollapse(target)
        }
    }

    /// Re-tapping Home scrolls to top; the header comes back at once, as on native.
    override func scrollToTop() -> Bool {
        let scrolled = super.scrollToTop()
        if scrolled { snapHeader(hidden: false) }
        return scrolled
    }

    // MARK: Refresh hold

    override func refreshWillBegin(hold: CGFloat) {
        #if DEBUG
        outlineGeneration += 1
        captureOutline("refresh-start")
        let generation = outlineGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.outlineGeneration == generation, self.isRefreshing else { return }
            self.captureOutline("refresh-loading")
        }
        #endif
        heldPull = hold
        setCollapse(0)
        tray.load()
    }

    override func refreshSettle() {
        setCollapse(0)
    }

    override func refreshDidFinish() {
        heldPull = nil
        travel = 0
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
        #if DEBUG
        scrolledCaptured = false
        if isRefreshing {
            captureOutline("refresh-end")
        } else {
            outlineGeneration += 1
            let generation = outlineGeneration
            captureOutline("ready")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self, self.outlineGeneration == generation, !self.isRefreshing else { return }
                self.captureOutline("ready-3s")
            }
        }
        #endif
        if isLoginContent || tray.isMeasured { reportLaunchReady(); return }
        trayWait?.invalidate()
        trayWait = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.reportLaunchReady() }
        }
    }

    /// Ends the launch splash once the skeleton's 0.2 s cross-fade (`markReady`) is over, so the
    /// splash fades straight into the feed or login page instead of through the skeleton.
    private func reportLaunchReady() {
        trayWait?.invalidate()
        guard !launchReported else { return }
        launchReported = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.onLaunchReady?() }
    }

    #if DEBUG
    /// Writes a sanitized page outline plus native layout numbers (no URLs, text or usernames).
    private func captureOutline(_ capture: String) {
        guard !isLoginContent else { return }
        let script = "window.__instagram&&window.__instagram.outline?window.__instagram.outline():null"
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let outline = result as? [String: Any] else { return }
            Task { @MainActor in
                guard let self else { return }
                let scrollView = self.webView.scrollView
                let native: [String: Any] = [
                    "contentOffsetY": Int(scrollView.contentOffset.y.rounded()),
                    "adjustedInsetTop": Int(scrollView.adjustedContentInset.top.rounded()),
                    "webViewFrame": Self.ints(self.webView.frame),
                    "headerCollapse": Double(self.collapse),
                    "headerHeight": Double(HomeHeaderView.height),
                    "trayFrame": Self.ints(self.tray.frame),
                    "trayHidden": self.tray.isHidden,
                    "trayAlpha": Double(self.tray.alpha),
                    "trayMeasured": self.tray.isMeasured,
                    "slotTop": self.slotTop.map { Double($0) as Any } ?? NSNull(),
                    "trayHeight": Double(self.trayHeight),
                    "isReady": self.isReady,
                    "isLoginContent": self.isLoginContent,
                    "refresh": self.debugRefreshState,
                ]
                Diagnostics.writeOutline(outline, native: native, capture: capture)
            }
        }
    }
    #endif

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
            let content = StoryViewerController(webView: tray.webView)
            let modal = ModalContainerController(content: content)
            content.onCloseRequest = { [weak self, weak modal] in
                guard let self else { return }
                self.tray.webView.evaluateJavaScript("window.__instagramTray&&window.__instagramTray.closeViewer()", completionHandler: nil)
                // If Instagram's viewer did not close (no close control, no history), dismiss and reset the tray.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak modal] in
                    guard let self, let modal, self.viewer === modal else { return }
                    self.closeViewer { [weak self] in self?.tray.load() }
                }
            }
            // The container's downward swipe closes Instagram's viewer; the page then reports it closed.
            modal.dismissalHandler = { [weak content] _ in content?.requestClose() }
            viewer = modal
            present(modal, animated: true)
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
