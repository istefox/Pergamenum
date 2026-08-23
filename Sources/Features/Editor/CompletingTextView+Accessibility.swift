import AppKit

/// Every embed the editor currently draws (ADR-0018 slice 3, Step 3), exposed as a real
/// accessibility element - the fix for the orphan `NSAccessibilityElement` this replaces.
/// `EditorDecorationDelegate` used to build one with `parent: nil` and hand it to
/// `.accessibilityAttachment` alone; `NSAccessibilityElement.h`'s own header says "the
/// vendor... must maintain ownership of the NSAccessibilityElements", and nothing there
/// ever called `accessibilityAddChildElement:` to give AppKit one to keep. VoiceOver
/// never adopted it: no `Image` node, no `editor-embed` identifier, in a dump of the real
/// accessibility tree.
///
/// `EditorDecorationDelegate` cannot own the fix itself: it is not `@MainActor`
/// (`NoteTextView+Embeds.swift:32-38` says why) and it has no `NSView` to parent an
/// element to. This text view is where an `NSView` and the delegate's own tables about
/// what is drawn right now finally meet.
///
/// Built on demand, from `accessibilityChildren()` itself, rather than pushed in from the
/// delegate on every layout pass: by the time VoiceOver asks, layout has already run, so
/// the frame read off `NSTextLayoutFragment` here is correct by construction, and there is
/// no rendition-lands-later state to keep synchronised with a push.
extension CompletingTextView {
    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + drawnEmbedElements()
    }

    /// One element per paragraph currently drawing an embed, reusing the one from the
    /// previous query where there is one and dropping every offset no longer drawn this
    /// same pass - never carried forward stale.
    ///
    /// The arithmetic is exactly `NoteTextView.Coordinator.selectEmbed(at:in:)`'s own
    /// (`NoteTextView+EmbedCaret.swift`), read here rather than duplicated: the same
    /// fragment enumeration `decoration(at:in:claimedBy:)` uses
    /// (`NoteTextView+Transclusion.swift:182-196`), the same
    /// `drawnEmbedRange(atParagraphStart:in:)` as the one source of truth for "this embed
    /// is on screen right now", the same `frameForTextAttachment(at:)` plus
    /// `layoutFragmentFrame` two-step `selectEmbed` already does.
    /// What every candidate paragraph in one `drawnEmbedElements()` pass reads from -
    /// bundled so `embedElement(at:fragment:in:)` stays at three parameters rather than
    /// the six passing each of these on its own would need.
    private struct Scan {
        let decorations: EditorDecorationDelegate
        let text: NSString
        let content: NSTextContentManager
        let window: NSWindow
    }

    private func drawnEmbedElements() -> [NSAccessibilityElement] {
        guard let decorations = textContentStorage?.delegate as? EditorDecorationDelegate,
              let manager = textLayoutManager, let content = manager.textContentManager,
              let window
        else {
            embedAccessibilityElements = [:]
            return []
        }
        let scan = Scan(decorations: decorations, text: string as NSString, content: content, window: window)

        var next: [Int: NSAccessibilityElement] = [:]
        var elements: [NSAccessibilityElement] = []
        manager.enumerateTextLayoutFragments(
            from: manager.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            let paragraphStart = content.offset(
                from: content.documentRange.location, to: fragment.rangeInElement.location
            )
            guard let element = embedElement(at: paragraphStart, fragment: fragment, in: scan) else { return true }
            next[paragraphStart] = element
            elements.append(element)
            return true
        }
        embedAccessibilityElements = next
        return elements
    }

    /// The element for the embed drawn at `paragraphStart`, or nil where none is drawn
    /// there right now - nil for exactly the reasons `drawnEmbedRange` and
    /// `frameForTextAttachment` already refuse one: no rendition, a stale marker, or a
    /// fragment TextKit has not measured yet.
    ///
    /// The frame is computed fresh on every call even for a reused element: `local` comes
    /// from the fragment's own current layout, `layoutFragmentFrame` translates it into
    /// the text container, `textContainerOrigin` undoes
    /// `NoteTextView.Coordinator.inContainer(_:of:)` (`NoteTextView+Transclusion.swift:204`)
    /// to reach this view's own coordinates, and `convert(_:to: nil)` plus
    /// `window.convertToScreen(_:)` reach the screen - `NSAccessibilityElement`'s own
    /// `accessibilityFrame` is documented "in screen coordinates", the same pair
    /// `caretRectOnScreen()` already uses for the same reason.
    private func embedElement(
        at paragraphStart: Int, fragment: NSTextLayoutFragment, in scan: Scan
    ) -> NSAccessibilityElement? {
        guard let markerRange = scan.decorations.drawnEmbedRange(atParagraphStart: paragraphStart, in: scan.text),
              let embed = Attachment.embed(inLine: scan.text.substring(with: markerRange)),
              let attachmentLocation = scan.content.location(
                  scan.content.documentRange.location, offsetBy: markerRange.location
              )
        else { return nil }

        let local = fragment.frameForTextAttachment(at: attachmentLocation)
        guard !local.isEmpty else { return nil }
        let containerFrame = fragment.layoutFragmentFrame
        let inContainer = local.offsetBy(dx: containerFrame.minX, dy: containerFrame.minY)
        let inView = inContainer.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let onScreen = scan.window.convertToScreen(convert(inView, to: nil))
        let label = embed.alt ?? embed.target

        if let reused = embedAccessibilityElements[paragraphStart] {
            reused.setAccessibilityLabel(label)
            reused.setAccessibilityFrame(onScreen)
            return reused
        }
        guard let element = NSAccessibilityElement.element(
            withRole: NSAccessibility.Role.image, frame: onScreen, label: label, parent: self
        ) as? NSAccessibilityElement else { return nil }
        element.setAccessibilityIdentifier("editor-embed")
        return element
    }
}
