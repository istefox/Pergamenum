import AppKit

/// The Coordinator's own half of the view-query builder's commit (ADR-0034 §D3): the write a
/// "Fatto" tap in the sheet reaches - `commitTable`'s exact shape
/// (`NoteTextView+Tables.swift:56-77`), carried into this construct's own currency.
extension NoteTextView.Coordinator {
    /// Rewrites the fence whose opening line starts at `offset` to carry `body`, refusing -
    /// the buffer left untouched - the moment any of three sources disagree: the note as the
    /// **model** still spells it (`parent.text`), the note as the **buffer** spells it
    /// (`textView.string`), and, when there is one, the fence's own body as it was recorded
    /// at the last styling pass that actually drew it (`viewBlocks.drawn`, ADR §D3's "the
    /// source recorded when the sheet opened").
    ///
    /// `commitTable`'s own guard only needs the first two - its edit applies to whatever the
    /// live table still is, by index. This commit instead replaces the whole body with text
    /// computed outside the buffer, so a change to the fence between the request opening and
    /// the commit has to be caught even when it leaves model and buffer back in agreement
    /// with each other (R-13's "equal-length changes defeat a range-only guard" case: model
    /// and buffer can both move to the *same* new text and still disagree with what the sheet
    /// was handed).
    ///
    /// The third check is conditional on `viewBlocks.drawn` actually holding an entry for
    /// `offset`, rather than a required unwrap, because that store is reveal-gated
    /// (`applyViewBlocks`, ADR-0033 §D4): a fence the caret is sitting inside draws nothing
    /// and registers no entry there, and this call is reachable directly - not only through a
    /// sheet the app would never have shown over a revealed fence in the first place - so a
    /// caret parked on the fence must not make an otherwise-consistent commit unrefusable.
    /// Where a drawn record does exist, it is the strongest signal of drift and is honoured.
    ///
    /// `replaceAtomically(_:with:in:)` is the only write here (ADR-0019 §D7's precedent) - one
    /// `shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing` write, therefore one
    /// `Cmd+Z` regardless of how many controls moved in the sheet. The written text is always
    /// the canonical `` ```pergamenum-view\n<body>\n``` `` (ADR §D3): `viewBlockRun`'s range
    /// starts at the opening fence paragraph and ends at the closing fence line's own last
    /// character, its newline excluded, so writing over the whole range also normalises a
    /// hand-typed opening line's indentation or trailing spaces.
    @discardableResult
    func commitViewBlock(_ body: String, at offset: Int, in textView: NSTextView) -> Bool {
        guard parent.hidesMarkup,
              let recorded = EditorDecorationDelegate.viewBlockRun(
                  in: parent.text as NSString, atParagraphStart: offset
              ),
              let live = EditorDecorationDelegate.viewBlockRun(
                  in: textView.string as NSString, atParagraphStart: offset
              ),
              recorded.range == live.range,
              (parent.text as NSString).substring(with: recorded.range)
                  == (textView.string as NSString).substring(with: live.range)
        else { return false }

        let liveBody = Self.viewBlockBody(in: textView.string as NSString, range: live.range)
        if let recordedSource = viewBlocks.drawn[offset]?.source, recordedSource != liveBody {
            return false
        }

        let fence = "```\(ViewBlock.language)\n" + body + "\n```"
        return Self.replaceAtomically(live.range, with: fence, in: textView)
    }

    /// The fence's body alone, read back out of its own whole source range - the opening and
    /// closing fence lines split off, `DrawnViewBlock.source`'s own currency
    /// (`NoteTextView+ViewBlocks.swift`), so the live buffer's body can be compared against
    /// what the last styling pass recorded without re-parsing the fence a second way.
    ///
    /// Not private because `NoteTextView+Update.swift`'s `consumeInsertion` reads the body of the
    /// fence "Inserisci ▸ Vista…" just wrote through it.
    static func viewBlockBody(in text: NSString, range: NSRange) -> String {
        let lines = text.substring(with: range).components(separatedBy: "\n")
        guard lines.count >= 2 else { return "" }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }
}

// MARK: - The reveal predicate (ADR-0033 §D4/§D5)

extension ViewBlockController {
    /// The `pergamenum-view` fence (opening line through closing line, inclusive) whose
    /// source range `selection` currently intersects, or `nil` when it sits outside every
    /// fence in `text` (ADR-0033 §D4).
    ///
    /// Pure offset arithmetic against the note's own source - `text`/`selection` and not an
    /// `NSTextView`, `MarkupReveal.paragraphs(in:selection:markedRange:currentMatch:)`'s own
    /// shape (`NoteTextView+Reveal.swift`) - which is also why this construct's reveal
    /// survives the caret moving from the opening fence line into the body it has just
    /// revealed, unlike a paragraph-keyed reveal: the answer stays the same non-nil range for
    /// every position inside the block, body lines included (Context finding 3).
    ///
    /// Read in two places, which are two questions asked of one rule: the §D5 guard
    /// (`selectionCrossedFence(in:)`) asks whether the answer *changed* since the last
    /// selection change - the one thing that makes a crossing re-run `applyStyling` - and
    /// `apply` asks, of each fence it is about to register, whether that one is revealed
    /// (`selectionReveals(_:fence:)` below, the same intersection applied per fence, which is
    /// how §D4 states it).
    ///
    /// `nonisolated`, deliberately: pure text/range arithmetic touches no actor-isolated
    /// state at all, and `ViewBlockRevealPredicate` (`Tests/ViewBlockCaretTests.swift`)
    /// calls it from a plain, non-`@MainActor` test - the "no `NSTextView`" half of this
    /// task's own tester brief also means no forced hop to the main actor to ask it a
    /// question about a `String`.
    nonisolated static func revealedViewBlock(in text: String, selection: NSRange) -> NSRange? {
        viewBlockRanges(in: text).first { selectionReveals(selection, fence: $0) }
    }

    /// Every closed `pergamenum-view` fence's whole source range in `text`, in document
    /// order - `MarkdownStyler.viewBlockRuns(outside:)`' own two filters over
    /// `CodeFence.regions(in:)`, which is this app's single rule for where a fence begins
    /// and ends. `EditorDecorationDelegate.viewBlockRun(in:atParagraphStart:)` reads the
    /// same boundary from the live characters one block at a time, and the two agree
    /// because both stop at the closing fence line's own last character.
    ///
    /// **Closed fences only** (ADR §D6): a `CodeFence.Region` synthesised for an unclosed
    /// fence has `body.upperBound == range.upperBound`, and an unclosed fence draws nothing
    /// at all - so there is nothing to reveal, and nothing to re-render on leaving it.
    ///
    /// Deliberately **not** gated on `ViewBlock.parse` the way `viewBlockRun` is: whether a
    /// body parses decides what is *drawn* (ADR §D7), not where the block's source starts
    /// and stops, and a reveal that blinked off while a `render:` line is half-typed would
    /// re-style the note on every keystroke inside it.
    nonisolated static func viewBlockRanges(in text: String) -> [NSRange] {
        // A note that never spells the language holds no view block, and this is asked on
        // every arrow key (ADR §D5: "a note with no fence pays one comparison"): one
        // substring search over the characters, rather than `CodeFence.regions`' line-range
        // array for the whole note.
        guard text.contains(ViewBlock.language) else { return [] }
        return CodeFence.regions(in: text)
            .filter { $0.language == ViewBlock.language && $0.body.upperBound != $0.range.upperBound }
            .map { NSRange($0.range, in: text) }
            .filter { $0.location != NSNotFound }
    }

    /// Whether `selection` puts the caret - or any part of a non-empty selection - inside
    /// `fence`'s own source range, both delimiter lines included (ADR §D4).
    ///
    /// Inclusive at both ends: an empty selection at the run's last character is a caret on
    /// the closing fence line, and one at its first is a caret on the opening line. ADR-0018
    /// §D2's trigger 2 arrives here as a non-empty range starting outside and ending inside,
    /// which is the same test rather than a second one.
    nonisolated static func selectionReveals(_ selection: NSRange, fence: NSRange) -> Bool {
        guard selection.location != NSNotFound else { return false }
        return selection.location <= NSMaxRange(fence) && NSMaxRange(selection) >= fence.location
    }
}
