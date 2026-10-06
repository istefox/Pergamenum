import AppKit

/// `CompletingTextView+CursorRects.swift`'s twin, not a shared helper (ADR-0027 §D9: this view
/// forks nothing from the note editor's). See that file's header (`PG-219`): `NSCursor` calls
/// made from here never reached the screen, so the view only answers which pointer it wants and
/// reports a change through `onPointerChange`, and `StickyTextCard` applies it with
/// `.pointerStyle` while the card is being edited (`docs/plans/note-workflow-n1.md` Task 4).
extension FormattingTextView {
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

    /// `.link` when a link's tracking area holds `point` (view space), `.text` otherwise.
    func pointer(at point: NSPoint) -> EditorPointer {
        linkTrackingAreas.contains { $0.rect.contains(point) } ? .link : .text
    }

    /// Reports the pointer at `point` through `onPointerChange`, only on a change.
    func trackPointer(at point: NSPoint) {
        let pointer = pointer(at: point)
        guard pointer != reportedPointer else { return }
        reportedPointer = pointer
        onPointerChange?(pointer)
    }

    /// `CompletingTextView+CursorRects.swift`'s twin: `NSTextView`'s whole-bounds tracking area
    /// carries `.cursorUpdate`, so this runs on every mouse-moved tick.
    override func cursorUpdate(with event: NSEvent) {
        trackPointer(at: convert(event.locationInWindow, from: nil))
        super.cursorUpdate(with: event)
    }

    /// One tracking area per `.editorLink` run, the same signal `followLinkIfPresent(at:)`
    /// already keys off. Geometry is `frame(for:type:)`'s own `NSTextRange`/
    /// `enumerateTextSegments` shape, run once per attribute run and per wrapped segment rather
    /// than unioned into one rectangle - a tracking area has to cover every line a span wraps
    /// across, not just the bounding box of its first and last.
    private static func linkTrackingAreas(in textView: FormattingTextView) -> [NSTrackingArea] {
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
                // `CompletingTextView+CursorRects.swift`'s twin finding: a tight glyph-run rect
                // has no tolerance for ordinary mouse jitter while holding "still" - a few
                // points of slack absorb it (padded areas are hover-only, never hit-testing).
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
