import Foundation

/// Where the caret lands, or what a Backspace/Delete removes, when it meets a drawn
/// embed's run (ADR-0018 slice 3, Step 4; D5's exception to the caret rule, spelled out
/// for a picture rather than a delimiter).
///
/// Pure range arithmetic only, matching `MarkupReveal`'s own split: no `NSTextView`, no
/// `NSTextLayoutFragment`, nothing that needs a window to run. `NoteTextView+EmbedCaret`
/// is the half that gathers `drawnRuns` from `EditorDecorationDelegate` and turns an
/// answer here into a `selectedRange` or an atomic delete.
///
/// `drawnRuns` is always the small set of embed ranges the caller found near the edge
/// being tested, never the whole document - `EditorDecorationDelegate.drawnEmbedRange
/// (atParagraphStart:in:)` is what re-validates each one against the text as it is right
/// now, the same discipline `stillSpellsAnEmbed` already keeps for drawing. A run this
/// function is handed is, by construction, always one `hidesMarkup` has approved and a
/// rendition backs - the caller's guard, never this file's, is what R4 rests on.
enum EmbedNavigation {
    enum Direction { case left, right }

    /// Where `selection` lands after one `moveLeft:`/`moveRight:`, or its extending
    /// variant, or `nil` when nothing about `drawnRuns` changes the ordinary,
    /// one-character answer - `super` is left to give it.
    ///
    /// **The edge tested depends on direction and on `extending`, not on the caret
    /// alone.** Moving right steps into whatever is to the caret's right, so the run
    /// that matters is the one starting exactly at the position that is about to move
    /// (`selection.location` for a plain move, `NSMaxRange(selection)` for an extending
    /// one - the end actually advancing). Moving left is symmetric on a run's other
    /// edge, and its own moving position is always `selection.location`: a plain move
    /// only reaches here with an empty selection (the guard below), and an extending
    /// move's minimum is what a leftward extension advances.
    ///
    /// A plain move is only intercepted from a bare caret (`selection.length == 0`):
    /// AppKit's own rule for `moveLeft:`/`moveRight:` over an existing selection is to
    /// collapse to one of its edges, never to step past it, and that collapse is not
    /// this function's concern.
    ///
    /// **Design decision, not spelled out verbatim in the brief:** for the extending
    /// variants this assumes the end of `selection` *not* being tested is the fixed
    /// anchor - the ordinary case of extending further in the direction already being
    /// extended, or starting to extend from a bare caret. A selection that reverses
    /// direction mid-drag (extended right, then shift-left back past its own start) is
    /// not this function's problem to solve: it is the same residual imperfection D5
    /// already names for headings and emphasis (*"the caret stops inside a collapsed
    /// run"*), never a crash, and `super` still moves it one character at a time.
    static func moved(
        selection: NSRange, direction: Direction, extending: Bool, drawnRuns: [NSRange]
    ) -> NSRange? {
        guard extending || selection.length == 0 else { return nil }
        switch direction {
        case .right:
            let movingEdge = extending ? NSMaxRange(selection) : selection.location
            guard let run = drawnRuns.first(where: { $0.location == movingEdge }) else { return nil }
            let far = NSMaxRange(run)
            return extending
                ? NSRange(location: selection.location, length: far - selection.location)
                : NSRange(location: far, length: 0)
        case .left:
            let movingEdge = selection.location
            guard let run = drawnRuns.first(where: { NSMaxRange($0) == movingEdge }) else { return nil }
            return extending
                ? NSRange(location: run.location, length: NSMaxRange(selection) - run.location)
                : NSRange(location: run.location, length: 0)
        }
    }

    enum DeleteDirection { case backward, forward }

    /// What a Backspace or a Delete removes when the caret meets a drawn embed's edge,
    /// or `nil` when it does not - the ordinary, one-character answer `super` already
    /// gives everywhere else.
    ///
    /// **Backspace at the run's right edge, Delete at its left edge**: whichever key
    /// would otherwise eat into the run from the direction it deletes in. Either way the
    /// range removed is the same - the whole run plus the paragraph's own trailing
    /// newline (D-1: deleting a picture must not leave an empty line in its place) -
    /// clamped to `textLength` for the one embed that could be the note's very last line
    /// with no newline after it.
    ///
    /// Only from a bare caret: a real selection is deleted by `super` exactly as it is
    /// today, and this function is not asked to decide what an arbitrary selection that
    /// happens to touch a run should do.
    static func deletionRange(
        selection: NSRange, direction: DeleteDirection, drawnRuns: [NSRange], textLength: Int
    ) -> NSRange? {
        guard selection.length == 0 else { return nil }
        let run: NSRange?
        switch direction {
        case .backward: run = drawnRuns.first(where: { NSMaxRange($0) == selection.location })
        case .forward: run = drawnRuns.first(where: { $0.location == selection.location })
        }
        guard let run, run.location >= 0 else { return nil }
        let end = min(NSMaxRange(run) + 1, textLength)
        guard end > run.location else { return nil }
        return NSRange(location: run.location, length: end - run.location)
    }
}
