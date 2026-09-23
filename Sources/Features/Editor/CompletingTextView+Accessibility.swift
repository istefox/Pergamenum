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
        (super.accessibilityChildren() ?? []) + drawnEmbedElements() + drawnTableGrids() + linkElements()
    }

    /// One `AXLink` per clickable span, built by hand because nothing builds it any more.
    ///
    /// AppKit used to synthesise this element itself, from the standard `.link` attribute -
    /// the attribute issue #191 stopped applying (`MarkdownAttributedText.editorLink`'s doc
    /// comment says why: it is also what engaged AppKit's own unreliable click gesture, which
    /// aborted drag-select everywhere). Removing it took the accessibility element with it, so
    /// a wikilink stopped being perceivable or activatable from VoiceOver at all. That was not
    /// a cost worth paying and is not one this branch accepts: the element is re-created here,
    /// from `.editorLink` itself, without handing AppKit a gesture to misfire on.
    ///
    /// Role and title are chosen to match what AppKit produced before, measured against the
    /// UI test that caught the loss (`WikilinkNavigationUITests`, which looks the element up as
    /// `app.links["Destinazione"]`): the title is the span's own characters, so a concealed
    /// `[[**Destinazione**]]` still titles itself `**Destinazione**` exactly as it used to.
    /// Both title and label are set, since which of the two XCUITest and VoiceOver read is not
    /// something to leave to chance for an element that exists to be found.
    private func linkElements() -> [NSAccessibilityElement] {
        guard let storage = textStorage, let layout = textLayoutManager,
              let content = layout.textContentManager, let window
        else {
            linkAccessibilityElements = [:]
            return []
        }

        var next: [Int: NSAccessibilityElement] = [:]
        var elements: [NSAccessibilityElement] = []
        storage.enumerateAttribute(.editorLink, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil,
                  let frame = firstSegmentFrame(of: range, layout: layout, content: content)
            else { return }
            let onScreen = window.convertToScreen(convert(frame, to: nil))
            let title = (storage.string as NSString).substring(with: range)
            guard let element = linkElement(at: range.location, title: title, frame: onScreen)
            else { return }
            next[range.location] = element
            elements.append(element)
        }
        linkAccessibilityElements = next
        return elements
    }

    /// The on-screen rectangle of a character range's **first** line fragment segment, in this
    /// view's own coordinates - the `NSTextRange`/`enumerateTextSegments` shape
    /// `CompletingTextView+CursorRects.swift` and `FormattingTextView.frame(for:type:)` already
    /// use for exact placement.
    ///
    /// The first segment rather than the union of all of them: a link that wraps across a line
    /// break has a union rectangle whose centre falls on whatever sits between the two pieces,
    /// and an accessibility client that clicks an element clicks the centre of its frame. The
    /// first segment always genuinely covers the link's own glyphs.
    private func firstSegmentFrame(
        of range: NSRange, layout: NSTextLayoutManager, content: NSTextContentManager
    ) -> CGRect? {
        guard let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else { return nil }

        var first: CGRect?
        layout.enumerateTextSegments(in: textRange, type: .standard) { _, frame, _, _ in
            first = frame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            return false
        }
        guard let first, !first.isEmpty else { return nil }
        return first
    }

    /// The element for the link starting at `location`, reusing the one from the previous
    /// query where there is one - the same identity-preserving reuse `embedElement(at:
    /// fragment:in:)` below makes, for the same reason (VoiceOver tracks an element's
    /// identity, and rebuilding it on every query made the embed one flicker).
    private func linkElement(at location: Int, title: String, frame: CGRect) -> NSAccessibilityElement? {
        if let reused = linkAccessibilityElements[location] {
            reused.setAccessibilityTitle(title)
            reused.setAccessibilityLabel(title)
            reused.setAccessibilityFrame(frame)
            return reused
        }
        guard let element = NSAccessibilityElement.element(
            withRole: NSAccessibility.Role.link, frame: frame, label: title, parent: self
        ) as? NSAccessibilityElement else { return nil }
        element.setAccessibilityTitle(title)
        return element
    }

    /// Every table grid TextKit 2 currently has in this view's hierarchy (ADR-0029 §D6).
    ///
    /// A `TableGridView` is a real `NSView`, unlike the embed elements below - but being a
    /// real view is not enough to be reachable. `NSTextAttachmentViewProvider`'s view is
    /// hosted inside the private `_NSTextViewportElementView` TextKit 2 makes per laid-out
    /// fragment, and `NSTextView` answers `accessibilityChildren()` from its *text*, not
    /// from its subviews: measured in the failing run of R-05's own UI test, the whole
    /// `TextView` node came back a leaf in XCUITest's accessibility snapshot while the grid
    /// was on screen, in the window, at 286×96. So the same hand-over `drawnEmbedElements()`
    /// makes for a drawn picture is what a hosted view needs too - it is added here, not
    /// left to AppKit to find.
    ///
    /// `superview != nil` is the whole of "on screen right now": TextKit 2 takes an
    /// attachment view out of the hierarchy when its fragment leaves the viewport and puts
    /// it back when it returns, so a grid the store still holds for a table scrolled far
    /// away is deliberately not offered here. Sorted by header offset so the order is the
    /// note's own rather than a dictionary's.
    private func drawnTableGrids() -> [TableGridView] {
        guard let decorations = textContentStorage?.delegate as? EditorDecorationDelegate
        else { return [] }
        return decorations.tableViews
            .sorted { $0.key < $1.key }
            .map(\.value)
            .filter { $0.superview != nil }
    }

    /// One element per paragraph currently drawing an embed, reusing the one from the
    /// previous query where there is one and dropping every offset no longer drawn this
    /// same pass - never carried forward stale.
    ///
    /// The arithmetic is exactly `NoteTextView.Coordinator.selectEmbed(at:in:)`'s own
    /// (`NoteTextView+EmbedCaret.swift`), read here rather than duplicated: the same
    /// fragment enumeration `decoration(in:claimedBy:)` uses
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
        let label = embed.label

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
