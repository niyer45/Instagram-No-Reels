import UIKit

/// Native Home header: Instagram wordmark on the left (16 pt inset, 103×29 pt box), the
/// notifications heart and Messenger on the right (24 pt glyphs, 20 pt apart, 16 pt trailing
/// inset). Collapses with scroll (HomePageViewController drives its transform and `setCollapse`).
final class HomeHeaderView: UIView {
    static let height: CGFloat = 44

    private let wordmark = WordmarkView()
    private let content = UIView()
    var onActivity: (() -> Void)?
    var onMessages: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let heart = PageHeaderView.iconButton(.heart, label: "Notifications") { [weak self] in self?.onActivity?() }
        let messenger = PageHeaderView.iconButton(.messenger, label: "Messages") { [weak self] in self?.onMessages?() }
        let buttons = UIStackView(arrangedSubviews: [heart, messenger])
        buttons.spacing = 0
        for view in [content, wordmark, buttons] { view.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(content)
        content.addSubview(wordmark)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            wordmark.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            wordmark.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            wordmark.widthAnchor.constraint(equalToConstant: WordmarkView.size.width),
            wordmark.heightAnchor.constraint(equalToConstant: WordmarkView.size.height),
            // 44 pt touch targets around 24 pt glyphs: 10 pt glyph padding + 6 = 16 pt trailing inset.
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            buttons.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            heart.widthAnchor.constraint(equalToConstant: 44), heart.heightAnchor.constraint(equalToConstant: 44),
            messenger.widthAnchor.constraint(equalToConstant: 44), messenger.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The captured wordmark; nil keeps the bundled one.
    func setWordmark(_ shape: WordmarkShape?) { wordmark.shape = shape }

    /// 0 = fully shown, 1 = fully collapsed; fades the content as it slides away (alpha only).
    func setCollapse(_ fraction: CGFloat) { content.alpha = 1 - min(max(fraction, 0), 1) * 1.2 }
}
