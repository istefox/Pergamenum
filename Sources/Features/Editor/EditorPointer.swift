import AppKit

/// Which pointer the editor's text asks for under the mouse (PG-219, ADR-0090): the text view
/// decides, `apply()` draws. `nil` in the places that carry it means "no pointer applies here,
/// leave the system's", never a third pointer.
///
/// This is the one place a text view's cursor is made an `NSCursor`: `CompletingTextView` and
/// `FormattingTextView` name no `NSCursor` themselves (`NoAppKitCursorInTheTextViews`), so the
/// decision stays in the view and the drawing stays here.
enum EditorPointer: Equatable, Sendable {
    /// Ordinary text: the I-beam.
    case text
    /// A click target (`.editorLink`): the pointing hand.
    case link

    @MainActor
    var cursor: NSCursor {
        switch self {
        case .text: .iBeam
        case .link: .pointingHand
        }
    }

    /// Makes this the cursor on screen. Called from `cursorUpdate(with:)` and again after
    /// `super.mouseMoved(with:)`: `NSTextView` puts its own I-beam back on every mouse-moved
    /// tick, so a cursor set only from `cursorUpdate` shows while the mouse is still and is gone
    /// at the first move (measured in PG-219, ADR-0090 §D1).
    @MainActor
    func apply() { cursor.set() }
}
