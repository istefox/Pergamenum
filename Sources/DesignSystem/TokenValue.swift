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
