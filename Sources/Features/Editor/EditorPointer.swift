import SwiftUI

/// What the pointer should be over editor text: the I-beam over text, the pointing hand over a
/// link (`PG-219`, #445, note-workflow R-09). The text views decide it from their link geometry
/// and report it through `onPointerChange`; the SwiftUI host applies it with `.pointerStyle`,
/// the one route that reaches the screen in this window.
enum EditorPointer: Equatable, Sendable {
    case text, link

    var style: PointerStyle {
        switch self {
        case .text: .horizontalText
        case .link: .link
        }
    }
}
