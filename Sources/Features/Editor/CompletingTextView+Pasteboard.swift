import AppKit

/// What arrives in the editor from outside the keyboard: a click on a drawing, a paste, a
/// drop.
///
/// Split from `CompletingTextView` because it shares nothing with the completion panel but
/// the view it hangs off - and because the two together put the file past the length the
/// linter allows, which is the linter being right.
extension CompletingTextView {
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
        super.mouseDown(with: event)
    }

    /// The middle and the end of the one drag this editor has (ADR-0019 §D6).
    ///
    /// Both fall through to `super` when unclaimed, and unclaimed is the ordinary case:
    /// `onEmbedResize` answers false whenever no resize is in flight, so selecting text by
    /// dragging is untouched by either override.
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if onEmbedResize?(.moved(point)) == true { return }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if onEmbedResize?(.ended(point)) == true { return }
        super.mouseUp(with: event)
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
    /// the Finder is deliberately left alone: it arrives as a URL and belongs to the drop
    /// path, which keeps the name it already has.
    private static func pastedImagePNG() -> Data? {
        let pasteboard = NSPasteboard.general
        guard pasteboard.data(forType: .fileURL) == nil else { return nil }
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
