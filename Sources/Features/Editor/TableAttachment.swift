import AppKit

/// Tracer-bullet probe for ADR-0029 §D16 probe 2 (Step 4.5 of the plan
/// `2026-09-02-editor-wysiwyg-unification`) - "can nested first-responder focus work inside
/// an `NSTextAttachmentViewProvider`-hosted view, in a real `CompletingTextView`, in a real
/// window." Not the production table grid (Task 4); a throwaway two-cell slice built only to
/// answer that one question, meant to be removed once the real Task 4/5 land.
///
/// `NSTextAttachment.h:90-91` says `allowsTextAttachmentView` is YES by default and
/// `tracksTextAttachmentViewBounds` (set on the provider below) makes the SDK's own
/// `attachmentBounds(for:...)` consult the provider instead of `-bounds` - neither overridden
/// here, unlike `EmbedAttachment`, because this probe answers a focus question, not a sizing
/// one (that is probe 3, separate).
final class TableAttachment: NSTextAttachment {
    /// The one grid this probe ever hands out - handed in from the Coordinator, on the main
    /// actor, the same finished-value crossing `EmbedAttachment.image` already makes (ADR
    /// §D6: "the delegate carries a reference and calls nothing"). Kept as the same instance
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

/// `NSTextAttachment.h:106-125`'s hook this repo had never called before this probe: "This is
/// where subclasses should create their custom view hierarchy. Should never be called
/// directly." `loadView` assigns the grid it was given rather than building one, so the same
/// `NSView` - and its first responder - survives every restyle (ADR §D6).
private final class TableAttachmentViewProvider: NSTextAttachmentViewProvider {
    var gridView: TableGridView?

    override func loadView() {
        view = gridView
    }
}
