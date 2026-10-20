import CoreGraphics
import Foundation

/// Parses SVG path data (the `d` attribute) into a CGPath.
///
/// Supports every SVG 1.1 path command in absolute and relative form
/// (M L H V C S Q T A Z), implicit command repetition, and the compact
/// number and arc-flag syntaxes allowed by the grammar. Arcs are converted
/// from endpoint to center parameterization (SVG 1.1 notes F.6.5/F.6.6) and
/// approximated with cubic Bézier segments of at most 90 degrees each.
enum SVGPath {
    /// Returns nil when the data is malformed (unknown command, missing numbers, number before first command, etc.).
    static func parse(_ data: String) -> CGPath? {
        var parser = Parser(bytes: Array(data.utf8))
        return parser.run()
    }

    // MARK: - Parser

    private struct Parser {
        let bytes: [UInt8]
        var pos = 0
        let path = CGMutablePath()

        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        /// Last cubic control point (after C/S) or quadratic control point (after Q/T).
        var lastControl: CGPoint?
        var lastKind: Character = " "

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func run() -> CGPath? {
            skipWhitespace()
            guard pos < bytes.count else { return nil }
            var command: UInt8 = 0
            var first = true
            while true {
                skipWhitespace()
                if pos >= bytes.count { break }
                let c = bytes[pos]
                if isLetter(c) {
                    command = c
                    pos += 1
                } else if command != 0, command != UInt8(ascii: "Z"), command != UInt8(ascii: "z"),
                          isNumberStart(c) || c == UInt8(ascii: ",") {
                    // Implicit repetition; moveto becomes lineto.
                    if command == UInt8(ascii: "M") {
                        command = UInt8(ascii: "L")
                    } else if command == UInt8(ascii: "m") {
                        command = UInt8(ascii: "l")
                    }
                } else {
                    return nil
                }
                if first {
                    guard command == UInt8(ascii: "M") || command == UInt8(ascii: "m") else { return nil }
                    first = false
                }
                guard execute(command) else { return nil }
            }
            return path
        }

        // MARK: Commands

        private mutating func execute(_ cmd: UInt8) -> Bool {
            let kind = Character(UnicodeScalar(cmd))
            let rel = kind.isLowercase
            let ox = rel ? current.x : 0
            let oy = rel ? current.y : 0
            switch kind {
            case "M", "m":
                guard let x = number(), let y = number() else { return false }
                let p = CGPoint(x: x + ox, y: y + oy)
                path.move(to: p)
                current = p
                subpathStart = p
                lastControl = nil
            case "L", "l":
                guard let x = number(), let y = number() else { return false }
                let p = CGPoint(x: x + ox, y: y + oy)
                path.addLine(to: p)
                current = p
                lastControl = nil
            case "H", "h":
                guard let x = number() else { return false }
                let p = CGPoint(x: x + ox, y: current.y)
                path.addLine(to: p)
                current = p
                lastControl = nil
            case "V", "v":
                guard let y = number() else { return false }
                let p = CGPoint(x: current.x, y: y + oy)
                path.addLine(to: p)
                current = p
                lastControl = nil
            case "C", "c":
                guard let x1 = number(), let y1 = number(),
                      let x2 = number(), let y2 = number(),
                      let x = number(), let y = number() else { return false }
                let c1 = CGPoint(x: x1 + ox, y: y1 + oy)
                let c2 = CGPoint(x: x2 + ox, y: y2 + oy)
                let p = CGPoint(x: x + ox, y: y + oy)
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastControl = c2
            case "S", "s":
                guard let x2 = number(), let y2 = number(),
                      let x = number(), let y = number() else { return false }
                let c1: CGPoint
                if lastKind == "C" || lastKind == "c" || lastKind == "S" || lastKind == "s",
                   let lc = lastControl {
                    c1 = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                } else {
                    c1 = current
                }
                let c2 = CGPoint(x: x2 + ox, y: y2 + oy)
                let p = CGPoint(x: x + ox, y: y + oy)
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastControl = c2
            case "Q", "q":
                guard let x1 = number(), let y1 = number(),
                      let x = number(), let y = number() else { return false }
                let c = CGPoint(x: x1 + ox, y: y1 + oy)
                let p = CGPoint(x: x + ox, y: y + oy)
                path.addQuadCurve(to: p, control: c)
                current = p
                lastControl = c
            case "T", "t":
                guard let x = number(), let y = number() else { return false }
                let c: CGPoint
                if lastKind == "Q" || lastKind == "q" || lastKind == "T" || lastKind == "t",
                   let lc = lastControl {
                    c = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                } else {
                    c = current
                }
                let p = CGPoint(x: x + ox, y: y + oy)
                path.addQuadCurve(to: p, control: c)
                current = p
                lastControl = c
            case "A", "a":
                guard let rx = number(), let ry = number(), let rot = number(),
                      let large = flag(), let sweep = flag(),
                      let x = number(), let y = number() else { return false }
                let p = CGPoint(x: x + ox, y: y + oy)
                SVGPath.addArc(to: path, from: current, rx: rx, ry: ry, rotationDegrees: rot,
                               largeArc: large, sweep: sweep, end: p)
                current = p
                lastControl = nil
            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
                lastControl = nil
            default:
                return false
            }
            lastKind = kind
            return true
        }

        // MARK: Lexing

        private func isLetter(_ c: UInt8) -> Bool {
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
        }

        private func isDigit(_ c: UInt8) -> Bool { c >= 48 && c <= 57 }

        private func isNumberStart(_ c: UInt8) -> Bool {
            isDigit(c) || c == UInt8(ascii: ".") || c == UInt8(ascii: "-") || c == UInt8(ascii: "+")
        }

        private mutating func skipWhitespace() {
            while pos < bytes.count {
                let c = bytes[pos]
                if c == 32 || c == 9 || c == 10 || c == 13 || c == 12 { pos += 1 } else { break }
            }
        }

        /// Skips whitespace and at most one comma separator.
        private mutating func skipSeparator() {
            skipWhitespace()
            if pos < bytes.count, bytes[pos] == UInt8(ascii: ",") {
                pos += 1
                skipWhitespace()
            }
        }

        private mutating func flag() -> Bool? {
            skipSeparator()
            guard pos < bytes.count else { return nil }
            let c = bytes[pos]
            if c == UInt8(ascii: "0") { pos += 1; return false }
            if c == UInt8(ascii: "1") { pos += 1; return true }
            return nil
        }

        private mutating func number() -> CGFloat? {
            skipSeparator()
            let start = pos
            var i = pos
            if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
            var digits = 0
            while i < bytes.count, isDigit(bytes[i]) { i += 1; digits += 1 }
            if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
                i += 1
                while i < bytes.count, isDigit(bytes[i]) { i += 1; digits += 1 }
            }
            guard digits > 0 else { return nil }
            if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
                var j = i + 1
                if j < bytes.count, bytes[j] == UInt8(ascii: "+") || bytes[j] == UInt8(ascii: "-") { j += 1 }
                if j < bytes.count, isDigit(bytes[j]) {
                    while j < bytes.count, isDigit(bytes[j]) { j += 1 }
                    i = j
                }
            }
            let text = String(decoding: bytes[start..<i], as: UTF8.self)
            guard let value = Double(text), value.isFinite else { return nil }
            pos = i
            return CGFloat(value)
        }
    }

    // MARK: - Arc conversion

    /// Appends an SVG elliptical arc using endpoint-to-center conversion (F.6.5, F.6.6)
    /// and cubic Bézier approximation of at most 90 degrees per segment.
    private static func addArc(to path: CGMutablePath, from p0: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                               rotationDegrees: CGFloat, largeArc: Bool, sweep: Bool, end p1: CGPoint) {
        if p0 == p1 { return }
        var rx = Double(abs(rxIn))
        var ry = Double(abs(ryIn))
        if rx == 0 || ry == 0 {
            path.addLine(to: p1)
            return
        }
        let phi = Double(rotationDegrees) * Double.pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let x0 = Double(p0.x), y0 = Double(p0.y), x1 = Double(p1.x), y1 = Double(p1.y)

        let dx = (x0 - x1) / 2
        let dy = (y0 - y1) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = lambda.squareRoot()
            rx *= s
            ry *= s
        }

        let rx2 = rx * rx, ry2 = ry * ry
        let num = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
        let den = rx2 * y1p * y1p + ry2 * x1p * x1p
        var coef = den == 0 ? 0 : max(0, num / den).squareRoot()
        if largeArc == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (x0 + x1) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (y0 + y1) / 2

        let theta1 = atan2((y1p - cyp) / ry, (x1p - cxp) / rx)
        let theta2 = atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx)
        var dTheta = theta2 - theta1
        if !sweep && dTheta > 0 { dTheta -= 2 * Double.pi }
        if sweep && dTheta < 0 { dTheta += 2 * Double.pi }

        let segments = max(1, Int((abs(dTheta) / (Double.pi / 2) - 1e-9).rounded(.up)))
        let delta = dTheta / Double(segments)
        let t = 4.0 / 3.0 * tan(delta / 4)

        func map(_ ux: Double, _ uy: Double) -> CGPoint {
            CGPoint(x: cx + rx * ux * cosPhi - ry * uy * sinPhi,
                    y: cy + rx * ux * sinPhi + ry * uy * cosPhi)
        }

        for i in 0..<segments {
            let a1 = theta1 + Double(i) * delta
            let a2 = a1 + delta
            let c1 = map(cos(a1) - t * sin(a1), sin(a1) + t * cos(a1))
            let c2 = map(cos(a2) + t * sin(a2), sin(a2) - t * cos(a2))
            let end = (i == segments - 1) ? p1 : map(cos(a2), sin(a2))
            path.addCurve(to: end, control1: c1, control2: c2)
        }
    }
}
