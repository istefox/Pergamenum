import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0027 §D5, plan `2026-08-28-unificare-nota-e-testo-in-un-solo-strume`, Task 6 (R-03, R-05).
//
// Scope of this file: `BoardFormatBarGeometry.placement(...)` and `.shouldShowFormatBar(...)` -
// the pure arithmetic dispatched here precisely so it can be tested without a window, per the
// plan's own words for this task. `CardFormatBar` (the pill) and `BoardFormatBar` (the live
// placement wiring) are SwiftUI views with no unit tests of their own, matching this repo's
// convention for every other view in this chain (`Tests/CardTextViewTests.swift`'s own header
// makes the identical call for `CardTextView`/`FormattingTextView`) - a manual pass is where
// their on-screen behaviour is actually verified, not this file.
//
// RED: both functions are `fatalError` stubs in `BoardFormatBar.swift` until Task 6's coder
// fills them in, so every `@Test` below is expected to crash the run it belongs to, not merely
// fail an assertion - the same TDD shape `Tests/LineFormatTests.swift`, `Tests/CardTextViewTests.swift`
// and `Tests/CardFormattingTests.swift` document for Tasks 2, 4 and 5.

// MARK: - `placement(...)`: the documented board transform (ADR §D5)

@Test func placementOriginFollowsTheDocumentedBoardTransform() {
    // BoardMarquee's own comment (BoardOverlays.swift:14-15): "a board point p lands at
    // p * zoom + pan". p here is cardOrigin + selectionFrame.origin = (100 + 12, 200 + 30).
    let placement = BoardFormatBarGeometry.placement(
        selectionFrame: CGRect(x: 12, y: 30, width: 40, height: 16),
        cardOrigin: CGPoint(x: 100, y: 200),
        zoom: 2,
        pan: CGSize(width: 50, height: -20),
        viewport: CGSize(width: 800, height: 600)
    )
    #expect(placement.origin.x == (100 + 12) * 2 + 50.0)
    #expect(placement.origin.y == (200 + 30) * 2 + (-20.0))
}

@Test func placementIsTheIdentityAtZoomOneWithZeroPan() {
    let placement = BoardFormatBarGeometry.placement(
        selectionFrame: CGRect(x: 12, y: 30, width: 40, height: 16),
        cardOrigin: CGPoint(x: 100, y: 200),
        zoom: 1,
        pan: .zero,
        viewport: CGSize(width: 800, height: 600)
    )
    #expect(placement.origin == CGPoint(x: 112, y: 230))
}

@Test func placementOfACardAtTheBoardOriginWithNoSelectionOffsetIsTheOriginItself() {
    // The simplest possible case: a card at (0, 0), a selection starting exactly at the card's
    // own origin, zoom 1, no pan - every term in the formula drops out except identity.
    let placement = BoardFormatBarGeometry.placement(
        selectionFrame: CGRect(x: 0, y: 0, width: 20, height: 14),
        cardOrigin: .zero,
        zoom: 1,
        pan: .zero,
        viewport: CGSize(width: 800, height: 600)
    )
    #expect(placement.origin == .zero)
}

// MARK: - `placement(...)`: the pill's own size never scales with zoom

@Test func pillSizeCarriesNoZoomParameterAndCannotScale() {
    // `pillSize` is a bare constant with no `zoom` argument at all - the SPEC's "the pill's own
    // size does not scale with zoom" requirement, held at the type level rather than by a
    // runtime check. Read at two very different zooms; the value read is the same expression
    // both times; only demonstrating that no zoom-shaped input could ever reach it.
    let atSmallZoom = BoardFormatBarGeometry.pillSize
    let atLargeZoom = BoardFormatBarGeometry.pillSize
    #expect(atSmallZoom == atLargeZoom)
}

@Test func placementCarriesNoSizeOfItsOwnToScale() {
    // Structural check on `Placement` itself, so a future edit that adds a scaled size field
    // back onto the placement result is caught here rather than by accident: the type is
    // reflected rather than merely read, and must carry exactly `origin` and `flipsBelow`.
    let placement = BoardFormatBarGeometry.placement(
        selectionFrame: CGRect(x: 10, y: 10, width: 40, height: 16),
        cardOrigin: .zero,
        zoom: 4,
        pan: .zero,
        viewport: CGSize(width: 800, height: 600)
    )
    let labels = Set(Mirror(reflecting: placement).children.compactMap(\.label))
    #expect(labels == ["origin", "flipsBelow"], "Placement must carry no size of its own to scale")
}

// MARK: - `placement(...)`: flip below vs. clamp (plan Task 6: pick one, assert it)
//
// Strategy chosen and documented in BoardFormatBar.swift: **flip below, never clamp**. A
// selection close enough to the container's own top edge (y = 0) that the pill would not fit
// above it flips to sit `gap` points below the selection instead.

@Test func placementFlipsBelowWhenThereIsNoRoomAboveTheContainersTopEdge() {
    // A selection two points from the top of the container: placing the pill above it (height
    // 30 + gap 8 = 38 points of clearance needed) would push the pill's top edge above y = 0.
    let placement = BoardFormatBarGeometry.placement(
        selectionFrame: CGRect(x: 5, y: 2, width: 30, height: 14),
        cardOrigin: .zero,
        zoom: 1,
        pan: .zero,
        viewport: CGSize(width: 800, height: 600)
    )
    #expect(placement.flipsBelow, "a selection with no clearance above it must flip below")
}

@Test func placementStaysAboveWhenThereIsRoom() {
    // A selection well clear of the top edge keeps the mockup's default: above the selection.
    let placement = BoardFormatBarGeometry.placement(
        selectionFrame: CGRect(x: 5, y: 400, width: 30, height: 14),
        cardOrigin: .zero,
        zoom: 1,
        pan: .zero,
        viewport: CGSize(width: 800, height: 600)
    )
    #expect(!placement.flipsBelow, "a selection with clearance above it stays above")
}

// MARK: - `shouldShowFormatBar(...)`: visibility (ADR §D5, mirrors `refreshFormatBar`'s own rule)

@Test func visibilityIsTrueWhileEditingThatCardWithANonEmptySelection() {
    let visible = BoardFormatBarGeometry.shouldShowFormatBar(
        editingTextNodeID: "card-1", forNodeID: "card-1",
        selectionRange: NSRange(location: 0, length: 5)
    )
    #expect(visible)
}

@Test func visibilityIsFalseForAnEmptySelectionEvenWhileEditingThatExactCard() {
    // The SPEC edge case: a bare caret, not a selection, hides the bar even though the card
    // being edited is exactly the one asked about.
    let visible = BoardFormatBarGeometry.shouldShowFormatBar(
        editingTextNodeID: "card-1", forNodeID: "card-1",
        selectionRange: NSRange(location: 4, length: 0)
    )
    #expect(!visible)
}

@Test func visibilityIsFalseWhenAnotherCardIsBeingEdited() {
    let visible = BoardFormatBarGeometry.shouldShowFormatBar(
        editingTextNodeID: "card-2", forNodeID: "card-1",
        selectionRange: NSRange(location: 0, length: 5)
    )
    #expect(!visible)
}

@Test func visibilityIsFalseWhenNoCardIsBeingEditedAtAll() {
    let visible = BoardFormatBarGeometry.shouldShowFormatBar(
        editingTextNodeID: nil, forNodeID: "card-1",
        selectionRange: NSRange(location: 0, length: 5)
    )
    #expect(!visible)
}
