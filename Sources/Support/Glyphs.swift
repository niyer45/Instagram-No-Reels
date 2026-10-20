import UIKit

/// Instagram-style 24×24 vector glyphs for the tab bar and native headers, drawn from SVG
/// path data with `SVGPath` and rendered as template images so they follow the tint colour.
enum Glyph: CaseIterable {
    case home, homeSelected, search, searchSelected, heart, heartSelected
    case messenger, messengerSelected, person, personSelected, back, menu, compose, close
    case newPost, chevronDown

    private enum Paint { case stroke(CGFloat), fill(evenOdd: Bool), knockout }

    private var layers: [(String, Paint)] {
        switch self {
        case .home:
            return [("M9.005 16.545a2.997 2.997 0 0 1 2.997-2.997A2.997 2.997 0 0 1 15 16.545V22h7V11.543L12 2 2 11.543V22h7.005Z", .stroke(2))]
        case .homeSelected:
            return [("M22 23h-6.001a1 1 0 0 1-1-1v-5.455a2.997 2.997 0 1 0-5.993 0V22a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1V11.543a1.002 1.002 0 0 1 .31-.724l10-9.543a1.001 1.001 0 0 1 1.38 0l10 9.543a1.002 1.002 0 0 1 .31.724V22a1 1 0 0 1-1 1Z", .fill(evenOdd: false))]
        case .search:
            return [("M19 10.5A8.5 8.5 0 1 1 10.5 2a8.5 8.5 0 0 1 8.5 8.5Z", .stroke(2)), ("M16.511 16.511 22 22", .stroke(2))]
        case .searchSelected:
            return [("M18.5 10.5a8 8 0 1 1-8-8 8 8 0 0 1 8 8Z", .stroke(3)), ("M16.511 16.511 21.5 21.5", .stroke(3))]
        case .heart:
            return [("M16.792 3.904A4.989 4.989 0 0 1 21.5 9.122c0 3.072-2.652 4.959-5.197 7.222-2.512 2.243-3.865 3.469-4.303 3.752-.477-.309-2.143-1.823-4.303-3.752C5.141 14.072 2.5 12.167 2.5 9.122a4.989 4.989 0 0 1 4.708-5.218 4.21 4.21 0 0 1 3.675 1.941c.84 1.175.98 1.763 1.12 1.763s.278-.588 1.11-1.766a4.17 4.17 0 0 1 3.679-1.938m0-2a6.04 6.04 0 0 0-4.797 2.127 6.052 6.052 0 0 0-4.787-2.127A6.985 6.985 0 0 0 .5 9.122c0 3.61 2.55 5.827 5.015 7.97.283.246.569.494.853.747l1.027.918a44.998 44.998 0 0 0 3.518 3.018 2 2 0 0 0 2.174 0 45.263 45.263 0 0 0 3.626-3.115l.922-.824c.293-.26.59-.519.885-.774 2.334-2.025 4.98-4.32 4.98-7.94a6.985 6.985 0 0 0-6.708-7.218Z", .fill(evenOdd: true))]
        case .heartSelected:
            return [("M17.075 1.987a5.852 5.852 0 0 0-5.07 2.66l-.008.012-.01-.014a5.878 5.878 0 0 0-5.062-2.658A6.719 6.719 0 0 0 .5 8.952c0 3.514 2.581 5.757 5.077 7.927.302.262.607.527.91.797l1.089.973c2.112 1.89 3.149 2.813 3.642 3.133a1.438 1.438 0 0 0 1.564 0c.472-.306 1.334-1.07 3.755-3.234l.978-.874c.314-.28.631-.555.945-.827 2.478-2.15 5.04-4.372 5.04-7.895a6.719 6.719 0 0 0-6.425-6.965Z", .fill(evenOdd: false))]
        case .messenger:
            return [("M12.003 2.001a9.705 9.705 0 1 1 0 19.4 10.876 10.876 0 0 1-2.895-.384.798.798 0 0 0-.533.04l-1.984.876a.801.801 0 0 1-1.123-.708l-.054-1.78a.806.806 0 0 0-.27-.569 9.49 9.49 0 0 1-3.14-7.175 9.65 9.65 0 0 1 10-9.7Z", .stroke(1.739)),
                    ("M17.79 10.132a.659.659 0 0 0-.962-.873l-2.556 2.05a.63.63 0 0 1-.758.002L11.06 9.47a1.576 1.576 0 0 0-2.277.42l-2.567 3.98a.659.659 0 0 0 .961.875l2.556-2.049a.63.63 0 0 1 .759-.002l2.452 1.84a1.576 1.576 0 0 0 2.278-.42Z", .fill(evenOdd: false))]
        case .messengerSelected:
            // The bubble filled, with the bolt knocked out to transparent.
            return [("M12.003 2.001a9.705 9.705 0 1 1 0 19.4 10.876 10.876 0 0 1-2.895-.384.798.798 0 0 0-.533.04l-1.984.876a.801.801 0 0 1-1.123-.708l-.054-1.78a.806.806 0 0 0-.27-.569 9.49 9.49 0 0 1-3.14-7.175 9.65 9.65 0 0 1 10-9.7Z", .fill(evenOdd: false)),
                    ("M17.79 10.132a.659.659 0 0 0-.962-.873l-2.556 2.05a.63.63 0 0 1-.758.002L11.06 9.47a1.576 1.576 0 0 0-2.277.42l-2.567 3.98a.659.659 0 0 0 .961.875l2.556-2.049a.63.63 0 0 1 .759-.002l2.452 1.84a1.576 1.576 0 0 0 2.278-.42Z", .knockout)]
        case .person:
            return [("M12 12.5a4.25 4.25 0 1 0 0-8.5 4.25 4.25 0 0 0 0 8.5Z", .stroke(1.75)), ("M4.5 21c.7-3.6 3.8-6 7.5-6s6.8 2.4 7.5 6", .stroke(1.75))]
        case .personSelected:
            return [("M12 12.5a4.25 4.25 0 1 0 0-8.5 4.25 4.25 0 0 0 0 8.5Z", .fill(evenOdd: false)), ("M4.5 21c.7-3.6 3.8-6 7.5-6s6.8 2.4 7.5 6Z", .fill(evenOdd: false)), ("M4.5 21c.7-3.6 3.8-6 7.5-6s6.8 2.4 7.5 6", .stroke(1.75))]
        case .back:
            return [("M15 4 7 12l8 8", .stroke(2.25))]
        case .menu:
            return [("M3 4h18M3 12h18M3 20h18", .stroke(2))]
        case .compose:
            return [("M12.202 3.203H5.25a3 3 0 0 0-3 3V18.75a3 3 0 0 0 3 3h12.547a3 3 0 0 0 3-3v-6.952", .stroke(2)),
                    ("M10.002 17.226H6.774v-3.228L18.607 2.165a1.417 1.417 0 0 1 2.004 0l1.224 1.225a1.417 1.417 0 0 1 0 2.004Z", .stroke(2)),
                    ("M16.848 3.924l3.228 3.229", .stroke(2))]
        case .close:
            return [("M4 4 20 20M20 4 4 20", .stroke(2))]
        case .newPost:
            // Instagram's "New post": a rounded square with a plus.
            return [("M2 12v3.45c0 2.849.698 4.005 1.606 4.944.94.909 2.098 1.608 4.946 1.608h6.896c2.848 0 4.006-.7 4.946-1.608C21.302 19.455 22 18.3 22 15.45V8.552c0-2.849-.698-4.006-1.606-4.945C19.454 2.7 18.296 2 15.448 2H8.552c-2.848 0-4.006.699-4.946 1.607C2.698 4.547 2 5.703 2 8.552Z", .stroke(2)),
                    ("M6.545 12.001h10.91M12.003 6.545v10.91", .stroke(2))]
        case .chevronDown:
            return [("M5 9l7 7 7-7", .stroke(2.5))]
        }
    }

    /// A template image of the glyph at the given point size.
    func image(pointSize: CGFloat = 24) -> UIImage {
        let scale = pointSize / 24
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pointSize, height: pointSize))
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.scaleBy(x: scale, y: scale)
            cg.setFillColor(UIColor.black.cgColor)
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for (data, paint) in layers {
                guard let path = SVGPath.parse(data) else { continue }
                cg.addPath(path)
                switch paint {
                case .stroke(let width):
                    cg.setLineWidth(width)
                    cg.strokePath()
                case .fill(let evenOdd):
                    cg.fillPath(using: evenOdd ? .evenOdd : .winding)
                case .knockout:
                    cg.setBlendMode(.clear)
                    cg.fillPath()
                    cg.setBlendMode(.normal)
                }
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
