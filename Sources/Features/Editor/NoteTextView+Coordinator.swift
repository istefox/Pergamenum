import AppKit
import SwiftUI

/// Everything the editor's `NSTextView` needs a delegate for: styling, completion, the
/// slash menu, links, folding and the caret.
///
/// In a file of its own because `NoteTextView` grew past the length and the type-body
/// length SwiftLint warns at when folding arrived. The struct is now the inputs and the
/// two `NSViewRepresentable` methods; everything that happens *afterwards* is here.
extension NoteTextView {
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, LinkNavigatingDelegate {
        var parent: NoteTextView
        weak var textView: NSTextView?
        /// Read live, at the moment `textView(_:clickedOnLink:at:)` runs, never captured at
        /// init (ADR-0053 §D2 seam #4) - the method's own comment above it explains why the
        /// check has to be live. A test injects a fixed value here instead of driving a real
        /// `NSEvent`; production never overrides the default.
        var modifierFlags: () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
        /// The window's `undoManager` as of the last update, captured here because
        /// `dismantleNSView` runs after SwiftUI has already detached the text view from
        /// its window - `textView.undoManager` resolves through the responder chain and
        /// is nil by then, which would make the cleanup it performs a no-op. Its did-undo and did-redo
        /// notifications replay the edit path (ADR-0093 §D7), moved here when the manager changes.
        weak var undoManager: UndoManager? {
            didSet { if undoManager !== oldValue { observeUndoNotifications(of: undoManager) } }
        }
        /// The two undo observations; `nonisolated(unsafe)` for `frameObserver`'s reason below.
        /// Written by `NoteTextView+EditReplay.swift` (ADR-0045).
        nonisolated(unsafe) var undoObservers: [NSObjectProtocol] = []
        /// Guards the delegate callback from re-entering while styling rewrites
        /// attributes.
        private var isStyling = false
        /// What the restyle did, counted by path (ADR-0091 §D8, per-paragraph-restyle plan Task 3).
        private(set) var restyleLog = RestyleLog()
        /// The kill switch (ADR-0091 §D8): true makes every styling a full restyle and shifts
        /// nothing by itself. Read from `EditorRestyleSwitch` at `init`; a test sets it directly.
        var forcesFullRestyle: Bool
        /// What the layout still owes, heard from the storage (ADR-0093 §D1).
        let layoutDebt = LayoutDebt()
        /// The layout kill switch (ADR-0093 §D6): true lays out the whole note on every grow-to-fit.
        var forcesFullLayout: Bool
        /// The last character edit the text storage reported, in the text as it now is. Recorded
        /// with the kill switch on too: it is a report, and nothing reads it to decide anything.
        private(set) var lastRecordedEdit: StorageEdit?
        /// What the last binding write handed over, so the next update need not compare the whole
        /// note with the model (ADR-0094 §D9).
        var modelSync = ModelSync()
        /// The outline store this coordinator feeds (ADR-0096 §D6); `NoteTextView+Outline.swift`.
        var outlineFeed = NoteTextView.OutlineFeed()
        /// The structure map and the decision pending on the edits since the last styling
        /// (ADR-0091 §D2/§D3). Nil with the kill switch on, and until the first full restyle.
        private(set) var restyleScope: RestyleScope?
        /// How many character edits the storage has reported, so a styling knows whether any
        /// arrived since the last one.
        private var recordedEdits = 0
        /// What the last styling read, and the edit count it styled up to (ADR-0091 §D8). Nil until
        /// the first full restyle, which is then the only path.
        private var stylingBaseline: (inputs: StylingInputs, edits: Int)?
        /// What the last styling restyled, for the two passes that follow it: each takes its own
        /// copy once (`takeEmbedScan`, `takeTransclusionScan`), and a pass with no styling before
        /// it finds nil and covers the whole note (ADR-0091 §D7).
        private var embedScan: TransclusionController.Scan?
        private var transclusionScan: TransclusionController.Scan?
        /// What the editor draws besides the note's characters - folds and transcluded
        /// notes. Here rather than on the view: it is a fact about this text view's layout,
        /// and the view struct is rebuilt on every update (M8).
        let decorations = EditorDecorationDelegate()
        /// The ranges the spell checker must leave alone: markdown syntax, not prose (M8).
        /// Filled by `applyStyling`, which already knows what every range of the note is,
        /// so recognising them costs no second parse. On a step (ADR-0094 §D7).
        private(set) var unspellableRanges = OffsetRanges<NSRange>()
        /// Every `![[file.est]]`/`![alt](file.est)` line's own syntax range, found by the
        /// same `applyStyling` walk over `MarkdownStyler.spans(in:)` that already
        /// recognises `.embedRun` (ADR-0018 slice 3, Step 2). `NoteTextView+Embeds.swift`
        /// reads this rather than parsing the note a second time. On a step (ADR-0094 §D7).
        private(set) var embedRuns = OffsetRanges<NSRange>()
        /// Where each embed resolves to, once resolved - the render table
        /// `EditorDecorationDelegate` reads from, via `decorations.apply(embeds:)`, to
        /// actually draw one (ADR-0018 slice 3, Step 3). Owned here rather than resolved
        /// inline: filling it calls `ThumbnailStore`, an actor, and that delegate cannot
        /// be `@MainActor` at all (Step 2).
        let embeds = EmbedTable()
        /// The table grids, their hidden rows and the table pass (ADR-0074 §D2,
        /// `NoteTextView+Tables.swift`). `lazy` only because its provider captures `self`,
        /// which an initial value cannot; `parent` is read through it when a pass runs.
        private(set) lazy var tables = TableBlockController(
            parent: { [weak self] in self?.parent }, decorations: decorations
        )
        /// The view-block hosts, their hidden lines, the reveal crossing and the view-block
        /// pass (ADR-0074 §D2, `NoteTextView+ViewBlocks.swift`). `lazy` for `tables`' reason.
        private(set) lazy var viewBlocks: ViewBlockController = {
            let controller = ViewBlockController(
                parent: { [weak self] in self?.parent }, decorations: decorations, layout: layoutDebt
            )
            // The fences an arrow key is tested against come from the map when it is current
            // (ADR-0091 §D6), not from a parse of the note per key.
            controller.fenceRanges = { [weak self] selection in self?.currentViewBlockFences(touching: selection) }
            return controller
        }()
        /// The embed resize drag and its three phases (ADR-0074 §D2, ADR-0019 §D6,
        /// `NoteTextView+EmbedResize.swift`). `lazy` for `tables`' reason.
        private(set) lazy var embedResize = EmbedResizeController(
            parent: { [weak self] in self?.parent }, embeds: embeds, decorations: decorations
        )
        /// The transcluded renditions, their cache and the click that opens one (ADR-0074
        /// §D2, `NoteTextView+Transclusion.swift`). `lazy` for `tables`' reason.
        private(set) lazy var transclusion = TransclusionController(
            parent: { [weak self] in self?.parent }, decorations: decorations, layout: layoutDebt
        )
        /// The last fold layout and the folding pass (ADR-0074 §D2,
        /// `NoteTextView+Folding.swift`). `lazy` for `tables`' reason.
        private(set) lazy var folding = FoldController(
            parent: { [weak self] in self?.parent }, decorations: decorations, layout: layoutDebt
        )
        /// The revealed paragraphs and spans and the reveal pass (ADR-0074 §D2, ADR-0018 §D2,
        /// `NoteTextView+Reveal.swift`). `lazy` for `tables`' reason.
        private(set) lazy var reveal = RevealController(
            parent: { [weak self] in self?.parent }, decorations: decorations
        )
        /// The one-shot requests already honoured, the last replacement batch, note path and
        /// outline entry (ADR-0074 §D2, `NoteTextView+Requests.swift`). `lazy` for `tables`'
        /// reason.
        private(set) lazy var requests = RequestLedger(parent: { [weak self] in self?.parent })
        /// The range the last change landed on, for the scoped renumber (ADR-0082 §D6,
        /// `NoteTextView+ListEditing.swift`).
        let renumbering = ListRenumberLedger()
        /// Where the choice a click on a shared title puts up is shown (ADR-0083 §D5): the real
        /// menu in production, a spy in a test, because the real one runs modal tracking.
        var linkChoiceMenus: LinkChoiceMenuPresenting = LinkChoiceMenu()
        /// The Cmd+hover preview's trigger, tracking area, monitor and popover (ADR-0083 §D7,
        /// `NoteTextView+LinkPreview.swift`), once `linkPreview` below has built it: nil for a
        /// text view that never previewed, so the teardown builds nothing just to tear it down.
        private(set) var builtLinkPreview: LinkPreviewController?
        /// The observation that keeps the readable-width inset right as the pane is resized
        /// (ADR-0030 §D6). It has to exist because `updateNSView` does **not** run on a
        /// window resize - nothing in the SwiftUI graph changed - so without it a column
        /// centred at one width stays centred for that width until the next keystroke.
        ///
        /// `nonisolated(unsafe)` for the reason `GlobalHotkey`'s two C handles are: a
        /// `deinit` on a `@MainActor` type is not itself main-actor isolated, and this
        /// token is exactly the thing that outlives the object if nobody unregisters it.
        /// Every other access is on the main actor, and `deinit` runs when no other can be
        /// in flight.
        private nonisolated(unsafe) var frameObserver: NSObjectProtocol?

        init(parent: NoteTextView) {
            self.parent = parent
            forcesFullRestyle = EditorRestyleSwitch.forcesFullRestyle(
                arguments: ProcessInfo.processInfo.arguments, defaults: .standard
            )
            forcesFullLayout = EditorRestyleSwitch.forcesFullLayout(
                arguments: ProcessInfo.processInfo.arguments, defaults: .standard
            )
            super.init()
            embeds.attach(decorations: decorations)
        }

        deinit {
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
            for observer in undoObservers { NotificationCenter.default.removeObserver(observer) }
        }

        /// Takes the caret to a line the index pointed at, or to a match the find bar
        /// stepped onto.
        ///
        /// The caret and not only the scroller: arriving at a section and typing should
        /// write there, and a view that scrolled without moving the insertion point would
        /// send the next keystroke back where it came from.
        ///
        /// **`takingFocus` is why this has a parameter.** For the index it must be true, for
        /// the reason above. For the find bar it must be false, and the cost of getting that
        /// wrong is not subtle: the first letter typed into the find field changes the query,
        /// the query finds a match, the match scrolls, the scroll takes first responder, and
        /// the second letter is typed into the note. Found on screen on 2026-08-18, one
        /// keystroke into the first use.
        ///
        /// The selection still moves in both cases. It is what «Sostituisci» acts on, and it
        /// is what leaves the caret at the match when Esc closes the bar.
        func scroll(_ textView: NSTextView, to range: NSRange, takingFocus: Bool = true) {
            let length = (textView.string as NSString).length
            guard range.location <= length else { return }
            let clamped = NSRange(location: range.location, length: min(range.length, length - range.location))
            textView.setSelectedRange(NSRange(location: clamped.location, length: 0))
            textView.scrollRangeToVisible(clamped)
            guard takingFocus else { return }
            textView.window?.makeFirstResponder(textView)
        }

        /// Reports which index entry the caret is inside, and only when it changes.
        ///
        /// This runs on every cursor movement, so publishing the offset itself would put
        /// a SwiftUI update behind every arrow key. The entry changes far less often than
        /// the caret does.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Same guard as `textDidChange`, for the same reason: a registration that outlived its
            // view is met by a new view at the same address, and a stale coordinator that once
            // revealed a view block read the new view's caret as a fence crossing, restyled it with
            // its own note's styling (dropping every `.editorLink`) and took its storage's delegate
            // slot (PG-331, reproduced in the unit suite).
            guard textView.delegate === self else { return }
            // The format bar first, and entirely inside AppKit: it is a child window this view
            // owns, so showing it needs no SwiftUI update at all. That matters here more than
            // anywhere - this method runs on every arrow key.
            (textView as? CompletingTextView)?.refreshFormatBar(theme: parent.theme)
            // Before the guard below, on purpose: moving the caret within the same
            // outline entry - by far the common case - would otherwise never reveal
            // anything (ADR-0018 §D2).
            applyReveal(to: textView)
            // And the view block's own reveal beside it (ADR-0033 §D5), which cannot go through
            // `applyReveal`: that one is keyed by paragraph, and a fence's reveal is keyed on
            // its whole source range (§D4). No second, lighter pass either - `applyStyling` is
            // the only producer of the marker, the hidden-line set and the host map, so a
            // crossing re-runs it, and the stored answer is what keeps that to a crossing
            // rather than to every arrow key.
            //
            // **Never while a pass is already in flight.** `isStyling` is a flag and not a
            // counter, and this notification is posted by any programmatic selection change -
            // including the caret rescues `tables.refresh`/`viewBlocks.refresh` perform at the
            // end of `applyStyling`, where the flag is still set by its own `defer`. A pass
            // entered from there would clear the flag on its way out and leave the rest of the
            // outer one unguarded; the answer is recomputed on the next selection change
            // anyway, and the stored one is deliberately left stale so that comparison sees it.
            if !isStyling, viewBlocks.selectionCrossedFence(in: textView) {
                applyStyling(to: textView, theme: parent.theme)
            }
            reportLinkAtCaret(in: textView)
            reportSelection(in: textView)
            reportOutlineEntry(in: textView)
        }

        /// Puts the cursor in the editor.
        ///
        /// Retried once on the next pass because a text view built during this same
        /// update is not in a window yet, and `makeFirstResponder` on no window is a
        /// silent no-op - the note would open with the caret nowhere.
        func takeFocus() {
            guard let textView, textView.window?.makeFirstResponder(textView) != true else { return }
            Task { @MainActor [weak self] in
                guard let textView = self?.textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }

        /// `FoldController.apply(to:folded:theme:)`, kept here under the name `updateNSView`
        /// calls (ADR-0074 §D5, `NoteTextView+Folding.swift`).
        func applyFolding(
            to textView: NSTextView, folded: Set<Int>, hidesFrontmatter: Bool = false,
            toggledCallouts: Set<Int> = [], theme: Theme
        ) {
            folding.apply(
                to: textView, folded: folded, hidesFrontmatter: hidesFrontmatter,
                toggledCallouts: toggledCallouts, theme: theme
            )
        }

        /// The styling the update path asks for (ADR-0091 §D8): the dirty range when every edit
        /// since the last styling was line-local, nothing when there was none and no input moved,
        /// and a full restyle otherwise - the kill switch, no baseline (a storage this coordinator
        /// never styled, or a direct `textDidChange` before any styling), a storage whose delegate is
        /// not this coordinator, so nothing was recorded (ADR-0093 §D5), a changed input, or a
        /// decision that asked for one.
        func applyStylingIfNeeded(to textView: NSTextView, theme: Theme) {
            guard let storage = textView.textStorage else { return }
            let inputs = StylingInputs(storage: storage, textView: textView, theme: theme, parent: parent)
            guard !forcesFullRestyle, restyleScope != nil, storage.delegate === self,
                  let baseline = stylingBaseline, baseline.inputs == inputs
            else {
                applyStyling(to: textView, theme: theme)
                return
            }
            switch restyleScope?.take() {
            case .lines(let dirty)?:
                applyIncrementalStyling(to: textView, theme: theme, dirty: dirty)
            case nil where baseline.edits == recordedEdits:
                skipStyling(in: textView, theme: theme)
            case .full?, nil:
                applyStyling(to: textView, theme: theme)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isStyling, let textView = notification.object as? NSTextView else { return }
            // Only the notification of a view this coordinator is the delegate of: AppKit keys a delegate's
            // registration by the view's address, and a registration that outlives its view can be
            // met by a new view allocated at the same address. A coordinator whose view is gone then
            // styled the new one with its own baseline, took the storage's delegate slot from the
            // live coordinator, and made every keystroke a full restyle (measured in the full unit
            // suite: 50 KB prose at 700 ms against 6 ms alone).
            guard textView.delegate === self else { return }
            // The passes live beside the two hooks that replay them (`NoteTextView+EditReplay.swift`).
            runEditPasses(in: textView, renumbering: true)
        }

        // AppKit can no longer invoke this method on its own (issue #191): clickable spans
        // carry the app's own `.editorLink` attribute now, never the standard `.link`
        // (`MarkdownAttributedText.editorLink`'s doc comment has the full history, including
        // why `.link` used to make AppKit's own unreliable click-navigation gesture engage -
        // sometimes on a plain click nowhere near a link - and abort its drag-tracking loop
        // for the whole gesture). This method is reachable only from this app's own explicit
        // call site, `followLinkIfPresent(at:)` in `mouseDown`, which already checked Cmd
        // before calling in; the `guard` here is defense in depth, not a live necessity, kept
        // live off `NSEvent.modifierFlags` rather than trusted from the caller. "Apri
        // collegamento" (R-07) deliberately does NOT go through this method at all, since it
        // is the one gesture that must navigate without Cmd.
        //
        // `false`/`true` are back to their plain `NSTextViewDelegate` meaning ("did this
        // navigate") - nothing depends any more on the refusal path returning `true` to stop
        // AppKit's own default unclaimed-link handling, because AppKit never reaches this
        // method on an unclaimed link any more.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let flags = modifierFlags()
            guard flags.contains(.command) else { return false }
            let how = LinkOpening.forClick(shift: flags.contains(.shift), option: flags.contains(.option))
            return performLinkNavigation(link, how: how, fromClick: true, in: textView)
        }

        /// What the span loop collects for the passes after it, in the note's coordinates.
        struct StyledSpans {
            var unspellable: [NSRange] = []
            /// Paragraph-start offset to its hidden markers, each relative to it - the key
            /// space `EditorDecorationDelegate` reads at layout time (ADR-0018 §D1).
            var hiddenMarkers: [Int: [HiddenMarker]] = [:]
            var embedRuns: [NSRange] = []
            /// Every GFM table's whole source run (ADR-0029 §D4). Collected here rather than
            /// mapped to a `HiddenMarker` by `hiddenKind(for:)` like the other constructs:
            /// a table's run spans several paragraphs and the delegate is asked about one at
            /// a time, so `applyTables` is what splits it into the header's own marker and
            /// the rows that leave the layout.
            var tableRuns: [NSRange] = []
            /// Every closed `pergamenum-view` fence's whole source run (ADR-0033 §D14),
            /// collected here for the same reason `tableRuns` above is and split the same
            /// way: a fence's run spans several paragraphs, so `hiddenKind(for:)` maps it to
            /// no marker at all and `applyViewBlocks` is what turns it into the opening
            /// line's own `.viewBlock` marker plus the lines that leave the layout.
            var viewBlockRuns: [NSRange] = []
        }

        /// The span loop both stylings share (ADR-0091 §D4): `spans` carry `source`'s own indices,
        /// `source` starts `offset` UTF-16 units into the note, and `note` is the whole note, which a
        /// paragraph start is read from.
        private func addAttributes(
            of spans: [MarkdownStyler.StyledRange], in source: String, at offset: Int, note: NSString,
            to storage: NSTextStorage, context: inout MarkdownAttributedText.StyleContext
        ) -> StyledSpans {
            var collected = StyledSpans()
            let length = (source as NSString).length
            // A chip is drawing (ADR-0087 §D5): with the markup shown, a tag and a date stay as N1 colours them.
            let chipPadding = parent.hidesMarkup ? InlineChip.Metrics(context.theme).padding : nil
            // So is a quote's text (ADR-0087 §D7), and the spans after its marker keep their colours.
            let quoteText = parent.hidesMarkup ? NSColor(context.theme.color(.textSecondary)) : nil
            // With the markup shown nothing paints the highlight's pill, so it is the plain background
            // the card and the reading view give it (ADR-0087 §D5); with it hidden the pill is the paint.
            let highlight = parent.hidesMarkup ? nil : NSColor(context.theme.color(.highlight))
            for styled in spans {
                let local = NSRange(styled.range, in: source)
                guard local.location != NSNotFound, NSMaxRange(local) <= length else { continue }
                let nsRange = NSRange(location: local.location + offset, length: local.length)
                // Through the source-aware entry: a tag's or a date's click (n1-seams R-12,
                // R-13) is read off the characters it covers, not the span alone.
                storage.addAttributes(context.attributes(for: styled, in: source), range: nsRange)
                if let chipPadding { InlineChip.finish(styled.span, nsRange, in: storage, padding: chipPadding) }
                if let highlight, case .highlight = styled.span {
                    storage.addAttribute(.backgroundColor, value: highlight, range: nsRange)
                }
                if let quoteText, case .blockquoteMarker = styled.span {
                    EditorDecorationDelegate.colourQuoteText(after: nsRange, in: storage, color: quoteText)
                }
                if MarkdownStyler.suppressesSpellCheck(styled.span) { collected.unspellable.append(nsRange) }
                if let kind = Self.hiddenKind(for: styled.span) {
                    let paragraphStart = note.paragraphRange(
                        for: NSRange(location: nsRange.location, length: 0)
                    ).location
                    let spans = kind == .link
                        ? Self.linkDelimiters(in: nsRange, of: note)
                        : [nsRange]
                    for span in spans {
                        collected.hiddenMarkers[paragraphStart, default: []].append(
                            Self.hiddenMarker(kind, at: span, paragraphStart: paragraphStart)
                        )
                    }
                }
                // A heading with no title yet has no `.headingMarker` (`MarkdownStyler`), so the
                // gutter had no run to hang it by (PG-425). Its run is registered here, as a heading
                // marker the delegate hangs when revealed and never collapses (`isTitlelessHeading`).
                if case .heading = styled.span,
                   let run = EditorDecorationDelegate.titlelessHeadingRun(in: nsRange, of: note) {
                    let paragraphStart = note.paragraphRange(
                        for: NSRange(location: run.location, length: 0)
                    ).location
                    collected.hiddenMarkers[paragraphStart, default: []].append(
                        Self.hiddenMarker(.heading, at: run, paragraphStart: paragraphStart)
                    )
                }
                if case .embedRun = styled.span { collected.embedRuns.append(nsRange) }
                if case .tableRun = styled.span { collected.tableRuns.append(nsRange) }
                if case .viewBlockRun = styled.span { collected.viewBlockRuns.append(nsRange) }
            }
            return collected
        }

        /// Rewrites the whole attribute run. Notes are small enough that styling the
        /// full text on each keystroke stays imperceptible, and a visible-range
        /// optimisation would have to be re-run on every scroll to avoid unstyled
        /// text appearing as the user moves through the note.
        ///
        /// Since ADR-0091 the full path rather than the only one: a line-local keystroke takes
        /// `applyIncrementalStyling`. This one also installs the storage delegate that records the
        /// edits, rebuilds the scope over the text it styled, and clears what was recorded.
        func applyStyling(to textView: NSTextView, theme: Theme) {
            guard let storage = textView.textStorage else { return }
            isStyling = true
            defer { isStyling = false }

            let text = textView.string
            let nsText = text as NSString
            // One memoised `StyleContext` for the whole pass (Task 2, PG-139/#239) rather
            // than a fresh heading/bold/italic/mono/codeBlock dictionary rebuilt per span -
            // this loop, not `MarkdownAttributedText.attributed(_:theme:)`, is the actual hot
            // caller: it restyles the whole note on every keystroke (this function's own
            // header comment above).
            // The gutter (ADR-0081 §D1) arrives with the base style, so every paragraph of the
            // page starts its content at it; the transcluded picture and the card keep 0.
            var context = MarkdownAttributedText.StyleContext(
                theme: theme, links: true, gutter: theme.spacing(.gutter)
            )
            storage.beginEditing()
            storage.setAttributes(
                context.base,
                range: NSRange(location: 0, length: nsText.length)
            )
            let spans = MarkdownStyler.spans(in: text)
            var collected = addAttributes(of: spans, in: text, at: 0, note: nsText, to: storage, context: &context)
            // The gap after a prose or heading line (n1-seams R-14), after every span has put its
            // own style down and before `applyTransclusions` reserves its height: merged into
            // the style already on the line, never a fresh one, because a list line, a heading
            // and a transclusion each carry a style of their own (ADR-0030 §D5).
            ProseParagraphSpacing.apply(ProseTypography.paragraphSpacing(theme), to: storage, text: text, spans: spans)
            pushFaces(theme)
            // The table pass (ADR §D5), here beside `apply(hiddenMarkers:)` below - its own
            // guard, since `applyFolding`'s early return does not cover it, and its own
            // `apply(tableRows:)`/`apply(tableViews:)` calls. It adds the header line's own
            // `.table` marker to the table about to be handed over, rather than making a
            // second `apply(hiddenMarkers:)` call of its own.
            // Before `endEditing()`, not after: that call is what fires the document-wide
            // `.editedAttributes` that re-triggers the content manager's enumeration, so
            // the table has to already be current when it does (ADR-0018 §D1).
            applyTables(to: textView, runs: collected.tableRuns, markers: &collected.hiddenMarkers)
            // The view-block pass (ADR-0033 §D1), beside the table one and before
            // `endEditing()` for the same reason: that call fires the document-wide
            // `.editedAttributes` that re-triggers the content manager's enumeration, so
            // which lines are out of the layout has to already be current when it does.
            applyViewBlocks(to: textView, runs: collected.viewBlockRuns, markers: &collected.hiddenMarkers)
            decorations.apply(hiddenMarkers: collected.hiddenMarkers, hidingMarkup: parent.hidesMarkup)
            // Pushed here rather than only from `applyReveal` (ADR-0037 §D7/F6): that pass
            // early-returns when the computed reveal equals what it last applied, so a
            // toggle flip with a stationary caret would otherwise never reach the delegate.
            // `applyStyling` runs on every `updateNSView` whose inputs moved.
            decorations.apply(revealsInlineSpans: parent.revealsInlineSpans)
            storage.endEditing()
            // The line after a note's final newline has no character to carry a style, so TextKit
            // places it, and the caret on it, by the typing attributes, which a plain-text view never
            // takes from the storage: without the base style the caret there sat a gutter left of
            // the column (PG-426).
            textView.typingAttributes = context.base
            unspellableRanges = OffsetRanges(sorted: MarkdownStyler.merged(collected.unspellable))
            self.embedRuns = OffsetRanges(sorted: collected.embedRuns)
            settleBaseline(storage: storage, textView: textView, text: text, theme: theme)
            restyleLog.full += 1
            // After the transaction, deliberately: a grid resizes itself and a caret rescue
            // moves the selection, and neither belongs inside an open editing session.
            tables.refresh(in: textView, theme: theme)
            refreshViewBlocks(in: textView, theme: theme)
        }

        /// The faces and colours the decoration delegate draws with, pushed on every styling.
        private func pushFaces(_ theme: Theme) {
            // A drawn embed's resize handle, from a token (ADR-0019 §D5) - the same
            // one-line hand-over `decorations.badgeColor = NSColor(theme.color(...))`
            // makes in the folding pass (`FoldController.apply`, `NoteTextView+Folding.swift`).
            // Here rather than threaded through
            // `applyEmbeds(to:)`, which has no theme and would need one at three call
            // sites; and here rather than beside `badgeColor`, because `applyFolding`
            // returns early for a note with nothing folded, which is most notes.
            // `.accentPrimary` and not the badge's `.textTertiary`: this square is
            // painted over an arbitrary picture and has to be aimed at, which a tertiary
            // text grey on a photograph is not.
            decorations.handleColor = NSColor(theme.color(.accentPrimary))
            // The thematic break's own line (ADR-0029 §D1), from `borderSubtle` and not
            // from a text token: it is a separator between blocks, which is what that token
            // names, and it is the only decoration here that is not drawn over text.
            decorations.ruleColor = NSColor(theme.color(.borderSubtle))
            // The Pratiche anchor line's marker (ADR-0076 §D9), from `textTertiary`: the colour
            // the raw line takes (`MarkdownAttributedText`), so revealing it changes its shape and
            // not its tone.
            decorations.messageAnchorColor = NSColor(theme.color(.textTertiary))
            // Its size from the caption token, the fold badge's own (below): both are small chrome
            // drawn beside a line, not text of the note.
            decorations.messageAnchorPointSize = theme.nsFont(.caption).pointSize
            // The two faces the delegate draws with (ADR-0030 §D2), resolved here for the same
            // reason the three colours above are: `EditorDecorationDelegate` is not
            // `@MainActor` and cannot read a `Theme` itself, so it is handed finished values.
            decorations.proseFont = ProseTypography.prose(theme)
            // The fold badge, at the caption token's size rather than the token's own: the
            // badge is chrome counting hidden lines, so it takes the mono face - a number that
            // changes width as it grows would make the badge twitch - at the size the rest of
            // this app's captions use. Pushed here and not in `applyFolding`, which returns
            // early for a note with nothing folded, i.e. for most notes.
            decorations.badgeFont = ProseTypography.mono(theme, size: theme.nsFont(.caption).pointSize)
            // The checkbox glyph's face, 7pt over prose (`ProseTypography.checkbox(_:)`) - the
            // one character `checkboxParagraph(at:storage:)` sizes on its own.
            decorations.checkboxFont = ProseTypography.checkbox(theme)
            // What a revealed list, quote or heading hangs its marker in (ADR-0081 §D2-§D4): the
            // gutter the base style above starts every paragraph at, and the face a heading's
            // `#` run takes there. The card pushes neither and stays at gutter 0 (§D6).
            decorations.gutter = theme.spacing(.gutter)
            decorations.markerFont = ProseTypography.gutterMarker(theme)
            // What ADR-0087's pills, fence chrome and quotes draw with.
            decorations.constructStyle = EditorConstructStyle(theme)
        }

        /// Which kind of hidden marker a span becomes, or none for a span that is only
        /// coloured.
        ///
        /// The note editor's own table, not the card's: `CardTextView`'s switch ends in
        /// `default: nil`, the seam ADR-0029 §D17 relies on to keep the live `NSView` grid
        /// above all, then the view block and the message anchor out of a card whose text
        /// view is deallocated on every culling-rect crossing; ADR-0037's §D8 amendment
        /// gave the card strikethrough and links, ADR-0082 §D8 the blockquote and the rule.
        /// The two are one call apart on purpose.
        static func hiddenKind(for span: MarkdownStyler.Span) -> HiddenMarker.Kind? {
            switch span {
            case .headingMarker: .heading
            case .emphasisMarker: .emphasis
            case .embedRun: .embed
            case .listMarker: .list
            case .taskMarker: .checkbox
            // The four ADR-0029 constructs (plan `2026-09-02-editor-wysiwyg-unification`,
            // Task 2). `.linkSyntax` is the one span here that was already emitted and only
            // coloured before this chain (§D1) - and the one whose range is not itself a
            // delimiter, which `linkDelimiters(in:of:)` below is what splits.
            case .blockquoteMarker: .blockquote
            case .strikethroughMarker: .strikethrough
            case .horizontalRule: .rule
            // ADR-0076 §D9: the rule's whole-line path, one line over.
            case .messageAnchor: .messageAnchor
            case .linkSyntax: .link
            // ADR-0087: the pills' delimiters, the fence chrome, a callout's title marker and an
            // embed chip's brackets, each collapsed on the generic path.
            case .inlineCodeMarker: .inlineCode
            case .highlightMarker: .highlight
            case .fenceOpening: .fenceOpening
            case .fenceClosing: .fenceClosing
            case .calloutMarker: .calloutMarker
            case .embedChipMarker: .embedChip
            // The one ADR-0029 construct that is *not* mapped here, and the reason is
            // structural rather than an omission: a `.tableRun` covers the header line, the
            // delimiter row and every body row, while a `HiddenMarker` is anchored to one
            // paragraph and read back when the delegate is asked about that paragraph alone.
            // `applyTables` (`NoteTextView+Tables.swift`) is what splits the run into the
            // header's own `.table` marker and the rows that leave the layout entirely.
            case .tableRun: nil
            default: nil
            }
        }

        /// The bracket runs of a `.linkSyntax` span - what is actually concealed, as
        /// opposed to what the span covers (ADR-0029 §D1, R-04).
        ///
        /// The asymmetry this exists for: `wikilinkSpans(in:from:outside:)` emits one
        /// `.linkSyntax` over the *whole* `[[Curva]]` and then paints `.linkTarget` on top
        /// of the title, because later spans win on overlap - so mapping that span straight
        /// to a `.link` marker would hide the title too and leave an empty line where a
        /// reference was. `markdownLinkSpans(in:absolute:)` emits the CommonMark form's `[`
        /// and `](url)` already split, and those are handed back untouched.
        ///
        /// An embed's `![[foto.png]]` gets none at all, and that is not only deference to
        /// `embedParagraph(at:storage:)` owning that run (ADR-0018 slice 3, whose branch
        /// runs first and would win anyway once a picture has resolved): the `!` is *inside*
        /// the opening delimiter and is the whole of what makes the run an embed, so hiding
        /// it would draw an embed as an ordinary link for as long as the render is in
        /// flight - and, for an inline `![[…]]` that never becomes a picture, for good.
        ///
        /// In UTF-16 and not in characters, like every range in this table: a target
        /// holding an emoji is two units per character, and offsets counted the other way
        /// would put the closing bracket's range one unit short of where it is.
        static func linkDelimiters(in span: NSRange, of text: NSString) -> [NSRange] {
            guard span.length > 0, NSMaxRange(span) <= text.length else { return [] }
            let run = text.substring(with: span)
            guard !run.hasPrefix("![[") else { return [] }
            let opening = run.hasPrefix("[[") ? 2 : 0
            guard opening > 0, run.hasSuffix("]]"), span.length > opening + 2 else { return [span] }
            return [
                NSRange(location: span.location, length: opening),
                NSRange(location: NSMaxRange(span) - 2, length: 2)
            ]
        }

        /// One span's hidden marker, its range relative to its own paragraph's start - the
        /// key space `EditorDecorationDelegate` reads at layout time (ADR-0018 §D1).
        ///
        /// A `.list` marker's range starts at the paragraph's own start, indentation
        /// included, and not at the marker character the way `.heading`/`.emphasis` do
        /// (ADR-0028 §D4): `listMarkerSpan` deliberately begins its span *after* the indent
        /// (`absolute(indent.count, marker.length)`), and the indent has to be inside the
        /// range or the delegate cannot collapse it - nor read the item's nesting level back
        /// out of it, which it does at layout time because `HiddenMarker.Kind.list` carries
        /// no level of its own. Only the start moves; the end is the span's own, so the
        /// range still stops at the marker's trailing space.
        static func hiddenMarker(
            _ kind: HiddenMarker.Kind, at span: NSRange, paragraphStart: Int
        ) -> HiddenMarker {
            let start = kind == .list ? paragraphStart : span.location
            return HiddenMarker(
                range: NSRange(location: start - paragraphStart, length: NSMaxRange(span) - start),
                kind: kind
            )
        }

        /// Keeps the spelling underline off markdown syntax (M8).
        ///
        /// AppKit asks before it marks anything, which is the only place this can be done:
        /// the checker works on the string, and the string is the source, so it has no way
        /// of knowing that `#project-pergamenum` is a tag and not a misspelling of anything.
        /// Returning zero means "no indicator here" and leaves the rest of the note checked.
        func textView(
            _ textView: NSTextView,
            shouldSetSpellingState value: Int,
            range affectedCharRange: NSRange
        ) -> Int {
            let isSyntax = unspellableRanges.intersects(affectedCharRange)
            return isSyntax ? 0 : value
        }

        /// Makes the text view as tall as what it now has to draw, and optionally brings the
        /// caret back into view.
        ///
        /// Styling changes heights - a heading carries paragraph spacing, a transcluded line
        /// reserves room under itself - and a vertically resizable `NSTextView` under TextKit 2
        /// does **not** notice on its own. Measured on a note of forty lines with a heading
        /// near the end: the layout needed 1431 points and the view stayed at the 1244 it was
        /// before the attributes went on, so the last 187 points of the note were outside the
        /// scroll view's reach. On screen that is a note that stops at its final heading, a
        /// click low in the pane landing lines above where it was aimed, and text typed at the
        /// end going into the file without ever appearing.
        ///
        /// Three other ways were tried and each is worth knowing about:
        ///
        /// - `sizeToFit()` does nothing at all here.
        /// - `layoutSubtreeIfNeeded()` works on a text view built by hand in a test and does
        ///   **not** work in the running app - the worst of the four, because it makes the
        ///   unit suite green over a defect that is still on screen.
        /// - `setFrameSize` works and costs too much: changing the frame re-enters SwiftUI's
        ///   update pass, `updateNSView` runs again while the binding still holds the text as
        ///   it was one keystroke ago, and its "only touch the text when the model diverges"
        ///   guard writes that old value back. It cost the diary everything typed into it.
        ///   `DiaryUITests` caught that; the unit suite stayed green. Deferring it by a run
        ///   loop turn did not help.
        ///
        /// Asking the viewport layout controller to run leaves the resizing to AppKit, which
        /// is what makes it safe: nothing here sets a frame, so nothing here re-enters SwiftUI.
        ///
        /// What was invalidated is laid out first, and only that (ADR-0093 §D4, which reopens and scopes
        /// ADR-0082 §D7). Every way a fragment loses its layout reaches `layoutDebt`: a processed
        /// storage edit is heard, a whole-document invalidation goes through its door, a new container
        /// width is compared, so a fragment outside what is owed keeps a layout that is still valid and
        /// no height is an estimate. The document range is laid out when everything is owed, the width
        /// moved, the storage's delegate is not this coordinator (the record then vouches for nothing),
        /// the length moved unheard, or `forcesFullLayout` is on (§D6). What failed G-grow on 2026-10-10
        /// was the other shape: the caret's fragment and the viewport, laid out by position while every
        /// update invalidated the whole note, so everything above the viewport became an estimate and a
        /// click after Cmd+Down landed on other text.
        func growToFitTheText(_ textView: NSTextView, revealingCaret: Bool = false) {
            guard let layout = textView.textLayoutManager else { return }
            layoutDebt.settle(
                textView, delegateIsCoordinator: textView.textStorage?.delegate === self, forcesWhole: forcesFullLayout
            )
            let needed = layout.usageBoundsForTextContainer.height
                + textView.textContainerInset.height * 2
            if abs(textView.frame.height - needed) > 0.5 {
                layout.textViewportLayoutController.layoutViewport()
            }
            // After the resize, so the scroll is not clamped to the height the note had a
            // moment ago and left short of the end.
            if revealingCaret { textView.scrollRangeToVisible(textView.selectedRange()) }
        }

        /// The vertical `textContainerInset`, unchanged by ADR-0030 and named here only so
        /// the two places that assign the pair cannot disagree about it.
        static let verticalInset: CGFloat = 20
        /// The horizontal inset the editor has always had, now the floor of the readable
        /// width rather than the whole of it (ADR-0030 §D6).
        static let minimumHorizontalInset: CGFloat = 24

        /// Recomputes the readable-width inset whenever the scroll view's own frame changes.
        ///
        /// On the clip view rather than on the text view: with `widthTracksTextView` left at
        /// its default `true`, the text view's width *follows* the clip view's, so the clip
        /// view is the one that knows the new width first - and reading the width the column
        /// is about to have, rather than the one it still has, is what keeps the inset from
        /// lagging a resize by a frame.
        ///
        /// Torn down in `deinit` through `frameObserver`: the block-based observer is not
        /// removed for us, and a coordinator is created per editor pane.
        func observeWidthChanges(of scrollView: NSScrollView) {
            scrollView.contentView.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                // The queue is `.main`, so this block runs on the main thread by
                // construction and the assumption is checked rather than asserted blind.
                MainActor.assumeIsolated {
                    guard let self, let textView = self.textView else { return }
                    self.applyReadableWidth(to: textView)
                }
            }
        }

        /// Applies `horizontalInset` to the text view at its current width.
        ///
        /// Called from three places - `makeNSView`, `updateNSView` and the frame
        /// observation above - because the width can change without the SwiftUI graph
        /// changing (a window resize) and the setting can change without the width changing
        /// (Impostazioni, R-10). Both have to reach an already-open note.
        ///
        /// **Nothing here sets a frame**, deliberately: `growToFitTheText`'s header above
        /// records what `setFrameSize` on this text view cost the Diario. The whole effect
        /// is one inset, and `widthTracksTextView` stays `true`.
        func applyReadableWidth(to textView: NSTextView) {
            let width = textView.enclosingScrollView?.contentView.bounds.width
                ?? textView.frame.width
            // Less the gutter every paragraph carries as its own indent (ADR-0081 §D1): the
            // column stays where the readable inset puts it, and the gutter sits inside the
            // container where a marker can hang into it.
            let inset = EditorGutter.containerInset(
                readableInset: Self.horizontalInset(
                    viewWidth: width,
                    cap: parent.theme.spacing(.readable),
                    minimum: Self.minimumHorizontalInset,
                    isOn: parent.readableWidth
                ),
                gutter: parent.theme.spacing(.gutter)
            )
            // Assigning an inset invalidates the layout, so an unchanged one is not assigned:
            // a resize drag posts a notification per frame and each would otherwise relayout
            // the whole note for nothing.
            guard abs(textView.textContainerInset.width - inset) > 0.5 else { return }
            textView.textContainerInset = NSSize(width: inset, height: Self.verticalInset)
        }

        /// The horizontal `textContainerInset` that keeps the text column readable
        /// (ADR-0030 §D6): `max(minimum, (viewWidth - cap) / 2)` when `isOn`, `minimum`
        /// otherwise - `minimum` is today's fixed `24`, unconditionally, when the setting
        /// is off or the view is narrower than `cap`.
        ///
        /// Pure and static on purpose, mirroring `hiddenMarker(_:at:paragraphStart:)` above:
        /// the geometry itself needs a live window, but this arithmetic does not, so it is
        /// tested without one.
        ///
        /// The `max` is the whole of the degenerate-width handling: a view no wider than
        /// `cap` - and a view of zero or negative width, which is what a text view not yet
        /// in a window reports - yields a negative half-difference and floors at `minimum`,
        /// so an inset out of this function is never smaller than today's fixed one and
        /// never negative.
        nonisolated static func horizontalInset(
            viewWidth: CGFloat, cap: CGFloat, minimum: CGFloat, isOn: Bool
        ) -> CGFloat {
            guard isOn else { return minimum }
            return max(minimum, (viewWidth - cap) / 2)
        }
    }
}

extension NoteTextView.Coordinator {
    /// The Cmd+hover preview's controller, built on first use for `tables`' reason. In this file so
    /// `builtLinkPreview` keeps its private setter.
    var linkPreview: LinkPreviewController {
        if let builtLinkPreview { return builtLinkPreview }
        let made = LinkPreviewController.live(for: self)
        builtLinkPreview = made
        return made
    }
}

// MARK: - The incremental restyle (ADR-0091)
//
// In this file, not the class body, for SwiftLint's type-body length; here and not in a file of its
// own because it writes the class's private state.
extension NoteTextView.Coordinator {
    /// The view-block hosts' root views, rebuilt after every styling, whatever path it took: each
    /// carries the closures and the query source of the `parent` it was built from
    /// (`ViewBlockController.refresh`). Same rule as the table refresh, same reason (ADR-0033 §D15):
    /// a host lays SwiftUI out and the caret rescue moves the selection. The commit holds `self`
    /// strongly, as the edit request it ends up in always has; the resize path does not.
    func refreshViewBlocks(in textView: NSTextView, theme: Theme) {
        viewBlocks.refresh(in: textView, theme: theme, commit: { self.commitViewBlock($0, at: $1, in: $2) },
                           growToFit: { [weak self] in self?.growToFitTheText($0) })
    }

    /// The full restyle's bookkeeping for the next one (ADR-0091 §D2, §D8): the storage delegate that
    /// records the edits, installed the first time this storage is styled; a scope built over the
    /// text just styled, none with the kill switch on; the inputs it read; and a whole-note scan for
    /// the two passes that follow.
    func settleBaseline(storage: NSTextStorage, textView: NSTextView, text: String, theme: Theme) {
        // Installing the delegate owes the layout everything (ADR-0093 §D2): the full restyle's own
        // edit was heard by whoever held the slot before.
        if storage.delegate !== self {
            storage.delegate = self
            layoutDebt.oweEverything()
        }
        restyleScope = forcesFullRestyle ? nil : RestyleScope(text: text)
        rebuildOutline(from: text)
        folding.restyled(text)
        let inputs = StylingInputs(storage: storage, textView: textView, theme: theme, parent: parent)
        stylingBaseline = (inputs, recordedEdits)
        embedScan = .whole
        transclusionScan = .whole
    }

    /// The dirty range's restyle (ADR-0091 §D4/§D5): the spans of `dirty` alone, through the loop
    /// the full restyle runs, over attributes reset on `dirty` only; the tables, view blocks and
    /// embeds inside it; the markers and the spell checker's ranges spliced in; and the fragment's
    /// own map handed back to the scope. Everything outside `dirty` is what the shift left at each
    /// edit.
    func applyIncrementalStyling(to textView: NSTextView, theme: Theme, dirty: NSRange) {
        // No binding of the scope: one alive across `absorb` below shares the map's storage, and the
        // mutation would copy every store whole (ADR-0094 §D4). What is needed of it is read into locals.
        // A fence's ordinal counts every fence above it in the note (ADR-0033 §D3); the map's runs
        // above `dirty` are the note's own, shifted.
        guard let storage = textView.textStorage,
              let listSeed = restyleScope?.listSeed(at: dirty.location),
              let firstOrdinal = restyleScope?.map.viewBlockRuns.count(endingAtOrBefore: dirty.location)
        else {
            return
        }
        isStyling = true
        defer { isStyling = false }

        let note = storage.string as NSString
        let fragment = note.substring(with: dirty)
        let spans = MarkdownStyler.spans(
            inFragment: fragment,
            context: .init(listSeed: listSeed, readsFrontmatter: dirty.location == 0)
        )
        var context = MarkdownAttributedText.StyleContext(theme: theme, links: true, gutter: theme.spacing(.gutter))
        storage.beginEditing()
        storage.setAttributes(context.base, range: dirty)
        var collected = addAttributes(
            of: spans, in: fragment, at: dirty.location, note: note, to: storage, context: &context
        )
        let spacing = ProseTypography.paragraphSpacing(theme)
        if spacing != 0 {
            ProseParagraphSpacing.merge(spacing, into: storage, ranges: ProseParagraphSpacing.paragraphRanges(
                inFragment: fragment, offset: dirty.location, spans: spans
            ))
        }
        pushFaces(theme)
        applyTables(to: textView, runs: collected.tableRuns, markers: &collected.hiddenMarkers, within: dirty)
        applyViewBlocks(
            to: textView, runs: collected.viewBlockRuns, markers: &collected.hiddenMarkers,
            within: dirty, firstOrdinal: firstOrdinal
        )
        decorations.splice(hiddenMarkers: collected.hiddenMarkers, in: dirty, hidingMarkup: parent.hidesMarkup)
        decorations.apply(revealsInlineSpans: parent.revealsInlineSpans)
        storage.endEditing()

        unspellableRanges.spliceMerging(MarkdownStyler.merged(collected.unspellable), replacing: dirty)
        embedRuns.splice(collected.embedRuns, replacing: dirty)
        restyleScope?.absorb(StructureMap(text: fragment), at: dirty.location, replacing: dirty)
        spliceOutline(in: textView, note: note, dirty: dirty)
        folding.restyled(fragment, replacing: dirty)
        stylingBaseline?.edits = recordedEdits
        owe(.range(dirty))
        restyleLog.incremental += 1
        restyleLog.lastDirtyRange = dirty
        tables.refresh(in: textView, theme: theme, within: dirty)
        refreshViewBlocks(in: textView, theme: theme)
    }

    /// A styling asked for over text and inputs it already styled (ADR-0091 §D8, R-08): the second
    /// pass of a keystroke. Nothing is restyled and the passes after it scan nothing; the view-block
    /// hosts still take the current `parent`.
    func skipStyling(in textView: NSTextView, theme: Theme) {
        restyleLog.skipped += 1
        owe(TransclusionController.Scan.none)
        refreshViewBlocks(in: textView, theme: theme)
    }

    /// Adds what this styling restyled to the scans the two passes after it still owe: a styling
    /// whose passes never ran (the first one, before the view is wired up) leaves its scan standing
    /// for the next passes, rather than a later skip wiping it.
    private func owe(_ scan: TransclusionController.Scan) {
        embedScan = embedScan.map { $0.then(scan) } ?? scan
        transclusionScan = transclusionScan.map { $0.then(scan) } ?? scan
    }

    /// The scan the last styling left for the embed pass, taken once.
    func takeEmbedScan() -> TransclusionController.Scan {
        defer { embedScan = nil }
        return embedScan ?? .whole
    }

    /// The scan the last styling left for the transclusion pass, taken once.
    func takeTransclusionScan() -> TransclusionController.Scan {
        defer { transclusionScan = nil }
        return transclusionScan ?? .whole
    }

    /// Takes one character edit the storage reported (ADR-0091 §D2): records it, folds it into the
    /// scope's pending decision, and moves every offset-keyed holder past it. With the kill switch
    /// on, only the record and the tab's flipped callouts, which no styling rebuilds: nothing else
    /// shifts by itself and every styling is full.
    func recordStorageEdit(_ edit: StorageEdit, in storage: NSTextStorage) {
        lastRecordedEdit = edit
        guard !forcesFullRestyle else {
            folding.shiftFlips(by: edit)
            return
        }
        recordedEdits += 1
        if let baseline = stylingBaseline, baseline.inputs.storage == ObjectIdentifier(storage) {
            restyleScope?.record(edit, in: storage.string as NSString)
        }
        shiftDerivedState(by: edit)
    }

    /// Whether the storage reported a character edit no styling has covered yet. The shift dropped
    /// whatever was keyed on the lines such an edit rewrote, and nothing has drawn them again.
    var hasUnstyledEdits: Bool {
        stylingBaseline.map { $0.edits != recordedEdits } ?? false
    }

    /// The closed view-block fences of the map that touch `selection`, in order, when the map is the
    /// text's own (ADR-0091 §D6). Found by search, the shape of `selectionReveals` (ADR-0094 §D6).
    func currentViewBlockFences(touching selection: NSRange) -> [NSRange]? {
        guard let scope = restyleScope, scope.fencesAreCurrent else { return nil }
        guard selection.location != NSNotFound else { return [] }
        let fences = scope.map.fences
        return fences.indices(touching: selection)
            .map { fences[$0] }
            .filter { $0.language == ViewBlock.language && $0.isClosed }
            .map(\.range)
    }

    /// Moves the spell checker's ranges and the embed runs past `edit`; the holders' own shifts are
    /// called from `shiftDerivedState(by:)` (ADR-0091 §D6). Here because both are `private(set)` to
    /// this file.
    func shiftStyledRanges(by edit: StorageEdit) {
        unspellableRanges.apply(edit, partial: .clip)
        embedRuns.apply(edit, partial: .drop)
    }

    /// The step tallies of the stores that grow with the note, by name (ADR-0094 §D5): `hiddenMarkers`,
    /// `unspellable` and `embedRuns`, and the structure map's seven `map.*` stores while a scope is kept.
    /// A test seam; the counting compiles only under `#if DEBUG`, and a Release build reads zeros.
    ///
    /// In the trailing extension, not the class body, because the stores it resets are `private(set)` to
    /// this file.
    func offsetStoreTallies() -> [String: StepTally] {
        var tallies = restyleScope?.map.tallies ?? [:]
        tallies["hiddenMarkers"] = decorations.hiddenMarkers.tally
        tallies["unspellable"] = unspellableRanges.tally
        tallies["embedRuns"] = embedRuns.tally
        return tallies
    }

    /// Zeroes every tally `offsetStoreTallies()` answers, so a test reads what one keystroke cost.
    func resetOffsetStoreTallies() {
        decorations.hiddenMarkers.resetTally()
        unspellableRanges.resetTally()
        embedRuns.resetTally()
        restyleScope?.resetTallies()
    }
}
