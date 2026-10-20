import UIKit

/// Creates the window, the shared AppEnvironment and the tab shell, and keeps the startup
/// splash up until Home reports it is ready (or 10 s pass), then cross-fades into Home.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var environment: AppEnvironment?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        MainActor.assumeIsolated { connect(scene) }
    }

    /// Builds the shell once per scene (also used to adopt scenes restored from older builds).
    @MainActor
    func connect(_ scene: UIWindowScene) {
        guard window == nil else { return }
        let environment = AppEnvironment()
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = environment.theme.interfaceStyle
        let root = RootTabBarController(environment: environment)
        window.rootViewController = root
        window.makeKeyAndVisible()
        let splash = SplashView(frame: window.bounds)
        splash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(splash)
        root.onLaunchReady = { [weak splash] in splash?.dismiss() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak splash] in splash?.dismiss() }
        self.environment = environment
        self.window = window
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        UIApplication.shared.ignoreSnapshotOnNextApplicationLaunch()
    }
}
