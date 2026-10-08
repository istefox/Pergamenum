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
    /// `spacing.s` on each side, the padding a `MockupCell` adds around its frame.
    private let cellPadding: CGFloat = 2 * 8

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

    // (note-workflow-n3-mockup Task 1, Task 2) The two N3 pages are reachable from the picker and
    // carry the milestone that marks them proposals. Same shape as the gutter page above: `page`
    // wraps the view value, its body is never evaluated.
    @Test func theN3PagesAreListedWithTheirTitleAndMilestone() {
        let all = MockupGalleryView.Screen.allCases
        #expect(all.contains(.linkPreview))
        #expect(all.contains(.inspectorLinks))
        #expect(MockupGalleryView.Screen.linkPreview.title == "Link")
        #expect(MockupGalleryView.Screen.linkPreview.milestone == "N3, da approvare")
        #expect(MockupGalleryView.Screen.inspectorLinks.title == "Ispettore: link")
        #expect(MockupGalleryView.Screen.inspectorLinks.milestone == "N3, da approvare")
    }

    // (note-workflow-n3-mockup Task 3) The «Menzioni» page gained its N3 half and its label says so.
    @Test func theMentionsPageCarriesTheN3Milestone() {
        #expect(MockupGalleryView.Screen.mentions.milestone == "M10, N3 da approvare")
    }

    // (note-workflow-n3-mockup Task 1) The preview is drawn at the proposed 360 pt (ADR-0083 §D7)
    // and inside the row, never wider than a page holds.
    @Test func theLinkPreviewScenesFitInTheRow() {
        #expect(LinkPreviewMockup.previewWidth > 0)
        #expect(LinkPreviewMockup.previewWidth <= MockupGalleryView.rowWidth)
    }

    // (note-workflow-n3-mockup Task 2, Task 3) The «Ispettore: link» page sets two inspector panels
    // side by side (badge forms, unresolved, «Dove compare»), so two of them plus the row gap must
    // fit the row. Both the structural sheet and the «Menzioni» page's «Collega» sheet are drawn at
    // `InspectorLinksMockup.sheetWidth`, one constant, so pinning it here covers both.
    @Test func theInspectorLinksScenesFitInTheRow() {
        let twoPanels = 2 * UnlinkedMentionsMockup.inspectorWidth + rowSpacing
        #expect(twoPanels <= MockupGalleryView.rowWidth)
        #expect(InspectorLinksMockup.sheetWidth > 0)
        #expect(InspectorLinksMockup.sheetWidth <= MockupGalleryView.rowWidth)
    }

    // (note-workflow-n3-mockup Task 2) The mirror scene sets two `MockupCell`s side by side at
    // `mirrorCellWidth`, and each cell pads after its frame: a width taken as `pairWidth` itself
    // would come to 704 and be clipped at both edges.
    @Test func theMirrorCellsFitInTheRow() {
        let row = 2 * (InspectorLinksMockup.mirrorCellWidth + cellPadding) + rowSpacing
        #expect(row <= MockupGalleryView.rowWidth)
    }
}
