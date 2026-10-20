import UIKit
import Combine
import UserNotifications

/// The message-notification feature as the rest of the app sees it: the on/off setting (default off) with
/// its permission request, the baseline, the watcher and the background scheduler. Owned by AppEnvironment.
/// Turning it off, or signing out, cancels the pending refresh and clears the stored baseline.
@MainActor
final class MessageNotifications: ObservableObject {
    /// `userInfo` key holding the tapped notification's thread id.
    static let threadKey = "threadId"
    /// `userInfo` key marking a DEBUG immediate-check notification, which may show while the app is active.
    static let debugKey = "debug"
    private static let enabledKey = "messageNotifications.enabled.v1"

    @Published private(set) var enabled: Bool
    /// The system permission was refused; the toggle explains where to allow it.
    @Published private(set) var permissionDenied = false

    let baseline: InboxBaseline
    let watcher: MessageWatcher
    let scheduler: BackgroundRefreshScheduler
    private let account: AccountStore
    private let defaults: UserDefaults
    private var sessionObservation: AnyCancellable?

    init(factory: WebPageFactory, account: AccountStore, defaults: UserDefaults = .standard) {
        self.account = account
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
        let baseline = InboxBaseline(defaults: defaults)
        let watcher = MessageWatcher(factory: factory, baseline: baseline, account: account,
                                     isEnabled: { defaults.bool(forKey: Self.enabledKey) })
        self.baseline = baseline
        self.watcher = watcher
        scheduler = BackgroundRefreshScheduler(
            isEligible: { [account] in defaults.bool(forKey: Self.enabledKey) && Self.isSignedIn(account) },
            work: { await watcher.run(.background).isSuccess })
    }

    /// A session is assumed until Instagram's own page says otherwise; the cached username is cleared on sign out.
    private static func isSignedIn(_ account: AccountStore) -> Bool {
        account.username != nil && account.session != .signedOut
    }

    /// Called once at launch: keeps the refresh scheduled while the feature is on and the session is signed in.
    func start() {
        sessionObservation = account.$session.sink { [weak self] session in
            // Instagram signed out (expired or another account next): no thread state of that session is kept.
            if session == .signedOut { self?.baseline.clear() }
            // @Published fires before the property changes; look at the store after the change.
            DispatchQueue.main.async { self?.scheduler.schedule() }
        }
        scheduler.schedule()
    }

    /// The settings toggle. Turning on asks for notification permission first; refusing leaves it off.
    func setEnabled(_ on: Bool) async {
        guard on != enabled else { return }
        if on {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else {
                permissionDenied = true
                return
            }
            permissionDenied = false
            enabled = true
            defaults.set(true, forKey: Self.enabledKey)
            scheduler.schedule()
            // Record what is unread now, so existing unread threads are not announced later.
            _ = await watcher.run(.seed)
        } else {
            enabled = false
            permissionDenied = false
            defaults.set(false, forKey: Self.enabledKey)
            scheduler.cancel()
            baseline.clear()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
    }

    /// Sign out: no stored message state remains and nothing stays scheduled (the setting itself is kept).
    func signedOut() {
        scheduler.cancel()
        baseline.clear()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// The Messages tab's own inbox reported its state while the user can see it: those threads are seen,
    /// so they become the baseline and are not announced later.
    func inboxPageDidReport(_ threads: [InboxThread], visible: Bool) {
        guard enabled, visible, UIApplication.shared.applicationState == .active else { return }
        baseline.save(threads)
    }

    /// A thread page is on screen while the app is active: that thread is read, so its next unread state is new
    /// (otherwise a reply after reading it in the app stays unannounced until a background check sees it read).
    func threadSeen(_ id: String) {
        guard enabled, UIApplication.shared.applicationState == .active, let previous = baseline.threads else { return }
        let next = InboxBaseline.markingRead(id, in: previous)
        if next != previous { baseline.save(next) }
    }
}
