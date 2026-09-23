import AppKit

/// `CompletingTextView+CursorRects.swift`'s twin, not a shared helper (ADR-0027 §D9: this view
/// forks nothing from the note editor's) - **currently non-functional, out of scope for this
/// branch.** See that file's header for the full root-cause chain (issue #191 follow-up): three
/// independent mechanisms all fired as designed and never changed the visible cursor, and the
/// decisive check - logging `NSCursor.current` itself through a real hover - showed AppKit's own
/// bookkeeping agreeing the pointing-hand cursor was active the whole time while the screen
/// still showed the arrow. Not a bug in this code: `NSCursor.current` and what the Window Server
/// draws have come apart, a window-level cursor-ownership issue outside what `NSCursor`'s public
/// API can query or fix from here.
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
        hoveredLinkCount += 1
    }

    override func mouseExited(with event: NSEvent) {
        guard let trackingArea = event.trackingArea, linkTrackingAreas.contains(trackingArea) else {
            super.mouseExited(with: event)
            return
        }
        hoveredLinkCount = max(0, hoveredLinkCount - 1)
    }

    /// `CompletingTextView+CursorRects.swift`'s twin finding: `NSTextView` installs its own
    /// whole-bounds tracking area with `.cursorUpdate` and `.mouseMoved`, so `cursorUpdate(with:)`
    /// fires on every mouse-moved tick and its default re-asserts a cursor each time - which is
    /// what discarded a one-shot `push()` from `mouseEntered`. Answering here, last every tick,
    /// is what makes it stick.
    override func cursorUpdate(with event: NSEvent) {
        if hoveredLinkCount > 0 {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
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
