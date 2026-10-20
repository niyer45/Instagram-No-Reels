import SwiftUI

/// Native failure state in Instagram's style ("Couldn't refresh feed", a short reason and a
/// Retry button), shown when a page fails to load or times out. The page also retries by
/// itself when the connection comes back.
struct LoadFailureView: View {
    let title: String
    let message: String
    let background: Color
    var topInset: CGFloat = 0
    let retry: () -> Void

    /// Instagram's title for a page kind that could not load.
    static func title(for kind: RouteKind) -> String {
        switch kind {
        case .home: return "Couldn't refresh feed"
        case .profile: return "Couldn't load profile"
        case .post: return "Couldn't load post"
        case .comments: return "Couldn't load comments"
        case .likes: return "Couldn't load likes"
        case .activity: return "Couldn't load activity"
        case .inbox, .thread: return "Couldn't load messages"
        case .search: return "Couldn't load search"
        case .settings, .login, .stories, .create, .other, .blocked: return "Couldn't load page"
        }
    }

    static func message(offline: Bool) -> String {
        offline ? "No internet connection. You'll see more when you're back online." : "Something went wrong. Tap Retry to try again."
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                Color.clear.frame(height: topInset)
                VStack(spacing: 0) {
                    ZStack {
                        Circle().strokeBorder(Color.primary, lineWidth: 2)
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 62, height: 62)
                    .padding(.bottom, 16)
                    .accessibilityHidden(true)
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 8)
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                    Button(action: retry) {
                        Text("Retry")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .frame(minWidth: 88, minHeight: 34)
                            .background(Color(red: 0, green: 149 / 255, blue: 246 / 255), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry")
                    .accessibilityHint("Loads the page again")
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
