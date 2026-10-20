import SwiftUI

/// Native "You're all caught up" state shown below the web search field while Search is idle.
struct SearchIdleView: View {
    private static let gradient = LinearGradient(
        colors: [
            Color(red: 0xfe / 255, green: 0xda / 255, blue: 0x75 / 255),
            Color(red: 0xfa / 255, green: 0x7e / 255, blue: 0x1e / 255),
            Color(red: 0xd6 / 255, green: 0x29 / 255, blue: 0x76 / 255),
            Color(red: 0x96 / 255, green: 0x2f / 255, blue: 0xbf / 255)
        ],
        startPoint: .bottomLeading,
        endPoint: .topTrailing)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().strokeBorder(Self.gradient, lineWidth: 2.5)
                CheckMark()
                    .stroke(Self.gradient, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 78, height: 78)

            Text("You're all caught up")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 24)

            Text("You've seen all new posts from the past 2 days.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// Check mark path expressed in fractions of its bounding box.
private struct CheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.33, y: rect.minY + rect.height * 0.52))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.47, y: rect.minY + rect.height * 0.66))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.minY + rect.height * 0.38))
        return p
    }
}
