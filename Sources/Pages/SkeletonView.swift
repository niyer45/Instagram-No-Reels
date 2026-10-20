import SwiftUI

/// Layout families for loading placeholders; chosen by the page controller from its page kind.
enum SkeletonLayout: Equatable { case feed, profile, search, list, inbox }

/// Shimmering Instagram-style placeholder shown until a page reports ready.
struct SkeletonView: View {
    let layout: SkeletonLayout
    let background: Color      // page surface colour; the view fills itself with it edge to edge
    var topInset: CGFloat = 0  // empty space reserved at the top (native header height)
    var storiesRow = false     // Home: a row of story rings above the feed cards

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let period: TimeInterval = 1.3

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            GeometryReader { geo in
                let width = geo.size.width
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let progress = CGFloat(t.truncatingRemainder(dividingBy: period) / period)
                    shimmering(width: width, progress: progress)
                }
                .padding(.top, topInset)
                .frame(width: width, height: geo.size.height, alignment: .top)
                .clipped()
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    @ViewBuilder
    private func shimmering(width: CGFloat, progress: CGFloat) -> some View {
        let bandWidth = max(width * 0.6, 1)
        ZStack(alignment: .topLeading) {
            SkeletonShapes(layout: layout, width: width, fill: Color.primary.opacity(0.09), storiesRow: storiesRow)
            if !reduceMotion {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, Color.primary.opacity(0.08), .clear],
                        startPoint: .leading,
                        endPoint: .trailing))
                    .frame(width: bandWidth)
                    .frame(maxHeight: .infinity)
                    .offset(x: -bandWidth + (width + bandWidth) * progress)
                    .frame(width: width, alignment: .topLeading)
                    .mask(alignment: .topLeading) {
                        SkeletonShapes(layout: layout, width: width, fill: .black, storiesRow: storiesRow)
                    }
            }
        }
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The placeholder blocks for a layout, drawn in a single fill colour (also used as the shimmer mask).
private struct SkeletonShapes: View {
    let layout: SkeletonLayout
    let width: CGFloat
    let fill: Color
    var storiesRow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if storiesRow { stories }
            switch layout {
            case .feed: feed
            case .profile: profile
            case .search: search
            case .list: list
            case .inbox: inbox
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func bar(_ w: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(fill).frame(width: w, height: h)
    }

    private func circle(_ d: CGFloat) -> some View {
        Circle().fill(fill).frame(width: d, height: d)
    }

    private func avatarRow(avatar: CGFloat, top: (CGFloat, CGFloat), bottom: (CGFloat, CGFloat),
                           spacing: CGFloat, height: CGFloat, trailing: Bool = false) -> some View {
        HStack(spacing: 12) {
            circle(avatar)
            VStack(alignment: .leading, spacing: spacing) {
                bar(top.0, top.1)
                bar(bottom.0, bottom.1)
            }
            Spacer(minLength: 0)
            if trailing {
                RoundedRectangle(cornerRadius: 8).fill(fill).frame(width: 88, height: 30)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: height)
    }

    // MARK: Stories

    private var stories: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(spacing: 8) {
                    circle(66)
                    bar(46, 8)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .frame(width: width, height: 106, alignment: .topLeading)
        .clipped()
    }

    // MARK: Feed

    private var feed: some View {
        ForEach(0..<2, id: \.self) { _ in
            HStack(spacing: 10) {
                circle(32)
                VStack(alignment: .leading, spacing: 6) {
                    bar(110, 10)
                    bar(70, 8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)

            Rectangle().fill(fill).frame(width: width, height: width)

            HStack(spacing: 16) {
                circle(24)
                circle(24)
                circle(24)
                Spacer(minLength: 0)
                circle(24)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            VStack(alignment: .leading, spacing: 8) {
                bar(140, 10)
                bar(240, 10)
                bar(90, 8)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
    }

    // MARK: Profile

    private var profile: some View {
        // Grid tiles are 3:4 portraits like the skinned page (NativeSkin.css Profile).
        let cell = max((width - 2) / 3, 1)
        return Group {
            HStack(spacing: 0) {
                circle(86)
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 6) {
                        bar(28, 14)
                        bar(52, 10)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                bar(120, 12)
                bar(200, 10)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8).fill(fill).frame(height: 32)
                RoundedRectangle(cornerRadius: 8).fill(fill).frame(height: 32)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            HStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { _ in circle(62) }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)

            VStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 1) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle().fill(fill).frame(width: cell, height: cell * 4 / 3)
                        }
                    }
                }
            }
            .frame(width: width, alignment: .leading)
            .padding(.top, 16)
        }
    }

    // MARK: Search

    private var search: some View {
        Group {
            RoundedRectangle(cornerRadius: 10).fill(fill)
                .frame(height: 36)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            ForEach(0..<9, id: \.self) { _ in
                avatarRow(avatar: 44, top: (130, 10), bottom: (90, 8), spacing: 6, height: 60)
            }
        }
    }

    // MARK: List

    private var list: some View {
        ForEach(0..<10, id: \.self) { _ in
            avatarRow(avatar: 44, top: (160, 10), bottom: (100, 8), spacing: 6, height: 64, trailing: true)
        }
    }

    // MARK: Inbox

    private var inbox: some View {
        Group {
            HStack {
                bar(90, 14)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            ForEach(0..<10, id: \.self) { _ in
                avatarRow(avatar: 56, top: (120, 11), bottom: (180, 9), spacing: 8, height: 72)
            }
        }
    }
}
