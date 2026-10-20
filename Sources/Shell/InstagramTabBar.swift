import UIKit

/// Instagram-styled native tab bar: opaque surface, hairline top border, Instagram glyphs
/// (filled when selected) and the signed-in avatar in the Profile slot.
final class InstagramTabBar: UIView {
    static let height: CGFloat = 49

    private var buttons: [TabItem: UIButton] = [:]
    private let hairline = UIView()
    private let stack = UIStackView()
    private var avatar: UIImage?
    private(set) var selected: TabItem = .home
    var onTap: ((TabItem) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        for tab in TabItem.allCases {
            let button = UIButton(type: .custom)
            button.accessibilityLabel = tab.title
            button.tintColor = .label
            button.imageView?.contentMode = .center
            button.addAction(UIAction { [weak self] _ in self?.onTap?(tab) }, for: .touchUpInside)
            buttons[tab] = button
            stack.addArrangedSubview(button)
        }
        addSubview(stack)
        addSubview(hairline)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (bar: InstagramTabBar, _: UITraitCollection) in bar.refresh() }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        stack.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.height)
        hairline.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1 / max(traitCollection.displayScale, 1))
    }

    func select(_ tab: TabItem) {
        selected = tab
        refresh()
    }

    func setAvatar(_ image: UIImage?) {
        avatar = image
        refresh()
    }

    func apply(background: UIColor, hairline color: UIColor) {
        backgroundColor = background
        hairline.backgroundColor = color
    }

    private func refresh() {
        for (tab, button) in buttons {
            let isSelected = tab == selected
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
            if tab == .profile, let avatar {
                button.setImage(Self.avatarImage(avatar, selected: isSelected, ring: UIColor.label.resolvedColor(with: traitCollection)), for: .normal)
            } else {
                button.setImage(tab.glyph(selected: isSelected).image(pointSize: 24), for: .normal)
            }
        }
    }

    /// The avatar as a 26 pt circle; selected adds Instagram's outer ring.
    private static func avatarImage(_ image: UIImage, selected: Bool, ring: UIColor) -> UIImage {
        let size = CGSize(width: 30, height: 30)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let inner = CGRect(x: 2, y: 2, width: 26, height: 26)
            if selected {
                ring.setStroke()
                let outline = UIBezierPath(ovalIn: CGRect(x: 0.75, y: 0.75, width: 28.5, height: 28.5))
                outline.lineWidth = 1.5
                outline.stroke()
            }
            UIBezierPath(ovalIn: inner).addClip()
            let scale = max(inner.width / max(image.size.width, 1), inner.height / max(image.size.height, 1))
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: inner.midX - drawn.width / 2, y: inner.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
        }.withRenderingMode(.alwaysOriginal)
    }
}
