import UIKit

/// Creates the window and the tab shell around the AppEnvironment that AppDelegate created
/// (and used to pre-warm Home), and keeps the startup splash up until Home reports it is ready
/// (or 10 s pass), then cross-fades into Home. Returning to the foreground after
/// `AppEnvironment.foregroundRefreshInterval` refreshes Home; shorter returns change nothing.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var environment: AppEnvironment?
    private weak var root: RootTabBarController?
    private var backgroundedAt: Date?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        MainActor.assumeIsolated { connect(scene) }
    }

    /// Builds the shell once per scene (also used to adopt scenes restored from older builds).
    @MainActor
    func connect(_ scene: UIWindowScene) {
        guard window == nil else { return }
        AudioSession.activateForPlayback()
        #if DEBUG
        Diagnostics.launchMark("scene")
        #endif
        let environment = (UIApplication.shared.delegate as? AppDelegate)?.environment ?? AppEnvironment()
        // Pre-warm Home here, not in didFinishLaunching: there a scene-based app is always `.background`, so a
        // background refresh launch (no scene, message notifications) cannot be told apart and must not load Home.
        environment.prewarmHome()
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = environment.theme.interfaceStyle
        // The scene's traits are the system's (the window's override does not reach them); web content follows them.
        environment.theme.setSystemStyle(scene.traitCollection.userInterfaceStyle)
        scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak environment] (scene: UIWindowScene, _: UITraitCollection) in
            environment?.theme.setSystemStyle(scene.traitCollection.userInterfaceStyle)
        }
        let root = RootTabBarController(environment: environment)
        window.rootViewController = root
        window.makeKeyAndVisible()
        // The splash waits only for Home (its feed and tray, or the login page) to be ready.
        let splash = SplashView(frame: window.bounds)
        splash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(splash)
        root.onLaunchReady = { [weak splash] in
            #if DEBUG
            Diagnostics.launchMark("splash-dismiss")
            #endif
            splash?.dismiss()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak splash] in
            #if DEBUG
            if splash?.superview != nil { Diagnostics.launchMark("splash-timeout") }
            #endif
            splash?.dismiss()
        }
        self.environment = environment
        self.root = root
        self.window = window
        #if DEBUG
        runDebugLaunchActions(environment: environment)
        #endif
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        UIApplication.shared.ignoreSnapshotOnNextApplicationLaunch()
        backgroundedAt = Date()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        MainActor.assumeIsolated { returnedToForeground() }
    }

    /// After a long absence Home reloads (when it is next on screen), like the native app.
    @MainActor
    private func returnedToForeground() {
        guard let since = backgroundedAt, let environment else { return }
        backgroundedAt = nil
        #if DEBUG
        Diagnostics.record("foreground", ["seconds": Int(Date().timeIntervalSince(since))])
        #endif
        guard Date().timeIntervalSince(since) >= environment.foregroundRefreshInterval else { return }
        #if DEBUG
        Diagnostics.record("foreground-refresh", ["seconds": Int(Date().timeIntervalSince(since))])
        #endif
        root?.homePage?.reloadWhenNextVisible()
    }

    #if DEBUG
    /// Preview modes, `SHELL_OPEN_URLS`, `SHELL_POP` and `SHELL_MEMORY_WARNING` (Sources/Support/DebugLaunchOptions.swift).
    @MainActor
    private func runDebugLaunchActions(environment: AppEnvironment) {
        // Preview modes never make Home ready; reveal them without waiting for the splash timeout.
        if DebugLaunchOptions.skeletonPreview || DebugLaunchOptions.failurePreview {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak root] in root?.onLaunchReady?() }
        }
        for (index, url) in DebugLaunchOptions.openURLs.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + 2 * Double(index)) { [weak environment] in
                environment?.router.open(url, from: nil)
            }
        }
        if let seconds = DebugLaunchOptions.popSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak root] in
                guard let navigation = root?.selectedNavigation, navigation.viewControllers.count > 1 else { return }
                navigation.popToViewController(navigation.viewControllers[1], animated: true)
            }
        }
        if let seconds = DebugLaunchOptions.memoryWarningSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                Diagnostics.record("simulated-memory-warning")
                NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
            }
        }
    }
    #endif
}
