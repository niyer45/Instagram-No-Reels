import Foundation

/// What an Instagram path shows. Mirrors `classify` in `Resources/Bridge.js`; both are
/// checked against `Tests/route-fixtures.json`, which is the single routing table.
enum RouteKind: String, CaseIterable {
    case home, search, profile, post, comments, likes, inbox, thread, activity
    case stories, settings, login, create, other, blocked
}

/// A classified route: its kind and the identity that distinguishes two pages of that kind
/// (username, post code, thread id or normalised path; empty when the kind has one page).
struct Route: Equatable {
    let kind: RouteKind
    let identity: String

    private static let blocked: Set<String> = ["reel", "reels", "tv", "clips"]
    private static let loginRoots: Set<String> = ["challenge", "checkpoint", "two_factor", "consent", "oauth"]
    private static let loginAccounts: Set<String> = ["login", "emailsignup", "signup", "password", "onetap", "logout", "suspended", "disabled"]
    private static let otherRoots: Set<String> = ["about", "legal", "privacy", "terms", "developer", "web", "emails", "session", "press", "api", "graphql", "ajax", "static", "_u"]
    private static let profileTabs: Set<String> = ["tagged", "saved", "feed"]
    private static let explorePages: Set<String> = ["tags", "locations"]

    init(kind: RouteKind, identity: String = "") {
        self.kind = kind
        self.identity = identity
    }

    /// Classifies a URL path such as `/alice/` or `/p/ABC/comments/`.
    init(path: String) {
        let parts = path.split(separator: "/").map(String.init)
        guard let firstPart = parts.first else { self.init(kind: .home); return }
        let first = firstPart.lowercased()
        let second = parts.count > 1 ? parts[1].lowercased() : ""
        let normal = "/" + parts.joined(separator: "/").lowercased() + "/"
        if Self.blocked.contains(first) { self.init(kind: .blocked); return }
        switch first {
        case "explore":
            // Hashtag and location pages are content pages of their own, not the Search tab.
            if Self.explorePages.contains(second) { self.init(kind: .other, identity: normal); return }
            self.init(kind: .search); return
        case "stories": self.init(kind: .stories); return
        case "create": self.init(kind: .create); return
        case "direct":
            if second == "t", parts.count > 2 { self.init(kind: .thread, identity: parts[2]); return }
            self.init(kind: second.isEmpty || second == "inbox" ? .inbox : .other, identity: second.isEmpty || second == "inbox" ? "" : normal)
            return
        case "accounts":
            if Self.loginAccounts.contains(second) { self.init(kind: .login); return }
            if second == "activity" { self.init(kind: .activity); return }
            self.init(kind: .settings, identity: normal)
            return
        case "notifications": self.init(kind: .activity); return
        case "settings": self.init(kind: .settings, identity: normal); return
        default: break
        }
        if Self.loginRoots.contains(first) { self.init(kind: .login); return }
        let offset = first == "p" ? 1 : (second == "p" && Self.isHandle(first) ? 2 : 0)
        if offset > 0 {
            guard parts.count > offset, Self.isCode(parts[offset]) else { self.init(kind: .other, identity: normal); return }
            let code = parts[offset]
            let rest = parts.count > offset + 1 ? parts[offset + 1].lowercased() : ""
            switch rest {
            case "": self.init(kind: .post, identity: code)
            case "comments", "c": self.init(kind: .comments, identity: code)
            case "liked_by": self.init(kind: .likes, identity: code)
            default: self.init(kind: .other, identity: normal)
            }
            return
        }
        if Self.otherRoots.contains(first) || !Self.isHandle(first) { self.init(kind: .other, identity: normal); return }
        if parts.count == 1 { self.init(kind: .profile, identity: first); return }
        if Self.blocked.contains(second) { self.init(kind: .blocked); return }
        if Self.profileTabs.contains(second), parts.count == 2 { self.init(kind: .profile, identity: first); return }
        self.init(kind: .other, identity: normal)
    }

    init(url: URL) { self.init(path: url.path.isEmpty ? "/" : url.path) }

    private static func isHandle(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 30 && value.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "_"
        }
    }

    private static func isCode(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-"
        }
    }
}
