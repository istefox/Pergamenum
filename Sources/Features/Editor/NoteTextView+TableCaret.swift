import AppKit

/// Return, and forward Delete, redirected around a GFM table's own hidden delimiter and
/// body rows (ADR-0029 §D4/§D5) - the caret trap a table with nothing laid out below its
/// grid falls into.
///
/// **The trap, in one sentence.** `EditorDecorationDelegate.shouldEnumerate` (the
/// `tableRowOffsets` check) keeps every row after the header out of the layout entirely, so
/// the header paragraph is the *only* laid-out element the table has - and `TableAttachment`
/// reports that one fragment's bounds as the whole grid's height. Every point below or beside
/// that stretched rectangle - "end of document" whenever nothing is laid out below it, or past
/// `TableGridView`'s own right edge (its real hosted `NSView` frame, wider than its drawn
/// border by the row/column control pills' own width - §D-below) - hit-tests back to one of
/// two text-storage offsets, one character apart: the header paragraph's own end (`end`, right
/// at the `|---|---|` delimiter line's own start) or its content end (`contentsEnd`, the
/// position right before the header's own trailing newline). Pressing Return at either inserts
/// `\n` *inside* the table's own source - between the header and the delimiter row, or between
/// the header's last character and its own newline - which breaks `GFMTable.parse`'s
/// contiguity either way: a real content corruption, not a rendering hiccup.
///
/// **A click inside `TableGridView`'s own frame - including the internal gap between its
/// drawn border and its real edge, when the control pills are the wider of the two - never
/// reaches this file at all.** `TableGridView` doesn't override `mouseDown`, so AppKit's
/// default (confirmed empirically, not assumed: neither the first responder nor the selection
/// changes) swallows it. Only a click *past* the hosted view's own right edge reaches
/// `CompletingTextView`'s ordinary point-to-character hit testing - and lands on
/// `contentsEnd`, one character short of the `end` this file already redirected, because the
/// header line's own remaining characters sit concealed at `collapsedFont` in a visual sliver
/// immediately after the attachment glyph, and any point to their right resolves to their own
/// far edge.
///
/// Wired the way `NoteTextView+EmbedCaret.swift` and `NoteTextView+ListEditing.swift` already
/// are: a third claimant of `CompletingTextView.claimsCommand`, chained in
/// `NoteTextView.swift`'s `wire(_:to:)`, writing through the one atomic mechanism this feature
/// family already shares, `replaceAtomically(_:with:in:)` (`NoteTextView+EmbedCaret.swift`).
///
/// **Backspace needs no equivalent claim, at either offset.** `deleteBackward` from `end`
/// deletes the character immediately *before* it - the header line's own last visible
/// character - which is exactly what Backspace does from the header's true end anyway; the
/// trap offset and the header's real end are the same text-storage location, so there is
/// nothing to redirect. From `contentsEnd` it deletes the header's own second-to-last
/// character, an ordinary edit of visible (if tiny) header text, not a merge across paragraphs.
/// Forward Delete is the asymmetric case at both offsets: from `end` it deletes the delimiter
/// row's own opening `|` - invisible, since that row is out of the layout; from `contentsEnd`
/// it deletes the header's own trailing newline, merging the header and delimiter paragraphs
/// into one line GFM cannot parse. Both are claimed here and redirected the same way Return is.
extension NoteTextView.Coordinator {
    /// Answers Return or forward Delete pressed at the trap offset by redirecting the edit to
    /// the table's true end (`NSMaxRange` of `EditorDecorationDelegate.tableRun`'s own range,
    /// past the last body row) instead of writing into the delimiter row. `false` for every
    /// other selector and every caret that is not at the trap - a table not at the end of its
    /// note, or an ordinary paragraph, reaches `super` completely unaffected.
    ///
    /// Gated on `decorations.hidesMarkup` like `claimsEmbedCommand`, unlike
    /// `claimsListCommand`: the trap exists only because `hidesMarkup` is what takes the
    /// delimiter/body rows out of the layout in the first place (D9's escape hatch clears
    /// `tableRowOffsets` when it is off, so every row lays out normally and there is no trap
    /// to redirect around).
    func claimsTableCommand(_ selector: Selector, in textView: NSTextView) -> Bool {
        guard decorations.hidesMarkup,
              selector == #selector(NSResponder.insertNewline(_:))
                  || selector == #selector(NSResponder.deleteForward(_:))
        else { return false }
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        guard selection.length == 0, let end = trappedTableEnd(at: selection.location, in: text)
        else { return false }

        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            guard replaceAtomically(NSRange(location: end, length: 0), with: "\n", in: textView)
            else { return false }
            textView.setSelectedRange(NSRange(location: end + 1, length: 0))
            // The redirected caret does not visibly blink here - a known, currently-open
            // AppKit/TextKit 2 platform limitation (Apple FB17103305: a TextKit-2-backed
            // `NSTextView`'s caret is drawn by an internal `NSTextInsertionIndicator`
            // subview whose blink state does not reliably follow a programmatic selection
            // change, only an interactive one), not a defect in this redirect. Six
            // different workarounds were tried and hand-verified live during this
            // feature's development - a second `growToFitTheText`, an unconditional
            // `layoutViewport()`, `updateInsertionPointStateAndRestartTimer(_:)`, a
            // `resignFirstResponder`/`becomeFirstResponder` reclaim cycle, and a
            // real-command-dispatch `moveLeft`/`moveRight` round trip - none restored the
            // blink. The model is always correct (`selectedRange()`, `firstResponder`, and
            // the text itself all land right, confirmed by this file's own regression
            // tests) and a click or a keystroke immediately makes the caret reappear, so
            // this is cosmetic, not a data-safety issue. See PROJECT_BRIEF.md's ADR-0029
            // §D16 status note.
            return true
        default:
            // At the true end of the document, forward Delete already does nothing - the
            // claim still holds the command so it never falls through to `super`'s own
            // deleteForward, which would otherwise resolve to the same offset today's bug
            // report already established and eat the delimiter row's first `|`.
            guard end < text.length else { return true }
            _ = replaceAtomically(NSRange(location: end, length: 1), with: "", in: textView)
            return true
        }
    }

    /// The table's true end when `location` is one of the two offsets a click or caret move
    /// beside a table's drawn grid collapses onto - the header paragraph's own end (`end`,
    /// including its trailing newline) or its own content end (`contentsEnd`, the position
    /// right before that newline) - or nil for every other location.
    ///
    /// **Two offsets, not one, because `TableGridView`'s real `NSView` frame does not cover
    /// every point a person would call "beside the table".** `attachmentBounds` reports
    /// exactly `gridView.intrinsicContentSize` (`TableGridStore.swift`), which is the wider of
    /// the cells' own width and the row/column control pills' width - a two-column table's
    /// pills are routinely the wider of the two, leaving a real gap between the grid's drawn
    /// border and the view's own edge, and open editor space past that edge again. A click
    /// inside the hosted view's frame (including that internal gap) is swallowed by
    /// `TableGridView`'s own default, unoverridden `mouseDown` - confirmed empirically, not
    /// assumed: it changes neither the first responder nor the selection - so the click that
    /// actually reaches `CompletingTextView`'s ordinary point-to-character hit testing is one
    /// past the hosted view's right edge entirely. Every one of those - however far right,
    /// still confirmed empirically - resolves to `contentsEnd`, because the header line's own
    /// remaining characters (concealed at `collapsedFont` right after the attachment glyph,
    /// `EditorDecorationDelegate+TableRendering.swift`'s `restRange`) are visually a sliver
    /// squeezed immediately after that glyph, and clicking anywhere to their right resolves to
    /// the nearest insertion point, which is their own far edge - one character short of `end`.
    /// Pressing Return there splits the header line's own trailing newline in two, inserting a
    /// blank line between the header and the delimiter row exactly as `end` would; forward
    /// Delete there deletes that trailing newline outright, merging the header and delimiter
    /// paragraphs into one line GFM cannot parse as a table. Both are the same corruption as
    /// the `end` trap, one text-storage position earlier, and get the same redirect.
    ///
    /// A real, separately laid-out paragraph right after the table (content with no blank
    /// line, or a blank line the table's own source does not include) never equals either
    /// offset: the hidden delimiter and body rows always sit between them, so a click landing
    /// on that next paragraph resolves to its own start, not to this file's header paragraph
    /// at all. That is what leaves the "content immediately after" and "blank paragraph
    /// already there" cases untouched by this claimant, without a separate guard for either.
    ///
    /// Iterates `decorations.tableViews.keys`, the same iteration
    /// `CompletingTextView+FormatBar.swift`'s `isInsideTable(_:)` already uses, and re-reads
    /// the live characters through `EditorDecorationDelegate.tableRun(in:atParagraphStart:)` -
    /// the one implementation of "is there still a table here" - rather than trusting whatever
    /// the last styling pass recorded.
    private func trappedTableEnd(at location: Int, in text: NSString) -> Int? {
        for header in decorations.tableViews.keys {
            guard let run = EditorDecorationDelegate.tableRun(in: text, atParagraphStart: header)
            else { continue }
            var start = 0, end = 0, contentsEnd = 0
            text.getParagraphStart(
                &start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: header, length: 0)
            )
            guard location == end || location == contentsEnd, location < NSMaxRange(run.range)
            else { continue }
            return NSMaxRange(run.range)
        }
        return nil
    }
}
