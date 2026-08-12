import CoreGraphics
import Foundation

/// A resolved token value, in the shape the design system needs rather than the
/// shape the JSON happens to use.
enum TokenValue: Equatable, Sendable {
    case color(RGBA)
    case dimension(CGFloat)
    case typography(TypographyValue)
    case shadow(ShadowValue)
    case string(String)
}

/// Straight sRGB components in 0...1. Kept framework-free so `Core`-style logic and
/// tests can handle tokens without importing SwiftUI.
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
}

struct TypographyValue: Equatable, Sendable {
    enum Family: String, Equatable, Sendable {
        case system
        case monospace
        case serif
    }

    var family: Family
    var size: CGFloat
    var weight: Int
    /// Multiple of the font size, as DTCG expresses unitless line heights.
    var lineHeight: Double
}

struct ShadowValue: Equatable, Sendable {
    var color: RGBA
    var offsetX: CGFloat
    var offsetY: CGFloat
    var blur: CGFloat
    var spread: CGFloat
}
