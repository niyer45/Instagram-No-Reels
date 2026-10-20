import Foundation

/// FeedFilter.js filter states (`status.state`).
enum FilterState: String, Decodable {
    case loading, login, filtered, unsupported, needsFollowing
}

/// The `status` bridge message: FeedFilter.js counts and state. Unknown fields are ignored;
/// counts are clamped. The structural counts are only used by DEBUG diagnostics.
struct FilterStatusPayload: Decodable, Equatable {
    let state: FilterState
    let shown: Int
    let hidden: Int
    let metadataRecords: Int
    let postCandidates: Int
    let reason: String?
    let homeFeed: Bool

    private enum CodingKeys: String, CodingKey { case state, shown, hidden, metadataRecords, postCandidates, reason, homeFeed }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) throws -> Int { min(max(try values.decode(Int.self, forKey: key), 0), 100_000) }
        state = try values.decode(FilterState.self, forKey: .state)
        shown = try count(.shown)
        hidden = try count(.hidden)
        metadataRecords = try count(.metadataRecords)
        postCandidates = try count(.postCandidates)
        reason = try values.decodeIfPresent(String.self, forKey: .reason)
        homeFeed = try values.decodeIfPresent(Bool.self, forKey: .homeFeed) ?? false
    }

    /// Matches the old launch reveal rule: content recognised, or Instagram's login page.
    var feedReady: Bool { state == .login || (shown > 0 || metadataRecords > 0) && postCandidates > 0 }
}
