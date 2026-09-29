import Foundation

/// The one map from a JSON Canvas preset number to the token it is drawn with (ADR-0071 §D1).
///
/// The Workspace sticky card and the Contenitore colour both read it, so the board and the pane
/// cannot drift apart: one token per preset (#569 point 10), and grey for anything outside
/// 1...6.
enum StickyPreset {
    static func token(for preset: Int) -> ColorToken {
        switch preset {
        case 1: .stickyPink
        case 2: .stickyOrange
        case 3: .stickyYellow
        case 4: .stickyGreen
        case 5: .stickyBlue
        case 6: .stickyPurple
        default: .stickyGrey
        }
    }

    /// The presets' names, in preset order, as the colour menus show them.
    static var names: [String] {
        ContenitoreColour.allCases.map(\.displayName)
    }
}
