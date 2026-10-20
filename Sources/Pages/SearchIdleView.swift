import SwiftUI

/// Native "You're all caught up" state shown below the web search field while Search is idle.
/// Same artwork and type as Instagram's caught-up card (and the feed card in NativeSkin.css):
/// a 78 pt gradient ring with a check, a 20 pt semibold title and 14 pt secondary text,
/// centred horizontally in the space below the field, a third of the way down.
struct SearchIdleView: View {
    private static let gradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0xfe / 255, green: 0xda / 255, blue: 0x75 / 255), location: 0),
            .init(color: Color(red: 0xfa / 255, green: 0x7e / 255, blue: 0x1e / 255), location: 0.3),
            .init(color: Color(red: 0xd6 / 255, green: 0x29 / 255, blue: 0x76 / 255), location: 0.65),
            .init(color: Color(red: 0x96 / 255, green: 0x2f / 255, blue: 0xbf / 255), location: 1),
        ],
        startPoint: .bottomLeading,
        endPoint: .topTrailing)

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            ZStack {
                Circle().strokeBorder(Self.gradient, lineWidth: 2.5)
                CheckMark()
                    .stroke(Self.gradient, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 78, height: 78)

            Text("You're all caught up")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 20)

            Text("You've seen all new posts from the past 2 days.")
                .font(.system(size: 14))
                .foregroundStyle(Color(white: 168 / 255))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, 8)
            Spacer(minLength: 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// The check of Instagram's caught-up artwork (`M26 40.5l9.5 9.5 17-20` in a 78 × 78 box).
private struct CheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 78
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 26 * scale, y: rect.minY + 40.5 * scale))
        p.addLine(to: CGPoint(x: rect.minX + 35.5 * scale, y: rect.minY + 50 * scale))
        p.addLine(to: CGPoint(x: rect.minX + 52.5 * scale, y: rect.minY + 30 * scale))
        return p
    }
}
