import UIKit

/// UIKit application entry point; the window and shell are owned by SceneDelegate.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
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
