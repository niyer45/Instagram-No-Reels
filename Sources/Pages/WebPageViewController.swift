import UIKit
import SwiftUI
import WebKit
import Combine

/// One Instagram page: exactly one WKWebView, a native header for its kind, a skeleton until
/// the page reports `ready`, a native retry state after 20 s or a failed load (retried by
/// itself on reconnect), the "No internet connection" banner, recovery from web content
/// process termination, pull-to-refresh that holds until the replacement is ready, and
/// memory relief: a page that is off screen, deep in its stack or hidden during a memory
/// warning, unloads its document behind a snapshot and reloads it when shown again.
@MainActor
class WebPageViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WebBridgeReceiver {
    /// Where the page lives; decides its header and frame.
    enum Placement: Equatable { case tabRoot(TabItem), pushed, modal }

    let environment: AppEnvironment
    let placement: Placement
    private(set) var url: URL?
    private(set) var route: Route
    private(set) var webTitle = ""
    private(set) var isReady = false
    /// Instagram's login content (a login route, or a page whose filter status says login).
    private(set) var isLoginContent = false
    var kind: RouteKind { isLoginContent ? .login : route.kind }
    var onReady: (() -> Void)?

    /// The page's web view, created on first use. A page unloaded to save memory releases it
    /// (`hibernate`) and gets a new one when it is shown again.
    var webView: WKWebView {
        if let webViewStorage { return webViewStorage }
        let webView = environment.webFactory.makeWebView(boot: currentBoot, receiver: self)
        webViewStorage = webView
        return webView
    }
    private var webViewStorage: WKWebView?
    /// The web view's frame (also the frame of the overlays covering it).
    private var contentFrame = CGRect.zero
    let statusBarBackdrop = UIView()
    private(set) var pageHeader: PageHeaderView?
    private var skeletonHost: UIHostingController<SkeletonView>?
    /// Covers the web view until ready: the skeleton host's view, or a plain surface for kinds without one.
    private var skeletonCover: UIView?
    private var failureHost: UIHostingController<LoadFailureView>?
    private var searchIdleHost: UIHostingController<SearchIdleView>?
    private var searchIdleTop: CGFloat = 0
    private var timeoutTimer: Timer?
    private var offlineBanner: OfflineBanner?
    private var bannerShown = false
    private var isOffline = false
    private var appearances = 0
    /// Covers an unloaded (hibernated) page with its last snapshot until it is ready again.
    private var placeholder: UIImageView?
    /// The page as it looked when last covered (pushed over, tab switched away); kept small.
    private var coverSnapshot: UIImage?
    private var hibernation: Hibernation?
    private var pendingScrollRestore: CGPoint?
    private var reloadWhenVisible = false
    private var hasCommitted = false
    private var rewroteHomeVariant = false
    var cancellables = Set<AnyCancellable>()

    /// What an unloaded page needs to come back.
    private struct Hibernation { let url: URL; let offset: CGPoint }
    /// Pages per stack (top first) whose documents stay loaded; deeper pages unload.
    static let liveStackDepth = 4

    private enum RefreshPhase: Equatable { case idle, waitingForRelease, reloading(hold: CGFloat), settling }
    private var refreshPhase = RefreshPhase.idle
    private var refreshSnapshot: UIView?

    init(environment: AppEnvironment, url: URL?, placement: Placement) {
        self.environment = environment
        self.placement = placement
        self.url = url
        self.route = url.map { Route(url: $0) } ?? Route(kind: placement == .tabRoot(.profile) ? .profile : .other)
        self.isLoginContent = route.kind == .login
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Layout policy (overridden by HomePageViewController)

    /// Height of the native header drawn over or above the web view (0 when none).
    /// Root pages hide their header over login content; pushed pages keep the back chevron.
    var headerHeight: CGFloat { pageHeader == nil || (isLoginContent && placement != .pushed) ? 0 : PageHeaderView.height }
    /// Whether the header overlays the web view (Home) instead of sitting above it.
    var headerOverlaysContent: Bool { false }
    var isFullScreen: Bool { placement == .modal }
    var supportsRefresh: Bool { [.home, .profile, .activity, .inbox].contains(route.kind) && placement != .modal }
    var storiesSlot: Bool { false }

    var currentBoot: UserScripts.Boot {
        UserScripts.Boot(role: .page,
                         headerHeight: headerOverlaysContent ? headerHeight : 0,
                         hideChrome: ![RouteKind.login, .stories, .create].contains(kind),
                         storiesSlot: storiesSlot)
    }

    var skeletonLayout: SkeletonLayout? {
        switch route.kind {
        case .home, .post: return .feed
        case .profile: return .profile
        case .search: return .search
        case .inbox, .thread: return .inbox
        case .activity, .likes, .comments, .settings, .other: return .list
        case .login, .stories, .create, .blocked: return nil
        }
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = environment.theme.background
        installWebView()
        // Start WebKit's work before building the native header and skeleton (launch and push speed).
        startInitialLoad()
        statusBarBackdrop.isUserInteractionEnabled = false
        view.addSubview(statusBarBackdrop)
        installHeader()
        if placement == .modal {
            let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeDismiss(_:)))
            edge.edges = .left
            view.addGestureRecognizer(edge)
        }
        environment.theme.changes.sink { [weak self] in self?.applyTheme() }.store(in: &cancellables)
        showSkeleton()
        // Act on the emitted value, never on a store property read inside the sink.
        environment.connectivity.changes.sink { [weak self] online in self?.connectivityChanged(online: online) }.store(in: &cancellables)
        // Pages that are not on screen (other tabs, pages under the top of a stack) unload on a memory
        // warning. Observed directly: UIKit does not send didReceiveMemoryWarning to the view
        // controllers of tabs the shell has detached.
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in self?.hibernate() }.store(in: &cancellables)
    }

    /// Wires the web view into the page: delegates, bottom of the view stack, native refresh control.
    private func installWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view.insertSubview(webView, at: 0)
        if supportsRefresh {
            let refresh = UIRefreshControl()
            refresh.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
            webView.scrollView.refreshControl = refresh
            webView.scrollView.panGestureRecognizer.addTarget(self, action: #selector(scrollPanChanged(_:)))
        }
    }

    private func startInitialLoad() {
        if let url {
            load(url)
        } else if placement == .tabRoot(.profile) {
            // The Profile route needs the signed-in username; wait for the bridge to report it.
            // Use the emitted values: @Published fires in willSet, before the store's properties change.
            environment.account.$username.combineLatest(environment.account.$session).sink { [weak self] username, session in
                guard let self, self.url == nil else { return }
                if let profile = username.flatMap(AccountStore.profileURL(for:)) {
                    self.load(profile)
                } else if session == .signedOut, let login = URL(string: "https://www.instagram.com/accounts/login/") {
                    self.load(login)
                }
            }.store(in: &cancellables)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPage()
    }

    override var prefersStatusBarHidden: Bool { isFullScreen }

    func layoutPage() {
        let bounds = view.bounds
        let top = isFullScreen ? 0 : view.safeAreaInsets.top
        let bottom = isFullScreen ? bounds.maxY : bounds.maxY - view.safeAreaInsets.bottom
        statusBarBackdrop.frame = CGRect(x: 0, y: 0, width: bounds.width, height: top)
        let headerSpace = headerOverlaysContent ? 0 : headerHeight
        contentFrame = CGRect(x: 0, y: top + headerSpace, width: bounds.width, height: max(bottom - top - headerSpace, 0))
        // An unloaded page has released its web view; do not create one just to lay it out.
        webViewStorage?.frame = contentFrame
        pageHeader?.frame = CGRect(x: 0, y: top, width: bounds.width, height: PageHeaderView.height)
        pageHeader?.isHidden = headerHeight == 0
        for overlay in [skeletonCover, failureHost?.view, placeholder] { overlay?.frame = contentFrame }
        layoutBanner()
        if let idle = searchIdleHost?.view { idle.frame = CGRect(x: 0, y: contentFrame.minY + searchIdleTop + 8, width: bounds.width, height: 240) }
    }

    func applyTheme() {
        let background = environment.theme.background
        view.backgroundColor = background
        statusBarBackdrop.backgroundColor = background
        if let webView = webViewStorage {
            webView.backgroundColor = background
            webView.underPageBackgroundColor = background
            webView.scrollView.backgroundColor = background
        }
        pageHeader?.apply(background: background, hairline: environment.theme.hairline)
        skeletonHost?.rootView = makeSkeleton()
        skeletonCover?.backgroundColor = background
        failureHost?.rootView = makeFailure()
        placeholder?.backgroundColor = background
        offlineBanner?.apply(isDark: environment.theme.isDark)
    }

    // MARK: Header

    func installHeader() {
        let header: PageHeaderView
        switch placement {
        case .modal: return
        case .tabRoot(.home), .tabRoot(.search): return
        case .tabRoot(.activity):
            header = PageHeaderView(showsBack: false)
        case .tabRoot(.profile):
            header = PageHeaderView(showsBack: false)
            header.setTrailing([profileMenuButton()])
        case .pushed:
            header = PageHeaderView(showsBack: true)
            header.onBack = { [weak self] in self?.navigationController?.popViewController(animated: true) }
            if route.kind == .inbox, let url = URL(string: "https://www.instagram.com/direct/new/") {
                header.setTrailing([PageHeaderView.iconButton(.compose, label: "New message") { [weak self] in
                    guard let self else { return }
                    self.environment.router.open(url, from: self)
                }])
            }
        }
        pageHeader = header
        view.addSubview(header)
        updateTitle()
    }

    private func profileMenuButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(Glyph.menu.image(pointSize: 24), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = "Options"
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: [
            UIAction(title: "Settings", image: UIImage(systemName: "gearshape")) { [weak self] _ in
                guard let self, let url = URL(string: "https://www.instagram.com/accounts/edit/") else { return }
                self.environment.router.open(url, from: self)
            },
            UIAction(title: "Content filters", image: UIImage(systemName: "line.3.horizontal.decrease.circle")) { [weak self] _ in
                self?.environment.router.presentSettings()
            },
        ])
        return button
    }

    func updateTitle() {
        guard let header = pageHeader else { return }
        switch (placement, route.kind) {
        case (.tabRoot(.activity), _), (_, .activity): header.title = "Notifications"
        case (_, .profile): header.title = route.identity.isEmpty ? (environment.account.username ?? "") : route.identity
        case (_, .post): header.title = "Post"
        case (_, .comments): header.title = "Comments"
        case (_, .likes): header.title = "Likes"
        case (_, .inbox): header.title = "Messages"
        case (_, .thread): header.title = webTitle.isEmpty ? "Message" : webTitle
        case (_, .settings): header.title = webTitle.isEmpty ? "Settings" : webTitle
        default: header.title = webTitle
        }
    }

    /// Re-evaluates header visibility and web layout after the page kind changes.
    func chromeDidChange() {
        environment.webFactory.update(currentBoot, for: webView)
        let boot = currentBoot
        webView.evaluateJavaScript("window.__instagram&&window.__instagram.layout({headerHeight:\(Double(boot.headerHeight)),hideChrome:\(boot.hideChrome)})", completionHandler: nil)
        updateTitle()
        view.setNeedsLayout()
    }

    // MARK: Loading and readiness

    func load(_ url: URL) {
        self.url = url
        route = Route(url: url)
        hasCommitted = false
        rewroteHomeVariant = false
        beginLoading()
        #if DEBUG
        if placement == .tabRoot(.home) { Diagnostics.launchMark("home-load") }
        if DebugLaunchOptions.skeletonPreview { timeoutTimer?.invalidate(); return }
        if DebugLaunchOptions.failurePreview { timeoutTimer?.invalidate(); showFailure(); return }
        #endif
        // Home adopts the web view AppEnvironment pre-warmed at launch, already loading this URL.
        let warm = environment.webFactory.claimPrewarmedLoad(of: webView, url: url)
        guard !warm.inProgress else {
            if warm.committed { adoptCommittedDocument() }
            return
        }
        webView.load(URLRequest(url: url))
    }

    /// The pre-warmed document committed before this page became its navigation delegate.
    private func adoptCommittedDocument() {
        hasCommitted = true
        guard let current = webView.url else { return }
        let next = Route(url: current)
        if next != route { route = next; updateTitle() }
        setLoginContent(next.kind == .login)
    }

    /// Reloads with the skeleton up (tab re-tap, retry, Content filters reload, reconnect).
    func reload() {
        if hibernation != nil { wake(restoringScroll: false); return }
        guard let url = webView.url ?? url else { return }
        cancelRefresh()
        beginLoading()
        if webView.url == nil { webView.load(URLRequest(url: url)) } else { webView.reload() }
    }

    /// Reloads now if on screen, otherwise the next time the page appears (foreground refresh).
    func reloadWhenNextVisible() {
        if viewIfLoaded?.window != nil { reload() } else { reloadWhenVisible = true }
    }

    private func beginLoading() {
        isReady = false
        // VoiceOver must not reach the half-loaded document under the skeleton.
        webView.accessibilityElementsHidden = true
        hideFailure()
        showSkeleton()
        startTimeout()
    }

    func markReady() {
        guard !isReady else { return }
        isReady = true
        #if DEBUG
        if placement == .tabRoot(.home) { Diagnostics.launchMark("home-ready") }
        #endif
        timeoutTimer?.invalidate()
        hideFailure()
        removePlaceholder()
        restoreScrollIfNeeded()
        webView.accessibilityElementsHidden = false
        if let cover = skeletonCover {
            let host = skeletonHost
            skeletonCover = nil
            skeletonHost = nil
            UIView.animate(withDuration: 0.2, animations: { cover.alpha = 0 }) { _ in
                host?.willMove(toParent: nil)
                cover.removeFromSuperview()
                host?.removeFromParent()
            }
        }
        finishRefreshIfNeeded()
        onReady?()
        environment.router.shell?.pageDidBecomeReady(self)
    }

    private func makeSkeleton() -> SkeletonView {
        SkeletonView(layout: skeletonLayout ?? .list, background: Color(uiColor: environment.theme.background),
                     topInset: headerOverlaysContent ? headerHeight : 0, storiesRow: storiesSlot && !isLoginContent)
    }

    func showSkeleton() {
        guard skeletonCover == nil, refreshPhase == .idle, isViewLoaded else { return }
        let cover: UIView
        if skeletonLayout != nil {
            let host = UIHostingController(rootView: makeSkeleton())
            addChild(host)
            cover = host.view
            skeletonHost = host
        } else {
            // Kinds without a skeleton (login, stories, create) still cover Instagram's own loader.
            cover = UIView()
        }
        cover.backgroundColor = environment.theme.background
        cover.isUserInteractionEnabled = false
        cover.frame = contentFrame
        if let webView = webViewStorage { view.insertSubview(cover, aboveSubview: webView) } else { view.insertSubview(cover, at: 0) }
        skeletonHost?.didMove(toParent: self)
        skeletonCover = cover
        if let header = pageHeader { view.bringSubviewToFront(header) }
    }

    private func startTimeout() {
        timeoutTimer?.invalidate()
        guard hibernation == nil else { return }
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.loadTimedOut() }
        }
    }

    private func loadTimedOut() {
        guard !isReady else { return }
        // Offscreen pages are not rendering frames; give them time once they are visible.
        guard viewIfLoaded?.window != nil else { startTimeout(); return }
        cancelRefresh()
        showFailure()
    }

    private func makeFailure() -> LoadFailureView {
        LoadFailureView(title: LoadFailureView.title(for: route.kind), message: LoadFailureView.message(offline: isOffline),
                        background: Color(uiColor: environment.theme.background),
                        topInset: headerOverlaysContent ? headerHeight : 0) { [weak self] in
            Haptics.selection()
            self?.reload()
        }
    }

    private func showFailure() {
        guard failureHost == nil else { return }
        removePlaceholder()
        let host = UIHostingController(rootView: makeFailure())
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        host.view.frame = contentFrame
        failureHost = host
        if let header = pageHeader { view.bringSubviewToFront(header) }
        view.setNeedsLayout()
        webView.accessibilityElementsHidden = true
        if viewIfLoaded?.window != nil { UIAccessibility.post(notification: .screenChanged, argument: host.view) }
    }

    private func hideFailure() {
        guard let host = failureHost else { return }
        failureHost = nil
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
    }

    // MARK: Appearance, memory and teardown

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        appearances += 1
        coverSnapshot = nil
        if hibernation != nil {
            wake(restoringScroll: !reloadWhenVisible)
            reloadWhenVisible = false
        } else if reloadWhenVisible {
            reloadWhenVisible = false
            reload()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Stack cap: only the top `liveStackDepth` pages of this stack keep their documents.
        guard let stack = navigationController?.viewControllers, stack.last === self, stack.count > Self.liveStackDepth else { return }
        for case let page as WebPageViewController in stack.dropLast(Self.liveStackDepth) { page.hibernate() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !isMovingFromParent, !isBeingDismissed { captureCoverSnapshot() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Popped or dismissed for good: stop the document and its timers now, not on deallocation.
        if isMovingFromParent || isBeingDismissed { tearDown() }
    }

    deinit {
        // UIKit releases view controllers on the main thread; elsewhere there is nothing safe to touch.
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated { tearDown() }
    }

    private func tearDown() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        webViewStorage?.stopLoading()
    }

    /// Keeps a reduced-size image of the page while another page or tab covers it, for `hibernate`.
    private func captureCoverSnapshot() {
        guard isReady, failureHost == nil, hibernation == nil, webView.bounds.width > 0 else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        // Half the point width: about 1.5x pixels on a 3x screen, a quarter of a full-size image.
        configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width / 2))
        let appearance = appearances
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let self, let image, self.appearances == appearance, self.hibernation == nil else { return }
            self.coverSnapshot = image
        }
    }

    /// Unloads the document of a page that is not on screen (stack cap, memory warning), leaving its
    /// last snapshot (or its skeleton) in place; it reloads when the page appears again, restoring
    /// the scroll position where the new document is long enough. Releases the web view, or for
    /// pages that must keep it (`releasesWebViewWhenUnloaded`), loads a blank document into it.
    func hibernate() {
        guard isViewLoaded, hibernation == nil, viewIfLoaded?.window == nil, placement != .modal,
              let current = webView.url ?? url, current.scheme == "https" else { return }
        hibernation = Hibernation(url: current, offset: webView.scrollView.contentOffset)
        timeoutTimer?.invalidate()
        cancelRefresh()
        hideFailure()
        isReady = false
        webView.accessibilityElementsHidden = true
        showPlaceholder()
        let old = webView
        old.stopLoading()
        old.navigationDelegate = nil
        if releasesWebViewWhenUnloaded {
            // Releasing the web view ends its web content process; a new one is made on wake.
            old.uiDelegate = nil
            old.scrollView.refreshControl = nil
            old.removeFromSuperview()
            webViewStorage = nil
        } else {
            // No delegate while blank: the blank document is not a navigation for the page to judge.
            old.loadHTMLString("", baseURL: nil)
        }
        #if DEBUG
        Diagnostics.record("page-unloaded", labels: ["kind": route.kind.rawValue])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [factory = environment.webFactory] in
            Diagnostics.record("live-web-views", ["count": factory.liveWebViewCount])
        }
        #endif
    }

    var isHibernating: Bool { hibernation != nil }

    /// Whether unloading releases the web view (ending its process) or only blanks its document.
    /// Subclasses that keep references to the web view or its scroll view (Home: the Stories tray
    /// and the header's scroll observation) must keep it.
    var releasesWebViewWhenUnloaded: Bool { !(self is HomePageViewController) }

    private func wake(restoringScroll: Bool) {
        guard let hibernation else { return }
        self.hibernation = nil
        if webView.superview !== view {
            installWebView()
            applyTheme()
            view.setNeedsLayout()
            view.layoutIfNeeded()
        } else {
            webView.navigationDelegate = self
        }
        let offset = hibernation.offset
        pendingScrollRestore = restoringScroll && offset.y > 1 ? offset : nil
        load(hibernation.url)
    }

    private func showPlaceholder() {
        guard placeholder == nil else { return }
        guard let snapshot = coverSnapshot else { showSkeleton(); return }
        coverSnapshot = nil
        let image = UIImageView(image: snapshot)
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.backgroundColor = environment.theme.background
        image.isUserInteractionEnabled = false
        image.isAccessibilityElement = true
        image.accessibilityLabel = "Loading"
        image.frame = contentFrame
        view.insertSubview(image, aboveSubview: skeletonCover ?? webView)
        placeholder = image
    }

    private func removePlaceholder() {
        guard let placeholder else { return }
        self.placeholder = nil
        UIView.animate(withDuration: 0.2, animations: { placeholder.alpha = 0 }) { _ in placeholder.removeFromSuperview() }
    }

    private func restoreScrollIfNeeded() {
        guard let offset = pendingScrollRestore else { return }
        pendingScrollRestore = nil
        let scrollView = webView.scrollView
        let maximum = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        scrollView.setContentOffset(CGPoint(x: 0, y: min(offset.y, maximum)), animated: false)
    }

    // MARK: Connectivity

    private func connectivityChanged(online: Bool) {
        let wasOffline = isOffline
        isOffline = !online
        setBannerVisible(!online)
        failureHost?.rootView = makeFailure()
        // Back online: a page that failed, or is still waiting for its document, tries again by itself.
        if online, wasOffline, failureHost != nil || (!isReady && hibernation == nil && refreshPhase == .idle) {
            #if DEBUG
            Diagnostics.record("reconnect-retry", labels: ["kind": route.kind.rawValue, "failed": failureHost != nil ? "yes" : "no"])
            #endif
            reload()
        }
    }

    private func setBannerVisible(_ visible: Bool) {
        if visible, offlineBanner == nil {
            let banner = OfflineBanner()
            banner.apply(isDark: environment.theme.isDark)
            offlineBanner = banner
            bannerShown = false
            view.addSubview(banner)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            bannerShown = true
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) { self.layoutBanner() }
            if viewIfLoaded?.window != nil {
                UIAccessibility.post(notification: .announcement, argument: OfflineBanner.text)
            }
        } else if !visible, let banner = offlineBanner {
            offlineBanner = nil
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn], animations: {
                banner.frame.origin.y -= OfflineBanner.height
            }, completion: { _ in banner.removeFromSuperview() })
        }
    }

    /// The banner sits under the page's header (or the status bar), above content and overlays,
    /// and slides out from behind the header.
    private func layoutBanner() {
        guard let banner = offlineBanner else { return }
        let top = (isFullScreen ? 0 : view.safeAreaInsets.top) + headerHeight
        banner.frame = CGRect(x: 0, y: bannerShown ? top : top - OfflineBanner.height, width: view.bounds.width, height: OfflineBanner.height)
        view.bringSubviewToFront(banner)
        if let header = pageHeader { view.bringSubviewToFront(header) }
        view.bringSubviewToFront(statusBarBackdrop)
    }

    // MARK: Tab re-selection

    /// Scrolls to top; returns false when the page was already at the top.
    func scrollToTop() -> Bool {
        let scrollView = webView.scrollView
        guard scrollView.contentOffset.y > 1 else { return false }
        scrollView.setContentOffset(.zero, animated: true)
        return true
    }

    // MARK: Pull-to-refresh, held until the new document is ready

    @objc private func refreshTriggered() {
        guard refreshPhase == .idle else { return }
        refreshPhase = .waitingForRelease
        if !webView.scrollView.isDragging { performRefresh() }
    }

    @objc func scrollPanChanged(_ pan: UIPanGestureRecognizer) {
        guard refreshPhase == .waitingForRelease, [.ended, .cancelled, .failed].contains(pan.state) else { return }
        DispatchQueue.main.async { [weak self] in self?.performRefresh() }
    }

    private func performRefresh() {
        guard refreshPhase == .waitingForRelease else { return }
        let hold = max(-webView.scrollView.contentOffset.y, 0)
        let region = CGRect(x: 0, y: hold, width: webView.bounds.width, height: max(webView.bounds.height - hold, 1))
        if let snapshot = webView.resizableSnapshotView(from: region, afterScreenUpdates: false, withCapInsets: .zero) {
            snapshot.frame = region.offsetBy(dx: webView.frame.minX, dy: webView.frame.minY)
            snapshot.isUserInteractionEnabled = false
            view.insertSubview(snapshot, aboveSubview: webView)
            refreshSnapshot = snapshot
        }
        refreshPhase = .reloading(hold: hold)
        refreshWillBegin(hold: hold)
        isReady = false
        startTimeout()
        webView.reload()
    }

    private func finishRefreshIfNeeded() {
        guard case .reloading(let hold) = refreshPhase else { return }
        refreshPhase = .settling
        UIView.performWithoutAnimation {
            webView.scrollView.refreshControl?.endRefreshing()
            webView.scrollView.setContentOffset(.zero, animated: false)
            webView.scrollView.layoutIfNeeded()
        }
        let snapshot = refreshSnapshot
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut], animations: {
            snapshot?.transform = CGAffineTransform(translationX: 0, y: -hold)
            self.refreshSettle()
        }, completion: { _ in
            UIView.animate(withDuration: 0.15, animations: { snapshot?.alpha = 0 }, completion: { _ in
                snapshot?.removeFromSuperview()
                if self.refreshSnapshot === snapshot { self.refreshSnapshot = nil }
                self.refreshPhase = .idle
                self.refreshDidFinish()
            })
        })
    }

    private func cancelRefresh() {
        guard refreshPhase != .idle else { return }
        webView.scrollView.refreshControl?.endRefreshing()
        refreshSnapshot?.removeFromSuperview()
        refreshSnapshot = nil
        refreshPhase = .idle
        refreshDidFinish()
    }

    var isRefreshing: Bool { refreshPhase != .idle && refreshPhase != .waitingForRelease }

    /// Hooks for Home: freeze the header at the held distance, then settle it with the posts.
    func refreshWillBegin(hold: CGFloat) {}
    func refreshSettle() {}
    func refreshDidFinish() {}

    // MARK: Bridge

    func bridge(didReceive message: BridgeMessage) {
        switch message {
        case .route(let path, _, let title):
            let next = Route(path: path)
            webTitle = title
            if placement == .modal, route.kind == .stories, next.kind != .stories { dismiss(animated: true); return }
            if next != route {
                route = next
                setLoginContent(next.kind == .login)
            }
            updateTitle()
        case .navigate(let target):
            environment.router.open(target, from: self)
        case .ready(let readyKind):
            if readyKind == .login { setLoginContent(true); environment.account.markSignedOut() }
            markReady()
        case .status(let status):
            setLoginContent(route.kind == .login || status.state == .login)
            if status.state == .login { environment.account.markSignedOut() }
            statusDidChange(status)
        case .theme(let rgb):
            // Only the page on screen sets the shared native surface colour.
            if viewIfLoaded?.window != nil { environment.theme.update(rgb: rgb) }
        case .avatar(let avatarURL, let username):
            environment.account.update(username: username, avatarURL: avatarURL)
        case .openControls:
            environment.router.presentSettings()
        case .searchIdle(let idle, let top):
            setSearchIdle(idle && route.kind == .search, top: top)
        case .storiesSlot, .storiesTray, .storyViewer, .wordmark:
            pageMessage(message)
        }
    }

    /// Filter status for this page (Home records it for the Content filters sheet).
    func statusDidChange(_ status: FilterStatusPayload) {}
    /// Messages only some pages use (Home: stories slot).
    func pageMessage(_ message: BridgeMessage) {}

    func setLoginContent(_ login: Bool) {
        guard login != isLoginContent else { return }
        isLoginContent = login
        if login { markReady() }
        chromeDidChange()
    }

    private func setSearchIdle(_ idle: Bool, top: CGFloat) {
        searchIdleTop = top
        if idle, searchIdleHost == nil {
            let host = UIHostingController(rootView: SearchIdleView())
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            addChild(host)
            view.insertSubview(host.view, aboveSubview: webView)
            host.didMove(toParent: self)
            searchIdleHost = host
        } else if !idle, let host = searchIdleHost {
            searchIdleHost = nil
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
        view.setNeedsLayout()
    }

    @objc private func edgeDismiss(_ gesture: UIScreenEdgePanGestureRecognizer) {
        if gesture.state == .recognized { dismiss(animated: true) }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let target = action.request.url else { decisionHandler(.cancel); return }
        // Subframes (login challenges, embeds) never become pages of their own.
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        let policy = InstagramNavigation.decision(for: target, following: [])
        guard policy == .allow else { decisionHandler(.cancel); environment.router.report(policy); return }
        let next = Route(url: target)
        if next.kind == .blocked { decisionHandler(.cancel); environment.router.report(.blockReels); return }
        if !hasCommitted {
            // The initial load and its redirects stay in this page (e.g. a redirect to login).
            let variant = URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "variant" })?.value ?? "home"
            if placement == .tabRoot(.home), next.kind == .home, variant == "home", !rewroteHomeVariant,
               let following = URL(string: "https://www.instagram.com/?variant=following") {
                rewroteHomeVariant = true
                decisionHandler(.cancel)
                webView.load(URLRequest(url: following))
                return
            }
            decisionHandler(.allow)
            return
        }
        if action.navigationType == .reload || target == webView.url { decisionHandler(.allow); return }
        if RouteDecision.decide(current: webView.url, target: target) == .native {
            decisionHandler(.cancel)
            environment.router.open(target, from: self)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if !isRefreshing && isReady { beginLoading() }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        hasCommitted = true
        if let current = webView.url {
            let next = Route(url: current)
            if next != route { route = next; updateTitle() }
            setLoginContent(next.kind == .login)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }

    private func failed(_ error: Error) {
        let error = error as NSError
        // Cancelled loads (our own interceptions) and WebKit's "frame load interrupted" are not failures.
        if error.code == NSURLErrorCancelled || (error.domain == "WebKitErrorDomain" && error.code == 102) { return }
        timeoutTimer?.invalidate()
        cancelRefresh()
        showFailure()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // An unloaded page reloads when it is shown again.
        guard hibernation == nil else { return }
        cancelRefresh()
        isReady = false
        webView.accessibilityElementsHidden = true
        hideFailure()
        showSkeleton()
        startTimeout()
        if let current = webView.url ?? url { webView.load(URLRequest(url: current)) }
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let target = action.request.url { environment.router.open(target, from: self) }
        return nil
    }

    /// Whether a JavaScript panel can be shown now. WebKit raises an exception if a panel's
    /// completion handler is released uncalled, which happens when `present` silently fails.
    private var canPresentPanel: Bool { viewIfLoaded?.window != nil && presentedViewController == nil && !isBeingDismissed }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        guard canPresentPanel else { completionHandler(); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        guard canPresentPanel else { completionHandler(false); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
}
