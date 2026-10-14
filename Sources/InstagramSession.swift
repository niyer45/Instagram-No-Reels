import Foundation
import WebKit
import Combine
import SwiftUI
import OSLog
import Darwin

@MainActor
final class InstagramSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    enum Screen: String, CaseIterable { case feed = "Home", inbox = "Messages" }
    enum State: String { case loading, login, filtered, unsupported, needsFollowing, failure }
    @Published var snapshot: FollowingSnapshot
    @Published var state: State = .loading
    @Published var shown = 0
    @Published var hidden = 0
    @Published var message = "Opening Instagram…"
    @Published var screen: Screen = .feed
    @Published var error: String?
    @Published var controlsPresented = false
    @Published var metadataRecords = 0
    @Published var viewingStories = false
    @Published var backgroundColor: UIColor = UIColor(red: 12/255, green: 16/255, blue: 20/255, alpha: 1)
    private var loadingPreviewView: UIImageView?
    private var previewTimeout: Timer?
    @Published var browsing = false
    @Published var profileActive = false
    @Published var searchActive = false
    private var searchPending = false
    private var searchLoaded = false
    private var searchDocumentLoads = 0
    private var searchUsedFallback = false
    private var searchRequestedAt: Date?
    private var searchReadyWait: Double = 0
    private var searchRevealTimeout: Timer?
    private var profileURL: URL?
    private var profileDocumentLoads = 0
    private var profileLoaded = false
    private var feedRefreshing = false
    private var refreshStarted = false
    private var refreshSettling = false
    private var refreshFinishedDocument = false
    private var refreshHold: CGFloat = 0
    private var refreshRequested = false
    @Published var pullOffset: CGFloat = 0
    @Published var isInitialLaunch = true
    private let logger = Logger(subsystem: "com.local.following", category: "ContentFilter")
    let webView: WKWebView
    let storiesWebView: WKWebView
    let browsingWebView: WKWebView
    let profileWebView: WKWebView
    let searchWebView: WKWebView
    @Published var storiesHeight: CGFloat = 0
    @Published var homeHeaderHeight: CGFloat = 56
    @Published var isHomeFeed = true
    @Published var storyViewerOpen = false
    @Published var storiesTop: CGFloat = 56
    @Published var storiesClipTop: CGFloat = 0
    @Published var storiesVisibleHeight: CGFloat = 0
    private var instagramWordmark: String?
    private var loadTimer: Timer?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var mainInterfaceReady = false
    private var storiesInterfaceReady = false
    private var launchRevealScheduled = false
    private var homeDocumentLoads = 0
    private static let storageKey = "followingSnapshot.v1"

    override init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(FollowingSnapshot.self, from: data) {
            snapshot = saved
        } else { snapshot = .empty }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: config)
        let browsingConfig = WKWebViewConfiguration()
        browsingConfig.websiteDataStore = .default()
        browsingConfig.allowsInlineMediaPlayback = true
        browsingConfig.mediaTypesRequiringUserActionForPlayback = .all
        browsingWebView = WKWebView(frame: .zero, configuration: browsingConfig)
        let profileConfig = WKWebViewConfiguration()
        profileConfig.websiteDataStore = .default()
        profileConfig.allowsInlineMediaPlayback = true
        profileConfig.mediaTypesRequiringUserActionForPlayback = .all
        profileWebView = WKWebView(frame: .zero, configuration: profileConfig)
        let searchConfig = WKWebViewConfiguration()
        searchConfig.websiteDataStore = .default()
        searchConfig.allowsInlineMediaPlayback = true
        searchConfig.mediaTypesRequiringUserActionForPlayback = .all
        searchWebView = WKWebView(frame: .zero, configuration: searchConfig)
        let storiesConfig = WKWebViewConfiguration()
        storiesConfig.websiteDataStore = .default()
        storiesConfig.allowsInlineMediaPlayback = true
        storiesConfig.mediaTypesRequiringUserActionForPlayback = .all
        storiesWebView = WKWebView(frame: .zero, configuration: storiesConfig)
        super.init()
        UIApplication.shared.ignoreSnapshotOnNextApplicationLaunch()
        #if DEBUG
        saveDiagnostics(stage: "session-start", values: [:])
        print("[ContentFilter] session-start")
        fflush(stdout)
        #endif
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        config.userContentController.add(WeakScriptHandler(self), name: "followingStatus")
        config.userContentController.add(WeakScriptHandler(self), name: "followingControls")
        config.userContentController.add(WeakScriptHandler(self), name: "followingStoriesPosition")
        config.userContentController.add(WeakScriptHandler(self), name: "followingOpenDestination")
        browsingWebView.navigationDelegate = self
        browsingWebView.uiDelegate = self
        browsingWebView.allowsBackForwardNavigationGestures = true
        browsingWebView.isOpaque = false
        browsingWebView.backgroundColor = backgroundColor
        browsingWebView.scrollView.backgroundColor = backgroundColor
        browsingWebView.scrollView.contentInsetAdjustmentBehavior = .never
        profileWebView.navigationDelegate = self
        profileWebView.uiDelegate = self
        profileWebView.isOpaque = false
        profileWebView.backgroundColor = backgroundColor
        profileWebView.scrollView.backgroundColor = backgroundColor
        profileWebView.scrollView.contentInsetAdjustmentBehavior = .never
        searchWebView.navigationDelegate = self
        searchWebView.uiDelegate = self
        searchWebView.isOpaque = false
        searchWebView.backgroundColor = backgroundColor
        searchWebView.scrollView.backgroundColor = backgroundColor
        searchWebView.scrollView.contentInsetAdjustmentBehavior = .never
        searchConfig.userContentController.add(WeakScriptHandler(self), name: "followingSearchReady")
        for controller in [browsingConfig.userContentController, profileConfig.userContentController, searchConfig.userContentController] {
            for name in ["followingStatus", "followingControls", "followingStoriesPosition", "followingOpenDestination"] {
                controller.add(WeakScriptHandler(self), name: name)
            }
        }
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        webView.scrollView.panGestureRecognizer.addTarget(self, action: #selector(refreshPanChanged(_:)))
        contentOffsetObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            let offset = max(-scrollView.contentOffset.y, 0)
            let dragging = scrollView.isDragging
            Task { @MainActor [weak self] in
                guard let self, !self.refreshSettling else { return }
                if self.feedRefreshing {
                    if dragging && !self.refreshStarted { self.refreshHold = max(self.refreshHold, offset) }
                    self.pullOffset = self.refreshHold
                } else { self.pullOffset = offset }
            }
        }
        #if DEBUG
        webView.isInspectable = true
        #endif
        storiesWebView.navigationDelegate = self
        storiesWebView.uiDelegate = self
        storiesWebView.isOpaque = false
        storiesWebView.backgroundColor = .black
        storiesWebView.scrollView.backgroundColor = .black
        storiesWebView.scrollView.contentInsetAdjustmentBehavior = .never
        storiesWebView.scrollView.bounces = false
        storiesConfig.userContentController.add(WeakScriptHandler(self), name: "followingStoriesReady")
        storiesConfig.userContentController.add(WeakScriptHandler(self), name: "followingOpenStory")
        storiesConfig.userContentController.add(WeakScriptHandler(self), name: "followingNavigate")
        storiesConfig.userContentController.addUserScript(WKUserScript(source: Self.storiesScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        storiesWebView.load(URLRequest(url: URL(string: "https://www.instagram.com/")!))
        installPolicy()
        navigate(.feed)
    }

    private static let storiesScript = #"""
    (()=>{
      let lastViewer=null;const confirmed=new WeakSet();
      function updateViewer(){const open=location.pathname.startsWith('/stories/');style.disabled=open;
        if(open!==lastViewer){lastViewer=open;window.webkit.messageHandlers.followingOpenStory.postMessage({open});}
        if(open){for(const dialog of document.querySelectorAll('[role="dialog"]')){
          if(confirmed.has(dialog)||!/view.*story.*signed.in|signed.in.*view.*story/i.test(dialog.textContent||''))continue;
          const button=[...dialog.querySelectorAll('button,[role="button"]')].find(b=>/^(view story|view|continue)$/i.test((b.textContent||'').trim()));
          if(button){confirmed.add(dialog);button.click();}
        }}
      }
      function forward(value){try{const u=new URL(value,location.href);if(u.protocol!=='https:'||!['instagram.com','www.instagram.com'].includes(u.hostname))return false;
        if(!location.pathname.startsWith('/stories/')&&!u.pathname.startsWith('/stories/')&&(u.pathname!=='/'||u.searchParams.get('variant')==='following')){window.webkit.messageHandlers.followingNavigate.postMessage({url:u.href});return true;}
      }catch(_){}return false;}
      for(const key of ['pushState','replaceState']){const original=history[key];history[key]=function(...args){if(args[2]&&forward(args[2]))return;const result=original.apply(this,args);updateViewer();return result;};}
      document.addEventListener('click',e=>{const a=e.target.closest?.('a[href]');if(a&&forward(a.href)){e.preventDefault();e.stopImmediatePropagation();}},true);
      window.addEventListener('popstate',updateViewer);
      const style=document.createElement('style');style.textContent='body{visibility:hidden!important;overflow:hidden!important}[data-instagram-home-header]{visibility:visible!important;position:fixed!important;top:0!important;left:0!important;width:100%!important;z-index:2147483647!important;isolation:isolate!important;background-color:var(--instagram-background,#000)!important}[data-instagram-story-tray]{visibility:visible!important;position:fixed!important;top:var(--story-top,56px)!important;left:0!important;width:100%!important;z-index:1!important;clip-path:inset(var(--story-clip,0px) 0 0 0)!important}';
      function scan(){
        if(!document.documentElement)return;
        updateViewer();if(lastViewer)return;
        if(!style.parentNode)document.documentElement.appendChild(style);
        const wordmark=document.querySelector('svg[aria-label="Instagram"]');let header=null;
        for(let node=wordmark,depth=0;node&&depth<8;node=node.parentElement,depth++){
          const r=node.getBoundingClientRect();if(r.width>=window.innerWidth*0.8&&r.height>=29&&r.height<=85&&!node.querySelector('a[href^="/stories/"],article'))header=node;
        }
        if(header){for(const old of document.querySelectorAll('[data-instagram-home-header]'))if(old!==header)old.removeAttribute('data-instagram-home-header');header.setAttribute('data-instagram-home-header','');const bg=getComputedStyle(document.body).backgroundColor;header.style.setProperty('--instagram-background',bg==='rgba(0, 0, 0, 0)'?'#000':bg);}
        const items=[...document.querySelectorAll('a[href^="/stories/"],button[aria-label*="story" i],[role="button"][aria-label*="story" i]')];
        let tray=null;
        for(const item of items){let node=item;for(let depth=0;node&&depth<7;depth++,node=node.parentElement){
          const r=node.getBoundingClientRect();
          if(r.height>=40&&r.height<=190&&r.width>=window.innerWidth*0.6&&!node.querySelector('article,a[href*="/p/"],svg[aria-label="Instagram"]'))tray=node;
        }}
        if(tray){for(const old of document.querySelectorAll('[data-instagram-story-tray]'))if(old!==tray)old.removeAttribute('data-instagram-story-tray');if(!tray.hasAttribute('data-instagram-story-tray'))tray.setAttribute('data-instagram-story-tray','');
          window.webkit.messageHandlers.followingStoriesReady.postMessage({height:Math.ceil(tray.getBoundingClientRect().height),items:items.length,headerHeight:header?Math.ceil(header.getBoundingClientRect().height):56,wordmark:document.querySelector('svg[aria-label="Instagram"]')?.outerHTML||null});}
      }
      new MutationObserver(scan).observe(document,{childList:true,subtree:true});document.addEventListener('DOMContentLoaded',scan);scan();
    })();
    """#

    private func revealInitialInterfaceIfReady() {
        guard isInitialLaunch, !launchRevealScheduled, mainInterfaceReady,
              state == .login || storiesInterfaceReady && storiesHeight > 0 && instagramWordmark != nil else { return }
        launchRevealScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let paint = "await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))); return true;"
            _ = try? await self.webView.callAsyncJavaScript(paint, arguments: [:], in: nil, contentWorld: .page)
            if self.state != .login {
                _ = try? await self.storiesWebView.callAsyncJavaScript(paint, arguments: [:], in: nil, contentWorld: .page)
            }
            self.isInitialLaunch = false
            #if DEBUG
            self.saveDiagnostics(stage: "launch-ready", values: ["mainReady": self.mainInterfaceReady, "storiesReady": self.storiesInterfaceReady, "visiblePosts": self.shown])
            if ProcessInfo.processInfo.environment["FOLLOWING_ROUTE_CHECK"] == "1" { await self.checkTabCycle() }
            #endif
        }
    }

    private func showLoadingPreview(_ image: UIImage) {
        removeLoadingPreview()
        let preview = UIImageView(image: image)
        preview.frame = webView.bounds
        preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        preview.contentMode = .scaleToFill
        preview.isUserInteractionEnabled = false
        webView.addSubview(preview)
        loadingPreviewView = preview
        previewTimeout = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in if self?.feedRefreshing != true { self?.removeLoadingPreview() } }
        }
    }

    private func removeLoadingPreview() {
        previewTimeout?.invalidate()
        previewTimeout = nil
        loadingPreviewView?.removeFromSuperview()
        loadingPreviewView = nil
    }

    private func openBrowsing(_ url: URL) {
        if url.path == "/" { restoreHome(); return }
        if url.path == "/explore" || url.path.hasPrefix("/explore/") { openSearch(url); return }
        searchPending = false
        searchActive = false
        if let profileURL, profileURL.path == url.path { openProfile(url, repeatTap: false); return }
        profileActive = false
        isInitialLaunch = false
        launchRevealScheduled = true
        browsing = true
        isHomeFeed = false
        storyViewerOpen = false
        browsingWebView.load(URLRequest(url: url))
        #if DEBUG
        saveDiagnostics(stage: "tab-opened", values: ["homeDocumentLoads": homeDocumentLoads, "homePosts": shown])
        #endif
    }

    private func activateSearch() {
        searchPending = false
        searchRevealTimeout?.invalidate()
        searchActive = true
        profileActive = false
        browsing = true
        isHomeFeed = false
        isInitialLaunch = false
        storyViewerOpen = false
    }

    private func openSearch(_ url: URL) {
        if searchLoaded { activateSearch(); return }
        if searchPending { return }
        searchRequestedAt = Date()
        searchPending = true
        if !searchWebView.isLoading { searchWebView.load(URLRequest(url: url)) }
        searchRevealTimeout?.invalidate()
        searchRevealTimeout = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.searchPending else { return }
                self.searchUsedFallback = true
                self.activateSearch()
            }
        }
    }

    private func openProfile(_ url: URL, repeatTap: Bool) {
        searchPending = false
        searchActive = false
        let alreadySelected = profileActive
        let cached = profileURL?.path == url.path && (profileLoaded || profileWebView.isLoading)
        profileURL = url
        profileActive = true
        browsing = true
        isHomeFeed = false
        isInitialLaunch = false
        storyViewerOpen = false
        if cached {
            if alreadySelected && repeatTap { profileLoaded = false; profileWebView.reload() }
        } else { profileLoaded = false; profileWebView.load(URLRequest(url: url)) }
        #if DEBUG
        saveDiagnostics(stage: "profile-selected", values: ["cached": cached, "repeatTap": alreadySelected && repeatTap, "documentLoads": profileDocumentLoads])
        #endif
    }

    private func restoreHome() {
        searchPending = false
        searchActive = false
        profileActive = false
        browsing = false
        isHomeFeed = true
        storyViewerOpen = false
        isInitialLaunch = false
        state = .filtered
        // The live Home document, its loaded posts and its scroll position survive tab visits.
        webView.evaluateJavaScript("window.dispatchEvent(new Event('following-policy-change'))", completionHandler: nil)
        #if DEBUG
        saveDiagnostics(stage: "home-restored", values: ["reloaded": false, "homeDocumentLoads": homeDocumentLoads, "visiblePosts": shown, "scrollOffset": webView.scrollView.contentOffset.y])
        #endif
    }

    private func searchCaughtUpImageURI() -> String {
        guard let url = Bundle.main.url(forResource: "SearchCaughtUpDark", withExtension: "svg"), let data = try? Data(contentsOf: url) else { return "" }
        return "data:image/svg+xml;base64," + data.base64EncodedString()
    }

    private func installPolicy() {
        guard let path = Bundle.main.url(forResource: "FeedFilter", withExtension: "js"),
              let filter = try? String(contentsOf: path, encoding: .utf8),
              let data = try? JSONSerialization.data(withJSONObject: ["handles": snapshot.handles, "revision": 1, "searchCaughtUpImage": searchCaughtUpImageURI()]),
              let json = String(data: data, encoding: .utf8) else {
            state = .failure
            message = "The feed filter is missing. Rebuild the app with FeedFilter.js included."
            return
        }
        for view in [webView, browsingWebView, profileWebView, searchWebView] {
            let controller = view.configuration.userContentController
            controller.removeAllUserScripts()
            controller.addUserScript(WKUserScript(source: "window.__instagramPinnedSearch = \(view === searchWebView ? "true" : "false");window.__instagramPinnedProfile = \(view === profileWebView ? "true" : "false");window.__followingPolicy = \(json);\n" + filter,
                                                 injectionTime: .atDocumentStart, forMainFrameOnly: true))
            #if DEBUG
            if ProcessInfo.processInfo.environment["FOLLOWING_ROUTE_CHECK"] == "1" {
                let probe = #"""
                (()=>{
                  const result=window.__bootSplashProbe={seen:false,visible:false};let queued=false;
                  function sample(){if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;const node=document.getElementById('splash-screen');if(!node)return;result.seen=true;const css=getComputedStyle(node);const rect=node.getBoundingClientRect();result.visible ||= css.display!=='none'&&css.visibility!=='hidden'&&css.opacity!=='0'&&rect.width>0&&rect.height>0;});}
                  new MutationObserver(sample).observe(document,{subtree:true,childList:true,attributes:true,attributeFilter:['style','class']});sample();
                })();
                """#
                controller.addUserScript(WKUserScript(source: probe, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
            #endif
            view.evaluateJavaScript("window.__followingPolicy = \(json);window.dispatchEvent(new Event('following-policy-change'))", completionHandler: nil)
        }
    }

    func showStories() {
        viewingStories = true
        webView.load(URLRequest(url: URL(string: "https://www.instagram.com/")!))
    }

    func navigate(_ destination: Screen) {
        viewingStories = false
        screen = destination
        if destination == .inbox {
            openBrowsing(URL(string: "https://www.instagram.com/direct/inbox/")!)
            return
        }
        if mainInterfaceReady && webView.url?.path == "/" { restoreHome(); return }
        browsing = false
        shown = 0; hidden = 0
        state = .loading; message = "Opening Instagram…"
        let path = destination == .feed ? "/?variant=following" : "/direct/inbox/"
        webView.load(URLRequest(url: URL(string: "https://www.instagram.com" + path)!))
        startTimeout()
    }

    @objc private func pullToRefresh() {
        beginFeedRefresh()
        refreshRequested = true
        if !webView.scrollView.isDragging { performFeedRefresh() }
    }

    @objc private func refreshPanChanged(_ pan: UIPanGestureRecognizer) {
        if refreshRequested && [.ended, .cancelled, .failed].contains(pan.state) { performFeedRefresh() }
    }

    private func beginFeedRefresh() {
        guard !feedRefreshing else { return }
        isInitialLaunch = false
        feedRefreshing = true
        refreshStarted = false
        refreshFinishedDocument = false
        refreshHold = max(pullOffset, -webView.scrollView.contentOffset.y, 0)
        pullOffset = refreshHold
        state = .loading
    }

    private func performFeedRefresh() {
        guard feedRefreshing, !refreshStarted else { return }
        refreshRequested = false
        refreshHold = max(refreshHold, -webView.scrollView.contentOffset.y, 0)
        pullOffset = refreshHold
        refreshStarted = true
        #if DEBUG
        saveDiagnostics(stage: "refresh-started", values: ["heldDistance": refreshHold])
        #endif
        mainInterfaceReady = false
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self else { return }
            if let image { self.showLoadingPreview(image) }
            self.webView.reload()
            self.startTimeout()
        }
    }

    private func finishFeedRefresh() {
        guard feedRefreshing else { return }
        refreshSettling = true
        feedRefreshing = false
        loadTimer?.invalidate()
        refreshRequested = false
        UIView.performWithoutAnimation {
            webView.scrollView.refreshControl?.endRefreshing()
            webView.scrollView.setContentOffset(.zero, animated: false)
            webView.scrollView.layoutIfNeeded()
        }
        let held = refreshHold
        refreshHold = 0
        withAnimation(.easeOut(duration: 0.25)) { pullOffset = 0 }
        UIView.animate(withDuration: 0.25, animations: {
            self.loadingPreviewView?.transform = CGAffineTransform(translationX: 0, y: -held)
        }) { [weak self] _ in
            guard let self else { return }
            self.removeLoadingPreview()
            self.webView.scrollView.setContentOffset(.zero, animated: false)
            self.pullOffset = 0
            self.refreshSettling = false
        }
        webView.evaluateJavaScript("window.dispatchEvent(new Event('following-policy-change'))", completionHandler: nil)
        #if DEBUG
        saveDiagnostics(stage: "refresh-finished", values: ["heldDistance": held, "visiblePosts": shown])
        #endif
    }

    func refresh() {
        if searchActive { searchLoaded = false; searchWebView.reload(); return }
        if profileActive { profileWebView.reload(); return }
        if browsing { browsingWebView.reload(); return }
        beginFeedRefresh()
        performFeedRefresh()
    }

    func showLogin() {
        searchPending = false
        searchActive = false
        profileActive = false
        mainInterfaceReady = false
        browsing = false
        isHomeFeed = false
        state = .loading
        message = "Opening Instagram sign-in…"
        webView.load(URLRequest(url: URL(string: "https://www.instagram.com/accounts/login/")!))
        startTimeout()
    }

    func importFollowing(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 10 * 1024 * 1024 else { throw FollowingImportError.tooLarge }
            let imported = try FollowingImport.parse(Data(contentsOf: url), sourceName: url.lastPathComponent)
            let data = try JSONEncoder().encode(imported)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
            snapshot = imported
            installPolicy()
            navigate(.feed)
        } catch { self.error = error.localizedDescription }
    }

    func clearFollowing() {
        snapshot = .empty
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        installPolicy(); navigate(.feed)
    }

    func signOut() {
        mainInterfaceReady = false
        browsing = false
        browsingWebView.stopLoading()
        profileWebView.stopLoading()
        searchWebView.stopLoading()
        searchLoaded = false
        searchActive = false
        searchPending = false
        profileURL = nil
        profileLoaded = false
        profileActive = false
        state = .loading; message = "Clearing your local Instagram session…"
        webView.stopLoading()
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.webView.load(URLRequest(url: URL(string: "https://www.instagram.com/accounts/login/")!))
                self.startTimeout()
            }
        }
    }

    #if DEBUG
    private func checkTabCycle() async {
        let initialLoads = homeDocumentLoads
        let remember = "window.__homeCheckFirst = document.querySelector('[data-following-approved=\"yes\"] a[href*=\"/p/\"]')?.getAttribute('href'); return !!window.__homeCheckFirst;"
        _ = try? await webView.callAsyncJavaScript(remember, arguments: [:], in: nil, contentWorld: .page)
        let profileCode = "return [...document.querySelectorAll('[data-instagram-bottom] a[href]')].map(a => new URL(a.href).pathname).find(p => /^\\/[A-Za-z0-9._]+\\/?$/.test(p) && !['/explore/','/reels/','/reels','/explore'].includes(p)) || null;"
        let profile = (try? await webView.callAsyncJavaScript(profileCode, arguments: [:], in: nil, contentWorld: .page)) as? String
        var destinations = [("search", "/explore/")]
        if let profile { destinations.append(("profile", profile)) }
        destinations.append(("messages", "/direct/inbox/"))
        var checks: [[String: Any]] = []
        for (kind, path) in destinations {
            let url = URL(string: "https://www.instagram.com" + path)!
            if kind == "profile" { openProfile(url, repeatTap: false) } else { openBrowsing(url) }
            let targetView = kind == "search" ? searchWebView : profileActive ? profileWebView : browsingWebView
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(100))
                if !targetView.isLoading && (kind != "search" || !searchPending) { break }
            }
            var searchImageReady = true
            var searchFocusClear = true
            if kind == "search" {
                let stateCode = "await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))); const image=document.querySelector('[data-instagram-search-caught-up] img'); const spinners=[...document.querySelectorAll('[role=progressbar],[data-visualcompletion=\"loading-state\"],[aria-label=\"Loading...\"]')].filter(n=>{const s=getComputedStyle(n);const r=n.getBoundingClientRect();return s.display!=='none'&&s.visibility!=='hidden'&&r.width>0&&r.height>0;}); return {imageLoaded:!!image&&image.complete&&image.naturalWidth>0,spinners:spinners.length};"
                let searchState = (try? await searchWebView.callAsyncJavaScript(stateCode, arguments: [:], in: nil, contentWorld: .page)) as? [String: Any]
                searchImageReady = (searchState?["imageLoaded"] as? Bool) == true && (searchState?["spinners"] as? Int) == 0
                let preview: UIImage? = await withCheckedContinuation { continuation in
                    searchWebView.takeSnapshot(with: nil) { image, _ in continuation.resume(returning: image) }
                }
                if let data = preview?.pngData(), let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                    try? data.write(to: folder.appendingPathComponent("search-preview-v042.png"), options: .atomic)
                }
                let focusCode = "const input=document.querySelector('input[placeholder*=\"Search\" i],input[aria-label*=\"Search\" i],input[type=search],[role=combobox]');if(!input)return false;input.focus();input.dispatchEvent(new FocusEvent('focusin',{bubbles:true}));await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));return !document.querySelector('[data-instagram-search-caught-up]');"
                searchFocusClear = (try? await searchWebView.callAsyncJavaScript(focusCode, arguments: [:], in: nil, contentWorld: .page)) as? Bool ?? false
            }
            let splash = (try? await targetView.callAsyncJavaScript("return window.__bootSplashProbe || null;", arguments: [:], in: nil, contentWorld: .page)) as? [String: Any]
            let splashHidden = splash != nil && (splash?["visible"] as? Bool) == false
            restoreHome()
            let verify = "await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))); return document.querySelector('[data-following-approved=\"yes\"] a[href*=\"/p/\"]')?.getAttribute('href') === window.__homeCheckFirst && !!window.__homeCheckFirst;"
            let retained = (try? await webView.callAsyncJavaScript(verify, arguments: [:], in: nil, contentWorld: .page)) as? Bool ?? false
            checks.append(["tab": kind, "sameFirstPost": retained, "sameHomeDocument": homeDocumentLoads == initialLoads, "restored": !browsing && isHomeFeed, "websiteSplashObserved": splash?["seen"] as? Bool ?? false, "websiteSplashHidden": splashHidden, "startupSplashHidden": !isInitialLaunch, "searchImageReady": searchImageReady, "searchFocusClear": searchFocusClear])
        }
        let firstSearchLoads = searchDocumentLoads
        openSearch(URL(string: "https://www.instagram.com/explore/")!)
        let searchCacheResult: [String: Any] = ["passed": searchLoaded && searchActive && searchDocumentLoads == firstSearchLoads && !searchUsedFallback, "initialDocumentLoads": firstSearchLoads, "loadsAfterReturn": searchDocumentLoads, "stableControlReady": searchLoaded, "fallbackUsed": searchUsedFallback, "initialWaitSeconds": searchReadyWait]
        if let data = try? JSONSerialization.data(withJSONObject: searchCacheResult, options: .sortedKeys), let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? data.write(to: folder.appendingPathComponent("search-cache-check.json"), options: .atomic)
        }
        restoreHome()
        if let profile, let url = URL(string: "https://www.instagram.com" + profile) {
            let initial = profileDocumentLoads
            openProfile(url, repeatTap: false)
            let offset = min(CGFloat(120), max(profileWebView.scrollView.contentSize.height - profileWebView.bounds.height, 0))
            profileWebView.scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            let savedOffset = profileWebView.scrollView.contentOffset.y
            restoreHome()
            openBrowsing(URL(string: "https://www.instagram.com/explore/")!)
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(100))
                if !browsingWebView.isLoading { break }
            }
            openProfile(url, repeatTap: false)
            let cachedLoads = profileDocumentLoads
            let scrollRetained = abs(profileWebView.scrollView.contentOffset.y - savedOffset) < 0.5
            openProfile(url, repeatTap: true)
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(100))
                if profileDocumentLoads > initial && !profileWebView.isLoading { break }
            }
            let result: [String: Any] = ["passed": cachedLoads == initial && profileDocumentLoads == initial + 1 && scrollRetained, "loadsBeforeReturn": initial, "loadsAfterReturn": cachedLoads, "loadsAfterRepeatedTap": profileDocumentLoads, "scrollPositionRetained": scrollRetained]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: .sortedKeys), let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                try? data.write(to: folder.appendingPathComponent("profile-cache-check.json"), options: .atomic)
            }
            restoreHome()
        }
        let passed = checks.count == 3 && checks.allSatisfy { ($0["sameFirstPost"] as? Bool) == true && ($0["sameHomeDocument"] as? Bool) == true && ($0["restored"] as? Bool) == true && ($0["websiteSplashHidden"] as? Bool) == true && ($0["startupSplashHidden"] as? Bool) == true && ($0["searchImageReady"] as? Bool) == true && ($0["searchFocusClear"] as? Bool) == true }
        let result: [String: Any] = ["passed": passed, "homeLoadsBefore": initialLoads, "homeLoadsAfter": homeDocumentLoads, "checks": checks]
        saveDiagnostics(stage: "tab-cycle-check", values: result)
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
           let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? data.write(to: folder.appendingPathComponent("navigation-check.json"), options: .atomic)
        }
        if ProcessInfo.processInfo.environment["FOLLOWING_REFRESH_CHECK"] == "1" {
            let held: CGFloat = 140
            webView.scrollView.setContentOffset(CGPoint(x: 0, y: -held), animated: false)
            pullOffset = held
            beginFeedRefresh()
            performFeedRefresh()
            var stable = true
            for _ in 0..<220 {
                if !feedRefreshing { break }
                if abs(pullOffset - held) > 0.5 { stable = false }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(400))
            let refreshResult: [String: Any] = ["heldDistance": held, "heldUntilReady": stable, "completed": !feedRefreshing, "feedReady": mainInterfaceReady, "visiblePosts": shown, "settledTogether": abs(pullOffset) < 0.5 && abs(webView.scrollView.contentOffset.y) < 0.5]
            saveDiagnostics(stage: "refresh-check", values: refreshResult)
            if let data = try? JSONSerialization.data(withJSONObject: refreshResult, options: .sortedKeys),
               let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                try? data.write(to: folder.appendingPathComponent("refresh-check.json"), options: .atomic)
            }
        }
    }

    private var diagnosticEvents: [[String: Any]] = []
    private func saveDiagnostics(stage: String, values: [String: Any]) {
        var event = values
        event["stage"] = stage
        diagnosticEvents.append(event)
        if diagnosticEvents.count > 20 { diagnosticEvents.removeFirst() }
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: ["events": diagnosticEvents], options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("filter-diagnostics.json"), options: [.atomic])
    }
    #endif

    private func startTimeout() {
        loadTimer?.invalidate()
        loadTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .loading || self.feedRefreshing else { return }
                self.state = .unsupported
                self.message = "Instagram’s feed is taking longer to load. Try reloading."
                self.finishFeedRefresh()
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive event: WKScriptMessage) {
        let origin = event.frameInfo.securityOrigin
        #if DEBUG
        let trusted = event.frameInfo.isMainFrame && origin.protocol == "https" && ["instagram.com", "www.instagram.com"].contains(origin.host.lowercased()) && (origin.port == 0 || origin.port == 443)
        if event.name != "followingStoriesPosition" { saveDiagnostics(stage: "bridge-received", values: ["trustedOrigin": trusted, "mainFrame": event.frameInfo.isMainFrame]) }
        #endif
        guard event.frameInfo.isMainFrame, origin.protocol == "https",
              ["instagram.com", "www.instagram.com"].contains(origin.host.lowercased()),
              origin.port == 0 || origin.port == 443 else { return }
        if event.name == "followingSearchReady", userContentController === searchWebView.configuration.userContentController {
            searchLoaded = true
            searchReadyWait = searchRequestedAt.map { Date().timeIntervalSince($0) } ?? 0
            if searchPending { activateSearch() }
            #if DEBUG
            saveDiagnostics(stage: "search-ready", values: ["documentLoads": searchDocumentLoads])
            #endif
            return
        }
        if event.name == "followingOpenDestination", let body = event.body as? [String: Any], let raw = body["url"] as? String, let url = URL(string: raw), InstagramNavigation.decision(for: url, following: Set(snapshot.handles)) == .allow {
            if body["tab"] as? String == "profile" { openProfile(url, repeatTap: true) }
            else { openBrowsing(url) }
            return
        }
        if event.name == "followingStoriesPosition", let body = event.body as? [String: Any], let top = body["top"] as? Double, let floor = body["headerBottom"] as? Double, top.isFinite, floor.isFinite {
            guard !browsing, !feedRefreshing, userContentController === webView.configuration.userContentController else { return }
            let top = min(top, homeHeaderHeight)
            let headerFloor = homeHeaderHeight
            let nextClip = min(max(headerFloor - top, 0), storiesHeight)
            if storiesTop == top && storiesClipTop == nextClip && storiesVisibleHeight == max(storiesHeight - nextClip, 0) { return }
            storiesTop = top
            storiesWebView.evaluateJavaScript("document.documentElement.style.setProperty('--story-top', '\(top)px');document.documentElement.style.setProperty('--story-clip', '\(nextClip)px')", completionHandler: nil)
            storiesClipTop = nextClip
            storiesVisibleHeight = max(storiesHeight - storiesClipTop, 0)
            return
        }
        if event.name == "followingNavigate", let body = event.body as? [String: Any], let raw = body["url"] as? String, let url = URL(string: raw), InstagramNavigation.decision(for: url, following: Set(snapshot.handles)) == .allow {
            storyViewerOpen = false
            if url.path == "/" { restoreHome() } else { openBrowsing(url) }
            return
        }
        if event.name == "followingOpenStory", let body = event.body as? [String: Any], let open = body["open"] as? Bool {
            storyViewerOpen = open
            if !open { webView.evaluateJavaScript("window.dispatchEvent(new Event('following-policy-change'))", completionHandler: nil) }
            return
        }
        if event.name == "followingStoriesReady", let body = event.body as? [String: Any], let height = body["height"] as? Double, height.isFinite, height > 0 {
            storiesInterfaceReady = (body["items"] as? Int ?? 0) > 0 && body["wordmark"] is String
            defer { revealInitialInterfaceIfReady() }
            var wordmarkChanged = false
            if let svg = body["wordmark"] as? String, svg.count < 20000, svg.hasPrefix("<svg"), svg != instagramWordmark {
                wordmarkChanged = true
                instagramWordmark = svg
                if let data = try? JSONSerialization.data(withJSONObject: ["svg": svg]), let json = String(data: data, encoding: .utf8) {
                    webView.evaluateJavaScript("window.__instagramWordmarkSVG = (\(json)).svg;", completionHandler: nil)
                }
            }
            let nextHeader = min(max(body["headerHeight"] as? Double ?? 56, 29), 85)
            let headerChanged = homeHeaderHeight != nextHeader
            homeHeaderHeight = nextHeader
            let nextHeight = min(max(height, 40), 190)
            guard storiesHeight != nextHeight || wordmarkChanged || headerChanged else { return }
            storiesHeight = nextHeight
            webView.evaluateJavaScript("window.__instagramStoriesHeight = \(storiesHeight); window.dispatchEvent(new Event('following-policy-change'))", completionHandler: nil)
            #if DEBUG
            saveDiagnostics(stage: "stories-tray", values: ["height": storiesHeight, "items": body["items"] as? Int ?? 0, "wordmark": instagramWordmark != nil])
            #endif
            return
        }
        if event.name == "followingControls" {
            controlsPresented = true
            return
        }
        if userContentController === browsingWebView.configuration.userContentController || userContentController === profileWebView.configuration.userContentController || userContentController === searchWebView.configuration.userContentController { return }
        guard event.name == "followingStatus", let body = event.body as? [String: Any],
              let raw = body["state"] as? String, let next = State(rawValue: raw),
              [.loading, .login, .filtered, .unsupported, .needsFollowing].contains(next) else { return }
        if let rgb = body["backgroundRGB"] as? [Double], rgb.count == 3, rgb.allSatisfy({ $0.isFinite && (0...255).contains($0) }) {
            let color = UIColor(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255, alpha: 1)
            backgroundColor = color
            webView.backgroundColor = color
            webView.scrollView.backgroundColor = color
            storiesWebView.backgroundColor = color
            storiesWebView.scrollView.backgroundColor = color
        }
        isHomeFeed = !browsing && (body["homeFeed"] as? Bool ?? true)
        if next != .loading && !feedRefreshing { loadTimer?.invalidate() }
        // Early unsupported/empty scans must not dismiss the launch screen.
        state = next
        shown = min(max(body["shown"] as? Int ?? 0, 0), 100000)
        hidden = min(max(body["hidden"] as? Int ?? 0, 0), 100000)
        metadataRecords = min(max(body["metadataRecords"] as? Int ?? 0, 0), 100000)
        mainInterfaceReady = next == .login || (shown > 0 || metadataRecords > 0) && (body["postCandidates"] as? Int ?? 0) > 0
        revealInitialInterfaceIfReady()
        if feedRefreshing {
            if mainInterfaceReady && refreshFinishedDocument { finishFeedRefresh() }
        } else { webView.scrollView.refreshControl?.endRefreshing() }
        // Diagnostics contain counts and an enumerated reason only, never feed
        // contents, usernames, request bodies, passwords or session cookies.
        let reason = body["reason"] as? String ?? "unknown"
        let acceptedReasons = Set(["login", "waiting", "filtered", "following-unavailable", "unrecognized-posts", "blocked-route", "no-posts", "unsupported-language"])
        let safeReason = acceptedReasons.contains(reason) ? reason : "unknown"
        logger.info("state=\(raw, privacy: .public) shown=\(self.shown, privacy: .public) hidden=\(self.hidden, privacy: .public) metadata=\(self.metadataRecords, privacy: .public) reason=\(safeReason, privacy: .public)")
        #if DEBUG
        let candidates = min(max(body["postCandidates"] as? Int ?? 0, 0), 100000)
        let articleCount = min(max(body["articleCount"] as? Int ?? 0, 0), 100000)
        let headerCount = min(max(body["headerCount"] as? Int ?? 0, 0), 100000)
        let h2Count = min(max(body["h2Count"] as? Int ?? 0, 0), 100000)
        let permalinkCount = min(max(body["permalinkCount"] as? Int ?? 0, 0), 100000)
        saveDiagnostics(stage: "filter-status", values: ["state": raw, "shown": shown, "hidden": hidden, "metadata": metadataRecords, "candidates": candidates, "articles": articleCount, "headers": headerCount, "headings": h2Count, "permalinks": permalinkCount, "reason": safeReason])
        print("[ContentFilter] state=\(raw) shown=\(shown) hidden=\(hidden) metadata=\(metadataRecords) candidates=\(candidates) articles=\(articleCount) headers=\(headerCount) headings=\(h2Count) permalinks=\(permalinkCount) reason=\(safeReason)")
        fflush(stdout)
        webView.evaluateJavaScript("typeof window.__instagramFilterDiagnostics === 'function' ? window.__instagramFilterDiagnostics() : null") { [weak self] result, _ in
            guard let structure = result as? [String: Any] else { return }
            Task { @MainActor [weak self] in self?.saveDiagnostics(stage: "filter-structure", values: structure) }
        }
        #endif
        switch next {
        case .login: message = "Sign in directly with Instagram."
        case .filtered: message = shown == 0 && hidden > 0 ? "All loaded posts were excluded by your filters. Reload to check for more posts." : "Your content filters are active."
        case .needsFollowing: message = "Instagram has not supplied follow status for these posts. Import your following list as a fallback."
        case .unsupported: message = "Some post layouts could not be recognized. Instagram’s navigation remains available."
        case .loading: message = "Loading Instagram…"
        default: break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        // Login challenge subframes can originate at Meta-owned hosts; never expose them as top-level navigation.
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if webView === storiesWebView {
            if InstagramNavigation.decision(for: url, following: Set(snapshot.handles)) == .allow {
                if !storyViewerOpen && url.path != "/" && !url.path.hasPrefix("/stories/") {
                    decisionHandler(.cancel)
                    openBrowsing(url)
                } else {
                    storyViewerOpen = url.path.hasPrefix("/stories/")
                    decisionHandler(.allow)
                }
            } else { decisionHandler(.cancel) }
            return
        }
        if InstagramNavigation.decision(for: url, following: Set(snapshot.handles)) == .allow {
            if (webView === browsingWebView || webView === profileWebView || webView === searchWebView) && url.path == "/" {
                decisionHandler(.cancel)
                restoreHome()
                return
            }
            if webView === searchWebView && url.path != "/explore" && !url.path.hasPrefix("/explore/") {
                decisionHandler(.cancel)
                openBrowsing(url)
                return
            }
            if webView === browsingWebView && (url.path == "/explore" || url.path.hasPrefix("/explore/")) {
                decisionHandler(.cancel)
                openSearch(url)
                return
            }
            if webView === profileWebView && url.path != profileURL?.path {
                decisionHandler(.cancel)
                openBrowsing(url)
                return
            }
            if webView === browsingWebView, let profileURL, profileURL.path == url.path {
                decisionHandler(.cancel)
                openProfile(url, repeatTap: false)
                return
            }
            if webView === self.webView && mainInterfaceReady && url.path != "/" {
                decisionHandler(.cancel)
                openBrowsing(url)
                return
            }
        }
        switch InstagramNavigation.decision(for: url, following: Set(snapshot.handles)) {
        case .allow:
            if !viewingStories, url.path == "/", [nil, "home"].contains(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "variant" })?.value) {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: URL(string: "https://www.instagram.com/?variant=following")!))
                return
            }
            decisionHandler(.allow)
        case .blockReels:
            decisionHandler(.cancel)
            error = "Reels are disabled."
        case .blockExternal:
            decisionHandler(.cancel)
            error = "External app redirects are disabled. Sign in directly on Instagram’s login page."
        case .blockUnknown:
            decisionHandler(.cancel)
            error = "This destination is not supported."
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === searchWebView { searchDocumentLoads += 1; return }
        if webView === profileWebView { profileDocumentLoads += 1; return }
        if webView === storiesWebView || webView === browsingWebView { return }
        homeDocumentLoads += 1
        #if DEBUG
        saveDiagnostics(stage: "home-document-load", values: ["count": homeDocumentLoads, "refresh": feedRefreshing])
        #endif
        if feedRefreshing { mainInterfaceReady = false }
        storiesVisibleHeight = 0
        state = .loading; startTimeout()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === storiesWebView { return }
        if webView === browsingWebView || webView === profileWebView || webView === searchWebView {
            if webView === profileWebView { profileLoaded = webView.url?.path == profileURL?.path }
            webView.evaluateJavaScript("window.dispatchEvent(new Event('following-policy-change'))", completionHandler: nil)
            return
        }
        if feedRefreshing {
            refreshFinishedDocument = true
            if mainInterfaceReady { finishFeedRefresh() }
        } else { webView.scrollView.refreshControl?.endRefreshing() }
        if let svg = instagramWordmark, let data = try? JSONSerialization.data(withJSONObject: ["svg": svg]), let json = String(data: data, encoding: .utf8) {
            webView.evaluateJavaScript("window.__instagramWordmarkSVG = (\(json)).svg;", completionHandler: nil)
        }
        // Re-scan after redirects and delayed page setup instead of leaving
        // a stale login/loading status over a successfully loaded page.
        webView.evaluateJavaScript("window.__instagramStoriesHeight = \(storiesHeight); window.dispatchEvent(new Event('following-policy-change'))", completionHandler: nil)
        #if DEBUG
        let summary = "({articles:document.querySelectorAll('article').length, headings:document.querySelectorAll('main h2').length, permalinks:document.querySelectorAll('main a[href*=\"/p/\"]').length, approved:document.querySelectorAll('[data-following-approved=\"yes\"]').length, rejected:document.querySelectorAll('[data-following-approved=\"no\"]').length, jsonScripts:document.querySelectorAll('script[type=\"application/json\"]').length, passwordForm:!!document.querySelector('input[type=\"password\"]')})"
        webView.evaluateJavaScript(summary) { [weak self] result, _ in
            guard let values = result as? [String: Any] else { return }
            let keys = ["articles", "headings", "permalinks", "approved", "rejected", "jsonScripts"]
            let counts = keys.map { "\($0)=\(min(max(values[$0] as? Int ?? 0, 0), 100000))" }.joined(separator: " ")
            let login = values["passwordForm"] as? Bool ?? false
            Task { @MainActor [weak self] in
                var summary: [String: Any] = [:]
                for key in keys { summary[key] = min(max(values[key] as? Int ?? 0, 0), 100000) }
                summary["login"] = login
                self?.saveDiagnostics(stage: "page-finished", values: summary)
            }
            print("[ContentFilter] page-finished \(counts) login=\(login)")
            fflush(stdout)
        }
        webView.evaluateJavaScript("typeof window.__instagramFilterDiagnostics === 'function' ? window.__instagramFilterDiagnostics() : null") { [weak self] result, _ in
            guard let structure = result as? [String: Any] else { return }
            Task { @MainActor [weak self] in self?.saveDiagnostics(stage: "filter-structure", values: structure) }
        }
        #endif
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if webView !== storiesWebView { fail(error) } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if webView !== storiesWebView { fail(error) } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === searchWebView { searchLoaded = false; if searchActive { webView.reload() }; return }
        if webView === profileWebView { profileLoaded = false; if profileActive { webView.reload() }; return }
        if webView === storiesWebView { storiesWebView.reload(); return }
        state = .failure; message = "The Instagram page stopped. Tap retry to reopen it."
    }
    private func fail(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        loadTimer?.invalidate(); isInitialLaunch = false; state = .failure
        finishFeedRefresh()
        message = "Instagram could not load. Check your connection and retry."
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url,
           InstagramNavigation.decision(for: url, following: Set(snapshot.handles)) == .allow {
            webView.load(action.request)
        }
        return nil
    }
}

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
