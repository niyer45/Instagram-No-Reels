import AVFoundation

/// The app's audio session category. WKWebView media otherwise plays under the ambient
/// category, which the ringer switch silences; Instagram's own app uses playback so posts and
/// stories have sound on silent. Only the category is set (once, at scene connect): the session
/// is not activated here, so other apps' audio is untouched until a video is actually unmuted,
/// when WebKit activates it (and, with no mix option, interrupts other audio like Instagram does).
@MainActor
enum AudioSession {
    private static var configured = false

    static func activateForPlayback() {
        guard !configured else { return }
        configured = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        } catch {
            #if DEBUG
            Diagnostics.record("audio-session-failed", ["code": (error as NSError).code])
            #endif
        }
    }
}
