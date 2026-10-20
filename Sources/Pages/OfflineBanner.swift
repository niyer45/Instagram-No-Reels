import UIKit

/// Instagram's "No internet connection" strip: slides in under a page's header while the
/// device is offline and slides away on reconnect. Positioned by WebPageViewController.
final class OfflineBanner: UIView {
    static let height: CGFloat = 32
    static let text = "No internet connection"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.text = Self.text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = false
        addSubview(label)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = Self.text
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 12, dy: 0)
    }

    /// Instagram's banner is a neutral grey that reads on both its dark and light surfaces.
    func apply(isDark: Bool) {
        backgroundColor = isDark ? UIColor(red: 54 / 255, green: 54 / 255, blue: 54 / 255, alpha: 1)
                                 : UIColor(red: 115 / 255, green: 115 / 255, blue: 115 / 255, alpha: 1)
    }
}
