import AppKit

/// The Workspace card's `AXLink` elements - `CompletingTextView+Accessibility.swift`'s
/// `linkElements()` twin, and a twin rather than a shared helper for the reason this class
/// exists at all (ADR-0027 §D9: a sibling of the note editor's text view, never a fork, with
/// nothing extracted from it).
///
/// The same loss is being repaired here as there: a clickable span in a card carried the
/// standard `.link` until issue #191 replaced it with `.editorLink`, and AppKit synthesised
/// its accessibility element from that attribute alone. Without a replacement a card's links
/// would be unreachable from VoiceOver - the note editor's regression, in the surface nobody
/// wrote a UI test for.
///
/// One deliberate difference from the editor's version: no element cache. The editor keeps
/// one because a note stays open and VoiceOver tracks element identity across queries; a card's
/// text view exists only for the length of one inline-editing session, and a stored property
/// would have to live on `FormattingTextView` itself, which is already over the linter's
/// type-body cap. If element flicker ever shows up here, the editor's cache is the shape to
/// copy.
extension FormattingTextView {
    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + linkElements()
    }

    /// One element per `.editorLink` run, titled with the span's own characters - the same
    /// role, title and first-segment geometry the editor's twin documents in full.
    private func linkElements() -> [NSAccessibilityElement] {
        guard let storage = textStorage, let layout = textLayoutManager,
              let content = layout.textContentManager, let window
        else { return [] }

        var elements: [NSAccessibilityElement] = []
        storage.enumerateAttribute(.editorLink, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil,
                  let frame = firstSegmentFrame(of: range, layout: layout, content: content)
            else { return }
            let title = (storage.string as NSString).substring(with: range)
            guard let element = NSAccessibilityElement.element(
                withRole: NSAccessibility.Role.link,
                frame: window.convertToScreen(convert(frame, to: nil)),
                label: title,
                parent: self
            ) as? NSAccessibilityElement else { return }
            element.setAccessibilityTitle(title)
            elements.append(element)
        }
        return elements
    }

    /// The first line-fragment segment of `range`, in this view's own coordinates. First and
    /// not the union, for the reason the editor's twin gives: an accessibility client clicks
    /// the centre of a frame, and a wrapped link's union rectangle has its centre on whatever
    /// lies between the two pieces.
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
}
