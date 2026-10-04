import AppKit
import SwiftUI

// Moved verbatim out of `Theme.swift` for its file length; `Theme`'s private `Int`
// extensions are its only readers besides the tests.

/// The nine weight stops a DTCG numeric weight (100...900) lands on.
///
/// The thresholds are written once, in `init(dtcg:)`; `swiftUI` and `appKit` only name
/// the same stop in each framework's units. Two threshold ladders used to sit side by
/// side, identical by hand, which is how a token would one day draw a different weight
/// in a SwiftUI view and in a bridged AppKit one.
enum FontWeightStop: CaseIterable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black

    /// Anything between two stops rounds down to the lighter one, which is how CSS
    /// behaves.
    init(dtcg weight: Int) {
        switch weight {
        case ..<150: self = .ultraLight
        case ..<250: self = .thin
        case ..<350: self = .light
        case ..<450: self = .regular
        case ..<550: self = .medium
        case ..<650: self = .semibold
        case ..<750: self = .bold
        case ..<850: self = .heavy
        default: self = .black
        }
    }

    var swiftUI: Font.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }

    var appKit: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
}
