import UIKit

/// Native header of the own-profile tab, laid out like Instagram's: the username in bold on the
/// left with a down chevron (account switcher), and the New post "+" and menu glyphs on the right.
final class ProfileHeaderView: UIView {
    static let height: CGFloat = 44

    private let switcher = UIButton(type: .system)
    private let createButton = UIButton(type: .system)
    let menuButton = UIButton(type: .system)
    var onSwitchAccount: (() -> Void)?
    var onCreate: (() -> Void)?
    var onMenu: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        var config = UIButton.Configuration.plain()
        config.image = Glyph.chevronDown.image(pointSize: 12)
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8)
        config.baseForegroundColor = .label
        config.titleLineBreakMode = .byTruncatingTail
        switcher.configuration = config
        switcher.contentHorizontalAlignment = .leading
        switcher.accessibilityHint = "Switch accounts"
        switcher.addAction(UIAction { [weak self] _ in self?.onSwitchAccount?() }, for: .touchUpInside)
        for (button, glyph, label) in [(createButton, Glyph.newPost, "New post"), (menuButton, Glyph.menu, "Options")] {
            button.setImage(glyph.image(pointSize: 24), for: .normal)
            button.tintColor = .label
            button.accessibilityLabel = label
        }
        createButton.addAction(UIAction { [weak self] _ in self?.onCreate?() }, for: .touchUpInside)
        menuButton.addAction(UIAction { [weak self] _ in self?.onMenu?() }, for: .touchUpInside)
        for view in [switcher, createButton, menuButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            switcher.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            switcher.centerYAnchor.constraint(equalTo: centerYAnchor),
            switcher.heightAnchor.constraint(equalToConstant: 44),
            switcher.trailingAnchor.constraint(lessThanOrEqualTo: createButton.leadingAnchor, constant: -8),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),
            createButton.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -2),
            createButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            createButton.widthAnchor.constraint(equalToConstant: 44),
            createButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        accessibilityElements = [switcher, createButton, menuButton]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var username: String = "" {
        didSet {
            guard username != oldValue else { return }
            var title = AttributedString(username)
            title.font = .systemFont(ofSize: 22, weight: .bold)
            switcher.configuration?.attributedTitle = title
            switcher.accessibilityLabel = username
        }
    }

    func apply(background: UIColor) {
        backgroundColor = background
    }
}
