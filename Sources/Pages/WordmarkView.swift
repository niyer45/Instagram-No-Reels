import UIKit

/// Draws Instagram's captured wordmark vector, or a text fallback until it is known.
final class WordmarkView: UIView {
    private let fallback = UILabel()

    var shape: WordmarkShape? {
        didSet {
            fallback.isHidden = shape?.bounds != nil
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = "Instagram"
        accessibilityTraits = .header
        fallback.text = "Instagram"
        fallback.font = UIFont(name: "SnellRoundhand-Bold", size: 30) ?? .systemFont(ofSize: 24, weight: .bold)
        fallback.textColor = .label
        fallback.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fallback)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: WordmarkView, _: UITraitCollection) in view.setNeedsDisplay() }
        NSLayoutConstraint.activate([
            fallback.leadingAnchor.constraint(equalTo: leadingAnchor),
            fallback.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize {
        guard let box = shape?.bounds else { return CGSize(width: fallback.intrinsicContentSize.width, height: 29) }
        return CGSize(width: 29 * box.width / box.height, height: 29)
    }

    override func draw(_ rect: CGRect) {
        guard let shape, let box = shape.bounds, let context = UIGraphicsGetCurrentContext() else { return }
        let scale = bounds.height / box.height
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.setFillColor(UIColor.label.resolvedColor(with: traitCollection).cgColor)
        for part in shape.paths {
            guard let path = SVGPath.parse(part.d) else { continue }
            context.addPath(path)
            context.fillPath(using: part.evenOdd ? .evenOdd : .winding)
        }
    }
}
