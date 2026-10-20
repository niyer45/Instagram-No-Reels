import CoreGraphics
import Foundation

/// Checks for `SVGPath`, driven by a caller-supplied assertion closure.
enum SVGPathChecks {
    /// Runs the checks through the supplied `check(condition, message)` closure.
    static func run(_ check: (Bool, String) -> Void) {
        func bbox(_ d: String) -> CGRect? { SVGPath.parse(d)?.boundingBoxOfPath }
        func near(_ r: CGRect?, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Bool {
            guard let r = r else { return false }
            let tol = 0.01
            return abs(Double(r.minX) - x) < tol && abs(Double(r.minY) - y) < tol
                && abs(Double(r.width) - w) < tol && abs(Double(r.height) - h) < tol
        }

        check(near(bbox("M2 2H22V22H2Z"), 2, 2, 20, 20), "absolute rect bbox")
        check(near(bbox("M2 2h20v20h-20z"), 2, 2, 20, 20), "relative rect bbox")
        check(near(bbox("M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0"), 2, 2, 20, 20), "two-arc circle bbox")
        check(near(bbox("M2 12a10 10 0 1020 0"), 2, 12, 20, 10), "compact arc flags parse (large=1, sweep=0, then 20 0)")
        check(near(bbox("M0 0 10 10"), 0, 0, 10, 10), "implicit lineto after moveto")
        check(near(bbox("M0 0l1 2 3 4"), 0, 0, 4, 6), "implicit relative lineto repeat")
        check(near(bbox("m5 5 10 10"), 5, 5, 10, 10), "relative moveto then implicit relative lineto")
        check(near(bbox("M0 0C0 10 10 10 10 0S20 0 20 0"), 0, -40.0 / 9.0, 20, 7.5 + 40.0 / 9.0), "smooth cubic reflects control point")
        check(near(bbox("M0 0C0 10 10 10 10 0L20 0S30 0 30 0"), 0, 0, 30, 7.5), "smooth cubic after line uses current point")
        check(near(bbox("M0 0Q5 10 10 0T20 0"), 0, -5, 20, 10), "smooth quadratic reflects control point")
        check(near(bbox("M0 0L10 0T20 0"), 0, 0, 20, 0), "smooth quadratic after line uses current point")
        check(near(bbox("M1e1 1E1L2e1 2.5e1"), 10, 10, 10, 15), "scientific notation")
        check(near(bbox("M0 0L1e-3 0"), 0, 0, 0.001, 0), "negative exponent")
        check(near(bbox("M-.5 .5.5.5"), -0.5, 0.5, 1, 0), "leading-dot and adjacent numbers")
        check(near(bbox("M1-2L3-4"), 1, -4, 2, 2), "minus as separator")
        check(near(bbox("M0,0 L10,5"), 0, 0, 10, 5), "comma separators")
        check(near(bbox("M0 0H10 20V5 8"), 0, 0, 20, 8), "repeated H and V")
        check(near(bbox("M0 0L10 0ZL0 10"), 0, 0, 10, 10), "lineto after close starts from subpath start")
        check(near(bbox("M0 0A0 5 0 0 1 10 0"), 0, 0, 10, 0), "zero radius arc becomes a line")
        check(near(bbox("M0 0A1 1 0 0 1 10 0"), 0, -5, 10, 5), "undersized radii are scaled up")
        check(SVGPath.parse("M5 5A3 3 0 0 1 5 5") != nil, "identical arc endpoints are skipped")
        check(SVGPath.parse("X1 2") == nil, "unknown command rejected")
        check(SVGPath.parse("M1") == nil, "missing number rejected")
        check(SVGPath.parse("1 2") == nil, "number before first command rejected")
        check(SVGPath.parse("M1 2 L") == nil, "command without numbers rejected")
        check(SVGPath.parse("") == nil, "empty string rejected")
        check(SVGPath.parse("   ") == nil, "blank string rejected")
        check(SVGPath.parse("L1 2") == nil, "path not starting with moveto rejected")
        check(SVGPath.parse("M0 0Z1 2") == nil, "number after Z rejected")
        check(SVGPath.parse("M0 0A1 1 0 2 0 1 1") == nil, "invalid arc flag rejected")

        let icon = "M16.792 3.904A4.989 4.989 0 0 1 21.5 9.122c0 3.072-2.652 4.959-5.197 7.222-2.512 2.243-3.865 3.469-4.303 3.752-.477-.309-2.143-1.823-4.303-3.752C5.141 14.072 2.5 12.167 2.5 9.122a4.989 4.989 0 0 1 4.708-5.218 4.21 4.21 0 0 1 3.675 1.941c.84 1.175.98 1.763 1.12 1.763s.278-.588 1.11-1.766a4.17 4.17 0 0 1 3.679-1.938m0-2a6.04 6.04 0 0 0-4.797 2.127 6.052 6.052 0 0 0-4.787-2.127A6.985 6.985 0 0 0 .5 9.122c0 3.61 2.55 5.827 5.015 7.97.283.246.569.494.853.747l1.027.918a44.998 44.998 0 0 0 3.518 3.018 2 2 0 0 0 2.174 0 45.263 45.263 0 0 0 3.626-3.115l.922-.824c.293-.26.59-.519.885-.774 2.334-2.025 4.98-4.32 4.98-7.94a6.985 6.985 0 0 0-6.708-7.218Z"
        if let b = bbox(icon) {
            check(b.minX >= 0 && b.minY >= 0 && b.maxX <= 24 && b.maxY <= 24 && b.width > 15 && b.height > 15,
                  "heart icon bbox inside 0...24")
        } else {
            check(false, "heart icon parses")
        }
    }
}
