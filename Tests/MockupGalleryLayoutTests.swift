import Foundation
import Testing
@testable import Pergamenum

// #332 / PG-178: the gallery's rows of cells were sized by hand and disagreed, 208 in two
// files, 213 in a third and 230 in a fourth, because `MockupCell` took a content width and
// added its padding on top while `TabBarMockup`'s `Column` took an outer width. A row wider
// than the page is clipped at both edges at once, so it reads as broken formatting.
//
// Scope of this file: the arithmetic only. Nothing here builds a view; what a row looks like is
// checked by eye in the gallery. A theme cannot be resolved from a test target, so the two
// spacings below are the literals of `Resources/Themes/*.json`.
@MainActor
struct MockupGalleryLayoutTests {
    /// `spacing.m`, the gap `HStack(spacing: theme.spacing(.m))` puts between cells in a row.
    private let rowSpacing: CGFloat = 16
    /// `spacing.l`, the padding `MockupPage` puts on each side of its content.
    private let pagePadding: CGFloat = 24

    private var available: CGFloat {
        MockupGalleryView.contentWidth - 2 * pagePadding
    }

    @Test func aRowOfThreeFitsInThePage() {
        let row = 3 * MockupGalleryView.tripleWidth + 2 * rowSpacing
        #expect(row <= available)
    }

    @Test func aRowOfTwoFitsInThePage() {
        let row = 2 * TemplateMockup.doubleWidth + rowSpacing
        #expect(row <= available)
    }
}
