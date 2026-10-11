import AppKit

/// The pointer over the note editor's text (PG-219, ADR-0090): this view decides which one
/// applies, `EditorPointer.apply()` draws it. Nothing here names an `NSCursor`.
///
/// Two things have to hold for it to reach the screen, both measured in PG-219. The cursor is
/// set from `cursorUpdate(with:)`, which `NSTextView`'s own whole-bounds tracking area
/// (`.cursorUpdate`/`.mouseMoved`/`.inVisibleRect`) delivers on every mouse-moved tick; and it
/// is set again after `super.mouseMoved(with:)`, because `NSTextView` puts its I-beam back there
/// - a cursor set only from `cursorUpdate` shows while the mouse is still and is gone at the
/// first move. A cursor set from a SwiftUI `.pointerStyle` over this view never wins against
/// that I-beam, which is why the earlier route was dropped.
///
/// `pointer(at:)` is the decision, made from the `.editorLink` attribute through the one
/// point-to-link resolution clicks use, `linkCharacterIndex(at:)` (PG-220), so hover and click
/// agree at every point.
///
/// The file keeps its `+CursorRects` name because ADR-0083 cites it.
extension CompletingTextView {
    /// Which pointer applies at `point`, in view coordinates (ADR-0090 §D2): nothing outside the
    /// view or over a hosted table grid, view block or drawn embed, the hand over a click target,
    /// the I-beam everywhere else in the view, empty space included.
    ///
    /// Over a link the point is resolved once: the embed check reuses the index
    /// `linkCharacterIndex(at:)` returned. Off a link that method returns no index, so the embed
    /// check resolves the point a second time. With markup shown no embed is drawn, so the check,
    /// and that second resolution, are skipped.
    func pointer(at point: NSPoint) -> EditorPointer? {
        guard bounds.contains(point) else { return nil }
        let decorations = textContentStorage?.delegate as? EditorDecorationDelegate
        if let decorations {
            let hosted: [NSView] = Array(decorations.tableViews.values) + Array(decorations.viewBlockHosts.values)
            if hosted.contains(where: { $0.superview != nil && convert($0.bounds, from: $0).contains(point) }) {
                return nil
            }
        }
        let link = linkCharacterIndex(at: point)
        // `drawnEmbedRange` refuses first on this same flag; asking it here spares bridging the
        // whole note and resolving the point again on every mouse-moved tick.
        if let decorations, decorations.hidesMarkup {
            let text = string as NSString
            let index = link ?? min(characterIndexForInsertion(at: point), text.length)
            let paragraph = text.paragraphRange(for: NSRange(location: index, length: 0))
            if decorations.drawnEmbedRange(atParagraphStart: paragraph.location, in: text) != nil {
                return nil
            }
        }
        return link != nil ? .link : .text
    }

    /// Applies the pointer for `point` (view coordinates) and returns it, or returns `nil` and
    /// touches nothing where none applies.
    @discardableResult
    func applyPointer(at point: NSPoint) -> EditorPointer? {
        guard let pointer = pointer(at: point) else { return nil }
        pointer.apply()
        return pointer
    }

    /// Arrives on every mouse-moved tick while the view is in a key window. Where a pointer
    /// applies it is the whole answer; elsewhere `super` keeps the system's. A window that is not
    /// key is left to `super` (ADR-0090 §D4).
    override func cursorUpdate(with event: NSEvent) {
        guard window?.isKeyWindow == true,
              applyPointer(at: convert(event.locationInWindow, from: nil)) != nil
        else { return super.cursorUpdate(with: event) }
    }

    /// After `super`, which puts `NSTextView`'s own I-beam back (see the header).
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard window?.isKeyWindow == true else { return }
        applyPointer(at: convert(event.locationInWindow, from: nil))
    }
}
