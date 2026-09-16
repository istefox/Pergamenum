import Foundation

/// Which token a category colour is drawn with.
///
/// Here rather than on `CategoryColor` itself, exactly for the reason `DiaryColour
/// +Token.swift` gives for its own split: the colour is data, so it belongs in `Core`
/// with the rest of the registry entry; which surface the app paints it with is a
/// question about the design system, and answering it inside `Core` would make a value
/// type depend on the theme (ADR-0001 §D1). Both connector targets would refuse to
/// compile the moment this lived beside `CategoryColor` instead.
extension CategoryColor {
    /// The sticky family, reused rather than widened: five names were already a small
    /// fixed palette before a category needed one (`CategoryColor.swift`).
    var token: ColorToken {
        switch self {
        case .giallo: .stickyYellow
        case .verde: .stickyGreen
        case .blu: .stickyBlue
        case .rosa: .stickyPink
        case .grigio: .stickyGrey
        }
    }
}

extension Category {
    /// `color`'s resolved token, falling back to a neutral one for a value the palette
    /// does not recognise - never a refusal to render the category
    /// (`CardTextStyle.rgba(for:)`'s own rule, restated: a malformed value reads as
    /// absent, not corrected, and the caller substitutes a token of its own).
    var colorToken: ColorToken {
        CategoryColor(rawValue: color)?.token ?? .textTertiary
    }
}
