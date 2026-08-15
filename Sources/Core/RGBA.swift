import Foundation

/// Straight sRGB components in 0...1, with no framework underneath them.
///
/// In `Core` rather than in `DesignSystem`, where it started: `Core/Canvas/JSONCanvas`
/// reads the colours of a JSON Canvas node with it, and a `Core` type reaching up into
/// the design system inverts the dependency direction ADR-0001 §D1 fixes. The comment
/// it carried in its old home already said it was meant to be framework-free so
/// "`Core`-style logic and tests can handle tokens without importing SwiftUI"; this
/// puts it where that sentence is true by construction.
///
/// The compiler found this, not a reader: the `perg` target of ADR-0007 §D2 compiles
/// `Sources/Core/**` without the design system, and refused.
struct RGBA: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    /// Parses `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA`, with or without the hash.
    /// Returns nil rather than a default colour: a malformed value must be reported
    /// as a parse failure, never silently rendered as black.
    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }

        // Expand shorthand: #A3F -> #AA33FF, so both forms take the same path below.
        if digits.count == 3 || digits.count == 4 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6 || digits.count == 8,
              let value = UInt32(digits, radix: 16) else { return nil }

        if digits.count == 6 {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        } else {
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        }
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// The value as a token file writes it: `#RRGGBB`, or `#RRGGBBAA` when it is not
    /// opaque. The short forms are only ever read, never written, so a file this app
    /// produces reads the same way to every other tool.
    var hexString: String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        let base = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return alpha >= 1 ? base : base + String(format: "%02X", byte(alpha))
    }
}
