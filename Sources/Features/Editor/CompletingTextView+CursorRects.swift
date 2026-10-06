import AppKit

/// The pointer over editor text (issue #191 follow-up, `PG-219`): the view decides it, SwiftUI
/// draws it. `NSCursor` calls made from here - cursor rects, `push()`/`.pop()` on enter and exit,
/// `.set()` in `cursorUpdate(with:)` - all ran as designed and never changed what the Window
/// Server drew in this SwiftUI-hosted window, while `NSCursor.current` agreed they had.
///
/// So the view only answers which pointer it wants, `EditorPointer`, from one tracking area per
/// `.editorLink` run (the geometry clicks already key off), and reports a change through
/// `onPointerChange`; the host applies it with `.pointerStyle`, the route SwiftUI honours here
/// (`docs/plans/note-workflow-n1.md` Task 4, note-workflow R-09).
extension CompletingTextView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in linkTrackingAreas { removeTrackingArea(area) }
        linkTrackingAreas = Self.linkTrackingAreas(in: self)
        for area in linkTrackingAreas { addTrackingArea(area) }
    }

    override func mouseEntered(with event: NSEvent) {
        guard let trackingArea = event.trackingArea, linkTrackingAreas.contains(trackingArea) else {
            super.mouseEntered(with: event)
            return
        }
        trackPointer(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard let trackingArea = event.trackingArea, linkTrackingAreas.contains(trackingArea) else {
            super.mouseExited(with: event)
            return
        }
        trackPointer(at: convert(event.locationInWindow, from: nil))
    }

    /// `.link` when a link's tracking area holds `point` (view space), `.text` otherwise: the
    /// same rectangles hover already uses, with no second scan of the text.
    func pointer(at point: NSPoint) -> EditorPointer {
        linkTrackingAreas.contains { $0.rect.contains(point) } ? .link : .text
    }

    /// Reports the pointer at `point` through `onPointerChange`, only when it changed since the
    /// last report - moving from one link straight into an adjacent one reports nothing.
    func trackPointer(at point: NSPoint) {
        let pointer = pointer(at: point)
        guard pointer != reportedPointer else { return }
        reportedPointer = pointer
        onPointerChange?(pointer)
    }

    /// `NSTextView`'s own whole-bounds tracking area carries `.cursorUpdate`, so this runs on
    /// every mouse-moved tick: the one place that sees the pointer cross a link's edge without
    /// an enter or exit of its own.
    override func cursorUpdate(with event: NSEvent) {
        trackPointer(at: convert(event.locationInWindow, from: nil))
        super.cursorUpdate(with: event)
    }

    /// One tracking area per `.editorLink` run - the same signal `followLinkIfPresent(at:)`
    /// already keys off, so hover and click agree on what counts as a link without a second
    /// attribute saying the same thing. Geometry is the `NSTextRange`/`enumerateTextSegments`
    /// shape `FormattingTextView.swift`'s `frame(for:type:)` already uses elsewhere for exact
    /// on-screen placement.
    private static func linkTrackingAreas(in textView: CompletingTextView) -> [NSTrackingArea] {
        guard let storage = textView.textStorage, let layout = textView.textLayoutManager,
              let content = layout.textContentManager
        else { return [] }

        var areas: [NSTrackingArea] = []
        storage.enumerateAttribute(
            .editorLink, in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            guard value != nil,
                  let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end)
            else { return }

            layout.enumerateTextSegments(in: textRange, type: .standard) { _, frame, _, _ in
                let rect = frame.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
                // `enumerateTextSegments` returns a rect tight to the glyph run, with no
                // tolerance for the ordinary sub-pixel jitter of a hand trying to hold a mouse
                // "still" - confirmed by logged exit events landing 1-3pt past the exact edge.
                // A few points of slack absorb that without reaching into genuinely different
                // text (padded areas are never used for hit-testing, only for hover).
                areas.append(NSTrackingArea(
                    rect: rect.insetBy(dx: -3, dy: -2),
                    options: [.mouseEnteredAndExited, .activeInKeyWindow],
                    owner: textView,
                    userInfo: nil
                ))
                return true
            }
        }
        return areas
    }
}
