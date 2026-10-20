import Foundation
import Combine

/// The Home feed filter's latest status, shown in the Content filters sheet.
@MainActor
final class FilterStatus: ObservableObject {
    @Published private(set) var state: FilterState = .loading
    @Published private(set) var shown = 0
    @Published private(set) var hidden = 0
    @Published private(set) var metadataRecords = 0

    var message: String {
        switch state {
        case .loading: return "Loading Instagram…"
        case .login: return "Sign in directly with Instagram."
        case .filtered: return shown == 0 && hidden > 0 ? "All loaded posts were excluded by your filters. Reload to check for more posts." : "Your content filters are active."
        case .needsFollowing: return "Instagram has not supplied follow status for these posts. Import your following list as a fallback."
        case .unsupported: return "Some post layouts could not be recognized. Instagram’s navigation remains available."
        }
    }

    func apply(_ payload: FilterStatusPayload) {
        state = payload.state
        shown = payload.shown
        hidden = payload.hidden
        metadataRecords = payload.metadataRecords
        Diagnostics.filterStatus(state: payload.state.rawValue, shown: payload.shown, hidden: payload.hidden, metadata: payload.metadataRecords, candidates: payload.postCandidates, reason: payload.reason)
    }

    func reset() {
        state = .loading
        shown = 0
        hidden = 0
        metadataRecords = 0
    }
}
