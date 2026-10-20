import Foundation

#if DEBUG
/// DEBUG-only launch environment for simulator screenshots, since agents cannot tap or sign in:
/// `SHELL_TAB=home|search|activity|profile` selects the starting tab,
/// `SHELL_SKELETON_PREVIEW=1` keeps every page on its skeleton (no web loads),
/// `SHELL_OPEN_URL=<instagram url>` opens that URL through the Router after launch.
/// Pass them with `SIMCTL_CHILD_` prefixes to `xcrun simctl launch`. Release builds exclude this.
enum DebugLaunchOptions {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static var tab: TabItem? {
        switch environment["SHELL_TAB"] {
        case "home": return .home
        case "search": return .search
        case "activity": return .activity
        case "profile": return .profile
        default: return nil
        }
    }

    static var skeletonPreview: Bool { environment["SHELL_SKELETON_PREVIEW"] == "1" }

    static var openURL: URL? {
        guard let raw = environment["SHELL_OPEN_URL"], let url = URL(string: raw), RouteDecision.isOfficial(url) else { return nil }
        return url
    }
}
#endif
