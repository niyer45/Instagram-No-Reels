import Foundation

#if DEBUG
/// DEBUG-only launch environment for simulator screenshots and measurements, since agents
/// cannot tap or sign in. Pass them with `SIMCTL_CHILD_` prefixes to `xcrun simctl launch`
/// (Tools/simshots.sh does). Release builds exclude this.
/// - `SHELL_TAB=home|search|activity|profile` selects the starting tab.
/// - `SHELL_SKELETON_PREVIEW=1` keeps every page on its skeleton (no web loads).
/// - `SHELL_FAILURE_PREVIEW=1` shows every page's load-failure state (no web loads).
/// - `SHELL_OPEN_URL=<instagram url>` opens that URL through the Router after launch.
/// - `SHELL_OPEN_URLS=<url> <url> …` opens each URL in turn, 2 s apart, after launch
///   (deep stacks for the memory cap).
/// - `SHELL_POP=<seconds>` pops the selected stack to its first pushed page that long after launch
///   (with `SHELL_OPEN_URLS`, a page the stack cap unloaded).
/// - `SHELL_OFFLINE=<seconds>` reports no connection for that long after launch (banner).
/// - `SHELL_MEMORY_WARNING=<seconds>` simulates a memory warning that long after launch.
/// - `SHELL_STALE_AFTER=<seconds>` replaces the 30-minute foreground refresh interval.
/// - `SHELL_PRESENT=filters|profile-menu|unread|search-idle|signout` opens a surface agents cannot
///   tap to, 2 s after launch (`Surface`).
/// - `SHELL_HOME_FIXTURE` / `SHELL_HOME_DEMO`: Home's fixture harness (`HomeDemo`).
enum DebugLaunchOptions {
    /// Surfaces `SHELL_PRESENT` opens: the Content filters sheet, the Profile action sheet, the
    /// Notifications dot, the Search caught-up state, and Sign out without its confirmation (to
    /// check that the avatar cache is cleared).
    enum Surface: String {
        case filters, profileMenu = "profile-menu", unread, searchIdle = "search-idle", signOut = "signout"
    }

    static var surface: Surface? { environment["SHELL_PRESENT"].flatMap(Surface.init(rawValue:)) }

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
    static var failurePreview: Bool { environment["SHELL_FAILURE_PREVIEW"] == "1" }

    static var openURL: URL? {
        guard let raw = environment["SHELL_OPEN_URL"], let url = URL(string: raw), RouteDecision.isOfficial(url) else { return nil }
        return url
    }

    static var openURLs: [URL] {
        (environment["SHELL_OPEN_URLS"] ?? "").split(separator: " ").compactMap { URL(string: String($0)) }.filter(RouteDecision.isOfficial)
    }

    static var offlineSeconds: TimeInterval? { seconds("SHELL_OFFLINE") }
    static var memoryWarningSeconds: TimeInterval? { seconds("SHELL_MEMORY_WARNING") }
    static var popSeconds: TimeInterval? { seconds("SHELL_POP") }
    static var staleAfterSeconds: TimeInterval? { seconds("SHELL_STALE_AFTER") }

    private static func seconds(_ key: String) -> TimeInterval? {
        guard let raw = environment[key], let value = TimeInterval(raw), value.isFinite, value >= 0 else { return nil }
        return value
    }
}
#endif
