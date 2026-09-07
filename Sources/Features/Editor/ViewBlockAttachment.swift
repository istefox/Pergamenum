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
/// `NSTextAttachment.h:90-91`: `allowsTextAttachmentView` is YES by default, and
/// `tracksTextAttachmentViewBounds` - set on the provider below, exactly as `TableAttachment`
/// sets it - is what makes the SDK consult `attachmentBounds(for:…)` instead of `-bounds`.
/// Without it TextKit never asks, and ADR §D8's formula would never run.
final class ViewBlockAttachment: NSTextAttachment {
    /// Fixed height every view-block attachment reserves, regardless of its rendered result
    /// set's size (ADR §D8, R-06): the note's layout below the block must not move as a board
    /// grows or shrinks. A constant, never derived from `hostView`'s content - the host scrolls
    /// internally instead (`ViewBlockHostStore.rootView(...)`'s own `ScrollView`).
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
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

/// `NSTextAttachment.h:106-125`'s view-hierarchy hook, the same one `TableAttachmentViewProvider`
/// already calls production for a table grid.
///
/// `loadView` assigns the host it was **given** rather than building one, exactly as
/// `TableAttachmentViewProvider` assigns its grid: the host comes from `ViewBlockHostStore`,
/// keyed by ordinal, so the same `NSHostingView` - and the SwiftUI state, the scroll position
/// and the evaluated result behind it - survives every restyle (ADR §D3/§D6). Building one
/// here would re-run the block's query on every keystroke, which is the whole thing this
/// chain's key space exists to avoid.
private final class ViewBlockAttachmentViewProvider: NSTextAttachmentViewProvider {
    var hostView: NSHostingView<AnyView>?

    override func loadView() {
        view = hostView
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
