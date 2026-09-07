import AppKit
import SwiftUI

/// A view block the editor is drawing right now: which fence of the note it is, and the
/// source its host renders.
///
/// Declared beside the Coordinator's view-block half rather than in
/// `NoteTextView+Coordinator.swift`, `DrawnTable`'s own reason: the three phases that fill,
/// read and clear it are all in this file, and the stored property that holds them is only a
/// place to keep a value between two of them.
///
/// The **ordinal** and not the offset is what reaches `ViewBlockHostStore` (ADR §D3): an
/// offset key would rebuild the host - and re-run the query behind it - on every keystroke
/// typed above the fence, which ADR-0009 §D7 forbids. The offset is this table's own key,
/// because that is the key space `EditorDecorationDelegate` reads at layout time.
struct DrawnViewBlock {
    let ordinal: Int
    /// The fence's body alone, closing backticks and opening line excluded - exactly the
    /// string `ViewBlock.parse` reads and exactly what `MarkdownBlocksView` hands
    /// `RenderedViewBlock` on the transclusion path, so the two surfaces render one note
    /// from one string (ADR §D2: one renderer, two hosts).
    let source: String
}

/// The Coordinator's own half of the view-block pass (ADR-0033 §D1/§D6/§D7/§D12/§D15; plan
/// `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 5): the styling pass that
/// recognises a closed `pergamenum-view` fence and registers its opening line's own marker,
/// the body/closing lines that leave the layout, and the host `ViewBlockHostStore` vends for
/// it, plus the caret rescue a fence hiding a line the caret was sitting in needs.
///
/// `NoteTextView+Tables.swift`'s `applyTables`/`refreshTableGrids`/`tableCaretRescue`/
/// `clearTables` shape, copied and diverging only where the sixth input
/// (`EditorDecorationDelegate.apply(viewBlockLines:)`/`apply(viewBlockHosts:)`, Task 2) and
/// the ordinal-keyed host store (`ViewBlockHostStore`, Task 4, ADR §D3) say to.
extension NoteTextView.Coordinator {
    /// Registers everything a view block needs drawn, from the `.viewBlockRun` spans
    /// `applyStyling` has just walked: the opening fence line's own `.viewBlock` marker, the
    /// body and closing-fence lines that leave the layout, and the host vended for each
    /// fence's ordinal.
    ///
    /// **Its own guard and its own change check**, `applyTables`'s own reasoning: with
    /// `hidesMarkup` off this registers nothing and clears what it registered before (ADR
    /// §D12) - the escape hatch has to reach the enumeration refusal too, or the body lines
    /// would stay out of the layout with the backticks visible above them. `markers` is
    /// `inout` for the same reason `applyTables`'s own is: the opening line's marker belongs
    /// in the same table `applyStyling` is about to hand over, and a second
    /// `apply(hiddenMarkers:)` call would be a second producer on one setter.
    ///
    /// The ordinal handed to `ViewBlockHostStore` counts every `.viewBlockRun` span the
    /// styler emitted, including one whose body fails to parse and is drawn as raw source
    /// (ADR §D7): a fence's ordinal must not depend on whether the fence *above* it happens
    /// to parse this keystroke, or fixing a typo in the first block would re-run the second
    /// block's query.
    func applyViewBlocks(to textView: NSTextView, runs: [NSRange], markers: inout [Int: [HiddenMarker]]) {
        guard parent.hidesMarkup else {
            clearViewBlocks()
            return
        }

        let text = textView.string as NSString
        // Read once for the whole pass, and against the live selection rather than against a
        // remembered one: this pass is what decides whether a block is drawn or left as source,
        // so it has to ask the question at the moment it decides (ADR §D4).
        let selection = textView.selectedRange()
        var found: [(opening: Int, ordinal: Int, source: String)] = []
        var lines: Set<Int> = []
        var openingOfLine: [Int: Int] = [:]

        for (ordinal, run) in runs.enumerated() {
            // The third condition is the reveal (ADR §D4, R-05): the fence the selection is
            // inside is registered not at all this pass - no marker, so the opening line keeps
            // its backticks; no hidden lines, so the body and the closing fence come back into
            // the layout; no host, so nothing is drawn over any of it. Per fence and never as
            // one flag for the note: revealing one leaves every other one drawn, and the
            // ordinal is consumed from `runs.enumerated()` above whatever this fence's answer
            // is, so the fences below keep the ordinals - and therefore the hosts, and
            // therefore the query results - they had before the caret arrived (ADR §D3).
            guard NSMaxRange(run) <= text.length,
                  let recognised = EditorDecorationDelegate.viewBlockRun(
                      in: text, atParagraphStart: run.location
                  ),
                  !Self.selectionReveals(selection, fence: recognised.range)
            else { continue }
            let opening = run.location
            var start = 0, end = 0, contentsEnd = 0
            text.getParagraphStart(
                &start, end: &end, contentsEnd: &contentsEnd,
                for: NSRange(location: opening, length: 0)
            )
            guard contentsEnd > start else { continue }
            // Anchored at the opening fence paragraph's own start and covering its backticks
            // alone, never the whole run - the convention `.table` already uses, and the one
            // the delegate can read back, since it is asked about one paragraph at a time.
            markers[opening, default: []].append(
                HiddenMarker(range: NSRange(location: 0, length: contentsEnd - start), kind: .viewBlock)
            )

            var body: [String] = []
            var cursor = end
            while cursor < NSMaxRange(recognised.range) {
                var lineStart = 0, lineEnd = 0, lineContentsEnd = 0
                text.getParagraphStart(
                    &lineStart, end: &lineEnd, contentsEnd: &lineContentsEnd,
                    for: NSRange(location: cursor, length: 0)
                )
                lines.insert(cursor)
                openingOfLine[cursor] = opening
                // The run ends at the closing fence line's own last character, so that line
                // is the only one whose contents end where the run does - it leaves the
                // layout with the body (C4) but is not part of what the block renders.
                if lineContentsEnd < NSMaxRange(recognised.range) {
                    body.append(
                        text.substring(with: NSRange(location: lineStart, length: lineContentsEnd - lineStart))
                    )
                }
                guard lineEnd > cursor else { break }
                cursor = lineEnd
            }
            found.append((opening, ordinal, body.joined(separator: "\n")))
        }

        // Pruned here and only here, `TableGridStore`'s own division of labour: a styling
        // pass is the one moment that knows every ordinal the note still spells, and a note
        // that loses a fence must not keep a live SwiftUI hierarchy over the index for it.
        let hosts = viewBlockHosts.hosts(for: found.map(\.ordinal), in: textView)
        var byOpening: [Int: NSView] = [:]
        var drawn: [Int: DrawnViewBlock] = [:]
        for entry in found {
            guard let host = hosts[entry.ordinal] else { continue }
            // Keyed by paragraph offset on the way out, by ordinal on the way in: the
            // delegate is asked about a paragraph, the store must survive one moving (§D3).
            byOpening[entry.opening] = host
            drawn[entry.opening] = DrawnViewBlock(ordinal: entry.ordinal, source: entry.source)
        }
        decorations.apply(viewBlockHosts: byOpening)
        drawnViewBlocks = drawn

        guard lines != lastViewBlockLines else { return }
        lastViewBlockLines = lines
        decorations.apply(viewBlockLines: lines)
        pendingViewBlockCaret = viewBlockCaretRescue(in: textView, lines: lines, openings: openingOfLine)
    }

    /// Pushes each drawn block's current source into the host already vended for it, and
    /// takes the caret out of a line that has just left the layout.
    ///
    /// **After `storage.endEditing()`, never inside it** - `refreshTableGrids`'s own rule,
    /// for both its reasons: a host lays SwiftUI out, and a caret rescue moves the selection,
    /// and neither belongs inside an open editing transaction.
    ///
    /// A new root view rather than a new host (ADR §D3): SwiftUI diffs it against the old
    /// one, and `RenderedViewBlock`'s `.task(id:)` re-runs only when the source, the scan
    /// generation or an explicit refresh actually changed - never once per keystroke, which
    /// is what ADR-0009 §D7 forbids.
    func refreshViewBlockHosts(in textView: NSTextView, theme: Theme) {
        for drawn in drawnViewBlocks.values {
            viewBlockHosts.update(
                ViewBlockHostStore.rootView(source: drawn.source, theme: theme),
                forOrdinal: drawn.ordinal
            )
        }
        guard let offset = pendingViewBlockCaret else { return }
        pendingViewBlockCaret = nil
        textView.setSelectedRange(NSRange(location: offset, length: 0))
        textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
    }

    /// `rescueCaret(in:from:)`'s and `tableCaretRescue`'s third twin (ADR §D15): a caret
    /// inside a body or closing-fence line that has just become hidden is an insertion point
    /// with nowhere to be drawn and nowhere to type. It goes to the opening fence line's own
    /// offset, which is where the block is and where `onEditSource` will later put it too.
    ///
    /// Nearly unreachable once reveal lands (a caret inside a fence keeps it revealed), and
    /// written anyway for the reason the ADR names: a programmatic selection - a find match,
    /// an outline jump, `onScrollApplied` - reaches a body line without going through the
    /// reveal path at all.
    private func viewBlockCaretRescue(
        in textView: NSTextView, lines: Set<Int>, openings: [Int: Int]
    ) -> Int? {
        guard !lines.isEmpty else { return nil }
        let text = textView.string as NSString
        let caret = textView.selectedRange().location
        guard caret <= text.length else { return nil }
        let line = text.paragraphRange(for: NSRange(location: caret, length: 0)).location
        guard lines.contains(line) else { return nil }
        return openings[line]
    }

    /// Clears every view block this pass has registered - `NoteTextView+Tables.swift`'s
    /// `clearTables()` twin, called both by `applyViewBlocks`'s own `hidesMarkup`-off guard
    /// (ADR §D12) and whenever a note stops naming any `pergamenum-view` fence at all.
    ///
    /// **Unconditional, unlike `clearTables()`'s own `lastTableRows` early return.** D12's
    /// escape hatch has to reach the delegate's enumeration refusal whatever this Coordinator
    /// last registered itself, or lines hidden by some earlier pass would stay out of the
    /// layout with the backticks visible above them - the exact trap that guard was written
    /// for, one object further along. The per-keystroke cost the early return used to buy is
    /// bought instead inside `apply(viewBlockLines:)`, which compares the set before storing
    /// or logging anything.
    ///
    /// The host store itself is not pruned here: `hosts(for:in:)` needs a text view this call
    /// does not have, and the next pass with `hidesMarkup` on prunes to whatever the note
    /// still spells - a note with no fence left prunes to nothing.
    func clearViewBlocks() {
        drawnViewBlocks = [:]
        pendingViewBlockCaret = nil
        decorations.apply(viewBlockHosts: [:])
        lastViewBlockLines = []
        decorations.apply(viewBlockLines: [])
    }
}
