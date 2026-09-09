import AppKit

/// Which paragraphs are drawn in full while the rest of the note may have a heading
/// marker collapsed (ADR-0018 §D1, §D2).
///
/// A file of its own, matching the `+Matches`/`+Transclusion` split: `+Coordinator.swift`
/// is already at SwiftLint's length limit, and reveal is a self-contained concern with a
/// pure core worth testing without an `NSTextView` at all.
enum MarkupReveal {
    /// The paragraph-start offsets `EditorDecorationDelegate` should draw in full, per
    /// ADR-0018 §D2's four triggers: the caret's paragraph, every paragraph a non-empty
    /// selection spans, an active IME composition's paragraph, and the find bar's current
    /// match's paragraph.
    ///
    /// Offset arithmetic only - no AppKit type beyond `NSString`/`NSRange` - so this is
    /// directly unit-testable against a plain `String`.
    static func paragraphs(
        in text: String,
        selection: NSRange,
        markedRange: NSRange,
        currentMatch: NSRange?
    ) -> Set<Int> {
        let string = text as NSString
        var result: Set<Int> = []
        add(selection, of: string, to: &result)
        // `NSNotFound` is what a text view with no active composition reports.
        if markedRange.location != NSNotFound {
            add(markedRange, of: string, to: &result)
        }
        if let currentMatch {
            add(currentMatch, of: string, to: &result)
        }
        return result
    }

    /// Note-wide table of revealed inline-span ranges (emphasis/strikethrough/link,
    /// ADR-0037 §D4), keyed by paragraph-start offset, values paragraph-relative — the
    /// same key space `hiddenMarkers` already uses (ADR-0037 §D6).
    ///
    /// **Stub for Task 2 of `2026-09-08-word-grained-markdown-reveal-on-caret-in`.**
    /// Returns `[:]` unconditionally; the tester owns this signature, the coder fills the
    /// body (walk each trigger's touched paragraphs; a paragraph entirely covered by a
    /// non-empty trigger emits one whole-paragraph span with no parse, ADR-0037 §D5;
    /// otherwise call `InlineSpanReveal.revealed` on that paragraph's substring).
    static func inlineSpans(
        in text: String,
        selection: NSRange,
        markedRange: NSRange,
        currentMatch: NSRange?
    ) -> [Int: [NSRange]] {
        [:]
    }

    /// Every paragraph-start offset `range` touches, walking forward so a selection
    /// spanning several paragraphs reveals all of them and not only the one the caret
    /// happens to land in.
    ///
    /// A stale or out-of-bounds range - the find bar's last match after an edit moved
    /// everything below it, say - is skipped rather than trusted: nothing in this
    /// function may crash the layout pass that calls it indirectly.
    private static func add(_ range: NSRange, of string: NSString, to result: inout Set<Int>) {
        guard range.location != NSNotFound, range.location <= string.length else { return }
        let clamped = NSRange(
            location: range.location,
            length: min(max(range.length, 0), string.length - range.location)
        )
        var offset = clamped.location
        repeat {
            let paragraph = string.paragraphRange(for: NSRange(location: offset, length: 0))
            result.insert(paragraph.location)
            offset = NSMaxRange(paragraph)
        } while offset < NSMaxRange(clamped)
    }
}

extension NoteTextView.Coordinator {
    /// Recomputes which paragraphs are drawn in full and, only for the ones that
    /// changed, tells the layout to read them again.
    ///
    /// **Never the whole document.** `applyStyling` invalidates everything on every
    /// keystroke and can afford to; this runs on every arrow key and every click, and the
    /// 0.89ms round-trip `docs/20260817_TextKit2_live_editing.md` measured was for two
    /// paragraphs, not a document.
    func applyReveal(to textView: NSTextView) {
        let currentMatch = parent.currentMatch.flatMap { index in
            parent.matches.indices.contains(index) ? parent.matches[index] : nil
        }
        let revealed = MarkupReveal.paragraphs(
            in: textView.string,
            selection: textView.selectedRange(),
            markedRange: textView.markedRange(),
            currentMatch: currentMatch
        )
        guard revealed != lastRevealed else { return }
        lastRevealed = revealed

        let changed = decorations.apply(revealedParagraphs: revealed)
        guard !changed.isEmpty, let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        storage.beginEditing()
        for offset in changed where offset < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: offset, length: 0))
            storage.edited(.editedAttributes, range: paragraph, changeInLength: 0)
        }
        storage.endEditing()
    }
}
