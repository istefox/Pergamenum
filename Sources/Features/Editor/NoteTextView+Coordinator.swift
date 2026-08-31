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
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        weak var textView: NSTextView?
        /// The window's `undoManager` as of the last update, captured here because
        /// `dismantleNSView` runs after SwiftUI has already detached the text view from
        /// its window - `textView.undoManager` resolves through the responder chain and
        /// is nil by then, which would make the cleanup it performs a no-op.
        weak var undoManager: UndoManager?
        /// Guards the delegate callback from re-entering while styling rewrites
        /// attributes.
        private var isStyling = false
        /// The focus request already honoured, so the cursor is not stolen back on
        /// every subsequent update.
        var lastFocusRequest = 0
        /// The same, for the index's jumps: without it every later view update would
        /// scroll back to the last heading clicked.
        var lastScrollRequest = 0
        /// And for the find bar's, which is a location rather than a counter: the stepper
        /// moves between matches and it is arriving at a *different* one that scrolls.
        var lastMatchLocation: Int?
        /// What the editor draws besides the note's characters - folds and transcluded
        /// notes. Here rather than on the view: it is a fact about this text view's layout,
        /// and the view struct is rebuilt on every update (M8).
        let decorations = EditorDecorationDelegate()
        /// The fold already applied, so an unchanged one does not invalidate the layout on
        /// every view update.
        private var lastFoldLayout = NoteFolding.Layout()
        /// The transcluded notes already drawn, for the same reason as `lastFoldLayout`.
        var lastRenditions: [Int: TranscludedRendition] = [:]
        /// Renditions by reference, section, scan generation and width. Not private
        /// because the code that fills it lives in `NoteTextView+Transclusion`, and not
        /// unbounded in practice: a note names as many targets as it names.
        var renditionCache: [String: TranscludedRendition] = [:]
        /// The revealed paragraphs already applied (ADR-0018 §D2), so an unchanged set
        /// does not invalidate the layout on every view update. Not private for the same
        /// reason as `lastRenditions`: the mutator, `applyReveal`, lives in
        /// `NoteTextView+Reveal`.
        var lastRevealed: Set<Int> = []
        /// The index entry the caret was last reported to be in. Kept so the callback
        /// fires when it *changes*, not on every arrow key.
        private var lastOutlineEntry: Int??
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
        /// The embed resize drag in flight, or nil when there is none (ADR-0019 §D6:
        /// the gesture's state lives here rather than on the text view, which owns no
        /// decoration's state and knows about none of them). Not private for the same
        /// reason as `lastRenditions` and `lastRevealed` above: the three phases that
        /// fill, rewrite and clear it are `resizeEmbed(_:in:)`'s own, in
        /// `NoteTextView+EmbedResize.swift`, where `EmbedDrag` itself is declared.
        var embedDrag: EmbedDrag?

        init(parent: NoteTextView) {
            self.parent = parent
            embeds.attach(decorations: decorations)
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
            let caret = textView.selectedRange().location
            let entry = parent.outlineRanges.lastIndex { $0.location <= caret }
            guard lastOutlineEntry != .some(entry) else { return }
            lastOutlineEntry = entry
            parent.onOutlineEntryChanged?(entry)
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

        /// Recomputes the fold and makes the layout read it again.
        ///
        /// `edited(.editedAttributes,…)` is what re-runs the content manager's enumeration
        /// without a character changing - the same trick the reveal-on-caret probe used in
        /// the TextKit study. Skipped entirely when nothing is folded and nothing was, so
        /// an ordinary note pays nothing for this.
        func applyFolding(to textView: NSTextView, folded: Set<Int>, theme: Theme) {
            guard decorations.isFolding || !folded.isEmpty else { return }
            let layout = NoteFolding.layout(in: textView.string, foldedEntries: folded)
            guard layout != lastFoldLayout else { return }
            lastFoldLayout = layout

            decorations.badgeColor = NSColor(theme.color(.textTertiary))
            decorations.badgeBackground = NSColor(theme.color(.backgroundTertiary))
            decorations.apply(hiddenLines: layout.hiddenLineOffsets, foldedHeadings: layout.foldedHeadings)

            let length = (textView.string as NSString).length
            textView.textContentStorage?.textStorage?.edited(
                .editedAttributes, range: NSRange(location: 0, length: length), changeInLength: 0
            )
            if let manager = textView.textLayoutManager {
                manager.invalidateLayout(for: manager.documentRange)
            }
            rescueCaret(in: textView, from: layout)
        }

        /// Moves the caret out of a section that has just been folded.
        ///
        /// The folded lines are not in the layout, so a caret left inside one is an
        /// insertion point with nowhere to be drawn and nowhere to type. It goes to the
        /// heading that swallowed it, which is where a person would look for it.
        private func rescueCaret(in textView: NSTextView, from layout: NoteFolding.Layout) {
            guard !layout.hiddenLineOffsets.isEmpty else { return }
            let text = textView.string as NSString
            let caret = textView.selectedRange().location
            guard caret <= text.length else { return }
            let line = text.paragraphRange(for: NSRange(location: caret, length: 0)).location
            guard layout.hiddenLineOffsets.contains(line) else { return }

            let heading = layout.foldedHeadings.keys.filter { $0 <= caret }.max() ?? 0
            textView.setSelectedRange(NSRange(location: heading, length: 0))
            textView.scrollRangeToVisible(NSRange(location: heading, length: 0))
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

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return false }

            if components.host == MarkdownAttributedText.embedHost,
               let name = components.queryItems?.first(where: { $0.name == "name" })?.value {
                parent.onOpenEmbed?(name)
                return true
            }
            guard let title = components.queryItems?
                .first(where: { $0.name == "title" })?.value
            else { return false }
            parent.onFollowLink(title)
            return true
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
            storage.beginEditing()
            storage.setAttributes(
                MarkdownAttributedText.base(theme: theme),
                range: NSRange(location: 0, length: nsText.length)
            )
            for styled in MarkdownStyler.spans(in: text) {
                let nsRange = NSRange(styled.range, in: text)
                guard nsRange.location != NSNotFound,
                      NSMaxRange(nsRange) <= nsText.length
                else { continue }
                storage.addAttributes(
                    MarkdownAttributedText.attributes(for: styled.span, theme: theme),
                    range: nsRange
                )
                if MarkdownStyler.suppressesSpellCheck(styled.span) { unspellable.append(nsRange) }
                let kind: HiddenMarker.Kind? = switch styled.span {
                case .headingMarker: .heading
                case .emphasisMarker: .emphasis
                case .embedRun: .embed
                case .listMarker: .list
                case .taskMarker: .checkbox
                default: nil
                }
                if let kind {
                    let paragraphStart = nsText.paragraphRange(
                        for: NSRange(location: nsRange.location, length: 0)
                    ).location
                    hiddenMarkers[paragraphStart, default: []].append(
                        Self.hiddenMarker(kind, at: nsRange, paragraphStart: paragraphStart)
                    )
                }
                if case .embedRun = styled.span { embedRuns.append(nsRange) }
            }
            // A drawn embed's resize handle, from a token (ADR-0019 §D5) - the same
            // one-line hand-over `decorations.badgeColor = NSColor(theme.color(...))`
            // makes in `applyFolding` above. Here rather than threaded through
            // `applyEmbeds(to:)`, which has no theme and would need one at three call
            // sites; and here rather than beside `badgeColor`, because `applyFolding`
            // returns early for a note with nothing folded, which is most notes.
            // `.accentPrimary` and not the badge's `.textTertiary`: this square is
            // painted over an arbitrary picture and has to be aimed at, which a tertiary
            // text grey on a photograph is not.
            decorations.handleColor = NSColor(theme.color(.accentPrimary))
            // Before `endEditing()`, not after: that call is what fires the document-wide
            // `.editedAttributes` that re-triggers the content manager's enumeration, so
            // the table has to already be current when it does (ADR-0018 §D1).
            decorations.apply(hiddenMarkers: hiddenMarkers, hidingMarkup: parent.hidesMarkup)
            storage.endEditing()
            unspellableRanges = MarkdownStyler.merged(unspellable)
            self.embedRuns = embedRuns
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
    }
}
