import Foundation

@main struct PolicyTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            if !condition() { fatalError(message) }
        }
        func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
        func rejects(_ value: Any) -> Bool { do { _ = try FollowingImport.parse(data(value), sourceName: "following.json"); return false } catch { return true } }
        let valid: [String: Any] = ["relationships_following": [
            ["title": "Alice", "string_list_data": [["href": "https://www.instagram.com/_u/Alice", "timestamp": 123]]],
            ["title": "", "string_list_data": [["href": "https://www.instagram.com/bob/", "value": "bob"]]],
            ["title": "alice", "string_list_data": [["href": "https://www.instagram.com/alice/", "value": "alice"]]]
        ]]
        let parsed = try FollowingImport.parse(data(valid), sourceName: "following.json", now: Date(timeIntervalSince1970: 1000))
        check(parsed.handles == ["alice", "bob"], "Normalized and deduplicated handles")
        check(parsed.importedAt == Date(timeIntervalSince1970: 1000), "Import timestamp")
        check(rejects(["followers": ["alice"]]), "Reject follower list")
        check(rejects(["alice", "bob"]), "Reject arbitrary usernames")
        check(rejects(["relationships_following": []]), "Reject empty following list")
        for link in ["https://evil.com/alice/", "http://www.instagram.com/alice/", "https://www.instagram.com/p/123/", "https://user@www.instagram.com/alice/", "https://www.instagram.com:8443/alice/", "https://www.instagram.com/alice/other/"] {
            check(rejects(["relationships_following": [["string_list_data": [["href": link, "value": "alice"]]]]]), "Reject invalid profile URL: \(link)")
        }
        check(rejects(["relationships_following": [["string_list_data": [["href": "https://www.instagram.com/alice/", "value": "bob"]]]]]), "Reject inconsistent username")
        for invalid in ["foo bar", "foo..bar", "foo.", "<script>", String(repeating: "x", count: 31)] {
            check(FollowingImport.username(invalid) == nil, "Invalid username")
        }
        let allowed = Set(parsed.handles)
        for path in ["/", "/accounts/login/", "/challenge/123/", "/direct/inbox/", "/alice/", "/accounts/edit/", "/stories/alice/123/", "/p/photo/", "/explore/", "/explore/search/"] {
            check(InstagramNavigation.decision(for: URL(string: "https://www.instagram.com" + path)!, following: allowed) == .allow, "Allowed route \(path)")
        }
        for path in ["/reel/123/", "/reels/", "/Reels/", "/tv/123/", "/clips/"] {
            check(InstagramNavigation.decision(for: URL(string: "https://www.instagram.com" + path)!, following: allowed) == .blockReels, "Blocked media route")
        }
        check(InstagramNavigation.decision(for: URL(string: "https://www.instagram.com/stranger/")!, following: allowed) == .allow, "Preserve profile navigation; filter posts in-page")
        for link in ["https://instagram.com.evil.com/", "instagram://reels/", "https://www.instagram.com:8443/", "https://user@www.instagram.com/", "http://www.instagram.com/"] {
            check(InstagramNavigation.decision(for: URL(string: link)!, following: allowed) == .blockExternal, "Unsafe navigation")
        }
        let policyChecks = checks
        try RouteChecks.run { check($0, $1) }
        let routeChecks = checks - policyChecks
        SVGPathChecks.run { check($0, $1) }
        let svgChecks = checks - policyChecks - routeChecks
        InboxChecks.run { check($0, $1) }
        print("Passed \(policyChecks) following-import and navigation checks, \(routeChecks) route-table checks, \(svgChecks) SVG path checks and \(checks - policyChecks - routeChecks - svgChecks) inbox checks.")
    }
}
