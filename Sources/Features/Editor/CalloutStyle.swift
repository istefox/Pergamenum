import CoreGraphics

/// What a callout looks like, kept outside `Sources/Core` because `ColorToken` is a design-system
/// type that `perg` and `pergamenum-mcp` do not compile (ADR-0087 §D3, §D4).
enum CalloutStyle {
    /// The card is the type colour at this one opacity, not a key of its own.
    static let backgroundOpacity: CGFloat = 0.08
}

extension CalloutKind {
    /// The type's colour token, nil for `other`, which draws neutral from `color.quote.bar`.
    var colorToken: ColorToken? {
        switch self {
        case .note: .calloutNote
        case .tip: .calloutTip
        case .important: .calloutImportant
        case .warning: .calloutWarning
        case .caution: .calloutCaution
        case .other: nil
        }
    }

    /// The SF Symbol drawn before the title, one per kind; an unknown type takes the quote's own.
    var symbolName: String {
        switch self {
        case .note: "info.circle"
        case .tip: "lightbulb"
        case .important: "exclamationmark.bubble"
        case .warning: "exclamationmark.triangle"
        case .caution: "exclamationmark.octagon"
        case .other: "text.quote"
        }
    }
}
