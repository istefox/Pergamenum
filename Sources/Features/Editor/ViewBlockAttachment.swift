import AppKit
import SwiftUI

/// The attachment substituted for a closed `pergamenum-view` fence (ADR-0033; plan
/// `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 4) - R-01/R-02/R-03 ("renders
/// as a live, interactive inline attachment"), R-06 (fixed height, scrolls internally).
///
/// Shape copied from `TableAttachment.swift`, diverging only where ADR §D3 (the host comes
/// from `ViewBlockHostStore`, keyed by ordinal, not built here) and §D8 (fixed height, never
/// an intrinsic one read off the hosted content) say to.
///
/// **TESTER STUB (ADR-0049).** `viewProvider(for:location:textContainer:)` hands back a
/// provider whose `loadView()` does not yet assign `hostView` and does not yet set
/// `tracksTextAttachmentViewBounds = true` - Task 4's coder work, copying
/// `TableAttachmentViewProvider`'s shape. `attachmentBounds(...)` on that provider *is*
/// written for real below: it is pure geometry with no coder-owned business logic behind it
/// (ADR §D8's formula is exact and content-independent), so `ViewBlockHostStoreTests`'
/// attachment-bounds assertions are green against this stub already and must stay that way -
/// Task 4's coder must not change this formula.
final class ViewBlockAttachment: NSTextAttachment {
    /// Fixed height every view-block attachment reserves, regardless of its rendered result
    /// set's size (ADR §D8, R-06): the note's layout below the block must not move as a board
    /// grows or shrinks. A placeholder value - Task 4's coder may tune it - but it must stay
    /// a constant, never derived from `hostView`'s content.
    static let height: CGFloat = 320

    /// The host this attachment draws - handed in from the Coordinator via
    /// `ViewBlockHostStore`, the same finished-value crossing `TableAttachment.gridView`
    /// already makes (ADR §D3/§D6: "the delegate carries a reference and calls nothing").
    var hostView: NSHostingView<AnyView>?

    override func viewProvider(
        for parentView: NSView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = ViewBlockAttachmentViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        provider.hostView = hostView
        return provider
    }
}

/// `NSTextAttachment.h:106-125`'s view-hierarchy hook, the same one `TableAttachmentViewProvider`
/// already calls production for a table grid.
///
/// **TESTER STUB:** `loadView()` does not yet assign the real host, and
/// `tracksTextAttachmentViewBounds` is not yet set to `true` on the attachment's own
/// `viewProvider(...)` above - both are Task 4's coder work (ADR §D3/§D6). `attachmentBounds`
/// below is written for real (see this file's header).
private final class ViewBlockAttachmentViewProvider: NSTextAttachmentViewProvider {
    var hostView: NSHostingView<AnyView>?

    override func loadView() {
        // TODO(coder, Task 4): `view = hostView`, matching `TableAttachmentViewProvider`, plus
        // `tracksTextAttachmentViewBounds = true` set on the attachment's provider above - or
        // TextKit never consults `attachmentBounds` below at all (ADR §D8).
        view = NSView()
    }

    /// R-06, ADR §D8: the width TextKit is offering for this line, and a constant height -
    /// independent of `hostView`'s content, which is exactly what keeps a forty-card board
    /// from pushing the rest of the note down as its result set changes.
    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        CGRect(
            origin: .zero,
            size: CGSize(width: proposedLineFragment.width, height: ViewBlockAttachment.height)
        )
    }
}
