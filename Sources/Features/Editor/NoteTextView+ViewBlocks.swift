import AppKit
import SwiftUI

/// A view block the editor is drawing right now: which fence of the note it is, and the
/// source its host renders.
///
/// Declared beside the view-block half rather than in `NoteTextView+Coordinator.swift`,
/// `DrawnTable`'s own reason: the three phases that fill, read and clear it are all in this
/// file, and the stored property that holds them is only a place to keep a value between two
/// of them.
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

extension NoteTextView.Coordinator {
    /// `ViewBlockController.apply(to:runs:markers:)`, under the name `applyStyling` calls in its
    /// sequence (ADR-0071 §D5). The pass and its state are the controller's, below.
    func applyViewBlocks(to textView: NSTextView, runs: [NSRange], markers: inout [Int: [HiddenMarker]]) {
        viewBlocks.apply(to: textView, runs: runs, markers: &markers)
    }
}

// MARK: - The controller (ADR-0071 §D2/§D3)

/// The view-block half's state and passes (ADR-0033 §D1/§D6/§D7/§D12/§D15; plan
/// `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 5): the styling pass that
/// recognises a closed `pergamenum-view` fence and registers its opening line's own marker,
/// the body/closing lines that leave the layout, and the host `ViewBlockHostStore` vends for
/// it, plus the caret rescue a fence hiding a line the caret was sitting in needs.
///
/// `TableBlockController`'s shape, diverging only where the sixth input
/// (`EditorDecorationDelegate.apply(viewBlockLines:)`/`apply(viewBlockHosts:)`, Task 2) and
/// the ordinal-keyed host store (`ViewBlockHostStore`, Task 4, ADR §D3) say to. The line walk
/// and the caret-rescue rule are not copied but shared: `HiddenBlockLines` and `CaretRescue`
/// (ADR-0071 §D8).
///
/// It holds no Coordinator (ADR-0071 §D3): the view's inputs come through `parent`, read at the
/// moment a pass uses them, and `commitViewBlock` and `growToFitTheText` are handed to `refresh`.
@MainActor
final class ViewBlockController {
    /// Read when a pass runs, never captured earlier (ADR-0071 §D3).
    private let parent: () -> NoteTextView?
    private let decorations: EditorDecorationDelegate

    /// The `NSHostingView` every view block on screen is drawn in, by the fence's own ordinal
    /// within the note (ADR-0033 §D3) - owned here for the reason `TableBlockController.grids`
    /// is: `EditorDecorationDelegate` cannot be `@MainActor`, so it cannot build a view and is
    /// handed finished ones through `decorations.apply(viewBlockHosts:)`.
    ///
    /// Keyed by ordinal and deliberately not by offset, which is where this store parts company
    /// with `TableGridStore`: an offset key would rebuild the host on every keystroke typed
    /// above the fence, and rebuilding it re-runs the query behind it (ADR-0009 §D7: never per
    /// keystroke).
    let hosts = ViewBlockHostStore()
    /// Each view block on screen, by its opening fence's offset - filled by `apply` inside the
    /// storage's editing transaction and read by `refresh` once it has closed.
    private(set) var drawn: [Int: DrawnViewBlock] = [:]
    /// The body and closing-fence lines already taken out of the layout, so an unchanged set
    /// does not re-invalidate it on every keystroke - the view-block pass's own change check,
    /// `TableBlockController.hiddenRows`' twin.
    private(set) var hiddenLines: Set<Int> = []
    /// Where the caret has to go once that transaction closes, when a line it was sitting in
    /// has just left the layout (the table rescue's twin, ADR-0033 §D15).
    private var pendingCaret: Int?
    /// True between a measured view-block height being stored and the coalesced re-layout
    /// running, so several fences reporting a height change within the same SwiftUI pass buy
    /// one relayout, not one each.
    private var pendingRelayout = false
    /// Which fence the selection was inside the last time it moved, or nil for none - the
    /// whole of ADR-0033 §D5's guard. A crossing into or out of a fence is the one selection
    /// change that has to re-run `applyStyling`, because that pass is the only producer of what
    /// a revealed fence looks like; every other arrow key pays one `NSRange?` comparison and
    /// nothing else.
    private var lastRevealed: NSRange?
    /// `Coordinator.growToFitTheText` as `refresh` last handed it, for the deferred re-layout.
    private var growToFit: ((NSTextView) -> Void)?

    init(parent: @escaping () -> NoteTextView?, decorations: EditorDecorationDelegate) {
        self.parent = parent
        self.decorations = decorations
    }

    /// Whether the selection crossed into or out of a fence since last asked (ADR-0033 §D5),
    /// recording the new answer when it did: `true` is what re-runs `applyStyling`.
    func selectionCrossedFence(in textView: NSTextView) -> Bool {
        let revealed = Self.revealedViewBlock(in: textView.string, selection: textView.selectedRange())
        guard revealed != lastRevealed else { return false }
        lastRevealed = revealed
        return true
    }

    /// Registers everything a view block needs drawn, from the `.viewBlockRun` spans
    /// `applyStyling` has just walked: the opening fence line's own `.viewBlock` marker, the
    /// body and closing-fence lines that leave the layout, and the host vended for each
    /// fence's ordinal.
    ///
    /// **Its own guard and its own change check**, the table pass's own reasoning: with
    /// `hidesMarkup` off this registers nothing and clears what it registered before (ADR
    /// §D12) - the escape hatch has to reach the enumeration refusal too, or the body lines
    /// would stay out of the layout with the backticks visible above them. `markers` is
    /// `inout` for the same reason the table pass's own is: the opening line's marker belongs
    /// in the same table `applyStyling` is about to hand over, and a second
    /// `apply(hiddenMarkers:)` call would be a second producer on one setter.
    ///
    /// The ordinal handed to `ViewBlockHostStore` counts every `.viewBlockRun` span the
    /// styler emitted, including one whose body fails to parse and draws `RenderedViewBlock`'s
    /// own error card instead of a query result (ADR §D7 follow-up): a fence's ordinal must
    /// not depend on whether the fence *above* it happens to parse this keystroke, or fixing a
    /// typo in the first block would re-run the second block's query.
    func apply(to textView: NSTextView, runs: [NSRange], markers: inout [Int: [HiddenMarker]]) {
        guard parent()?.hidesMarkup == true else {
            clear()
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
            // The opening fence's own backticks are the marker; the body and the closing fence
            // are the hidden lines (`HiddenBlockLines`, ADR-0071 §D8).
            let walked = HiddenBlockLines(text: text, anchor: opening, range: recognised.range, kind: .viewBlock)
            guard let marker = walked.marker else { continue }
            markers[opening, default: []].append(marker)

            var body: [String] = []
            for line in walked.lines {
                lines.insert(line.start)
                openingOfLine[line.start] = opening
                // The run ends at the closing fence line's own last character, so that line
                // is the only one whose contents end where the run does - it leaves the
                // layout with the body (C4) but is not part of what the block renders.
                if line.contentsEnd < NSMaxRange(recognised.range) {
                    body.append(
                        text.substring(with: NSRange(location: line.start, length: line.contentsEnd - line.start))
                    )
                }
            }
            found.append((opening, ordinal, body.joined(separator: "\n")))
        }

        // Pruned here and only here, `TableGridStore`'s own division of labour: a styling
        // pass is the one moment that knows every ordinal the note still spells, and a note
        // that loses a fence must not keep a live SwiftUI hierarchy over the index for it.
        let vended = hosts.hosts(for: found.map(\.ordinal), in: textView)
        var byOpening: [Int: NSView] = [:]
        var drawn: [Int: DrawnViewBlock] = [:]
        for entry in found {
            guard let host = vended[entry.ordinal] else { continue }
            // Keyed by paragraph offset on the way out, by ordinal on the way in: the
            // delegate is asked about a paragraph, the store must survive one moving (§D3).
            byOpening[entry.opening] = host
            drawn[entry.opening] = DrawnViewBlock(ordinal: entry.ordinal, source: entry.source)
        }
        decorations.apply(viewBlockHosts: byOpening)
        self.drawn = drawn

        guard lines != hiddenLines else { return }
        hiddenLines = lines
        decorations.apply(viewBlockLines: lines)
        pendingCaret = caretRescue(in: textView, lines: lines, openings: openingOfLine)
    }

    /// Pushes each drawn block's current source into the host already vended for it, and
    /// takes the caret out of a line that has just left the layout.
    ///
    /// **After `storage.endEditing()`, never inside it** - the table refresh's own rule, for
    /// both its reasons: a host lays SwiftUI out, and a caret rescue moves the selection, and
    /// neither belongs inside an open editing transaction.
    ///
    /// A new root view rather than a new host (ADR §D3): SwiftUI diffs it against the old
    /// one, and `RenderedViewBlock`'s `.task(id:)` re-runs only when the source, the scan
    /// generation or an explicit refresh actually changed - never once per keystroke, which
    /// is what ADR-0009 §D7 forbids. Rebuilding the root view every pass is what keeps the
    /// closures below current: `parent` is a struct SwiftUI replaces on each update, so a
    /// closure captured once at `makeNSView` time would go on calling an older column's
    /// `onFollowLink` for as long as the note stays open.
    ///
    /// **This is the whole of the vault reaching a drawn fence** (ADR §D9, R-04/R-07/R-09).
    /// `queries` is what turns "Nessun vault dietro questa vista" into rows, and it is passed
    /// with `notePath`/`vaultRoot`/`thumbnails` because a `render: gallery` block resolves an
    /// embedded file beside the note the same way an embed does. Nil-safe in every one of
    /// them: `DiaryView`/`TodayView` pass no `queries` (ADR Consequences) and the block says
    /// so instead of drawing an empty result.
    ///
    /// **`onOpenNote` is `parent.onFollowLink` and deliberately not a second door** (R-09): a
    /// row carries a title, which is the string a `[[wikilink]]` carries, so a click here is
    /// the click a wikilink already is - one lookup of one name, never two rules for it.
    ///
    /// **`onEditSource` sets the selection to the fence's own opening line** (ADR §D10),
    /// which is the offset this loop iterates by. §D4's range test then answers `true` for
    /// that fence, §D5's guard fires on the selection change, and the next pass draws the
    /// source instead of the attachment - the same landing the arrow keys reach from the line
    /// above, and the same one `caretRescue` below aims at. Weakly held, the reason
    /// `TableGridStore.view(for:in:)`'s own `resignToTextView` closure is: the host outlives
    /// nothing here, but a root view kept by the store must not be what keeps a text view
    /// alive.
    ///
    /// **`onEditQuery` builds the `ViewQueryEditRequest` here, not inside `rootView`** (ADR-0034
    /// §D2): this loop is where `opening` and `drawn.source` are known, and it is rebuilt every
    /// pass for the same staleness reason the two closures above are - a click reads whatever
    /// `drawn.source` this pass last recorded, never a value captured on an earlier one. The
    /// commit closure carries `opening` and `[weak textView]`, `commitViewBlock`'s own currency
    /// (`ViewQueryCommitTests.swift`'s fixture uses the identical shape).
    ///
    /// `commit` is `Coordinator.commitViewBlock(_:at:in:)`; `growToFit` is `growToFitTheText`,
    /// run by the coalesced relayout (ADR-0035 §D5).
    func refresh(
        in textView: NSTextView, theme: Theme,
        commit: @escaping (String, Int, NSTextView) -> Bool,
        growToFit: @escaping (NSTextView) -> Void
    ) {
        self.growToFit = growToFit
        for (opening, drawn) in self.drawn {
            guard let view = parent() else { continue }
            let host = hosts.host(for: drawn.ordinal, in: textView)
            hosts.update(
                ViewBlockHostStore.rootView(
                    source: drawn.source,
                    notePath: view.vault.notePath,
                    vaultRoot: view.vault.vaultRoot,
                    thumbnails: view.vault.thumbnails,
                    queries: view.vault.queries,
                    onEditSource: { [weak textView] in
                        guard let textView, opening <= (textView.string as NSString).length else { return }
                        textView.setSelectedRange(NSRange(location: opening, length: 0))
                    },
                    onOpenNote: view.onFollowLink,
                    onEditQuery: view.vault.onEditQuery.map { onEditQuery in
                        { [weak textView] in
                            let request = ViewQueryEditRequest(id: UUID(), source: drawn.source) {
                                [weak textView] body in
                                guard let textView else { return false }
                                return commit(body, opening, textView)
                            }
                            onEditQuery(request)
                        }
                    },
                    onHeightChange: { [weak self, weak host, weak textView] height in
                        guard let self, let host, let textView else { return }
                        self.heightChanged(height, on: host, in: textView)
                    },
                    theme: theme
                ),
                forOrdinal: drawn.ordinal
            )
        }
        guard let offset = pendingCaret else { return }
        pendingCaret = nil
        CaretRescue.place(offset, in: textView)
    }

    /// Records a host's freshly measured content height, and asks for a re-layout only when the
    /// rectangle TextKit would reserve for it actually changes (ADR-0035).
    private func heightChanged(_ height: CGFloat, on host: ViewBlockHostView, in textView: NSTextView) {
        guard let stored = ViewBlockAttachment.storableHeight(
            measured: height, current: host.measuredHeight.height
        ) else { return }
        host.measuredHeight.height = stored
        scheduleRelayout(in: textView)
    }

    /// One re-layout per turn, however many fences reported a height change in it - and never on
    /// the call stack that reported it: `onHeightChange` runs during SwiftUI's own layout of a
    /// view TextKit is laying out, so invalidating `NSTextLayoutManager` synchronously here would
    /// re-enter it. `Task { @MainActor }` leaves that stack; `invalidateLayout` is the same call
    /// `applyFolding`/`applyTransclusion` already make in production, and `growToFitTheText`
    /// afterwards is the existing, already-safe resize path (never sets a frame directly - see
    /// its own doc comment on why that matters here).
    private func scheduleRelayout(in textView: NSTextView) {
        guard !pendingRelayout else { return }
        pendingRelayout = true
        Task { @MainActor [weak self, weak textView] in
            guard let self else { return }
            self.pendingRelayout = false
            guard let textView, let manager = textView.textLayoutManager else { return }
            manager.invalidateLayout(for: manager.documentRange)
            self.growToFit?(textView)
        }
    }

    /// `FoldController.rescueCaret(in:from:)`'s and the table rescue's third twin (ADR §D15): a caret inside a
    /// body or closing-fence line that has just become hidden is an insertion point with
    /// nowhere to be drawn and nowhere to type. It goes to the opening fence line's own offset,
    /// which is where the block is and where `onEditSource` puts it too - the same offset,
    /// reached by the two doors §D10 names.
    ///
    /// Nearly unreachable once reveal lands (a caret inside a fence keeps it revealed), and
    /// written anyway for the reason the ADR names: a programmatic selection - a find match,
    /// an outline jump, `onScrollApplied` - reaches a body line without going through the
    /// reveal path at all.
    ///
    /// The rule itself is `CaretRescue.target`'s; the owner is the opening fence.
    private func caretRescue(
        in textView: NSTextView, lines: Set<Int>, openings: [Int: Int]
    ) -> Int? {
        CaretRescue.target(
            for: textView.selectedRange(), hidden: lines, in: textView.string as NSString
        ) { openings[$0] }
    }

    /// Clears every view block this pass has registered - the table pass's `clear()` twin,
    /// called both by `apply`'s own `hidesMarkup`-off guard (ADR §D12) and whenever a note stops
    /// naming any `pergamenum-view` fence at all.
    ///
    /// **Unconditional, unlike the table `clear()`'s own `hiddenRows` early return.** D12's
    /// escape hatch has to reach the delegate's enumeration refusal whatever this controller
    /// last registered itself, or lines hidden by some earlier pass would stay out of the
    /// layout with the backticks visible above them - the exact trap that guard was written
    /// for, one object further along. The per-keystroke cost the early return used to buy is
    /// bought instead inside `apply(viewBlockLines:)`, which compares the set before storing
    /// or logging anything.
    ///
    /// The host store itself is not pruned here: `hosts(for:in:)` needs a text view this call
    /// does not have, and the next pass with `hidesMarkup` on prunes to whatever the note
    /// still spells - a note with no fence left prunes to nothing.
    func clear() {
        drawn = [:]
        pendingCaret = nil
        decorations.apply(viewBlockHosts: [:])
        hiddenLines = []
        decorations.apply(viewBlockLines: [])
    }
}
