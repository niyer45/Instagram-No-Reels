import UIKit
import UserNotifications

/// UIKit application entry point. Creates the shared AppEnvironment at launch; SceneDelegate pre-warms
/// Home's web view with it when the scene connects (a background refresh launch has none) and owns the
/// window and shell.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    /// The app's one environment, handed to the scene (created here so WebKit starts early).
    private(set) var environment: AppEnvironment?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        Diagnostics.launchMark("launch")
        #endif
        let environment = AppEnvironment()
        self.environment = environment
        // Message notifications: the refresh handler must be registered before launch finishes, and the
        // notification delegate set now so a tap that launched the app is delivered.
        environment.messages.scheduler.register()
        environment.messages.start()
        UNUserNotificationCenter.current().delegate = self
        #if DEBUG
        // SHELL_INBOX_CHECK=1 runs one check in the foreground a few seconds after launch and posts its notifications
        // even though the app is active (read here, not in DebugLaunchOptions, which is not part of this change).
        if ProcessInfo.processInfo.environment["SHELL_INBOX_CHECK"] == "1" {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                _ = await environment.messages.watcher.run(.debug)
            }
        }
        #endif
        // The live web views hold signed-in content; never reuse a stale launch snapshot.
        application.ignoreSnapshotOnNextApplicationLaunch()
        // Builds up to 0.4.5 used the SwiftUI App lifecycle. A scene session restored from such an
        // install keeps its stored delegate class and never asks for a configuration, so adopt
        // those scenes here; otherwise an in-place upgrade launches to an empty window.
        NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let scene = note.object as? UIWindowScene, !(scene.delegate is SceneDelegate) else { return }
                let delegate = SceneDelegate()
                scene.delegate = delegate
                delegate.connect(scene)
            }
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Message notifications: banners only for the DEBUG immediate check while active, and taps open the Messages tab.
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let debug = notification.request.content.userInfo[MessageNotifications.debugKey] as? Bool == true
        completionHandler(debug ? [.banner, .list, .sound] : [])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let thread = response.notification.request.content.userInfo[MessageNotifications.threadKey] as? String
            environment?.router.openMessages(thread: thread)
        }
        completionHandler()
    }
}
