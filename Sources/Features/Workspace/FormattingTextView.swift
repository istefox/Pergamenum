import AppKit

/// The Workspace card's own `NSTextView` (ADR-0027 §D1).
///
/// A sibling of `CompletingTextView`, never a fork of it: the note editor's view carries about
/// forty inputs - titles, tags, slash commands, emoji, embeds, transclusions, folding, find
/// matches, outline ranges - and a canvas card has none of them. Nothing is extracted from that
/// class, which is also what keeps the protected `CompletingTextView+Pasteboard.swift` outside
/// this chain's blast radius (ADR-0027 §D9).
///
/// What it is for: draw a card's markdown source with `CardTextAttributes`, report where its
/// selection is **in its own coordinates**, leave editing on Esc, and turn a format request -
/// from Cmd+B/Cmd+I or from the floating bar - into one undoable edit on its own text.
final class FormattingTextView: NSTextView {
    /// Esc: leave editing (SPEC §6.3).
    ///
    /// The card's editing surface used to be a SwiftUI `TextEditor` with an `.onKeyPress(.escape)`
    /// over it. A key press only reaches that modifier while SwiftUI's focus system holds the
    /// keyboard, and once an `NSTextView` is first responder AppKit does - so the handler has to
    /// live where the responder is, or Esc silently stops leaving the card.
    var onCancel: (() -> Void)?

    /// A click landed on a folded heading's badge, naming the entry ordinal it stands for
    /// (ADR-0028 §D8). Nil on a card whose board never asked to be told, which is a preview or a
    /// test - and nil is also what makes the click fall through to `super` untouched.
    var onToggleFold: ((Int) -> Void)?

    /// A click landed on a task line's checkbox glyph, naming the zero-based line the task is
    /// on within the card's own text (SPEC §7.1, PG-074). Nil on a card whose board never asked
    /// to be told, which is a preview or a test.
    var onToggleTask: ((Int) -> Void)?

    /// Read from the raw event rather than from `cancelOperation(_:)`, which is what the key
    /// looks like it should arrive as: AppKit's standard key bindings send Esc inside a text view
    /// to `complete:`, word completion, so the responder method that reads as its obvious home is
    /// not reliably called at all. A card has no completion to offer, so the key is taken here and
    /// never passed on.
    private static let escapeKeyCode: UInt16 = 53

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == Self.escapeKeyCode else { return super.keyDown(with: event) }
        // The wikilink popup owns Esc while it is open (dismiss without leaving editing),
        // exactly as `dismissCompletion()` does for the note editor's own panel - so this
        // has to be checked before `onCancel?()`, which would otherwise close the card too.
        if wikilinkCompletion != nil {
            dismissWikilinkCompletion()
            return
        }
        onCancel?()
    }

    /// The rectangle the current selection occupies, in **this view's own coordinates**.
    ///
    /// View-local on purpose and never a screen coordinate (ADR-0027 §D5): the board wraps its
    /// content in `.scaleEffect(zoom, anchor: .topLeading)` plus a `pan` offset, and a rectangle
    /// taken from `firstRect(forCharacterRange:)` - the way `FormatBarPanel` places the note
    /// editor's bar - is a screen rectangle that may know nothing about either. A card adds its
    /// own board origin to what this returns and the board overlay draws at `p * zoom + pan`, the
    /// transform `BoardMarquee` and `BoardGuides` already use.
    ///
    /// `nil` when there is no selection to point at: a caret is not a selection, and the floating
    /// bar exists only while there is one.
    func selectionFrameInView() -> CGRect? {
        let selection = selectedRange()
        guard selection.length > 0 else { return nil }
        return frame(for: selection, type: .selection)
    }

    /// `selectionFrameInView()`'s sibling for a zero-length range at the caret, for the
    /// wikilink popup's own placement - same view-local contract, same reason. `nil` when the
    /// caret's position cannot be resolved to a layout segment (an as-yet-unlaid-out range).
    func caretFrameInView() -> CGRect? {
        frame(for: selectedRange(), type: .standard)
    }

    /// The shared `NSTextRange`/`enumerateTextSegments` plumbing behind both methods above.
    private func frame(for range: NSRange, type: NSTextLayoutManager.SegmentType) -> CGRect? {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else { return nil }

        var union: CGRect?
        layoutManager.enumerateTextSegments(in: textRange, type: type) { _, frame, _, _ in
            union = union.map { $0.union(frame) } ?? frame
            return true
        }
        // The segments come back in the text container's space; the inset between the container
        // and the view is exactly `textContainerOrigin`, so adding it is the whole conversion.
        let origin = textContainerOrigin
        return union?.offsetBy(dx: origin.x, dy: origin.y)
    }

    // MARK: - Selection formatting (ADR-0027 §D1, plan
    // `2026-08-28-unificare-nota-e-testo-in-un-solo-strume` Task 5, R-03/R-04/R-05)

    /// Wraps or unwraps the current selection in `format`'s markdown markers.
    ///
    /// `InlineFormat.toggled` is reused verbatim, never reimplemented (C4 in the plan): it
    /// already carries the `isLongerMarker` guard against `****text**` and the two-shape
    /// unwrap rule (markers inside a drag-selection, markers outside a double-click selection).
    /// This method's own job is only the one-edit-per-press idiom that turns the pure result
    /// into a single undo step - `shouldChangeText(in:replacementString:)` →
    /// `textStorage.replaceCharacters` → `didChangeText()` → `setSelectedRange`, copied verbatim
    /// from `CompletingTextView+FormatBar.swift:103-109` rather than extracted from it: that
    /// file is a declared protected interface under `Sources/Features/Editor/`, outside this
    /// chain's edits (ADR §D9).
    func toggleInlineFormat(_ format: InlineFormat) {
        let edit = InlineFormat.toggled(format, in: string, over: selectedRange())
        replaceWholeText(with: edit.text, selecting: edit.selection)
    }

    /// Applies `format`'s line prefix (bullet/numbered/heading) to every line the current
    /// selection touches, via `LineFormat.toggled` (Task 2) through the same one-edit-per-press
    /// idiom as `toggleInlineFormat(_:)` above.
    ///
    /// No `selectedRange().length > 0` guard, unlike the note editor's `applyFormat(_:)`: a bare
    /// caret still touches exactly one line - its own - and `LineFormat.toggled` documents that
    /// as a real edit rather than the no-op an empty inline selection is.
    func toggleLineFormat(_ format: LineFormat) {
        let edit = LineFormat.toggled(format, in: string, over: selectedRange())
        replaceWholeText(with: edit.text, selecting: edit.selection)
    }

    // MARK: - Return inside a list (ADR-0028 §D6, plan
    // `2026-08-29-wysiwyg-markdown-in-workspace` Task 6, R-07/R-08/R-12)

    /// Return inside a list item: the item's own marker is carried onto the new line, an empty
    /// item leaves the list instead, and an ordered run is made contiguous again around the item
    /// that has just gone in.
    ///
    /// The card's half of `NoteTextView+ListEditing.claimsListCommand`, and deliberately the same
    /// shape - every rule about where a run starts, what continues it and how it is numbered is
    /// `ListContinuation`'s and is tested there (`Tests/ListContinuationTests.swift`). Only the
    /// site differs: the note editor claims the selector through `CompletingTextView
    /// .claimsCommand`'s chain, which a card has none of, so the responder method itself is where
    /// the key is taken here.
    ///
    /// `ListContinuation.newline` answering nil is what leaves Return to `super` - a caret on
    /// prose, one still inside its own marker, one over a non-empty selection - so this claim is
    /// exactly as narrow as that pure function is, and nothing else about AppKit's Return moves.
    ///
    /// **One write, whatever it rewrote.** The insertion and the renumbering it forces come back
    /// from `ListContinuation` already applied to the same string, so they reach the storage as a
    /// single replacement through `replaceWholeText(with:selecting:)` and one Cmd+Z on the card's
    /// own stack (ADR-0027 §D2) takes both back - never an item gone from a run still numbered
    /// around it (R-12).
    override func insertNewline(_ sender: Any?) {
        guard let edit = ListContinuation.newline(in: string, at: selectedRange()) else {
            return super.insertNewline(sender)
        }
        replaceWholeText(with: edit.text, selecting: edit.selection)
    }

    // MARK: - Unfolding by click (ADR-0028 §D8, plan
    // `2026-08-29-wysiwyg-markdown-in-workspace` Task 7, R-09/R-11)

    /// A click on a folded heading's badge opens the section, and is not a click in the text.
    ///
    /// Handled before `super`, which would otherwise move the caret to the nearest character - and
    /// the nearest character to a badge drawn past the end of a line is that line's own end, so the
    /// caret would jump every time somebody meant to unfold. The same order, and the same reason,
    /// as `CompletingTextView.mouseDown(with:)`.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if claimsFoldBadge(at: point) { return }
        if claimsCheckbox(at: point) { return }
        // Cmd+click on a link/wikilink navigates instead of placing the caret (issue #188,
        // R-06) - the card's half of `CompletingTextView.mouseDown(with:)`'s own addition, for
        // the identical reason: this view runs TextKit 2 with the same shared content-storage
        // delegate (`EditorDecorationDelegate`, ADR-0028 §D1), so AppKit's automatic
        // "clickedOnLink" gesture is equally unreachable here.
        if event.modifierFlags.contains(.command), followLinkIfPresent(at: point) { return }
        super.mouseDown(with: event)
    }

    /// The card's half of `CompletingTextView.rightMouseDown(with:)`'s own addition (issue
    /// #188) - identical reason, including the selection-restore step: `menu(for:)`'s own
    /// `super.menu(for: event)` call selects the link's whole range as an internal AppKit
    /// side effect while building the standard "Open Link"/"Copy Link" items, which
    /// reveal-on-caret reacts to. See that method's own comment for the full mechanism.
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let storage = textStorage else {
            super.rightMouseDown(with: event)
            return
        }
        let index = characterIndexForInsertion(at: point)
        guard index < storage.length,
              storage.attribute(.link, at: index, effectiveRange: nil) is URL
        else {
            super.rightMouseDown(with: event)
            return
        }
        let originalSelection = selectedRange()
        guard let menu = menu(for: event) else { return }
        setSelectedRange(originalSelection)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    /// The card's own copy of `CompletingTextView.followLinkIfPresent(at:)` - not extracted,
    /// for the reason every other shared piece of behaviour between these two views (this
    /// file's header) already gives: `CompletingTextView+Pasteboard.swift` is outside this
    /// chain's edits (ADR-0027 §D9), and the two views share `EditorDecorationDelegate`/
    /// `MarkdownAttributedText.clickTarget(for:)` already, which is where the real logic lives.
    @discardableResult
    func followLinkIfPresent(at point: CGPoint) -> Bool {
        guard let storage = textStorage else { return false }
        let index = characterIndexForInsertion(at: point)
        guard index < storage.length,
              let url = storage.attribute(.link, at: index, effectiveRange: nil) as? URL
        else { return false }
        return delegate?.textView?(self, clickedOnLink: url, at: index) ?? false
    }

    /// «Apri collegamento» (R-07), the card's half of `CompletingTextView.menu(for:)`'s own
    /// addition - no `menu(for:)` override existed on this view before this feature.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let base = super.menu(for: event)
        guard let storage = textStorage else { return base }
        let index = characterIndexForInsertion(at: point)
        guard index < storage.length,
              let url = storage.attribute(.link, at: index, effectiveRange: nil) as? URL
        else { return base }
        let menu = base ?? NSMenu()
        let item = NSMenuItem(
            title: "Apri collegamento", action: #selector(openLinkFromMenu(_:)), keyEquivalent: ""
        )
        item.target = self
        item.representedObject = PendingLinkClick(url: url)
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    /// «Apri collegamento» navigates without Cmd held, by design (R-07) - so it calls
    /// `LinkNavigatingDelegate.performLinkNavigation(_:)` directly rather than
    /// `NSTextViewDelegate.textView(_:clickedOnLink:at:)`, which the Coordinator gates on Cmd
    /// actually being down (issue #188's plain-click regression fix).
    @objc private func openLinkFromMenu(_ sender: NSMenuItem) {
        guard let pending = sender.representedObject as? PendingLinkClick else { return }
        (delegate as? LinkNavigatingDelegate)?.performLinkNavigation(pending.url)
    }

    /// What "Apri collegamento" needs to replay the click it was offered from - the card's
    /// own copy of `CompletingTextView+Pasteboard.swift`'s private `PendingLinkClick`.
    private struct PendingLinkClick {
        let url: URL
    }

    /// Whether a folded heading's badge is under `point`, and toggling its section when one is.
    ///
    /// **While editable only.** A card at rest is neither editable nor selectable
    /// (`CardTextView.Coordinator.configure`), because at rest the pointer belongs to the board's
    /// own tap, drag and double-click gestures - a text view that swallowed a click there would
    /// take it from `BoardContentLayer`'s selection, and the badge would be a dead spot on the card
    /// that also stopped it being picked up. The heading is still reachable from «Ripiega titoli»
    /// in both states, which is the command this only ever shadows.
    ///
    /// The fragment walk below re-states `NoteTextView+Transclusion.decoration(in:claimedBy:)`
    /// rather than extracting it (ADR-0028 §D9): that file is the note editor's, outside this
    /// chain's edits, and a shared helper would mean editing it. `textContainerOrigin` is taken off
    /// the point for the reason `NoteTextView+Transclusion.inContainer(_:of:)` exists at all - a
    /// layout fragment's frame is in the container's coordinates and a click arrives in the view's,
    /// and comparing the two directly is a containment test that can never succeed.
    private func claimsFoldBadge(at point: CGPoint) -> Bool {
        guard isEditable, let onToggleFold, let manager = textLayoutManager else { return false }
        let origin = textContainerOrigin
        let inContainer = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        let text = string

        var handled = false
        manager.enumerateTextLayoutFragments(
            from: manager.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            guard let folded = fragment as? FoldedHeadingFragment,
                  folded.badgeFrameInContainer.contains(inContainer),
                  let entry = Self.entry(atHeadingOffset: folded.headingOffset, in: text)
            else { return true }
            onToggleFold(entry)
            handled = true
            return false
        }
        return handled
    }

    /// The outline ordinal of the heading whose line begins at `offset`, or nil when no entry does.
    ///
    /// The fold is held by entry ordinal and the fragment knows a character offset, so the two are
    /// joined by the outline itself - the same translation the note editor makes through
    /// `parent.outlineRanges`, which is that list precomputed. A card has no such property to read,
    /// and `NoteOutline.entries(in:)` over a card's worth of text is cheap enough to ask per click;
    /// a second opinion about which section is which is the one thing this must not be, so the
    /// ordinals are counted over *every* entry, embeds included, exactly as `NoteFolding` counts
    /// them.
    private static func entry(atHeadingOffset offset: Int, in text: String) -> Int? {
        NoteOutline.entries(in: text).firstIndex { entry in
            NSRange(entry.range, in: text).location == offset
        }
    }

    // MARK: - Checkbox toggling (PG-074, plan
    // `2026-08-31-pg-074-give-the-to-do-tool-an-interactiv` Task 3)

    /// A click on a task line's checkbox glyph, naming the line and toggling it.
    ///
    /// **Not gated on `isEditable`**, unlike `claimsFoldBadge(at:)` above - a task list you must
    /// double-click into before ticking a box is not the interactive list SPEC §6.4 asks for
    /// (plan decision 1). The click still has to land on the glyph's own drawn rect, never merely
    /// somewhere on the task's line: a card at rest hands every other point to the board's own
    /// tap/drag/double-click gestures untouched, exactly as `claimsFoldBadge` does for its badge.
    ///
    /// This view has no access to the coordinator's `hiddenMarkers` table - it only ever sees
    /// what that table drew - so the marker is re-read from the raw characters here, the same
    /// re-validation `EditorDecorationDelegate.stillSpellsATaskMarker` performs before drawing.
    private func claimsCheckbox(at point: CGPoint) -> Bool {
        guard let onToggleTask, let manager = textLayoutManager else { return false }
        let origin = textContainerOrigin
        let inContainer = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        let text = string as NSString

        var handled = false
        manager.enumerateTextLayoutFragments(
            from: manager.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            let range = fragment.rangeInElement
            let offset = manager.offset(from: manager.documentRange.location, to: range.location)
            let length = manager.offset(from: range.location, to: range.endLocation)
            guard length > 0, offset >= 0, offset + length <= text.length,
                  let stateOffset = Self.checkboxStateOffset(
                      in: text.substring(with: NSRange(location: offset, length: length))
                  )
            else { return true }

            guard let stateStart = manager.location(range.location, offsetBy: stateOffset),
                  let stateEnd = manager.location(stateStart, offsetBy: 1),
                  let stateRange = NSTextRange(location: stateStart, end: stateEnd)
            else { return true }

            var glyphFrame: CGRect?
            manager.enumerateTextSegments(in: stateRange, type: .standard) { _, frame, _, _ in
                glyphFrame = frame
                return true
            }
            guard let glyphFrame, glyphFrame.contains(inContainer) else { return true }

            onToggleTask(Self.lineIndex(atParagraphOffset: offset, in: text as String))
            handled = true
            return false
        }
        return handled
    }

    /// The offset, within a paragraph's own text, of the state character in its task marker -
    /// dash-or-star, space, `[`, state, `]`, after any leading indentation. Nil for a line that
    /// is not a task line, or one too short to hold a whole five-character marker.
    private static func checkboxStateOffset(in paragraph: String) -> Int? {
        let indent = paragraph.prefix { $0 == " " || $0 == "\t" }.count
        let characters = Array(paragraph)
        guard characters.count >= indent + 5,
              characters[indent] == "-" || characters[indent] == "*",
              characters[indent + 1] == " ", characters[indent + 2] == "[", characters[indent + 4] == "]"
        else { return nil }
        return indent + 3
    }

    /// The zero-based line number of the paragraph starting at `offset` - `TaskParser`'s own
    /// counting, so the index handed to `onToggleTask` is the one `TaskItem.lineIndex` means.
    private static func lineIndex(atParagraphOffset offset: Int, in text: String) -> Int {
        (text as NSString).substring(to: offset).reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
    }

    /// The single edit path both formatters go through: the whole card's text replaced as one
    /// `NSTextView` change, so one press is one undo step however many lines it rewrote.
    ///
    /// Copied from `CompletingTextView+FormatBar.swift:98-109` - its `applyFormat(_:)` no-op
    /// guard plus its `replaceWholeText(with:selecting:)` - rather than extracted into something
    /// both files call. The duplication is deliberate: that file lives under
    /// `Sources/Features/Editor/`, which this chain does not touch (ADR-0027 §D1/§D9), and any
    /// shared helper would mean editing it.
    ///
    /// Written through AppKit and never into `string`, which is the point of the idiom: assigning
    /// `string` bypasses `shouldChangeText`/`didChangeText` and leaves the undo stack, the
    /// delegate and the layout with no record of the change.
    ///
    /// Not private since ADR-0028 Task 6: `CardTextView+ListEditing.renumberLists(in:)` writes
    /// through it too. Widening the existing path rather than adding a second one is the whole
    /// reason "one press is one undo step" holds - a renumbering that opened its own edit path
    /// would be the second way for a card's text to reach the storage, and the first one anybody
    /// forgot to keep atomic.
    func replaceWholeText(with replacement: String, selecting selection: NSRange) {
        guard replacement != string else { return }
        let whole = NSRange(location: 0, length: (string as NSString).length)
        guard shouldChangeText(in: whole, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: whole, with: replacement)
        didChangeText()
        setSelectedRange(selection)
    }

    // MARK: - Wikilink completion (`[[`, point 1 of the workspace wikilink regression chain)

    /// The vault's note titles, offered as `[[` completion candidates - threaded in from
    /// `CardTextView`/`StickyTextCard`/`WorkspaceController.wikilinkNoteTitles`, the same
    /// `hidesMarkup`-style data route this file's header describes. Empty on a card built in
    /// a preview or a test, which then offers nothing rather than crashing.
    var wikilinkNoteTitles: [String] = []
    /// The vault's boards, offered the same way - a card can link `[[board.canvas]]` too,
    /// which the note editor's own `[[` completion never offers.
    var wikilinkBoardTitles: [String] = []

    /// The popup's current state, or nil while the caret sits outside an unclosed `[[`, or
    /// while what has been typed matches nothing.
    private(set) var wikilinkCompletion: WikilinkCompletion?
    /// Fired whenever `wikilinkCompletion` changes, including to nil - mirrors
    /// `CardTextView.onSelectionChange`'s own shape: the closure reads state off the view it
    /// is handed, never carries it as a parameter.
    var onWikilinkCompletionChange: ((FormattingTextView) -> Void)?

    /// The trigger location Escape (or a click away) dismissed, so the popup does not reopen
    /// on the very next keystroke of the same still-open `[[` -
    /// `CompletingTextView.dismissedLocation`'s own rule, copied rather than shared for the
    /// reason every duplicated method in this file gives.
    private var wikilinkDismissedLocation: Int?

    /// Recomputes the popup for wherever the caret is now.
    ///
    /// Called from `CardTextView.Coordinator.textDidChange` after `applyStyling`, and from
    /// `textViewDidChangeSelection` - arrow keys carry the caret in and out of a `[[...]]`
    /// span with no text change of their own, the same second call site
    /// `CompletingTextView.refreshCompletion` has via `refreshFormatBar`'s neighbouring hook.
    func refreshWikilinkCompletion() {
        let caret = selectedRange().location
        guard let context = WikilinkTrigger.context(in: string, caret: caret) else {
            wikilinkDismissedLocation = nil
            setWikilinkCompletion(nil)
            return
        }
        guard context.range.location != wikilinkDismissedLocation else { return }
        let candidates = CardWikilinkCompletion.candidates(
            matching: context.prefix, notes: wikilinkNoteTitles, boards: wikilinkBoardTitles
        )
        guard !candidates.isEmpty else {
            setWikilinkCompletion(nil)
            return
        }
        setWikilinkCompletion(WikilinkCompletion(context: context, candidates: candidates))
    }

    /// Escape's half of the dismissal (see `keyDown(with:)`): the popup goes, the typed prefix
    /// stays - `CompletingTextView.dismissCompletion()`'s own "don't eat a literal character"
    /// rule, since deleting what was typed on dismissal would make a literal `[[` unwritable.
    private func dismissWikilinkCompletion() {
        wikilinkDismissedLocation = wikilinkCompletion?.context.range.location
        setWikilinkCompletion(nil)
    }

    private func setWikilinkCompletion(_ completion: WikilinkCompletion?) {
        guard wikilinkCompletion != completion else { return }
        wikilinkCompletion = completion
        onWikilinkCompletionChange?(self)
    }

    private func moveWikilinkSelection(by offset: Int) {
        guard var completion = wikilinkCompletion, !completion.candidates.isEmpty else { return }
        completion.selectedIndex = min(
            max(completion.selectedIndex + offset, 0), completion.candidates.count - 1
        )
        setWikilinkCompletion(completion)
    }

    /// Splices `candidate` into the trigger's range as `[[<insertText>]]` - the `[[` is
    /// already there, only `prefix` (what `context.range` covers) and the closing `]]` are
    /// written - through the single one-undo-step edit path
    /// (`replaceWholeText(with:selecting:)`) every other programmatic edit on this view
    /// already goes through.
    func applyWikilinkCompletion(_ candidate: WikilinkCandidate) {
        guard let completion = wikilinkCompletion else { return }
        let whole = string as NSString
        let inserted = "\(candidate.insertText)]]"
        let newText = whole.replacingCharacters(in: completion.context.range, with: inserted)
        let caret = completion.context.range.location + (inserted as NSString).length
        wikilinkDismissedLocation = nil
        setWikilinkCompletion(nil)
        replaceWholeText(with: newText, selecting: NSRange(location: caret, length: 0))
    }

    /// The keys the popup owns while it is open, and only while it is open - the card's half
    /// of `CompletingTextView.doCommand(by:)`. This view had no such override before this
    /// feature, so nothing existing is touched by adding it; every unhandled selector still
    /// reaches `super`, which is where `insertNewline(_:)`'s own list-continuation override
    /// above is reached when no popup is open.
    override func doCommand(by selector: Selector) {
        guard wikilinkCompletion != nil else {
            super.doCommand(by: selector)
            return
        }
        switch selector {
        case #selector(moveUp(_:)):
            moveWikilinkSelection(by: -1)
        case #selector(moveDown(_:)):
            moveWikilinkSelection(by: 1)
        case #selector(insertNewline(_:)), #selector(insertTab(_:)):
            if let selected = wikilinkCompletion?.selected { applyWikilinkCompletion(selected) }
        // Escape is intercepted earlier, in `keyDown(with:)`, before AppKit's own key-binding
        // dispatch ever reaches this method - `complete:` is kept here regardless, the same
        // belt-and-braces the note editor's own `dismissCompletion()` call site keeps, since
        // some configurations route word completion here instead.
        case #selector(cancelOperation(_:)), #selector(complete(_:)):
            dismissWikilinkCompletion()
        default:
            super.doCommand(by: selector)
        }
    }

    /// Cmd+B → `.bold`, Cmd+I → `.italic`, every other key or modifier combination → `nil`.
    ///
    /// A pure mapping, deliberately taking the flags and the character apart from a whole
    /// `NSEvent`, so `performKeyEquivalent(with:)`'s own routing can be asserted without
    /// dispatching a live event through the responder chain - unreliable off-screen, and not
    /// what R-04 is actually about (plan Task 5: "assert against the key-event → action
    /// mapping, not against a real keystroke").
    ///
    /// `modifierFlags` is expected already masked to `.deviceIndependentFlagsMask`
    /// (`ShortcutSettings.swift:162`'s own convention for reading a key event's modifiers).
    /// Exactly `.command` and no more is what R-04's "no collision with any existing
    /// `ShortcutCommand` binding" requires: `newBoard` is Cmd+Shift+B and `toggleInspector` is
    /// Cmd+Opt+I (`ShortcutCommand.swift:215`, `:276`), so a stray Shift or Option held down
    /// alongside B/I must resolve to neither format here and fall through to those bindings.
    static func inlineFormat(
        forKeyEquivalent characters: String, modifierFlags: NSEvent.ModifierFlags
    ) -> InlineFormat? {
        guard modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return nil
        }
        switch characters {
        case "b": return .bold
        case "i": return .italic
        default: return nil
        }
    }

    /// Routes Cmd+B/Cmd+I to `toggleInlineFormat(_:)` while the view is editable; claims nothing
    /// else, letting every other event fall through - including to
    /// `BoardChrome.swift:118-128`'s bare-key tool-shortcut suppression, a different and
    /// unaffected path, since a tool shortcut carries no modifier at all and Cmd+B/Cmd+I always
    /// carry one.
    ///
    /// Every unhandled case returns `super.performKeyEquivalent(with:)` rather than a bare
    /// `false`: this override sits in the live key-event path of every card text view, and
    /// answering `false` without asking the superclass would silently drop whatever `NSTextView`
    /// itself does with a key equivalent - a wider blast radius than the two keys this method is
    /// here for. A read-only card (`isEditable == false`) takes that same path before the
    /// mapping is even consulted: a card nobody is typing into formats nothing.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEditable,
              let characters = event.charactersIgnoringModifiers,
              let format = Self.inlineFormat(
                  forKeyEquivalent: characters, modifierFlags: event.modifierFlags
              )
        else { return super.performKeyEquivalent(with: event) }
        toggleInlineFormat(format)
        return true
    }

    // MARK: - Accessibility

    /// A resting card (`isEditable == false`) reads exactly as the SwiftUI `Text` it replaced
    /// did: a plain static label. UI tests and VoiceOver both located a `.text` card by its
    /// content before ADR-0027 (`app.staticTexts["CARD A"]`), and that lookup broke the moment
    /// the card became this `NSTextView`, whose default accessibility role is a text area, not
    /// static text. The moment editing starts (`isEditable == true`) this reverts to
    /// `NSTextView`'s own default role, which is what typing into it actually needs.
    override func accessibilityRole() -> NSAccessibility.Role? {
        isEditable ? super.accessibilityRole() : .staticText
    }
}
