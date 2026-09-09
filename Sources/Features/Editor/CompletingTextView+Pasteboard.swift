import AppKit

/// What arrives in the editor from outside the keyboard: a click on a drawing, a paste, a
/// drop.
///
/// Split from `CompletingTextView` because it shares nothing with the completion panel but
/// the view it hangs off - and because the two together put the file past the length the
/// linter allows, which is the linter being right.
extension CompletingTextView {
    /// What "Apri collegamento" (R-07) needs to replay the click it was offered from -
    /// the same shape `NoteTextView+EmbedCaret.swift`'s `PendingEmbedDeletion` carries for
    /// "Elimina", one field short since there is only ever one text view here.
    private struct PendingLinkClick {
        let url: URL
        let characterIndex: Int
    }

    /// A click on a drawn decoration is not a click in the text.
    ///
    /// Handled before `super`, which would otherwise move the caret to the nearest
    /// character - and the nearest character to a rendition is the source line above it, so
    /// the caret would jump every time somebody meant to follow the note.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // The resize handle first, and the order is load-bearing (ADR-0019 §D6):
        // `selectEmbed(at:in:)`, which `onClickInMargin` reaches next, claims the whole
        // picture's frame - asked first it would swallow the corner, and the handle would
        // be a square that selects. Asked second it answers exactly as it does today,
        // because `.began` claims a 22-point corner square and declines everywhere else.
        if onEmbedResize?(.began(point)) == true { return }
        if onClickInMargin?(point) == true { return }
        // Asked last, and still before `super`: a click that lands on a checkbox glyph must
        // never reach the default caret placement, or `NoteTextView+Reveal`'s reveal-on-caret
        // would expose the raw `- [ ]` the instant the caret entered that paragraph.
        if onToggleCheckbox?(point) == true { return }
        // Cmd+click on a link/wikilink navigates instead of placing the caret (issue #188).
        // AppKit's own automatic "clickedOnLink" `mouseDown` convenience never fires here:
        // `NoteTextView` runs TextKit 2 with a content-storage delegate that substitutes a
        // fresh `NSTextParagraph` per paragraph on every layout pass, and that convenience
        // does not reliably re-derive `.link` through the substitution. So this is detected
        // explicitly, at mouse-down (never mouse-up: Cmd released mid-click reads as a plain
        // click, matching what `NSEvent.modifierFlags` is sampled for everywhere else in this
        // file), and the event is consumed either way once Cmd is held over a link - a
        // Cmd+click on a link is a distinct gesture, never a caret placement.
        if event.modifierFlags.contains(.command), followLinkIfPresent(at: point) { return }
        super.mouseDown(with: event)
    }

    /// A right-click on a link shows "Apri collegamento" without leaving the link's
    /// paragraph un-concealed (issue #188). Skipping `super.rightMouseDown(with:)` for the
    /// on-link case rules out its own default caret-move, but that alone was NOT enough
    /// (confirmed on-screen, 2026-09-09, second round): `menu(for:)` below still calls
    /// `super.menu(for: event)` to get AppKit's standard "Open Link"/"Copy Link" items for a
    /// URL, and building THAT menu is itself what selects the link's whole range as an
    /// internal side effect - the screenshot showed the link actually highlighted, a real
    /// selection, not merely a moved caret. `textViewDidChangeSelection` → `applyReveal`
    /// (`NoteTextView+Reveal.swift`) then un-conceals its paragraph (ADR-0018 §D2) before
    /// "Apri collegamento" is ever chosen. Restoring the selection captured *before* the menu
    /// is built - synchronously, before `NSMenu.popUpContextMenu` yields to the run loop and
    /// anything is drawn - undoes whichever of AppKit's own selection side effects caused it,
    /// without needing to name the exact one. A right-click anywhere else falls straight
    /// through to `super`, unchanged - this is deliberately scoped to links only, matching
    /// R-07/R-08.
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

    /// Resolves the character under `point` the same TextKit-2-safe way `linkTitle(_:at:)`
    /// below already does, reads `.link` off the real `textStorage` there, and - if one is
    /// present - invokes the delegate method AppKit's own gesture was supposed to call.
    /// Shared between the Cmd+click handling above and the "Apri collegamento" context-menu
    /// item below, so the two can never resolve a click point two different ways.
    @discardableResult
    func followLinkIfPresent(at point: CGPoint) -> Bool {
        guard let storage = textStorage else { return false }
        let index = characterIndexForInsertion(at: point)
        guard index < storage.length,
              let url = storage.attribute(.link, at: index, effectiveRange: nil) as? URL
        else { return false }
        return delegate?.textView?(self, clickedOnLink: url, at: index) ?? false
    }

    /// The middle and the end of the one drag this editor has (ADR-0019 §D6).
    ///
    /// Both fall through to `super` when unclaimed, and unclaimed is the ordinary case:
    /// `onEmbedResize` answers false whenever no resize is in flight, so selecting text by
    /// dragging is untouched by either override.
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Shift is read off *this* event and passed on rather than remembered anywhere
        // (ADR-0019 §D9, R-11). Latching it at `.began` would make it a mode the gesture
        // enters, and a modifier the person is holding is one they can let go of: read
        // per-event, the lock engages and releases mid-drag exactly as the hand does.
        // Not Control: Control-click is macOS's system-wide secondary-click gesture and
        // opens the contextual menu before this handler ever sees the drag (confirmed on
        // screen, 2026-08-23).
        if onEmbedResize?(.moved(point, constrained: event.modifierFlags.contains(.shift))) == true {
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if onEmbedResize?(.ended(point)) == true { return }
        super.mouseUp(with: event)
    }

    /// The contextual menu for a secondary click: a drawn embed's own where one landed on
    /// a picture, and AppKit's everywhere else (ADR-0023 §D9, R-08).
    ///
    /// **The fall-through is the whole of this override.** `onEmbedMenu` answers nil for
    /// every point outside a picture - which is almost every point in a note - and `super`
    /// is what then builds the menu the editor has always had: spelling, substitutions,
    /// cut, copy, paste. An override that returned its own nil there would take that menu
    /// away from the entire text view rather than from the embed, and nothing about the
    /// picture's own menu would look wrong while it did.
    ///
    /// `menu(for:)` and not `rightMouseDown(with:)`: AppKit asks the view what menu to
    /// show and then shows it, so the ordinary path stays ordinary and Ctrl-click - the
    /// system-wide secondary click `mouseDragged(with:)` above already has to work around
    /// - arrives here on its own.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let base = onEmbedMenu?(point) ?? super.menu(for: event)
        // "Apri collegamento" (R-07): the non-modifier alternative to Cmd+click, prepended
        // only when the right-click itself landed on a link/wikilink range - everywhere else
        // this falls straight through to the menu above, unchanged.
        guard let storage = textStorage else { return base }
        let index = characterIndexForInsertion(at: point)
        guard index < storage.length,
              let url = storage.attribute(.link, at: index, effectiveRange: nil) as? URL
        else { return base }
        let menu = base ?? NSMenu()
        let item = NSMenuItem(
            title: "Apri collegamento", action: #selector(openLinkFromMenu(_:)), keyEquivalent: ""
        )
        // Held weakly by the menu item (AppKit convention); `self` outlives the menu.
        item.target = self
        item.representedObject = PendingLinkClick(url: url, characterIndex: index)
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    /// «Apri collegamento» navigates without Cmd held, by design (R-07) - so it calls
    /// `LinkNavigatingDelegate.performLinkNavigation(_:)` directly rather than
    /// `NSTextViewDelegate.textView(_:clickedOnLink:at:)`, which both Coordinators gate on
    /// Cmd actually being down (issue #188's plain-click regression fix). Not
    /// `followLinkIfPresent(at:)` either: the menu already resolved the click point once, in
    /// `menu(for:)`, and resolving it a second time from a stored `NSPoint` would drift if
    /// the view scrolled between right-click and menu selection.
    @objc private func openLinkFromMenu(_ sender: NSMenuItem) {
        guard let pending = sender.representedObject as? PendingLinkClick else { return }
        (delegate as? LinkNavigatingDelegate)?.performLinkNavigation(pending.url)
    }

    /// Pasting a URL over a selection writes a markdown link (SPEC §5); pasting a
    /// picture writes the file into the vault and embeds it.
    override func paste(_ sender: Any?) {
        if let pasted = NSPasteboard.general.string(forType: .string),
           onPasteURL?(pasted) == true {
            return
        }
        if let onPasteImage, let png = Self.pastedImagePNG(), let name = onPasteImage(png) {
            insertText(EditorEdits.embed(forFileNamed: name), replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    /// PNG bytes for an image sitting on the pasteboard, whatever form it arrived in.
    ///
    /// A screenshot comes as TIFF and a picture copied from a browser as PNG, so both
    /// are normalised here and the vault only ever receives one format. A file copied in
    /// the Finder and carrying no image bytes of its own is left alone: it arrives as a
    /// bare URL and belongs to the drop path, which keeps the name it already has. A
    /// screenshot tool that advertises both a `.fileURL` and real image data on the same
    /// pasteboard (CleanShot X does) is not that case, and is treated as a picture.
    private static func pastedImagePNG() -> Data? {
        let pasteboard = NSPasteboard.general
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff),
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        // A note title dragged from the sidebar onto a task line links the two
        // (SPEC §7.2, "collegamento assistito"). Checked before the file case: a
        // sidebar row carries a string, not a URL.
        if let title = sender.draggingPasteboard.string(forType: .string),
           !title.contains("\n"),
           noteTitles.contains(title),
           linkTitle(title, at: sender.draggingLocation) {
            return true
        }

        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: nil
        ) as? [URL] ?? []
        guard !urls.isEmpty, let onDropFile else { return super.performDragOperation(sender) }

        // Each dropped file is copied into the vault and embedded by name; the app
        // never links to a path outside the vault, which would break the day the file
        // moves or the disk is not mounted.
        let embeds = urls.compactMap(onDropFile).map(EditorEdits.embed(forFileNamed:))
        guard !embeds.isEmpty else { return super.performDragOperation(sender) }

        insertText(embeds.joined(separator: "\n"), replacementRange: selectedRange())
        return true
    }

    /// Appends `[[title]]` to the task line under the drop point.
    ///
    /// Only a task line: dropping a note in the middle of a paragraph would rewrite
    /// prose the user did not ask to change, and §7.2 is about tasks.
    private func linkTitle(_ title: String, at windowPoint: NSPoint) -> Bool {
        let point = convert(windowPoint, from: nil)
        let index = characterIndexForInsertion(at: point)
        let text = string as NSString
        guard index <= text.length else { return false }

        let lineRange = text.lineRange(for: NSRange(location: min(index, max(0, text.length - 1)), length: 0))
        let line = text.substring(with: lineRange)
        guard TaskParser.parse(line: line, sourcePath: "", lineIndex: 0) != nil else { return false }
        guard !line.contains("[[\(title)]]") else { return true }

        // Before the newline, so the link joins the task rather than starting a line.
        let trimmed = line.hasSuffix("\n") ? String(line.dropLast()) : line
        let replacement = trimmed + " [[\(title)]]" + (line.hasSuffix("\n") ? "\n" : "")
        insertText(replacement, replacementRange: lineRange)
        return true
    }
}
