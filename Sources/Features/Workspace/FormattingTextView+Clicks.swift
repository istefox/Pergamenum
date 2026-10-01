import AppKit

/// What a click does on a Workspace card's text: the folded heading's badge, the task checkbox,
/// Cmd+click on a link and the right-click link menu.
///
/// An ADR-0045 size split of `FormattingTextView` that widens nothing: every `private` member
/// here is read only inside this file, and the range holds no stored property. The wikilink
/// completion stays in `FormattingTextView.swift`, because it holds two access-limited stored
/// properties (`wikilinkCompletion`, `wikilinkDismissedLocation`) that moving it would widen.
///
/// Like the rest of this view, this is a sibling of the note editor's own click handling and
/// never shared with it (`FormattingTextView.swift`'s header): `CompletingTextView+Pasteboard.swift`
/// is the note editor's, a protected interface outside the Workspace (ADR-0027 §D9).
extension FormattingTextView {
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
        // delegate (`EditorDecorationDelegate`, ADR-0028 §D1). Clickable spans carry the app's
        // own `.editorLink` attribute, not the standard `.link` (issue #191, `.editorLink`'s
        // doc comment has the full history), so AppKit's automatic "clickedOnLink" gesture
        // cannot engage here at all - this is detected explicitly, by hand, the same as the
        // note editor's own twin.
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
              storage.attribute(.editorLink, at: index, effectiveRange: nil) is URL
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
              let url = storage.attribute(.editorLink, at: index, effectiveRange: nil) as? URL
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
              let url = storage.attribute(.editorLink, at: index, effectiveRange: nil) as? URL
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
    ///
    /// `offset` is a paragraph start in UTF-16, so the prefix never splits a `\r\n` pair, and the
    /// count walks `Character`s, where that pair is one: `LineBreak.isTerminator` counts it, a
    /// `"\n"` comparison never did and sent every CRLF checkbox to line 0 (PG-316).
    ///
    /// Not private since PG-316: `Tests/CRLFLineWalkTests.swift` reads it.
    static func lineIndex(atParagraphOffset offset: Int, in text: String) -> Int {
        (text as NSString).substring(to: offset).reduce(into: 0) { count, character in
            if LineBreak.isTerminator(character) { count += 1 }
        }
    }
}
