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
        #expect(MockupGalleryView.Screen.linkPreview.milestone == "N3, approvato")
        #expect(MockupGalleryView.Screen.inspectorLinks.title == "Ispettore: link")
        #expect(MockupGalleryView.Screen.inspectorLinks.milestone == "N3, approvato")
    }

    // (note-workflow-n3-mockup Task 3) The «Menzioni» page gained its N3 half and its label says so.
    @Test func theMentionsPageCarriesTheN3Milestone() {
        #expect(MockupGalleryView.Screen.mentions.milestone == "M10, N3 approvato")
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

    // (pg-387-n4 Task 1) The «Nascita di una nota» page is reachable from the picker, with the
    // milestone Task 5 gives it once the code adopts its variants.
    @Test func theNoteBirthPageIsListedWithItsMilestone() {
        #expect(MockupGalleryView.Screen.allCases.contains(.noteBirth))
        #expect(MockupGalleryView.Screen.noteBirth.title == "Nascita di una nota")
        #expect(MockupGalleryView.Screen.noteBirth.milestone == "N4, approvato")
    }

    // (pg-387-n4 Task 1) Two sidebars side by side, the pane, the sheets and the two toasts all fit
    // the row: a scene wider than `rowWidth` is clipped at both edges.
    @Test func theNoteBirthScenesFitInTheRow() {
        #expect(2 * NoteBirthMockup.sidebarWidth + rowSpacing <= MockupGalleryView.rowWidth)
        #expect(NoteBirthMockup.paneWidth <= MockupGalleryView.rowWidth)
        #expect(NoteBirthMockup.sheetWidth > 0)
        #expect(NoteBirthMockup.sheetWidth <= MockupGalleryView.rowWidth)
        #expect(NoteBirthMockup.toastHeight > 0)
    }

    // (note-workflow-n3-mockup Task 2) The mirror scene sets two `MockupCell`s side by side at
    // `mirrorCellWidth`, and each cell pads after its frame: a width taken as `pairWidth` itself
    // would come to 704 and be clipped at both edges.
    @Test func theMirrorCellsFitInTheRow() {
        let row = 2 * (InspectorLinksMockup.mirrorCellWidth + cellPadding) + rowSpacing
        #expect(row <= MockupGalleryView.rowWidth)
    }

    // (note-workflow-n5-mockup Task 3, R-35) The three N5 pages are reachable from the picker and
    // carry the milestone that marks them proposals, the shape of the N3 test above.
    @Test func theN5PagesAreListedWithTheirTitleAndMilestone() {
        let pages: [(MockupGalleryView.Screen, String)] = [
            (.callouts, "Callout"),
            (.constructs, "Codice, citazioni e chip"),
            (.embedsAndTables, "Embed, transclusioni e tabelle"),
        ]
        for (screen, title) in pages {
            #expect(MockupGalleryView.Screen.allCases.contains(screen))
            #expect(screen.title == title)
            #expect(screen.milestone == "N5, da approvare")
        }
    }

    // (note-workflow-n5-mockup Task 3) The N5 sheets start their text at the gutter (`spacing.gutter`,
    // 48) and pad `spacing.m` on the right, so the placeholder, the three table columns and the
    // column menu must fit what is left of the row, or they are clipped at both edges.
    @Test func theN5EmbedScenesFitTheTextColumn() {
        let sheetTrailingPadding: CGFloat = 16 // `spacing.m`
        let textColumn = MockupGalleryView.rowWidth - 48 - sheetTrailingPadding
        #expect(PageEmbedsMockup.placeholderWidth > 0)
        #expect(PageEmbedsMockup.placeholderWidth <= textColumn)
        #expect(3 * PageEmbedsMockup.columnWidth <= textColumn)
        #expect(PageEmbedsMockup.menuWidth <= 3 * PageEmbedsMockup.columnWidth)
    }
}
