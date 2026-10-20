import UIKit
import WebKit

/// Shared app state and services: stores, theme, web view factory and router.
@MainActor
final class AppEnvironment {
    let following = FollowingStore()
    let filterStatus = FilterStatus()
    let account = AccountStore()
    let theme = Theme()
    let webFactory: WebPageFactory
    let router = Router()

    init() {
        webFactory = WebPageFactory(following: following, theme: theme)
        router.environment = self
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
