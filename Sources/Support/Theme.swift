import UIKit
import Combine

/// Native surface colours, mirrored from the page background reported by the bridge `theme`
/// message so headers, tab bar, skeletons and web views share one surface colour.
@MainActor
final class Theme: ObservableObject {
    /// Instagram's dark surface (#0C1014), used until a page reports its own.
    static let instagramDark = UIColor(red: 12 / 255, green: 16 / 255, blue: 20 / 255, alpha: 1)
    static let link = UIColor(red: 0, green: 149 / 255, blue: 246 / 255, alpha: 1)
    private static let storageKey = "theme.background.v1"

    @Published private(set) var background: UIColor

    init(defaults: UserDefaults = .standard) {
        if let rgb = defaults.array(forKey: Self.storageKey) as? [Double], let color = Self.color(rgb) {
            background = color
        } else {
            background = Self.instagramDark
        }
    }

    /// Whether the current surface is dark; drives the window's interface style.
    var isDark: Bool { Self.luminance(background) < 0.5 }
    var interfaceStyle: UIUserInterfaceStyle { isDark ? .dark : .light }
    /// Hairline separators (tab bar top border, header bottom border).
    var hairline: UIColor { isDark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 0, alpha: 0.12) }

    func update(rgb: [Double], defaults: UserDefaults = .standard) {
        guard let color = Self.color(rgb), !color.isEqual(background) else { return }
        background = color
        defaults.set(rgb, forKey: Self.storageKey)
    }

    private static func color(_ rgb: [Double]) -> UIColor? {
        guard rgb.count == 3, rgb.allSatisfy({ $0.isFinite && (0...255).contains($0) }) else { return nil }
        return UIColor(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255, alpha: 1)
    }

    private static func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
