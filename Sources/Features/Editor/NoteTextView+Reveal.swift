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
    /// Reads ADR-0018 §D2's same triggers as `paragraphs` above, through the same private
    /// walk, with the same `NSNotFound` guard on `markedRange` and the same tolerance for a
    /// stale range. That shared walk is what makes ADR-0037 §D6's invariant hold by
    /// construction rather than by care: every key here is also a member of `paragraphs`'
    /// answer for the same inputs, so the delegate's list, checkbox and blockquote branches
    /// - which already return `nil` for a revealed paragraph - can never be handed one that
    /// has spans, and need no edit.
    ///
    /// A paragraph a non-empty trigger covers **entirely** contributes one whole-paragraph
    /// span and is never parsed (ADR-0037 §D5): that is what bounds a Cmd+A to arithmetic
    /// over the paragraphs instead of a parse of the note. Every other touched paragraph is
    /// handed to `InlineSpanReveal.revealed` with the trigger clipped to it and translated
    /// into its own coordinates. A paragraph with nothing revealed contributes no key.
    static func inlineSpans(
        in text: String,
        selection: NSRange,
        markedRange: NSRange,
        currentMatch: NSRange?
    ) -> [Int: [NSRange]] {
        let string = text as NSString
        var result: [Int: [NSRange]] = [:]
        // Paragraphs some trigger already covered whole: their single span subsumes anything
        // a later trigger could reveal inside them, so they are never appended to afterwards.
        var covered: Set<Int> = []
        addSpans(selection, of: string, to: &result, covering: &covered)
        // `NSNotFound` is what a text view with no active composition reports.
        if markedRange.location != NSNotFound {
            addSpans(markedRange, of: string, to: &result, covering: &covered)
        }
        if let currentMatch {
            addSpans(currentMatch, of: string, to: &result, covering: &covered)
        }
        return result
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

    /// `add(_:of:to:)`'s walk, collecting each touched paragraph's revealed spans instead
    /// of its bare offset: same `NSNotFound` and out-of-bounds guard, same clamp, same
    /// forward walk. Deliberately the same shape rather than a second traversal - the two
    /// answers have to agree on which paragraphs exist at all (ADR-0037 §D6's invariant).
    private static func addSpans(
        _ range: NSRange,
        of string: NSString,
        to result: inout [Int: [NSRange]],
        covering covered: inout Set<Int>
    ) {
        guard range.location != NSNotFound, range.location <= string.length else { return }
        let clamped = NSRange(
            location: range.location,
            length: min(max(range.length, 0), string.length - range.location)
        )
        var offset = clamped.location
        repeat {
            let paragraph = string.paragraphRange(for: NSRange(location: offset, length: 0))
            offset = NSMaxRange(paragraph)
            // Clipped to this paragraph, never translated whole: a trigger spanning two
            // paragraphs runs past the end of each one taken alone, and
            // `InlineSpanReveal.revealed` answers `[]` to a range out of its bounds.
            let start = max(clamped.location, paragraph.location)
            let end = min(NSMaxRange(clamped), NSMaxRange(paragraph))
            let local = NSRange(location: start - paragraph.location, length: max(end - start, 0))
            // Entirely covered by a non-empty trigger: one whole-paragraph span, no parse
            // (ADR-0037 §D5). Equal lengths imply a zero local location, the range being
            // inside the paragraph by construction.
            if paragraph.length > 0, local.length == paragraph.length {
                covered.insert(paragraph.location)
                result[paragraph.location] = [NSRange(location: 0, length: paragraph.length)]
                continue
            }
            guard !covered.contains(paragraph.location) else { continue }
            let spans = InlineSpanReveal.revealed(
                inParagraph: string.substring(with: paragraph), touchedBy: local
            )
            guard !spans.isEmpty else { continue }
            // Two triggers can land in one paragraph (a caret and the find bar's match, say):
            // their spans are unioned, kept sorted with the outer of two runs starting
            // together first - the order `InlineSpanReveal.constructs` itself returns.
            var merged = result[paragraph.location] ?? []
            for span in spans where !merged.contains(span) {
                merged.append(span)
            }
            result[paragraph.location] = merged.sorted {
                $0.location == $1.location ? $0.length > $1.length : $0.location < $1.location
            }
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
        let selection = textView.selectedRange()
        let markedRange = textView.markedRange()
        let revealed = MarkupReveal.paragraphs(
            in: textView.string, selection: selection, markedRange: markedRange, currentMatch: currentMatch
        )
        // Off means `[:]`, byte-for-byte `MarkupHiding`'s R-07 rule at this layer too
        // (ADR-0037 §D6): a text view with the setting off never asks `MarkupReveal` to
        // parse a single paragraph.
        let revealedSpans = parent.revealsInlineSpans
            ? MarkupReveal.inlineSpans(
                in: textView.string, selection: selection, markedRange: markedRange, currentMatch: currentMatch
              )
            : [:]
        // Both must be unchanged to skip work (ADR-0037 §D6) - a caret held still while
        // only the setting flips must still redraw, which a guard on `lastRevealed` alone
        // would miss.
        guard revealed != lastRevealed || revealedSpans != lastRevealedSpans else { return }
        lastRevealed = revealed
        lastRevealedSpans = revealedSpans

        // Each `apply` call answers with only the keys that changed against what the
        // delegate already held, so unioning the two is exactly "every paragraph either
        // trigger touched" and never the whole document.
        let changedParagraphs = decorations.apply(revealedParagraphs: revealed)
        let changedSpans = decorations.apply(revealedSpans: revealedSpans)
        let changed = changedParagraphs.union(changedSpans)
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
