import Foundation

/// Which token a diary colour is drawn with.
///
/// Here rather than on `DiaryColour` itself, where it began. The colour is data: it is
/// written into the markdown and read back, so it belongs in `Core` with everything
/// else the file carries. Which surface the app paints for it is a question about the
/// design system, and answering it inside `Core` made a value type depend on the theme
/// (ADR-0001 §D1). The `perg` target found it by refusing to compile (ADR-0007 §D2).
extension DiaryColour {
    /// The sticky family exists for exactly this: a coloured surface that a custom
    /// theme can restate.
    var token: ColorToken {
        switch self {
        case .blu: .stickyBlue
        case .verde: .stickyGreen
        case .giallo: .stickyYellow
        case .rosa: .stickyPink
        case .grigio: .stickyGrey
        }
    }
}
