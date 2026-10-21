import Foundation

/// Checks the Swift route table, navigation decisions and header titles against `Tests/route-fixtures.json`
/// (the same fixture `Tests/bridge.test.cjs` runs against `Resources/Bridge.js`), plus the external-link and
/// session-evidence rules the Router uses.
enum RouteChecks {
    static func run(_ check: (Bool, String) -> Void) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("route-fixtures.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [[String]]] ?? [:]
        let classify = object["classify"] ?? []
        let decide = object["decide"] ?? []
        let titles = object["titles"] ?? []
        let presentations = object["presentations"] ?? []
        check(classify.count > 60 && decide.count > 50 && titles.count > 30 && presentations.count > 10, "Route fixtures loaded")
        for row in classify where row.count == 3 {
            let route = Route(path: row[0])
            check(route.kind.rawValue == row[1] && route.identity == row[2], "Classify \(row[0]) -> \(row[1]) \(row[2]), got \(route.kind) \(route.identity)")
        }
        for row in decide where row.count == 4 {
            guard let current = URL(string: row[0]), let target = URL(string: row[1]), let role = RouteDecision.Role(rawValue: row[2]) else {
                check(false, "Fixture URL \(row)"); continue
            }
            let result = RouteDecision.decide(current: current, target: target, role: role)
            check(result.rawValue == row[3], "Decide \(row[0]) -> \(row[1]) (\(row[2])) = \(row[3]), got \(result)")
        }
        for row in titles where row.count == 5 {
            let title = Route(path: row[0]).title(query: row[1], webTitle: row[2], ownUsername: row[3].isEmpty ? nil : row[3])
            check(title == row[4], "Title \(row[0])\(row[1]) = \"\(row[4])\", got \"\(title)\"")
        }
        for row in object["shapes"] ?? [] where row.count == 2 {
            let shape = RouteShape.of(row[0])
            check(shape == row[1], "Shape \(row[0]) = \(row[1]), got \(shape ?? "nil")")
        }
        check(RouteShape.of("") == nil && !(object["shapes"] ?? []).isEmpty, "Shape fixtures loaded; an empty link has no shape")
        for row in presentations where row.count == 2 {
            let presentation = Presentation(route: Route(path: row[0]))
            check(presentation.name == row[1], "Presentation \(row[0]) = \(row[1]), got \(presentation.name)")
        }
        check(Presentation(kind: .stories) == .fullScreen && Presentation(kind: .create) == .fullScreen, "Stories and create present full screen")
        check(!Route(path: "/create/story/").dismissesBySwipe && Route(path: "/stories/alice/1/").dismissesBySwipe, "The story composer ignores the swipe-down dismissal; the story viewer keeps it")
        check(Route(path: "/p/ABC/") == Route(path: "/alice/p/ABC/") && Route(path: "/p/ABC/") != Route(path: "/p/DEF/"), "A post page is recognised by its code, so closing a composer over it does not push a second copy")
        check(Presentation(kind: .login) == .replaceRoot, "Login replaces the root")
        check(Presentation(kind: .blocked) == .block, "Reels routes are blocked")
        for kind in [RouteKind.profile, .post, .comments, .likes, .activity, .settings, .other] {
            check(Presentation(kind: kind) == .push, "Content page \(kind) pushes")
        }
        check(Presentation(kind: .inbox) == .messagesTab && Presentation(kind: .thread) == .messagesPush, "Inbox switches to the Messages tab; threads push on it")
        check(Route(url: URL(string: "https://www.instagram.com")!).kind == .home, "Empty path is Home")
        if let tag = URL(string: "https://www.instagram.com/explore/tags/cats/") {
            check(Presentation(kind: Route(url: tag).kind) == .push, "Hashtag pages push instead of switching to the Search tab")
        }
        if let keyword = URL(string: "https://www.instagram.com/explore/search/keyword/?q=cats") {
            check(Presentation(kind: Route(url: keyword).kind) == .push, "Keyword results push instead of staying in the Search tab")
        }
        check(Route(path: "/direct/t/1/").hidesTabBar && Route(path: "/direct/new/").hidesTabBar, "Threads and the composer hide the tab bar")
        check(["/direct/inbox/", "/alice/", "/p/ABC/", "/accounts/activity/"].allSatisfy { !Route(path: $0).hidesTabBar }, "Other pages keep the tab bar")
        externalLinks(check)
        sessionEvidence(check)
    }

    private static func externalLinks(_ check: (Bool, String) -> Void) {
        func link(_ raw: String, user: Bool = true) -> ExternalLink { URL(string: raw).map { ExternalLink.decide($0, userInitiated: user) } ?? .ignore }
        let site = URL(string: "https://example.com/shop?a=1")!
        check(link("https://example.com/shop?a=1") == .safari(site), "Tapped web links open in Safari View Controller")
        check(link("https://example.com/shop?a=1", user: false) == .ignore, "Scripted redirects to other sites are dropped")
        check(link("https://l.instagram.com/?u=https%3A%2F%2Fexample.com%2Fshop%3Fa%3D1&e=AT0", user: false) == .safari(site), "Link shim opens its target, not the tracker")
        check(link("https://l.instagram.com/?u=https%3A%2F%2Fwww.instagram.com%2Falice%2F") == .instagram(URL(string: "https://www.instagram.com/alice/")!), "Link shim to Instagram stays in the app")
        check(link("https://l.instagram.com/?u=instagram%3A%2F%2Fuser") == .ignore && link("https://l.instagram.com/") == .ignore, "Link shim without a web target is dropped")
        check(link("https://help.instagram.com/123") == .safari(URL(string: "https://help.instagram.com/123")!), "Instagram help pages open in Safari View Controller")
        for blocked in ["https://apps.apple.com/app/instagram/id389801252", "https://itunes.apple.com/app/id1", "itms-apps://itunes.apple.com/app/id1",
                        "instagram://user?username=alice", "fb://profile", "intent://x", "http://www.instagram.com/alice/", "https://www.instagram.com:8443/",
                        "https://user@example.com/", "about:blank", "javascript:alert(1)"] {
            check(link(blocked) == .ignore, "App and unsafe redirects are dropped silently: \(blocked)")
        }
        check(link("mailto:hi@example.com") == .system(URL(string: "mailto:hi@example.com")!) && link("tel:+15550100", user: false) == .ignore, "Mail and phone links need a tap")
        check(link("https://www.instagram.com/alice/") == .ignore, "Official pages are not external links")
    }

    private static func sessionEvidence(_ check: (Bool, String) -> Void) {
        func route(_ path: String) -> Route { Route(path: path) }
        check(SessionEvidence.signsIn(ready: .home, route: route("/")), "A ready Home feed proves a session")
        check(SessionEvidence.signsIn(ready: .inbox, route: route("/direct/inbox/")) && SessionEvidence.signsIn(ready: .activity, route: route("/accounts/activity/")), "Inbox and Notifications prove a session")
        check(!SessionEvidence.signsIn(ready: .login, route: route("/")), "Logged-out landing is not a session")
        for path in ["/alice/", "/p/ABC/", "/legal/terms/", "/about/", "/web/lite/", "/accounts/password/change/", "/explore/"] {
            let page = route(path)
            check(!SessionEvidence.signsIn(ready: page.kind, route: page), "Public or ambiguous page is no evidence: \(path)")
        }
        check(!SessionEvidence.signsIn(ready: .home, route: route("/legal/terms/")), "A ready kind must match its route")
        check(route("/legal/privacy/").isPublicInformation && route("/web/lite/").isPublicInformation && !route("/alice/followers/").isPublicInformation, "Public information pages")
        for path in ["/", "/alice/", "/direct/inbox/", "/p/ABC/"] {
            check(SessionEvidence.opensInPlaceFromLogin(route(path)), "Login root opens the post-login page in place: \(path)")
        }
        for path in ["/legal/terms/", "/about/", "/accounts/edit/", "/web/lite/", "/accounts/login/", "/reels/"] {
            check(!SessionEvidence.opensInPlaceFromLogin(route(path)), "Login root pushes or keeps: \(path)")
        }
        check(SessionEvidence.rebuildsAfterSignIn(root: route("/accounts/login/"), isLoginContent: true, tabKind: .activity), "Login roots rebuild")
        check(SessionEvidence.rebuildsAfterSignIn(root: route("/"), isLoginContent: true, tabKind: .home), "The logged-out landing rebuilds")
        check(SessionEvidence.rebuildsAfterSignIn(root: route("/"), isLoginContent: false, tabKind: .profile), "A tab showing another tab's page rebuilds")
        check(!SessionEvidence.rebuildsAfterSignIn(root: route("/accounts/activity/"), isLoginContent: true, tabKind: .activity), "A tab on its own page is kept")
        check(!SessionEvidence.rebuildsAfterSignIn(root: route("/"), isLoginContent: false, tabKind: .home), "A signed-in Home is kept")
    }
}
