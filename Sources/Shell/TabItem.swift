import UIKit

/// The shell's tabs in Instagram's native order with the Reels slot removed. Create is
/// replaced by Messages (docs/DIRECTION.md §3.1 records why Create is not possible); Notifications
/// stays reachable from the Home header heart.
enum TabItem: Int, CaseIterable {
    case home, search, messages, profile

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .messages: return "Messages"
        case .profile: return "Profile"
        }
    }

    /// The tab's root route; Profile depends on the signed-in username and has none until known.
    @MainActor func rootURL(account: AccountStore) -> URL? {
        switch self {
        case .home: return URL(string: "https://www.instagram.com/?variant=following")
        case .search: return URL(string: "https://www.instagram.com/explore/")
        case .messages: return URL(string: "https://www.instagram.com/direct/inbox/")
        case .profile: return account.profileURL
        }
    }

    func glyph(selected: Bool) -> Glyph {
        switch self {
        case .home: return selected ? .homeSelected : .home
        case .search: return selected ? .searchSelected : .search
        case .messages: return selected ? .messengerSelected : .messenger
        case .profile: return selected ? .personSelected : .person
        }
    }
}
