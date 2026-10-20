import Foundation

struct FollowingSnapshot: Codable, Equatable {
    let handles: [String]
    let importedAt: Date
    let sourceName: String

    static let empty = FollowingSnapshot(handles: [], importedAt: .distantPast, sourceName: "")
}

enum FollowingImportError: LocalizedError {
    case tooLarge, unsupported, noAccounts, malformedAccount
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "This file is too large. Select the following.json file from your Instagram information export (up to 10 MB)."
        case .unsupported: return "Select Instagram’s following.json export. Expected relationships_following and string_list_data; arbitrary username lists are not accepted."
        case .noAccounts: return "No followed accounts were found in this export."
        case .malformedAccount: return "An account in this export has an invalid or conflicting username. The import was cancelled."
        }
    }
}

enum FollowingImport {
    static func username(_ input: String) -> String? {
        let name = input.lowercased()
        guard !name.isEmpty, name.count <= 30,
              name.range(of: "^[a-z0-9_][a-z0-9_.]*$", options: .regularExpression) != nil,
              !name.hasSuffix("."), !name.contains("..") else { return nil }
        return name
    }

    static func parse(_ data: Data, sourceName: String, now: Date = Date()) throws -> FollowingSnapshot {
        guard data.count <= 10 * 1024 * 1024 else { throw FollowingImportError.tooLarge }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["relationships_following"] as? [[String: Any]] else {
            throw FollowingImportError.unsupported
        }
        var handles = Set<String>()
        for row in rows {
            guard let entries = row["string_list_data"] as? [[String: Any]], !entries.isEmpty else {
                throw FollowingImportError.malformedAccount
            }
            for entry in entries {
                guard let link = entry["href"] as? String, let url = URL(string: link),
                      url.scheme == "https", let host = url.host?.lowercased(),
                      ["instagram.com", "www.instagram.com"].contains(host),
                      url.user == nil, url.password == nil, url.port == nil else {
                    throw FollowingImportError.malformedAccount
                }
                var parts = url.path.split(separator: "/").map(String.init)
                if parts.first == "_u" { parts.removeFirst() }
                guard parts.count == 1, let fromURL = username(parts[0]) else {
                    throw FollowingImportError.malformedAccount
                }
                // Some exports omit value and store the username in title.
                let supplied = (entry["value"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (row["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                if let supplied, username(supplied) != fromURL { throw FollowingImportError.malformedAccount }
                handles.insert(fromURL)
            }
        }
        guard !handles.isEmpty else { throw FollowingImportError.noAccounts }
        return FollowingSnapshot(handles: handles.sorted(), importedAt: now, sourceName: sourceName)
    }
}

enum NavigationDecision: Equatable { case allow, blockReels, blockExternal, blockUnknown }

enum InstagramNavigation {
    static func decision(for url: URL, following: Set<String>) -> NavigationDecision {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              ["instagram.com", "www.instagram.com"].contains(host),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return .blockExternal }
        let parts = url.path.lowercased().split(separator: "/").map(String.init)
        guard let first = parts.first else { return .allow }
        if ["reel", "reels", "tv", "clips"].contains(first) { return .blockReels }
        // Instagram keeps its own navigation. Filtering is applied to posts,
        // not to account/profile/settings pages as a whole.
        return .allow
    }
}
