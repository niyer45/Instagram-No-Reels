import UIKit

/// Light haptics used by the shell: selection ticks on tab changes, a light tap on pushes.
@MainActor
enum Haptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    static func selection() { selectionGenerator.selectionChanged() }
    static func push() { impactGenerator.impactOccurred(intensity: 0.6) }
}
