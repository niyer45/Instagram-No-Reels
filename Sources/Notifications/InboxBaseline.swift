import Foundation

/// The last known inbox state (thread id, unread flag, display name), kept in UserDefaults so a later
/// background check can tell which threads are newly unread. Cleared on sign out and when the feature
/// is turned off. `nil` means no baseline exists yet.
struct InboxBaseline {
    private static let key = "messageNotifications.baseline.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var threads: [InboxThread]? {
        guard let data = defaults.data(forKey: Self.key),
              let threads = try? JSONDecoder().decode([InboxThread].self, from: data), InboxThread.isValid(threads) else { return nil }
        return threads
    }

    func save(_ threads: [InboxThread]) {
        guard InboxThread.isValid(threads), let data = try? JSONEncoder().encode(threads) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() { defaults.removeObject(forKey: Self.key) }

    /// Threads unread now that were not unread before (read, or unknown, in `previous`).
    static func newlyUnread(current: [InboxThread], previous: [InboxThread]) -> [InboxThread] {
        let wasUnread = Set(previous.filter(\.unread).map(\.id))
        return current.filter { $0.unread && !wasUnread.contains($0.id) }
    }

    /// `previous` with thread `id` marked read (unchanged when it is absent or already read).
    static func markingRead(_ id: String, in previous: [InboxThread]) -> [InboxThread] {
        previous.map { $0.id == id && $0.unread ? InboxThread(id: $0.id, unread: false, name: $0.name) : $0 }
    }
}
