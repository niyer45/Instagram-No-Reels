import UIKit

/// Native Home header: Instagram wordmark on the left (16 pt inset, 103×29 pt box), the
/// notifications heart on the right (24 pt glyph in a 44 pt touch target, 16 pt trailing inset). Collapses with scroll (HomePageViewController drives its transform and `setCollapse`).
final class HomeHeaderView: UIView {
    static let height: CGFloat = 44

    private let wordmark = WordmarkView()
    private let content = UIView()
    private let activityBadge = UIView()
    var onActivity: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let heart = PageHeaderView.iconButton(.heart, label: "Notifications") { [weak self] in self?.onActivity?() }
        activityBadge.backgroundColor = InstagramTabBar.badgeColor
        activityBadge.layer.cornerRadius = 2.5
        activityBadge.isHidden = true
        activityBadge.isUserInteractionEnabled = false
        activityBadge.frame = CGRect(x: 19.5, y: 35, width: 5, height: 5)
        heart.addSubview(activityBadge)
        for view in [content, wordmark, heart] { view.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(content)
        content.addSubview(wordmark)
        content.addSubview(heart)
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
            heart.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            heart.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            heart.widthAnchor.constraint(equalToConstant: 44), heart.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Instagram's unread-activity dot, centred under the heart glyph like the tab bar's dots.
    func setActivityBadge(_ visible: Bool) { activityBadge.isHidden = !visible }

    /// The captured wordmark; nil keeps the bundled one.
    func setWordmark(_ shape: WordmarkShape?) { wordmark.shape = shape }

    /// 0 = fully shown, 1 = fully collapsed; fades the content as it slides away (alpha only).
    func setCollapse(_ fraction: CGFloat) { content.alpha = 1 - min(max(fraction, 0), 1) * 1.2 }
}
