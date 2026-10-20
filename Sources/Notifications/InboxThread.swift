import Foundation

/// One row of the Messages inbox as reported by Bridge.js (`inboxState`): the thread id from the row's
/// `/direct/t/<id>/` link, whether the row looks unread, and its visible title (a display name). This is
/// also the minimal state kept in UserDefaults between background checks.
struct InboxThread: Codable, Equatable {
    let id: String
    let unread: Bool
    let name: String

    static let maximumCount = 50
    static let maximumNameLength = 80

    /// Thread ids are short URL-safe tokens; anything else is not a thread.
    static func isValidID(_ id: String) -> Bool {
        (1...64).contains(id.utf8.count) && id.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45 || byte == 46 || byte == 95
        }
    }

    /// Whether a decoded batch of threads is acceptable: in range, valid ids, no duplicates.
    static func isValid(_ threads: [InboxThread]) -> Bool {
        threads.count <= maximumCount
            && threads.allSatisfy { isValidID($0.id) && $0.name.count <= maximumNameLength }
            && Set(threads.map(\.id)).count == threads.count
    }
}
