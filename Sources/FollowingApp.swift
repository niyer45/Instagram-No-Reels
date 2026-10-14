import SwiftUI

@main
struct FollowingApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = InstagramSession()
    var body: some Scene {
        WindowGroup {
            FollowingView().environmentObject(session)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { UIApplication.shared.ignoreSnapshotOnNextApplicationLaunch() }
                }
        }
    }
}
