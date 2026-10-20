import CoreGraphics
import Foundation

/// Instagram's wordmark vector, captured from the signed-in page's `svg[aria-label="Instagram"]`
/// by the Stories tray web view and cached so the native Home header can draw it.
struct WordmarkShape: Codable, Equatable {
    /// One `<path>` of the wordmark.
    struct Part: Codable, Equatable { let d: String; let evenOdd: Bool }

    let viewBox: String
    let paths: [Part]

    /// The viewBox as a rectangle, when it is four finite numbers with a positive size.
    var bounds: CGRect? {
        let numbers = viewBox.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        guard numbers.count == 4, numbers.allSatisfy(\.isFinite), numbers[2] > 0, numbers[3] > 0 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    var isValid: Bool {
        bounds != nil && !paths.isEmpty && paths.count <= 12 && paths.allSatisfy { $0.d.count <= 20_000 && SVGPath.parse($0.d) != nil }
    }

    private static let storageKey = "instagram.wordmark.v1"

    static func cached(defaults: UserDefaults = .standard) -> WordmarkShape? {
        guard let data = defaults.data(forKey: storageKey), let shape = try? JSONDecoder().decode(WordmarkShape.self, from: data), shape.isValid else { return nil }
        return shape
    }

    func cache(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}
