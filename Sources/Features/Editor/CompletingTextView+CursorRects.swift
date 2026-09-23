import AppKit

/// The pointing-hand cursor over a wikilink target or a CommonMark label (issue #191
/// follow-up) - **currently non-functional, out of scope for this branch, see below.**
///
/// Three independent mechanisms were tried and instrumented with logging to confirm each one
/// actually ran: `resetCursorRects()`/`addCursorRect(_:cursor:)`; `mouseEntered`/`mouseExited`
/// calling `NSCursor.push()`/`.pop()` directly (the shape `EditorColumns.swift`'s divider uses
/// successfully elsewhere in this app); and `cursorUpdate(with:)` calling `.set()` (chosen after
/// logging showed `NSTextView`'s own whole-bounds tracking area carries `.cursorUpdate`/
/// `.mouseMoved`/`.inVisibleRect`, consulted on every mouse-moved tick). All three fired exactly
/// as designed and none changed the visible cursor. Padding the tracking rects (in case ordinary
/// mouse jitter was exiting a too-tight boundary) made no difference either.
///
/// The decisive check: logging `NSCursor.current` itself, before and after every `.set()` call,
/// for the whole duration of a real hover. It read as our pushed `NSCursor.pointingHand`
/// instance, consistently, for every tick of the dwell - AppKit's own bookkeeping agrees the
/// pointing-hand cursor is active the entire time. The screen still showed the arrow throughout.
/// This is not a logic, geometry or timing bug in this code: `NSCursor.current` and what the
/// Window Server actually draws have come apart, which is a window-level cursor-ownership issue
/// outside anything `NSCursor`'s public API can query or override from here.
///
/// Every *working* custom cursor in this codebase (`BoardHandles.swift`, `BoardCropEditor.swift`,
/// `WorkspacePaneDivider.swift`, `EditorColumns.swift`) goes through SwiftUI's own `.onHover` +
/// `push()`/`.pop()`, never a raw `NSTrackingArea`/`cursorUpdate` override - consistent with
/// SwiftUI owning cursor display for this window and not honoring AppKit-side changes made
/// outside its own hover pipeline. Recommended, not yet filed: a ticket covering this together
/// with the separately-confirmed, app-wide absence of the ordinary I-beam cursor (same family of
/// symptom). A real fix likely means restructuring `NoteTextView`/`FormattingTextView` around
/// `.onContinuousHover`, which for `NoteTextView` means threading through its ~40 forwarded
/// properties across four call sites - too wide for a click-reveal bugfix branch.
///
/// The `cursorUpdate(with:)` shape and the padded tracking-area geometry are left in place below:
/// both are correct and harmless (hover-only, no effect on click hit-testing), just not sufficient
/// on their own to make the cursor visible.
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
        hoveredLinkCount += 1
    }

    override func mouseExited(with event: NSEvent) {
        guard let trackingArea = event.trackingArea, linkTrackingAreas.contains(trackingArea) else {
            super.mouseExited(with: event)
            return
        }
        hoveredLinkCount = max(0, hoveredLinkCount - 1)
    }

    override func cursorUpdate(with event: NSEvent) {
        if hoveredLinkCount > 0 {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
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
