import AppKit

/// Where the caret is, in the coordinates a floating panel needs.
///
/// Its own file because the answer turned out to be two answers - the text input client's,
/// and TextKit 2's when that one comes back empty - and because `CompletingTextView` is at
/// the length the linter allows.
extension CompletingTextView {
    /// Where the caret is on screen, which is where the panel hangs itself.
    ///
    /// `firstRect(forCharacterRange:actualRange:)` is the obvious answer and is right most
    /// of the time, but it returns a rectangle of zero for a range TextKit 2 has not laid
    /// out - and TextKit 2 lays out lazily, so the end of a long note is exactly such a
    /// range. A zero rectangle sent to `CompletionPanel.place` clamps to the screen's
    /// bottom-left corner, which is where the panel appeared: at the other end of the
    /// display from the caret that opened it.
    ///
    /// So the input-client answer is kept where it works and TextKit 2 is asked directly
    /// where it does not.
    func caretRectOnScreen() -> NSRect {
        let fromInputClient = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        // Height, not `isEmpty`: a caret is zero characters wide and its rectangle is a
        // zero-width one, which `isEmpty` calls empty.
        if fromInputClient.height > 0 { return fromInputClient }
        guard let window, let local = caretRectInView() else { return fromInputClient }
        return window.convertToScreen(convert(local, to: nil))
    }

    /// The caret's rectangle in this view's own coordinates, from the layout manager.
    ///
    /// A text segment first, which is the caret itself; the whole line's fragment as a
    /// fallback, because a caret sitting after the final newline has no segment of its own
    /// and that is the commonest place to open a completion - the empty line at the end of
    /// what is being written.
    private func caretRectInView() -> NSRect? {
        guard let layout = textLayoutManager,
              let content = layout.textContentManager,
              let location = content.location(
                  content.documentRange.location, offsetBy: selectedRange().location
              )
        else { return nil }

        let caret = NSTextRange(location: location)
        layout.ensureLayout(for: caret)

        var found: NSRect?
        layout.enumerateTextSegments(in: caret, type: .selection, options: []) { _, frame, _, _ in
            found = frame
            return false
        }
        if found == nil || found?.height == 0 {
            found = layout.textLayoutFragment(for: location)?.layoutFragmentFrame
        }
        guard let rect = found, rect.height > 0 else { return nil }
        // The layout manager measures inside the text container; the view has the container
        // inset by `textContainerOrigin`, and forgetting it puts the panel a few points off
        // rather than in the wrong corner - which is the harder kind of wrong to notice.
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }
}
