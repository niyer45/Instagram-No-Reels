import SwiftUI

/// Native "Couldn't load" state with a retry action, shown when a page times out.
struct LoadFailureView: View {
    let background: Color
    var topInset: CGFloat = 0
    let retry: () -> Void

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                Color.clear.frame(height: topInset)
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                    Text("Couldn't load")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Check your connection and try again.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button(action: retry) {
                        Text("Tap to retry")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0, green: 149 / 255, blue: 246 / 255))
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: retry)
    }
}
