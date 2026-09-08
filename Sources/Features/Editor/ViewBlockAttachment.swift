import AppKit
import SwiftUI

/// The one value that crosses from SwiftUI's main-actor layout into TextKit's nonisolated
/// `attachmentBounds`. A class and not a property on the host because `NSHostingView` is
/// `@MainActor` and the provider's `attachmentBounds` override is not.
final class ViewBlockHeightBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CGFloat?
    var height: CGFloat? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// The `NSHostingView` a view block's host is vended as, carrying its own measured content
/// height alongside the SwiftUI root view — `nonisolated` so the layout-time,
/// non-main-actor `attachmentBounds` override can read it.
final class ViewBlockHostView: NSHostingView<AnyView> {
    nonisolated let measuredHeight = ViewBlockHeightBox()

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) non supportato")
    }
}

/// The attachment substituted for a closed `pergamenum-view` fence (ADR-0033; plan
/// `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 4) - R-01/R-02/R-03 ("renders
/// as a live, interactive inline attachment"), R-06 (adaptive height, capped, scrolls
/// internally past the cap).
///
/// Shape copied from `TableAttachment.swift`, diverging only where ADR §D3 (the host comes
/// from `ViewBlockHostStore`, keyed by ordinal, not built here) and §D8 (the height is capped
/// at a maximum, but adaptive below it - ADR-0035, amending §D8's original fixed constant) say
/// to.
///
/// `NSTextAttachment.h:90-91`: `allowsTextAttachmentView` is YES by default, and
/// `tracksTextAttachmentViewBounds` - set on the provider below, exactly as `TableAttachment`
/// sets it - is what makes the SDK consult `attachmentBounds(for:…)` instead of `-bounds`.
/// Without it TextKit never asks, and ADR §D8's formula would never run.
final class ViewBlockAttachment: NSTextAttachment {
    /// The maximum height a view-block attachment will ever reserve — R-06's original cap,
    /// now a ceiling on an otherwise content-adaptive height rather than a constant (ADR-0035,
    /// amending ADR-0033 §D8): past this the host's own `ScrollView` takes over, exactly as it
    /// did when this was the only height.
    static let maximumHeight: CGFloat = 320
    /// The floor: a measurement of 0 (or near it) must not collapse the block's paragraph to
    /// nothing.
    static let minimumHeight: CGFloat = 24
    /// What an attachment reserves before its host has reported a real measurement — chosen to
    /// approximate the "header + no result yet" placeholder height so the common case (a fence
    /// scrolled into view for the first time) does not visibly collapse from a bigger placeholder
    /// down to its real, usually smaller, height.
    static let unmeasuredHeight: CGFloat = 120
    /// Tolerance below which a new measurement is not considered a change worth a re-layout —
    /// matches the tolerance `growToFitTheText` already uses on the text view's own frame height.
    static let heightEpsilon: CGFloat = 0.5

    /// The height to store for a freshly measured content height, or `nil` when the rectangle
    /// TextKit would actually reserve does not change and no re-layout is owed.
    ///
    /// Clamps *before* it compares against `current` — this is what makes a measure → relayout →
    /// remeasure cycle terminate for content taller than the cap: a board measuring 5000 and then
    /// 5003 both clamp to `maximumHeight`, so the second measurement stores nothing and schedules
    /// no further relayout.
    static func storableHeight(measured: CGFloat, current: CGFloat?) -> CGFloat? {
        let clamped = min(max(measured, minimumHeight), maximumHeight)
        guard let current else { return clamped }
        return abs(current - clamped) > heightEpsilon ? clamped : nil
    }

    /// The host this attachment draws - handed in from the Coordinator via
    /// `ViewBlockHostStore`, the same finished-value crossing `TableAttachment.gridView`
    /// already makes (ADR §D3/§D6: "the delegate carries a reference and calls nothing").
    var hostView: ViewBlockHostView?

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
    var hostView: ViewBlockHostView?

    override func loadView() {
        view = hostView
    }

    /// R-06, ADR §D8/ADR-0035: the width TextKit is offering for this line, and a height
    /// clamped between `minimumHeight` and `maximumHeight` - adaptive to `hostView`'s
    /// measured content within that range, which is what keeps a small result set from
    /// leaving a big empty box while a large one still scrolls internally past the cap
    /// instead of pushing the rest of the note down.
    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let raw = hostView?.measuredHeight.height ?? ViewBlockAttachment.unmeasuredHeight
        let height = min(max(raw, ViewBlockAttachment.minimumHeight), ViewBlockAttachment.maximumHeight)
        return CGRect(
            origin: .zero,
            size: CGSize(width: proposedLineFragment.width, height: height)
        )
    }
}
