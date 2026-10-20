import Foundation

/// Checks the Swift route table and navigation decisions against `Tests/route-fixtures.json`,
/// the same fixture `Tests/bridge.test.cjs` runs against `Resources/Bridge.js`.
enum RouteChecks {
    static func run(_ check: (Bool, String) -> Void) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("route-fixtures.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [[String]]] ?? [:]
        let classify = object["classify"] ?? []
        let decide = object["decide"] ?? []
        check(classify.count > 30 && decide.count > 20, "Route fixtures loaded")
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
        check(Presentation(kind: .stories) == .fullScreen && Presentation(kind: .create) == .fullScreen, "Stories and create present full screen")
        check(Presentation(kind: .login) == .replaceRoot, "Login replaces the root")
        check(Presentation(kind: .blocked) == .block, "Reels routes are blocked")
        for kind in [RouteKind.profile, .post, .comments, .likes, .inbox, .thread, .activity, .settings, .other] {
            check(Presentation(kind: kind) == .push, "Content page \(kind) pushes")
        }
        check(Route(url: URL(string: "https://www.instagram.com")!).kind == .home, "Empty path is Home")
        if let tag = URL(string: "https://www.instagram.com/explore/tags/cats/") {
            check(Presentation(kind: Route(url: tag).kind) == .push, "Hashtag pages push instead of switching to the Search tab")
        }
    }
}
