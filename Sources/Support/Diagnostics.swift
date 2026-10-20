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

    // MARK: Launch timing

    /// Milestones of this launch in ms since `didFinishLaunching` (mark `launch`), first
    /// occurrence of each only (DEBUG): logged and written to Caches/launch-timing.json for
    /// Tools/launch-timing.sh. `process` is how long the process existed before that (large
    /// when iOS pre-warmed it).
    @MainActor private static var launchMarks: [(name: String, ms: Int)] = []
    @MainActor private static var launchStart: Date?

    /// Records a launch milestone such as `launch`, `scene`, `home-load` or `home-ready`.
    @MainActor
    static func launchMark(_ name: String) {
        guard !launchMarks.contains(where: { $0.name == name }) else { return }
        let now = Date()
        if launchStart == nil {
            launchStart = now
            launchMarks.append(("process", Int((now.timeIntervalSince(processStart) * 1000).rounded())))
        }
        let ms = Int((now.timeIntervalSince(launchStart ?? now) * 1000).rounded())
        launchMarks.append((name, ms))
        logger.debug("launch \(name, privacy: .public) \(ms, privacy: .public) ms")
        let marks = launchMarks.map { ["name": $0.name, "ms": $0.ms] as [String: Any] }
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: ["marks": marks], options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("launch-timing.json"), options: [.atomic])
    }

    /// When the kernel started this process.
    private static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return Date() }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }()

    // MARK: Page outlines

    private static let outlineCaptures: Set<String> = ["ready", "ready-3s", "refresh-start", "refresh-loading", "refresh-end", "scrolled"]
    @MainActor private static var outlineSequence: Int?

    /// Sequence number of an outline file name (`page-outline-<capture>-<n>.json`).
    private static func outlineNumber(_ name: String) -> Int? {
        guard name.hasPrefix("page-outline-"), name.hasSuffix(".json") else { return nil }
        let stem = name.dropLast(".json".count)
        guard let last = stem.split(separator: "-").last else { return nil }
        return Int(last)
    }

    /// Writes a sanitized page outline (structure only) to Caches/page-outline-<capture>-<n>.json and keeps the 12 newest.
    /// `n` continues after the highest number already on disk, so relaunches do not overwrite earlier files.
    @MainActor
    static func writeOutline(_ outline: [String: Any], native: [String: Any] = [:], capture: String) {
        guard outlineCaptures.contains(capture),
              let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = ((try? manager.contentsOfDirectory(atPath: directory.path)) ?? []).compactMap { name in outlineNumber(name).map { (name, $0) } }
        let n = outlineSequence ?? ((existing.map { $0.1 }.max() ?? 0) + 1)
        outlineSequence = n + 1
        var document: [String: Any] = ["capture": capture, "n": n, "time": ISO8601DateFormatter().string(from: Date()), "page": outline]
        for (key, value) in native { document[key] = value }
        guard JSONSerialization.isValidJSONObject(document),
              let data = try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .prettyPrinted]) else { return }
        try? data.write(to: directory.appendingPathComponent("page-outline-\(capture)-\(n).json"), options: [.atomic])
        let all = existing + [("page-outline-\(capture)-\(n).json", n)]
        for (name, _) in all.sorted(by: { $0.1 > $1.1 }).dropFirst(12) {
            try? manager.removeItem(at: directory.appendingPathComponent(name))
        }
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
