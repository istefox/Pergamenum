import AppKit

/// The Workspace card's own `NSTextView` (ADR-0027 §D1).
///
/// A sibling of `CompletingTextView`, never a fork of it: the note editor's view carries about
/// forty inputs - titles, tags, slash commands, emoji, embeds, transclusions, folding, find
/// matches, outline ranges - and a canvas card has none of them. Nothing is extracted from that
/// class, which is also what keeps the protected `CompletingTextView+Pasteboard.swift` outside
/// this chain's blast radius (ADR-0027 §D9).
///
/// What it is for: draw a card's markdown source with `CardTextAttributes`, report where its
/// selection is **in its own coordinates**, and leave editing on Esc. Cmd+B/Cmd+I and the
/// formatting edits themselves arrive in the next slice; this file deliberately stops short of
/// them.
final class FormattingTextView: NSTextView {
    /// Esc: leave editing (SPEC §6.3).
    ///
    /// The card's editing surface used to be a SwiftUI `TextEditor` with an `.onKeyPress(.escape)`
    /// over it. A key press only reaches that modifier while SwiftUI's focus system holds the
    /// keyboard, and once an `NSTextView` is first responder AppKit does - so the handler has to
    /// live where the responder is, or Esc silently stops leaving the card.
    var onCancel: (() -> Void)?

    /// Read from the raw event rather than from `cancelOperation(_:)`, which is what the key
    /// looks like it should arrive as: AppKit's standard key bindings send Esc inside a text view
    /// to `complete:`, word completion, so the responder method that reads as its obvious home is
    /// not reliably called at all. A card has no completion to offer, so the key is taken here and
    /// never passed on.
    private static let escapeKeyCode: UInt16 = 53

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == Self.escapeKeyCode else { return super.keyDown(with: event) }
        onCancel?()
    }

    /// The rectangle the current selection occupies, in **this view's own coordinates**.
    ///
    /// View-local on purpose and never a screen coordinate (ADR-0027 §D5): the board wraps its
    /// content in `.scaleEffect(zoom, anchor: .topLeading)` plus a `pan` offset, and a rectangle
    /// taken from `firstRect(forCharacterRange:)` - the way `FormatBarPanel` places the note
    /// editor's bar - is a screen rectangle that may know nothing about either. A card adds its
    /// own board origin to what this returns and the board overlay draws at `p * zoom + pan`, the
    /// transform `BoardMarquee` and `BoardGuides` already use.
    ///
    /// `nil` when there is no selection to point at: a caret is not a selection, and the floating
    /// bar exists only while there is one.
    func selectionFrameInView() -> CGRect? {
        let selection = selectedRange()
        guard selection.length > 0,
              let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: selection.location),
              let end = contentManager.location(start, offsetBy: selection.length),
              let range = NSTextRange(location: start, end: end)
        else { return nil }

        var union: CGRect?
        layoutManager.enumerateTextSegments(in: range, type: .selection) { _, frame, _, _ in
            union = union.map { $0.union(frame) } ?? frame
            return true
        }
        // The segments come back in the text container's space; the inset between the container
        // and the view is exactly `textContainerOrigin`, so adding it is the whole conversion.
        let origin = textContainerOrigin
        return union?.offsetBy(dx: origin.x, dy: origin.y)
    }
}
