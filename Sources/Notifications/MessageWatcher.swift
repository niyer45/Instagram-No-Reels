import UIKit
import WebKit
import UserNotifications

/// One check for new direct messages: loads the inbox in a hidden web view (`InboxProbe`), compares its
/// unread threads with the stored baseline, posts one local notification per newly unread thread and
/// stores the new baseline. Never posts while the app is active, except for the DEBUG immediate check.
/// Logs counts and enumerated reasons only; names and thread ids appear only in the notification itself.
@MainActor
final class MessageWatcher {
    enum Mode: String {
        /// Background refresh: notify, but only when the app is not active; the first run without a baseline just records it.
        case background
        /// DEBUG immediate check: notify even though the app is active, treating a missing baseline as empty.
        case debug
        /// Records the baseline without notifying (when the feature is turned on).
        case seed
    }

    enum Outcome: Equatable {
        case completed(notified: Int)
        case skipped, signedOut, failed, cancelled

        /// Whether the run counts as successful for `BGTask.setTaskCompleted`.
        var isSuccess: Bool { self != .failed && self != .cancelled }
    }

    private let factory: WebPageFactory
    private let baseline: InboxBaseline
    private let account: AccountStore
    /// Whether the feature is on (read at the start and again before anything is posted or stored).
    private let isEnabled: @MainActor () -> Bool
    private let center = UNUserNotificationCenter.current()
    private var isRunning = false

    init(factory: WebPageFactory, baseline: InboxBaseline, account: AccountStore, isEnabled: @escaping @MainActor () -> Bool) {
        self.factory = factory
        self.baseline = baseline
        self.account = account
        self.isEnabled = isEnabled
    }

    /// The feature is on and the session is not known to be signed out (the DEBUG check ignores the setting).
    private func mayProceed(_ mode: Mode) -> Bool {
        mode == .debug || (isEnabled() && account.session != .signedOut)
    }

    func run(_ mode: Mode) async -> Outcome {
        guard !isRunning else { return .skipped }
        isRunning = true
        defer { isRunning = false }
        if mode == .background, UIApplication.shared.applicationState == .active || !mayProceed(mode) { return finish(mode, .skipped) }
        if mode != .seed, !(await canNotify(requestIfNeeded: mode == .debug)) { return finish(mode, .skipped) }

        let result = await InboxProbe(factory: factory).run()
        switch result {
        case .cancelled:
            return finish(mode, .cancelled)
        case .failed, .timedOut:
            return finish(mode, .failed, timedOut: result == .timedOut)
        case .signedOut:
            account.markSignedOut()
            return finish(mode, .signedOut)
        case .threads(let current):
            // The user opened the app while the check ran: they can see their messages; announce nothing.
            if mode == .background, UIApplication.shared.applicationState == .active { return finish(mode, .skipped, current: current) }
            // Turned off or signed out while the check ran: store nothing, announce nothing.
            guard mayProceed(mode) else { return finish(mode, .skipped, current: current) }
            let previous = baseline.threads
            let fresh: [InboxThread]
            switch mode {
            case .seed: fresh = []
            case .background: fresh = previous.map { InboxBaseline.newlyUnread(current: current, previous: $0) } ?? []
            case .debug: fresh = InboxBaseline.newlyUnread(current: current, previous: previous ?? [])
            }
            for thread in fresh { await post(thread, debug: mode == .debug) }
            baseline.save(current)
            return finish(mode, .completed(notified: fresh.count), current: current, fresh: fresh.count)
        }
    }

    /// Whether notifications are allowed; the DEBUG check may ask once (the settings toggle asks otherwise).
    private func canNotify(requestIfNeeded: Bool) async -> Bool {
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined, requestIfNeeded {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        return [.authorized, .provisional, .ephemeral].contains(status)
    }

    private func post(_ thread: InboxThread, debug: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = thread.name.isEmpty ? "New message" : "New message from \(thread.name)"
        content.sound = .default
        content.threadIdentifier = "direct-messages"
        var info: [String: Any] = [MessageNotifications.threadKey: thread.id]
        if debug { info[MessageNotifications.debugKey] = true }
        content.userInfo = info
        let request = UNNotificationRequest(identifier: "direct-thread-\(thread.id)", content: content, trigger: nil)
        try? await center.add(request)
    }

    /// DEBUG event log: counts and an enumerated outcome only.
    /// `scene` (0/1) tells a background launch without a scene from one with the app's window present.
    private func finish(_ mode: Mode, _ outcome: Outcome, current: [InboxThread] = [], fresh: Int = 0, timedOut: Bool = false) -> Outcome {
        #if DEBUG
        let label: String
        switch outcome {
        case .completed: label = "completed"
        case .skipped: label = "skipped"
        case .signedOut: label = "signed-out"
        case .failed: label = timedOut ? "timed-out" : "failed"
        case .cancelled: label = "cancelled"
        }
        Diagnostics.record("inbox-check", ["threads": current.count, "unread": current.filter(\.unread).count, "new": fresh,
                                           "scene": UIApplication.shared.connectedScenes.isEmpty ? 0 : 1],
                           labels: ["mode": mode.rawValue, "outcome": label])
        #endif
        return outcome
    }

    #if DEBUG
    /// Writes the `inbox-ready` page outline (structure only, no text) of an inbox web view, then calls `completion`.
    /// The signed-in inbox markup has never been observed; this is how it is pulled from a device if detection is wrong.
    static func captureOutline(of webView: WKWebView, source: String, completion: (@MainActor () -> Void)? = nil) {
        let script = "window.__instagram&&window.__instagram.outline?window.__instagram.outline():null"
        webView.evaluateJavaScript(script) { result, _ in
            Task { @MainActor in
                if let outline = result as? [String: Any] {
                    Diagnostics.writeOutline(outline, native: ["source": source], capture: "inbox-ready")
                }
                completion?()
            }
        }
    }
    #endif
}
