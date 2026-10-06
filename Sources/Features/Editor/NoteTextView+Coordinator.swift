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
        /// is nil by then, which would make the cleanup it performs a no-op.
        weak var undoManager: UndoManager?
        /// Guards the delegate callback from re-entering while styling rewrites
        /// attributes.
        private var isStyling = false
        /// What the editor draws besides the note's characters - folds and transcluded
        /// notes. Here rather than on the view: it is a fact about this text view's layout,
        /// and the view struct is rebuilt on every update (M8).
        let decorations = EditorDecorationDelegate()
        /// The ranges the spell checker must leave alone: markdown syntax, not prose (M8).
        /// Filled by `applyStyling`, which already knows what every range of the note is,
        /// so recognising them costs no second parse.
        private(set) var unspellableRanges: [NSRange] = []
        /// Every `![[file.est]]`/`![alt](file.est)` line's own syntax range, found by the
        /// same `applyStyling` walk over `MarkdownStyler.spans(in:)` that already
        /// recognises `.embedRun` (ADR-0018 slice 3, Step 2). `NoteTextView+Embeds.swift`
        /// reads this rather than parsing the note a second time.
        private(set) var embedRuns: [NSRange] = []
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
        private(set) lazy var viewBlocks = ViewBlockController(
            parent: { [weak self] in self?.parent }, decorations: decorations
        )
        /// The embed resize drag and its three phases (ADR-0074 §D2, ADR-0019 §D6,
        /// `NoteTextView+EmbedResize.swift`). `lazy` for `tables`' reason.
        private(set) lazy var embedResize = EmbedResizeController(
            parent: { [weak self] in self?.parent }, embeds: embeds, decorations: decorations
        )
        /// The transcluded renditions, their cache and the click that opens one (ADR-0074
        /// §D2, `NoteTextView+Transclusion.swift`). `lazy` for `tables`' reason.
        private(set) lazy var transclusion = TransclusionController(
            parent: { [weak self] in self?.parent }, decorations: decorations
        )
        /// The last fold layout and the folding pass (ADR-0074 §D2,
        /// `NoteTextView+Folding.swift`). `lazy` for `tables`' reason.
        private(set) lazy var folding = FoldController(
            parent: { [weak self] in self?.parent }, decorations: decorations
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
            embeds.attach(decorations: decorations)
        }

        deinit {
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
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
            let caret = textView.selectedRange().location
            let entry = parent.outline.outlineRanges.lastIndex { $0.location <= caret }
            guard requests.claimOutlineEntry(entry) else { return }
            parent.outline.onOutlineEntryChanged?(entry)
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
            to textView: NSTextView, folded: Set<Int>, hidesFrontmatter: Bool = false, theme: Theme
        ) {
            folding.apply(to: textView, folded: folded, hidesFrontmatter: hidesFrontmatter, theme: theme)
        }

        func textDidChange(_ notification: Notification) {
            guard !isStyling, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyStyling(to: textView, theme: parent.theme)
            applyEmbeds(to: textView)
            applyTransclusions(to: textView, theme: parent.theme)
            // After the styling and before the reveal, in that order and for both reasons:
            // this is a text change of its own, so the attributes it needs are the ones the
            // pass it triggers writes, and the offsets the reveal works in are the ones it
            // leaves behind (ADR-0028 §D6, R-08).
            renumberLists(in: textView)
            // After the passes above: a keystroke shifts every offset below it, and
            // the revealed set has to be recomputed against the new text (ADR-0018 §D2).
            applyReveal(to: textView)

            // Typing has to keep the caret on screen, and under TextKit 2 it does not do so
            // by itself once the note has just grown taller: the two `apply` passes above
            // change the height on this very keystroke, and the scroll view is still showing
            // what fitted before. Only on a real edit - never when a note is merely being
            // opened or restyled - so the index's jumps and the user's own scrolling are
            // left alone.
            growToFitTheText(textView, revealingCaret: true)

            guard let completing = textView as? CompletingTextView else { return }
            // Unconditionally, and once for all four triggers: the panel has to close when
            // the context stops being one, not only open when it starts.
            //
            // It cannot recur, and that is worth saying because the call it replaced could.
            // AppKit's `complete(nil)` put the first candidate into the text as it opened
            // the list, that edit called `textDidChange` straight back, the context was
            // still a completion one - `#area-training` is a tag prefix like `#a` was - and
            // the app died on a stack overflow from typing `#` at the start of a line. The
            // panel writes nothing until a row is chosen, so there is no edit to come back.
            completing.refreshCompletion(theme: parent.theme)
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
            guard modifierFlags().contains(.command) else { return false }
            return performLinkNavigation(link)
        }

        /// Rewrites the whole attribute run. Notes are small enough that styling the
        /// full text on each keystroke stays imperceptible, and a visible-range
        /// optimisation would have to be re-run on every scroll to avoid unstyled
        /// text appearing as the user moves through the note.
        func applyStyling(to textView: NSTextView, theme: Theme) {
            guard let storage = textView.textStorage else { return }
            isStyling = true
            defer { isStyling = false }

            let text = textView.string
            let nsText = text as NSString
            var unspellable: [NSRange] = []
            // Paragraph-start offset to its hidden markers, each relative to it - the key
            // space `EditorDecorationDelegate` reads at layout time (ADR-0018 §D1).
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
            // One memoised `StyleContext` for the whole pass (Task 2, PG-139/#239) rather
            // than a fresh heading/bold/italic/mono/codeBlock dictionary rebuilt per span -
            // this loop, not `MarkdownAttributedText.attributed(_:theme:)`, is the actual hot
            // caller: it restyles the whole note on every keystroke (this function's own
            // header comment above).
            var context = MarkdownAttributedText.StyleContext(theme: theme, links: true)
            storage.beginEditing()
            storage.setAttributes(
                context.base,
                range: NSRange(location: 0, length: nsText.length)
            )
            let spans = MarkdownStyler.spans(in: text)
            for styled in spans {
                let nsRange = NSRange(styled.range, in: text)
                guard nsRange.location != NSNotFound,
                      NSMaxRange(nsRange) <= nsText.length
                else { continue }
                // Through the source-aware entry: a tag's or a date's click (n1-seams R-12,
                // R-13) is read off the characters it covers, not the span alone.
                storage.addAttributes(
                    context.attributes(for: styled, in: text),
                    range: nsRange
                )
                if MarkdownStyler.suppressesSpellCheck(styled.span) { unspellable.append(nsRange) }
                if let kind = Self.hiddenKind(for: styled.span) {
                    let paragraphStart = nsText.paragraphRange(
                        for: NSRange(location: nsRange.location, length: 0)
                    ).location
                    let spans = kind == .link
                        ? Self.linkDelimiters(in: nsRange, of: nsText)
                        : [nsRange]
                    for span in spans {
                        hiddenMarkers[paragraphStart, default: []].append(
                            Self.hiddenMarker(kind, at: span, paragraphStart: paragraphStart)
                        )
                    }
                }
                if case .embedRun = styled.span { embedRuns.append(nsRange) }
                if case .tableRun = styled.span { tableRuns.append(nsRange) }
                if case .viewBlockRun = styled.span { viewBlockRuns.append(nsRange) }
            }
            // The gap after a prose or heading line (n1-seams R-14), after every span has put its
            // own style down and before `applyTransclusions` reserves its height: merged into
            // the style already on the line, never a fresh one, because a list line, a heading
            // and a transclusion each carry a style of their own (ADR-0030 §D5).
            ProseParagraphSpacing.apply(ProseTypography.paragraphSpacing(theme), to: storage, text: text, spans: spans)
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
            // The table pass (ADR §D5), here beside `apply(hiddenMarkers:)` below - its own
            // guard, since `applyFolding`'s early return does not cover it, and its own
            // `apply(tableRows:)`/`apply(tableViews:)` calls. It adds the header line's own
            // `.table` marker to the table about to be handed over, rather than making a
            // second `apply(hiddenMarkers:)` call of its own.
            // Before `endEditing()`, not after: that call is what fires the document-wide
            // `.editedAttributes` that re-triggers the content manager's enumeration, so
            // the table has to already be current when it does (ADR-0018 §D1).
            applyTables(to: textView, runs: tableRuns, markers: &hiddenMarkers)
            // The view-block pass (ADR-0033 §D1), beside the table one and before
            // `endEditing()` for the same reason: that call fires the document-wide
            // `.editedAttributes` that re-triggers the content manager's enumeration, so
            // which lines are out of the layout has to already be current when it does.
            applyViewBlocks(to: textView, runs: viewBlockRuns, markers: &hiddenMarkers)
            decorations.apply(hiddenMarkers: hiddenMarkers, hidingMarkup: parent.hidesMarkup)
            // Pushed here rather than only from `applyReveal` (ADR-0037 §D7/F6): that pass
            // early-returns when the computed reveal equals what it last applied, so a
            // toggle flip with a stationary caret would otherwise never reach the delegate.
            // `applyStyling` runs unconditionally on every `updateNSView`.
            decorations.apply(revealsInlineSpans: parent.revealsInlineSpans)
            storage.endEditing()
            unspellableRanges = MarkdownStyler.merged(unspellable)
            self.embedRuns = embedRuns
            // After the transaction, deliberately: a grid resizes itself and a caret rescue
            // moves the selection, and neither belongs inside an open editing session.
            tables.refresh(in: textView, theme: theme)
            // Same rule, same reason (ADR-0033 §D15): a host lays SwiftUI out and the caret
            // rescue moves the selection. The commit holds `self` strongly, as the edit request
            // it ends up in always has; the resize path does not.
            viewBlocks.refresh(in: textView, theme: theme, commit: { self.commitViewBlock($0, at: $1, in: $2) },
                               growToFit: { [weak self] in self?.growToFitTheText($0) })
            // `.editorLink` spans can have moved without the view resizing (an edit above or
            // beside one, a reveal toggling a marker's width) - a tracking area does not
            // follow that on its own the way it follows a resize, so this is the seam that asks
            // `CompletingTextView+CursorRects.swift` to rebuild them (issue #191 follow-up).
            // `NSView` has no settable "needs update" flag for tracking areas the way it does
            // for layout/display - `updateTrackingAreas()` is itself the public call.
            textView.updateTrackingAreas()
        }

        /// Which kind of hidden marker a span becomes, or none for a span that is only
        /// coloured.
        ///
        /// The note editor's own table, not the card's: `CardTextView`'s switch ends in
        /// `default: nil`, the seam ADR-0029 §D17 relies on to keep the live `NSView` grid
        /// above all, then blockquote, rule and message anchor out of a card whose text
        /// view is deallocated on every culling-rect crossing; ADR-0037's §D8 amendment
        /// gave the card strikethrough and links. The two are one call apart on purpose.
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
            let isSyntax = unspellableRanges.contains { NSIntersectionRange($0, affectedCharRange).length > 0 }
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
        /// `ensureLayout` over the whole document is what makes `usageBoundsForTextContainer`
        /// mean anything - TextKit 2 lays out lazily, so without it the bounds describe only
        /// the part that happens to have been drawn. It is the same bargain `applyStyling`
        /// takes: notes are small, and the alternative is a note whose end cannot be reached.
        func growToFitTheText(_ textView: NSTextView, revealingCaret: Bool = false) {
            guard let layout = textView.textLayoutManager else { return }
            layout.ensureLayout(for: layout.documentRange)
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
            let inset = Self.horizontalInset(
                viewWidth: width,
                cap: parent.theme.spacing(.readable),
                minimum: Self.minimumHorizontalInset,
                isOn: parent.readableWidth
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
