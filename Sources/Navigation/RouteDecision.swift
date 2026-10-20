import Foundation

/// How a navigation inside a web view is carried out. Mirrors `decide` in `Resources/Bridge.js`
/// (fixture-checked): stay in the page, hand it to the native Router, block it, or let the
/// navigation policy decide (non-Instagram URLs).
enum RouteDecision: String, Equatable {
    case stay, native, block, pass

    /// Which web view role the navigation starts from.
    enum Role: String { case page, tray }

    private static let flowKinds: Set<RouteKind> = [.login, .stories, .create]

    static func decide(current: URL?, target: URL, role: Role = .page) -> RouteDecision {
        guard isOfficial(target) else { return .pass }
        let next = Route(url: target)
        if next.kind == .blocked { return .block }
        if role == .tray { return next.kind == .stories || next.kind == .home ? .stay : .native }
        guard let current else { return .native }
        let now = Route(url: current)
        if now.kind != next.kind { return .native }
        if flowKinds.contains(now.kind) { return .stay }
        return now.identity == next.identity ? .stay : .native
    }

    static func isOfficial(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return ["instagram.com", "www.instagram.com"].contains(host) && url.user == nil && url.password == nil && url.port == nil
    }
}

/// The native presentation for a route kind (§3.2 of docs/DIRECTION.md).
enum Presentation: Equatable {
    case homeTab, searchTab, push, fullScreen, replaceRoot, block

    init(kind: RouteKind) {
        switch kind {
        case .home: self = .homeTab
        case .search: self = .searchTab
        case .stories, .create: self = .fullScreen
        case .login: self = .replaceRoot
        case .blocked: self = .block
        case .profile, .post, .comments, .likes, .inbox, .thread, .activity, .settings, .other: self = .push
        }
    }
}
