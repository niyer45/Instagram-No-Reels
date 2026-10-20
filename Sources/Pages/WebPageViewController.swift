import UIKit
import SwiftUI
import WebKit
import Combine

/// One Instagram page: exactly one WKWebView, a native header for its kind, a skeleton until
/// the page reports `ready`, a native retry state after 20 s, recovery from web content
/// process termination, and pull-to-refresh that holds until the replacement is ready.
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

    private(set) lazy var webView: WKWebView = environment.webFactory.makeWebView(boot: currentBoot, receiver: self)
    let statusBarBackdrop = UIView()
    private(set) var pageHeader: PageHeaderView?
    private var skeletonHost: UIHostingController<SkeletonView>?
    /// Covers the web view until ready: the skeleton host's view, or a plain surface for kinds without one.
    private var skeletonCover: UIView?
    private var failureHost: UIHostingController<LoadFailureView>?
    private var searchIdleHost: UIHostingController<SearchIdleView>?
    private var searchIdleTop: CGFloat = 0
    private var timeoutTimer: Timer?
    private var hasCommitted = false
    private var rewroteHomeVariant = false
    var cancellables = Set<AnyCancellable>()

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
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view.addSubview(webView)
        statusBarBackdrop.isUserInteractionEnabled = false
        view.addSubview(statusBarBackdrop)
        installHeader()
        if supportsRefresh {
            let refresh = UIRefreshControl()
            refresh.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
            webView.scrollView.refreshControl = refresh
            webView.scrollView.panGestureRecognizer.addTarget(self, action: #selector(scrollPanChanged(_:)))
        }
        if placement == .modal {
            let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeDismiss(_:)))
            edge.edges = .left
            view.addGestureRecognizer(edge)
        }
        environment.theme.changes.sink { [weak self] in self?.applyTheme() }.store(in: &cancellables)
        showSkeleton()
        if let url {
            load(url)
        } else if placement == .tabRoot(.profile) {
            // The Profile route needs the signed-in username; wait for the bridge to report it.
            environment.account.$username.combineLatest(environment.account.$session).sink { [weak self] _, session in
                guard let self, self.url == nil else { return }
                if let profile = self.environment.account.profileURL {
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
        webView.frame = CGRect(x: 0, y: top + headerSpace, width: bounds.width, height: max(bottom - top - headerSpace, 0))
        pageHeader?.frame = CGRect(x: 0, y: top, width: bounds.width, height: PageHeaderView.height)
        pageHeader?.isHidden = headerHeight == 0
        for overlay in [skeletonCover, failureHost?.view] { overlay?.frame = webView.frame }
        if let idle = searchIdleHost?.view { idle.frame = CGRect(x: 0, y: webView.frame.minY + searchIdleTop + 8, width: bounds.width, height: 240) }
    }

    func applyTheme() {
        let background = environment.theme.background
        view.backgroundColor = background
        statusBarBackdrop.backgroundColor = background
        webView.backgroundColor = background
        webView.underPageBackgroundColor = background
        webView.scrollView.backgroundColor = background
        pageHeader?.apply(background: background, hairline: environment.theme.hairline)
        skeletonHost?.rootView = makeSkeleton()
        skeletonCover?.backgroundColor = background
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
        if DebugLaunchOptions.skeletonPreview { timeoutTimer?.invalidate(); return }
        #endif
        webView.load(URLRequest(url: url))
    }

    /// Reloads with the skeleton up (tab re-tap, retry, Content filters reload).
    func reload() {
        guard let url = webView.url ?? url else { return }
        cancelRefresh()
        beginLoading()
        if webView.url == nil { webView.load(URLRequest(url: url)) } else { webView.reload() }
    }

    private func beginLoading() {
        isReady = false
        hideFailure()
        showSkeleton()
        startTimeout()
    }

    func markReady() {
        guard !isReady else { return }
        isReady = true
        timeoutTimer?.invalidate()
        hideFailure()
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
        cover.frame = webView.frame
        view.insertSubview(cover, aboveSubview: webView)
        skeletonHost?.didMove(toParent: self)
        skeletonCover = cover
        if let header = pageHeader { view.bringSubviewToFront(header) }
    }

    private func startTimeout() {
        timeoutTimer?.invalidate()
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

    private func showFailure() {
        guard failureHost == nil else { return }
        let host = UIHostingController(rootView: LoadFailureView(background: Color(uiColor: environment.theme.background)) { [weak self] in
            self?.reload()
        })
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        host.view.frame = webView.frame
        failureHost = host
        if let header = pageHeader { view.bringSubviewToFront(header) }
    }

    private func hideFailure() {
        guard let host = failureHost else { return }
        failureHost = nil
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
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
        cancelRefresh()
        isReady = false
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

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
}
