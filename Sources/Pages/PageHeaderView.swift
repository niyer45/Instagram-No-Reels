import UIKit

/// Native header for non-Home pages: optional back chevron, centred title, optional trailing
/// buttons, and a hairline bottom border. Replaces Instagram's web top bar.
final class PageHeaderView: UIView {
    static let height: CGFloat = 44

    let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let trailingStack = UIStackView()
    private let hairline = UIView()
    var onBack: (() -> Void)?

    init(showsBack: Bool) {
        super.init(frame: .zero)
        backButton.setImage(Glyph.back.image(pointSize: 24), for: .normal)
        backButton.tintColor = .label
        backButton.accessibilityLabel = "Back"
        backButton.isHidden = !showsBack
        backButton.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.accessibilityTraits = .header
        trailingStack.axis = .horizontal
        trailingStack.spacing = 4
        trailingStack.alignment = .center
        for view in [backButton, titleLabel, trailingStack, hairline] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -4),
            trailingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            trailingStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1 / max(UIScreen.main.scale, 1)),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var title: String {
        get { titleLabel.text ?? "" }
        set { titleLabel.text = newValue }
    }

    func setTrailing(_ buttons: [UIButton]) {
        trailingStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for button in buttons {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            trailingStack.addArrangedSubview(button)
        }
    }

    func apply(background: UIColor, hairline color: UIColor) {
        backgroundColor = background
        hairline.backgroundColor = color
    }

    /// A header icon button with a glyph and accessibility label.
    static func iconButton(_ glyph: Glyph, label: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(glyph.image(pointSize: 24), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}
