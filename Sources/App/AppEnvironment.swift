import UIKit
import WebKit

/// Shared app state and services: stores, theme, connectivity, web view factory and router.
/// Created once at launch by AppDelegate, which also pre-warms Home's web view through it.
@MainActor
final class AppEnvironment {
    /// Returning from the background after at least this long refreshes Home, like the native
    /// app; shorter returns leave every page and scroll position untouched.
    static let foregroundRefreshInterval: TimeInterval = 30 * 60

    let following = FollowingStore()
    let filterStatus = FilterStatus()
    let account = AccountStore()
    let theme = Theme()
    let connectivity = Connectivity()
    let webFactory: WebPageFactory
    let router = Router()

    init() {
        webFactory = WebPageFactory(following: following, theme: theme)
        router.environment = self
    }

    /// The interval in effect (DEBUG builds can shorten it with `SHELL_STALE_AFTER`).
    var foregroundRefreshInterval: TimeInterval {
        #if DEBUG
        if let seconds = DebugLaunchOptions.staleAfterSeconds { return seconds }
        #endif
        return Self.foregroundRefreshInterval
    }

    /// Starts WebKit and Home's document before the scene and shell exist, so the slow part of a
    /// launch (web content and networking processes, the first request) overlaps building the UI.
    /// Home's page adopts the web view when it is created (`WebPageFactory.makeWebView`).
    func prewarmHome() {
        #if DEBUG
        if DebugLaunchOptions.skeletonPreview || DebugLaunchOptions.failurePreview { return }
        #endif
        guard let url = TabItem.home.rootURL(account: account) else { return }
        // Matches HomePageViewController's boot; fields that differ are corrected on adoption.
        let boot = UserScripts.Boot(role: .page, headerHeight: HomeHeaderView.height, hideChrome: true,
                                    storiesSlot: true, storiesHeight: StoriesTrayHost.defaultHeight)
        webFactory.prewarm(url: url, boot: boot)
    }

    func importFollowing(from url: URL) throws {
        try following.importFile(at: url)
        webFactory.policyDidChange()
    }

    func clearFollowing() {
        following.clear()
        webFactory.policyDidChange()
    }

    /// Clears Instagram's website data for this app and returns every tab to the login page.
    func signOut(completion: @escaping @MainActor () -> Void) {
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in
                self?.account.clear()
                self?.filterStatus.reset()
                completion()
            }
        }
    }
}
