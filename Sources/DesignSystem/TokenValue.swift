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
    /// Not `RawRepresentable`: that protocol's `init?(rawValue:)` is failable, and a
    /// theme naming any installed font family is not a parse-time error (ADR-0030
    /// §D3) — whether the family is actually installed is resolved later, at draw
    /// time, in `Theme.nsFont(_:)`. The hand-written `rawValue`/`init(rawValue:)`
    /// below keep the same call shape the DTCG parser already used, minus the
    /// optional.
    enum Family: Equatable, Sendable {
        case system
        case monospace
        case serif
        /// Any font family name that is not one of the three built-in design
        /// keywords, e.g. `"Avenir Next"`. Carried verbatim; not checked against
        /// installed fonts here.
        case named(String)

        init(rawValue: String) {
            switch rawValue {
            case "system": self = .system
            case "monospace": self = .monospace
            case "serif": self = .serif
            default: self = .named(rawValue)
            }
        }

        var rawValue: String {
            switch self {
            case .system: "system"
            case .monospace: "monospace"
            case .serif: "serif"
            case .named(let name): name
            }
        }
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
