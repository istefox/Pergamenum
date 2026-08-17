import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// Clicking the badge of a folded section opens it (PG-021).
//
// Driven through a real `NSTextView` offscreen, like the transclusion tests, and for the
// reason that slice taught: a decoration's rectangle is in the text container's coordinates
// and a click arrives in the view's. Comparing the two directly is a hit test that never
// hits, and it looks exactly like a feature that was never wired.

@MainActor
@Suite struct FoldBadgeClick {
    private static let note = "# Uno\ncorpo uno\ncorpo due\n\n# Due\ncorpo tre\n"

    private static func editor(
        folded: Set<Int>,
        onToggleFold: @escaping (Int) -> Void
    ) -> (NSTextView, NoteTextView.Coordinator) {
        let ranges = NoteOutline.entries(in: note).map { NSRange($0.range, in: note) }
        let view = NoteTextView(
            text: .constant(note),
            theme: .emergency,
            noteTitles: [],
            tagSuggestions: [],
            onFollowLink: { _ in },
            outlineRanges: ranges,
            foldedEntries: folded,
            onToggleFold: onToggleFold
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = note
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyFolding(to: textView, folded: folded, theme: .emergency)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
        return (textView, coordinator)
    }

    /// The badge's rectangle, in the view's coordinates - what a click carries.
    private static func badge(in textView: NSTextView) -> CGRect {
        guard let manager = textView.textLayoutManager else { return .null }
        var found: CGRect = .null
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) {
            if let fragment = $0 as? FoldedHeadingFragment { found = fragment.badgeFrameInContainer }
            return true
        }
        guard !found.isNull else { return .null }
        let origin = textView.textContainerOrigin
        return found.offsetBy(dx: origin.x, dy: origin.y)
    }

    @Test func aClickOnTheBadgeOpensTheSectionItBelongsTo() {
        var toggled: Int?
        // Entry 0 is `# Uno`, which hides two lines and a blank one.
        let (textView, coordinator) = Self.editor(folded: [0]) { toggled = $0 }

        let box = Self.badge(in: textView)
        #expect(box.width > 0)
        #expect(coordinator.unfold(at: CGPoint(x: box.midX, y: box.midY), in: textView))
        #expect(toggled == 0)
    }

    @Test func aClickOnTheHeadingItselfBelongsToTheText() {
        // Swallowing it would stop the caret being placed by a click, which is a worse
        // defect than the one this feature fixes.
        var toggled: Int?
        let (textView, coordinator) = Self.editor(folded: [0]) { toggled = $0 }

        let box = Self.badge(in: textView)
        let onTheHeading = CGPoint(x: max(1, box.minX - 20), y: box.midY)
        #expect(!coordinator.unfold(at: onTheHeading, in: textView))
        #expect(toggled == nil)
    }

    @Test func withNothingFoldedThereIsNoBadgeToClick() {
        // The case that matters: the rectangle exists as arithmetic even when nothing is
        // drawn, so the hit test has to be guarded by the fold and not only by the geometry.
        var toggled: Int?
        let (textView, coordinator) = Self.editor(folded: []) { toggled = $0 }

        #expect(Self.badge(in: textView).isNull)
        #expect(!coordinator.unfold(at: CGPoint(x: 200, y: 30), in: textView))
        #expect(toggled == nil)
    }
}
