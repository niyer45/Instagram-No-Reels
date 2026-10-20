import Foundation
import Combine

/// The optional imported following list (`following.json` fallback), persisted locally and
/// handed to FeedFilter.js as its policy.
@MainActor
final class FollowingStore: ObservableObject {
    private static let storageKey = "followingSnapshot.v1"
    @Published private(set) var snapshot: FollowingSnapshot
    private let defaults: UserDefaults
    private var revision = 1

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(FollowingSnapshot.self, from: data) {
            snapshot = saved
        } else {
            snapshot = .empty
        }
    }

    /// The policy object FeedFilter.js reads (`handles`, `revision`).
    var policy: [String: Any] { ["handles": snapshot.handles, "revision": revision] }

    var policyJSON: String {
        guard let data = try? JSONSerialization.data(withJSONObject: policy), let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    func importFile(at url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 10 * 1024 * 1024 else { throw FollowingImportError.tooLarge }
        let imported = try FollowingImport.parse(Data(contentsOf: url), sourceName: url.lastPathComponent)
        defaults.set(try JSONEncoder().encode(imported), forKey: Self.storageKey)
        revision += 1
        snapshot = imported
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
        revision += 1
        snapshot = .empty
    }
}
