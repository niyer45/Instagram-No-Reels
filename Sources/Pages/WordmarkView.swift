import UIKit

/// Draws Instagram's wordmark vector (the captured one, else the bundled copy), aspect-fitted to
/// the ink of its paths, left aligned and vertically centred in the view, in the label colour.
final class WordmarkView: UIView {
    /// Native wordmark box on iPhone (the header pins the view to this size).
    static let size = CGSize(width: 103, height: 29)

    private var parsed: [(path: CGPath, evenOdd: Bool)] = []
    private var ink = CGRect.null

    /// The wordmark to draw; nil or an unusable shape falls back to `WordmarkShape.bundled`.
    var shape: WordmarkShape? {
        didSet {
            guard shape != oldValue else { return }
            prepare()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = "Instagram"
        accessibilityTraits = .header
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: WordmarkView, _: UITraitCollection) in view.setNeedsDisplay() }
        prepare()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize { Self.size }

    /// Parses the paths once per shape so drawing (on every theme change) does no parsing.
    private func prepare() {
        let candidate = shape.flatMap { $0.isValid ? $0 : nil } ?? .bundled
        parsed = candidate.paths.compactMap { part in SVGPath.parse(part.d).map { ($0, part.evenOdd) } }
        ink = parsed.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard !ink.isNull, ink.width > 0, ink.height > 0, let context = UIGraphicsGetCurrentContext() else { return }
        let scale = min(bounds.width / ink.width, bounds.height / ink.height)
        let y = (bounds.height - ink.height * scale) / 2
        context.translateBy(x: 0, y: y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -ink.minX, y: -ink.minY)
        context.setFillColor(UIColor.label.resolvedColor(with: traitCollection).cgColor)
        for part in parsed {
            context.addPath(part.path)
            context.fillPath(using: part.evenOdd ? .evenOdd : .winding)
        }
    }
}
