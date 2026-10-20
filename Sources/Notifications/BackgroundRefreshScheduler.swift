import UIKit
import BackgroundTasks

/// Schedules and runs the `BGAppRefreshTask` that checks the inbox. iOS decides when (and whether) it
/// runs; the request only sets the earliest time, 15 minutes ahead. Every run and every move to the
/// background schedules the next one, and the task's expiration handler cancels the running check.
@MainActor
final class BackgroundRefreshScheduler {
    static let identifier = "com.local.following.inbox-refresh"
    static let interval: TimeInterval = 15 * 60

    private let isEligible: @MainActor () -> Bool
    private let work: @MainActor () async -> Bool

    /// `isEligible`: the feature is on and the session is signed in. `work`: one check; returns whether it succeeded.
    init(isEligible: @escaping @MainActor () -> Bool, work: @escaping @MainActor () async -> Bool) {
        self.isEligible = isEligible
        self.work = work
    }

    /// Registers the launch handler. Must run before `didFinishLaunching` returns.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self else { task.setTaskCompleted(success: false); return }
                self.handle(task)
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
    }

    /// Replaces the pending request with one 15 minutes out; none when the feature is off or signed out.
    func schedule() {
        let scheduler = BGTaskScheduler.shared
        scheduler.cancel(taskRequestWithIdentifier: Self.identifier)
        guard isEligible() else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.interval)
        do {
            try scheduler.submit(request)
            record("scheduled")
        } catch {
            // The simulator always refuses; on a device this is Background App Refresh being off.
            record("schedule-failed")
        }
    }

    func cancel() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier) }

    private func handle(_ task: BGTask) {
        schedule()
        var completed = false
        let running = Task { @MainActor [work] in
            let success = await work()
            guard !completed else { return }
            completed = true
            task.setTaskCompleted(success: success)
        }
        // The system calls this on an arbitrary queue; cancelling the Task is thread safe, and the
        // cancelled check ends (tearing its web view down) and completes the task on the main actor.
        task.expirationHandler = { running.cancel() }
    }

    private func record(_ reason: String) {
        #if DEBUG
        Diagnostics.record("inbox-refresh", labels: ["reason": reason])
        #endif
    }
}
