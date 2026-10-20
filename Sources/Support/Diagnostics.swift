import Foundation
import OSLog

/// Filter diagnostics. Logs carry counts and an enumerated reason only — never usernames,
/// post content, cookies or request bodies. The cached JSON event log exists in DEBUG only.
enum Diagnostics {
    /// Enumerated filter reasons reported by FeedFilter.js; anything else becomes `unknown`.
    static let acceptedReasons: Set<String> = ["login", "waiting", "filtered", "following-unavailable", "unrecognized-posts", "blocked-route", "no-posts", "unsupported-language"]
    private static let logger = Logger(subsystem: "com.local.following", category: "ContentFilter")

    static func safeReason(_ reason: String?) -> String {
        guard let reason, acceptedReasons.contains(reason) else { return "unknown" }
        return reason
    }

    /// Logs a filter status line (all builds) and records it to the DEBUG event log.
    @MainActor
    static func filterStatus(state: String, shown: Int, hidden: Int, metadata: Int, candidates: Int, reason: String?) {
        let reason = safeReason(reason)
        logger.info("state=\(state, privacy: .public) shown=\(shown, privacy: .public) hidden=\(hidden, privacy: .public) metadata=\(metadata, privacy: .public) reason=\(reason, privacy: .public)")
        #if DEBUG
        record("filter-status", ["shown": shown, "hidden": hidden, "metadata": metadata, "candidates": candidates], labels: ["state": state, "reason": reason])
        #endif
    }

    #if DEBUG
    @MainActor private static var events: [[String: Any]] = []

    /// Records a DEBUG-only event with integer counts and enumerated labels.
    @MainActor
    static func record(_ stage: String, _ counts: [String: Int] = [:], labels: [String: String] = [:]) {
        var event: [String: Any] = counts.mapValues { min(max($0, 0), 100_000) }
        for (key, value) in labels { event[key] = value }
        event["stage"] = stage
        append(event)
    }

    /// Records FeedFilter's structural diagnostics (shapes and counts, no content).
    @MainActor
    static func recordStructure(_ structure: [String: Any]) {
        var event = structure
        event["stage"] = "filter-structure"
        append(event)
    }

    @MainActor
    private static func append(_ event: [String: Any]) {
        events.append(event)
        if events.count > 20 { events.removeFirst() }
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              JSONSerialization.isValidJSONObject(["events": events]),
              let data = try? JSONSerialization.data(withJSONObject: ["events": events], options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("filter-diagnostics.json"), options: [.atomic])
    }
    #endif
}
