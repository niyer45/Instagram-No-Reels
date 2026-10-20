import Foundation

/// A decoded page -> native message (`{type, ...}` on the `instagram` handler; protocol in
/// docs/DIRECTION.md §3.4). Decoding is strict: wrong types or out-of-range values drop the
/// message; unknown fields are ignored.
enum BridgeMessage: Equatable {
    case route(path: String, search: String, title: String)
    case navigate(URL)
    case ready(RouteKind)
    case status(FilterStatusPayload)
    case theme(rgb: [Double])
    case avatar(url: URL, username: String)
    case storyViewer(open: Bool)
    case storiesTray(height: Double, items: Int)
    case storiesSlot(top: Double)
    case searchIdle(idle: Bool, top: Double)
    case searchFocus
    case wordmark(WordmarkShape)
    case openControls

    private struct Envelope: Decodable { let type: String }
    private struct RouteBody: Decodable { let path: String; let search: String; let title: String? }
    private struct URLBody: Decodable { let url: String }
    private struct KindBody: Decodable { let kind: String }
    private struct ThemeBody: Decodable { let backgroundRGB: [Double] }
    private struct AvatarBody: Decodable { let url: String; let username: String }
    private struct OpenBody: Decodable { let open: Bool }
    private struct TrayBody: Decodable { let height: Double; let items: Int }
    private struct TopBody: Decodable { let top: Double }
    private struct IdleBody: Decodable { let idle: Bool; let top: Double }

    private static let maximumBytes = 128 * 1024

    static func decode(_ body: Any) -> BridgeMessage? {
        guard let object = body as? [String: Any], JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object), data.count <= maximumBytes else { return nil }
        let decoder = JSONDecoder()
        func read<T: Decodable>(_ type: T.Type) -> T? { try? decoder.decode(type, from: data) }
        guard let envelope = read(Envelope.self) else { return nil }
        switch envelope.type {
        case "route":
            guard let value = read(RouteBody.self), value.path.hasPrefix("/"), value.path.count <= 2048, value.search.count <= 4096 else { return nil }
            return .route(path: value.path, search: value.search, title: String((value.title ?? "").prefix(80)))
        case "navigate":
            guard let value = read(URLBody.self), value.url.count <= 4096, let url = URL(string: value.url), RouteDecision.isOfficial(url) else { return nil }
            return .navigate(url)
        case "ready":
            guard let value = read(KindBody.self), let kind = RouteKind(rawValue: value.kind) else { return nil }
            return .ready(kind)
        case "status":
            return read(FilterStatusPayload.self).map(BridgeMessage.status)
        case "theme":
            guard let value = read(ThemeBody.self), value.backgroundRGB.count == 3,
                  value.backgroundRGB.allSatisfy({ $0.isFinite && (0...255).contains($0) }) else { return nil }
            return .theme(rgb: value.backgroundRGB)
        case "avatar":
            guard let value = read(AvatarBody.self), let url = URL(string: value.url), isAvatarHost(url),
                  let username = FollowingImport.username(value.username) else { return nil }
            return .avatar(url: url, username: username)
        case "storyViewer":
            return read(OpenBody.self).map { .storyViewer(open: $0.open) }
        case "storiesTray":
            guard let value = read(TrayBody.self), value.height.isFinite, (0...400).contains(value.height), (0...1000).contains(value.items) else { return nil }
            return .storiesTray(height: value.height, items: value.items)
        case "storiesSlot":
            guard let value = read(TopBody.self), value.top.isFinite, (0...5000).contains(value.top) else { return nil }
            return .storiesSlot(top: value.top)
        case "searchIdle":
            guard let value = read(IdleBody.self), value.top.isFinite, (0...2000).contains(value.top) else { return nil }
            return .searchIdle(idle: value.idle, top: value.top)
        case "searchFocus":
            return .searchFocus
        case "wordmark":
            return read(WordmarkShape.self).flatMap { $0.isValid ? .wordmark($0) : nil }
        case "openControls":
            return .openControls
        default:
            return nil
        }
    }

    /// Avatar images come from Instagram's CDN only.
    static func isAvatarHost(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), url.user == nil else { return false }
        return ["cdninstagram.com", "fbcdn.net"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
