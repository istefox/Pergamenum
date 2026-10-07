import Foundation
import Testing
@testable import Pergamenum

// The gallery's rows of cells used to be sized by hand and overflowed the page: 208 and 230
// against the 672 points a `MockupPage` gives, which a vertical `ScrollView` clips at both edges
// at once. `MockupGalleryView` now derives `pairWidth` and `tripleWidth` from `contentWidth`;
// this file pins that they still fit if someone changes the constants or the padding.
//
// Scope: the arithmetic only, no view is built. What a row looks like is checked by eye in the
// gallery. A theme cannot be resolved from a test target, so the row gap is the literal of
// `spacing.m` in `Resources/Themes/*.json`.
@MainActor
struct MockupGalleryLayoutTests {
    /// `spacing.m`, the gap `HStack(spacing: theme.spacing(.m))` puts between cells in a row.
    private let rowSpacing: CGFloat = 16

    @Test func aRowOfThreeFitsInTheRow() {
        let row = 3 * MockupGalleryView.tripleWidth + 2 * rowSpacing
        #expect(row <= MockupGalleryView.rowWidth)
    }

    @Test func aRowOfTwoFitsInTheRow() {
        let row = 2 * MockupGalleryView.pairWidth + rowSpacing
        #expect(row <= MockupGalleryView.rowWidth)
    }

    @Test func theRowNeverExceedsWhatAPageHolds() {
        #expect(MockupGalleryView.rowWidth <= MockupGalleryView.contentWidth)
    }

    // (n2-page R-13) (n2-page R-14) The gutter page is reachable from the gallery's picker and
    // carries the milestone that marks it a proposal, not a shipped screen. `milestone` reads
    // `Screen.page`, which wraps the page's view value in an `AnyView`; its body is never
    // evaluated, so nothing is laid out or rendered.
    @Test func theGutterPageIsListedWithItsMilestone() {
        #expect(MockupGalleryView.Screen.allCases.contains(.gutter))
        #expect(MockupGalleryView.Screen.gutter.milestone == "N2, da approvare")
    }

    // (n2-page R-13) (n2-page R-14) Both scenes are drawn inside the row: a scene wider than
    // `rowWidth` is clipped at both edges, the defect this file exists to keep out.
    @Test func theGutterScenesFitInTheRow() {
        #expect(GutterRevealMockup.narrowWidth > 0)
        #expect(GutterRevealMockup.readableWidth > 0)
        #expect(GutterRevealMockup.narrowWidth <= MockupGalleryView.rowWidth)
        #expect(GutterRevealMockup.readableWidth <= MockupGalleryView.rowWidth)
    }
}
