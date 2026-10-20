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
        // The tray never hands login redirects to native: they would replace the Home root (the tray shows itself).
        if role == .tray { return next.kind == .stories || next.kind == .home ? .stay : next.kind == .login ? .block : .native }
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

/// The native presentation for a route (§3.2 of docs/DIRECTION.md). Messages routes belong to the Messages tab:
/// the inbox switches to it, threads and other `/direct/` pages push onto its stack.
enum Presentation: Equatable {
    case homeTab, searchTab, messagesTab, messagesPush, push, fullScreen, replaceRoot, block

    /// A stable name for fixture checks.
    var name: String { String(describing: self) }

    init(route: Route) {
        if route.kind == .other, route.identity.hasPrefix("/direct/") { self = .messagesPush; return }
        self.init(kind: route.kind)
    }

    init(kind: RouteKind) {
        switch kind {
        case .home: self = .homeTab
        case .search: self = .searchTab
        case .stories, .create: self = .fullScreen
        case .login: self = .replaceRoot
        case .blocked: self = .block
        case .inbox: self = .messagesTab
        case .thread: self = .messagesPush
        case .profile, .post, .comments, .likes, .activity, .settings, .other: self = .push
        }
    }
}

/// What happens to a URL outside Instagram's two official hosts: web links the user tapped open in Safari View
/// Controller over the current page, Instagram's `l.instagram.com` link shim is unwrapped, mail/phone links go to the
/// system, and everything else (App Store, `instagram://` and other app redirects, scripted redirects) is dropped
/// silently, like the native app.
enum ExternalLink: Equatable {
    case safari(URL), system(URL), instagram(URL), ignore

    private static let storeHosts = ["apps.apple.com", "itunes.apple.com", "play.google.com", "apps.microsoft.com"]

    static func decide(_ url: URL, userInitiated: Bool) -> ExternalLink {
        guard !RouteDecision.isOfficial(url), let scheme = url.scheme?.lowercased() else { return .ignore }
        if ["mailto", "tel", "sms"].contains(scheme) { return userInitiated ? .system(url) : .ignore }
        guard ["http", "https"].contains(scheme), let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return .ignore }
        if storeHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return .ignore }
        // Instagram's own hosts on the wrong scheme or port are app or tracking redirects, not pages.
        if host == "instagram.com" || host == "www.instagram.com" { return .ignore }
        // Caption and bio links go through the link shim (`?u=<target>`); open the target, never the tracker.
        if host == "l.instagram.com" {
            let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "u" }?.value
            guard let raw, let target = URL(string: raw), target.host != "l.instagram.com" else { return .ignore }
            if RouteDecision.isOfficial(target) { return .instagram(target) }
            return decide(target, userInitiated: true)
        }
        return userInitiated ? .safari(url) : .ignore
    }
}

/// Evidence-based session rules for the Router. Signing in is inferred only from what a page shows (a signed-in page
/// kind that is ready, an avatar or the filtered feed); a navigation away from a login page proves nothing (legal
/// links). Signing out stays explicit (Settings) or comes from login content.
enum SessionEvidence {
    /// Kinds that Instagram only serves to a signed-in session (logged out, they redirect to login).
    static let signedInKinds: Set<RouteKind> = [.home, .inbox, .thread, .activity]
    /// Kinds a login root page opens in place, because they are where Instagram goes after signing in.
    private static let afterLoginKinds: Set<RouteKind> = [.home, .search, .profile, .post, .comments, .likes, .inbox, .thread, .activity]

    /// Whether a page's `ready {kind}` proves a signed-in session.
    static func signsIn(ready: RouteKind, route: Route) -> Bool {
        ready == route.kind && signedInKinds.contains(ready) && !route.isPublicInformation
    }

    /// Whether a tab root showing a login page opens this target in place (instead of pushing it).
    static func opensInPlaceFromLogin(_ target: Route) -> Bool { afterLoginKinds.contains(target.kind) }

    /// Whether a tab root must be rebuilt once the session is signed in: it shows a login page, Instagram's logged-out
    /// landing, or a page other than the tab's own.
    static func rebuildsAfterSignIn(root: Route, isLoginContent: Bool, tabKind: RouteKind) -> Bool {
        root.kind == .login || root.kind != tabKind || (isLoginContent && root.kind == .home)
    }
}
