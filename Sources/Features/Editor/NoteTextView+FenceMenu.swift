import AppKit

/// «Copia il blocco» (ADR-0087 §D6): the editor's ordinary context menu gains one item inside a
/// closed fence. AppKit asks the delegate from `super.menu(for:)`, which the protected
/// `CompletingTextView.menu(for:)` reaches whenever its own embed menu answers nil, so nothing on
/// the view side changes.
extension NoteTextView.Coordinator {
    /// AppKit's menu for a click at `charIndex`, with a separator and «Copia il blocco» appended
    /// when the index is on a closed fence's opening line, its body or its closing line; the menu
    /// unchanged anywhere else.
    ///
    /// The selector is spelled out so the method AppKit asks for is this one whatever Swift infers
    /// for an optional `NSTextViewDelegate` requirement witnessed in an extension rather than in
    /// the class that declares the conformance.
    @objc(textView:menu:forEvent:atIndex:)
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        let text = view.string
        // A note with no fence mark has no block to copy, and `clickedParagraph` lays out everything
        // above the click: the scan of the characters is the cheaper of the two (the PG-401 cost class).
        // The mark is `CodeFence.marks`', which opens a fence on backticks only.
        guard text.contains("```") else { return menu }
        let index = Self.clickedParagraph(of: event, in: view) ?? charIndex
        guard let block = FenceChrome.block(containing: index, in: text) else { return menu }
        let item = NSMenuItem(title: "Copia il blocco", action: #selector(copyFenceBlock(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = String(text[block.body])
        menu.addItem(.separator())
        menu.addItem(item)
        return menu
    }

    /// The offset of the paragraph under the click, read off the laid-out fragments, or nil when the
    /// event is not this view's or lands on no fragment. AppKit's own `charIndex` is not TextKit-2
    /// safe: measured on macOS 27, it answered the end of the note for a click on a fence's body line
    /// (the reason `CompletingTextView.linkCharacterIndex(at:)` resolves its own point too). A line is
    /// enough here: a fence is a run of whole lines. Only the row is tested, never the frame's
    /// width: a fence line's concealed backticks leave a fragment a few points wide, and a click
    /// right of it is still on that line. The event's window is not compared with the view's: a
    /// guard on it refused every event in the hosted test (`CodeFenceChromeTests`), whose window
    /// is never ordered on screen; a context click only ever reaches the view it landed in.
    static func clickedParagraph(of event: NSEvent, in view: NSTextView) -> Int? {
        guard view.window != nil, let manager = view.textLayoutManager, let content = manager.textContentManager
        else { return nil }
        let point = inContainer(view.convert(event.locationInWindow, from: nil), of: view)
        var paragraph: Int?
        // `.ensuresLayout`: by the time AppKit asks, its own handling of the click has invalidated
        // the layout under it, and an enumeration of what is laid out found nothing (measured).
        let start = manager.documentRange.location
        manager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard frame.minY <= point.y else { return false }
            guard point.y < frame.maxY else { return true }
            paragraph = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            return false
        }
        return paragraph
    }

    /// Writes the block's body, its fence lines excluded, to the general pasteboard as plain text.
    @objc func copyFenceBlock(_ sender: NSMenuItem) {
        copyFenceBlock(sender, to: .general)
    }

    /// The item's body to `pasteboard`: a parameter so the hosted test writes a private pasteboard and
    /// never the person's clipboard. A second method rather than a defaulted parameter, because the
    /// menu item's action selector must keep the single `sender` argument AppKit sends.
    func copyFenceBlock(_ sender: NSMenuItem, to pasteboard: NSPasteboard) {
        guard let body = sender.representedObject as? String else { return }
        pasteboard.clearContents()
        pasteboard.setString(body, forType: .string)
    }
}
