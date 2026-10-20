import Foundation
import Network
import Combine

/// Whether the device has a usable network path, from `NWPathMonitor`, delivered on the main
/// actor. Drives the native "No internet connection" banner and retrying failed pages on
/// reconnect. Starts optimistic (online) so launch never flashes the banner.
@MainActor
final class Connectivity {
    private let subject = CurrentValueSubject<Bool, Never>(true)
    private let monitor = NWPathMonitor()
    #if DEBUG
    private var forcedOffline = false
    #endif

    /// The current state; prefer the value `changes` emits inside sinks.
    var isOnline: Bool { subject.value }
    /// Emits the current state on subscription and then every change.
    var changes: AnyPublisher<Bool, Never> { subject.removeDuplicates().eraseToAnyPublisher() }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "com.local.following.connectivity", qos: .utility))
        #if DEBUG
        if let seconds = DebugLaunchOptions.offlineSeconds {
            forcedOffline = true
            subject.send(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self else { return }
                self.forcedOffline = false
                self.subject.send(self.monitor.currentPath.status == .satisfied)
            }
        }
        #endif
    }

    deinit { monitor.cancel() }

    private func update(_ online: Bool) {
        #if DEBUG
        if forcedOffline { return }
        #endif
        subject.send(online)
    }
}
