import AppKit

/// The one character a GFM table's header line is substituted for (ADR-0029 §D4/§D6; plan
/// `2026-09-02-editor-wysiwyg-unification`, Task 4) - `\u{FFFC}` carrying this attachment,
/// whose view provider hands TextKit 2 the real `TableGridView` the Coordinator already
/// built. Grew out of the Step 4.5 tracer-bullet probe for §D16 probe 2, which answered the
/// one question this repo had never asked - nested first-responder focus does work inside an
/// `NSTextAttachmentViewProvider` view in a real `CompletingTextView` - and is now the
/// production path rather than a slice of one.
///
/// `NSTextAttachment.h:90-91` says `allowsTextAttachmentView` is YES by default and
/// `tracksTextAttachmentViewBounds` (set on the provider below) makes the SDK's own
/// `attachmentBounds(for:...)` consult the provider instead of `-bounds` - which is the whole
/// of §D16 probe 3: the line fragment is as tall as the grid because the grid is what was
/// asked, not because a number was pushed in that a window resize would make stale (ADR-0019
/// §D2's argument for the negotiation hook, one level up).
final class TableAttachment: NSTextAttachment {
    /// The grid this attachment draws - handed in from the Coordinator, on the main actor,
    /// the same finished-value crossing `EmbedAttachment.image` already makes (ADR §D6:
    /// "the delegate carries a reference and calls nothing"). Kept as the same instance
    /// across every styling pass, or first responder would be lost on the next keystroke.
    var gridView: TableGridView?

    override func viewProvider(
        for parentView: NSView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = TableAttachmentViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        provider.gridView = gridView
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

/// `NSTextAttachment.h:106-125`'s hook this repo had never called before this chain: "This is
/// where subclasses should create their custom view hierarchy. Should never be called
/// directly." `loadView` assigns the grid it was given rather than building one, so the same
/// `NSView` - and its first responder - survives every restyle (ADR §D6).
private final class TableAttachmentViewProvider: NSTextAttachmentViewProvider {
    var gridView: TableGridView?

    override func loadView() {
        view = gridView
    }

    /// The line's height, asked of the grid itself (`NSTextAttachment.h:127-128` routes here
    /// once `tracksTextAttachmentViewBounds` is set).
    ///
    /// Overridden rather than left to the default, which measures whatever the view's frame
    /// happens to be at the moment it is asked: a grid rebuilt for a new row count is laid
    /// out on the *next* pass, so a frame-derived answer would be one structural edit behind
    /// and the paragraph under a three-row table would sit over its last row. The intrinsic
    /// size is computed from the table's own cells, so it is right the first time it is
    /// asked (§D16 probe 3's pass criterion).
    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        guard let gridView else {
            return super.attachmentBounds(
                for: attributes, location: location, textContainer: textContainer,
                proposedLineFragment: proposedLineFragment, position: position
            )
        }
        return CGRect(origin: .zero, size: gridView.intrinsicContentSize)
    }
}
