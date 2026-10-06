import AppKit

/// `CompletingTextView+CursorRects.swift`'s twin, not a shared helper (ADR-0027 §D1/§D9: this
/// view forks nothing from the note editor's): the card decides which pointer applies while it
/// is being edited and `EditorPointer.apply()` draws it (PG-219, ADR-0090). Nothing here names an
/// `NSCursor`. The same two rules hold, for the same measured reason: the cursor is set from
/// `cursorUpdate(with:)` and again after `super.mouseMoved(with:)`, which is where `NSTextView`
/// puts its I-beam back.
///
/// The decision reads `.editorLink` through this view's own `linkCharacterIndex(at:)`, the one
/// its clicks use (PG-220). The file keeps its `+CursorRects` name because ADR-0083 cites its
/// twin by name and the two stay paired.
extension FormattingTextView {
    /// Which pointer applies at `point`, in view coordinates (ADR-0090 §D2): nothing while the
    /// card is not being edited or outside the view, the hand over a click target, the I-beam
    /// everywhere else.
    func pointer(at point: NSPoint) -> EditorPointer? {
        guard isEditable, bounds.contains(point) else { return nil }
        return linkCharacterIndex(at: point) != nil ? .link : .text
    }

    /// Applies the pointer for `point` (view coordinates) and returns it, or returns `nil` and
    /// touches nothing where none applies.
    @discardableResult
    func applyPointer(at point: NSPoint) -> EditorPointer? {
        guard let pointer = pointer(at: point) else { return nil }
        pointer.apply()
        return pointer
    }

    /// `CompletingTextView+CursorRects.swift`'s twin: arrives on every mouse-moved tick while the
    /// card is in a key window; where a pointer applies it is the whole answer.
    override func cursorUpdate(with event: NSEvent) {
        guard window?.isKeyWindow == true,
              applyPointer(at: convert(event.locationInWindow, from: nil)) != nil
        else { return super.cursorUpdate(with: event) }
    }

    /// After `super`, which puts `NSTextView`'s own I-beam back.
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard window?.isKeyWindow == true else { return }
        applyPointer(at: convert(event.locationInWindow, from: nil))
    }
}
