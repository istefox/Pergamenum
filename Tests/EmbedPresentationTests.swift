import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0087 §D10, plan docs/plans/note-workflow-n5.md, Task 3 (R-40).
//
// An embed reserves its written or default size before its thumbnail loads, and an inline or
// non-renderable embed reads as a chip. Pure: sizes and the three presentations.

@Suite struct EmbedPlaceholderSize {
    private static let column: CGFloat = 600

    private static var ratio: CGFloat { EmbedPlaceholder.defaultSize.height / EmbedPlaceholder.defaultSize.width }

    /// PG-420: the default is the width an unsized embed is rendered at, at 16:9, read from the one
    /// constant rather than written twice.
    @Test func theDefaultSizeIsTheRenderWidthAtSixteenByNine() { // R-40
        #expect(EmbedPlaceholder.defaultSize.width == EmbedTable.renderWidth)
        #expect(abs(EmbedPlaceholder.defaultSize.height - EmbedTable.renderWidth * 9 / 16) < 0.001)
    }

    @Test func theDefaultSizeIsARealSize() { // R-40
        #expect(EmbedPlaceholder.defaultSize.width > 0)
        #expect(EmbedPlaceholder.defaultSize.height > 0)
    }

    @Test func noWrittenSizeReservesTheDefaultClampedToTheColumn() { // R-40
        let size = EmbedPlaceholder.defaultSize
        #expect(size.width > 0, "il default non può essere zero")
        let wide = EmbedPlaceholder.size(written: nil, column: 600)
        let expectedWidth = min(size.width, 600)
        #expect(abs(wide.width - expectedWidth) < 0.5)
        #expect(abs(wide.height - expectedWidth * Self.ratio) < 0.5)

        let narrow = EmbedPlaceholder.size(written: nil, column: 100)
        #expect(abs(narrow.width - min(size.width, 100)) < 0.5)
        #expect(abs(narrow.height - min(size.width, 100) * Self.ratio) < 0.5)
    }

    @Test func aWrittenWidthKeepsThatWidthAtTheDefaultRatio() { // R-40
        let size = EmbedPlaceholder.size(written: .width(300), column: Self.column)
        #expect(size.width == 300)
        #expect(abs(size.height - 300 * Self.ratio) < 0.5)
    }

    @Test func aWrittenWidthAndHeightGiveExactlyThatSize() { // R-40
        #expect(EmbedPlaceholder.size(written: .both(300, 200), column: Self.column) == CGSize(width: 300, height: 200))
    }

    @Test func aWrittenWidthOverTheColumnClampsToItKeepingTheRatio() { // R-40
        let size = EmbedPlaceholder.size(written: .width(900), column: Self.column)
        #expect(size.width == Self.column)
        #expect(abs(size.height - Self.column * Self.ratio) < 0.5)

        let both = EmbedPlaceholder.size(written: .both(900, 300), column: Self.column)
        #expect(both.width == Self.column)
        // The width clamps to the column and the written height stays as written: `EmbedResize.resolved`'s
        // `.both` arm leaves the height free of the column and the ratio (ADR-0019 §D3), and the picture
        // is drawn through it, so a ratio-preserving placeholder (200 high) made the line jump when the
        // thumbnail landed. Expected 200 before this correction.
        #expect(abs(both.height - 300) < 0.5, "900x300 clamps its width only, so it stays 300 high: \(both)")
    }
}

@Suite struct EmbedPresentationRule {
    @Test func aWholeLinePictureOrPdfIsDrawn() { // R-40
        #expect(EmbedPresentation.of(target: "foto.png", isWholeLine: true) == .drawn)
        #expect(EmbedPresentation.of(target: "a.pdf", isWholeLine: true) == .drawn)
    }

    @Test func anInlineEmbedIsAChip() { // R-40
        #expect(EmbedPresentation.of(target: "scheda.pdf", isWholeLine: false) == .chip)
        #expect(EmbedPresentation.of(target: "foto.png", isWholeLine: false) == .chip)
    }

    @Test func aNonRenderableFileOnALineOfItsOwnIsAChip() { // R-40
        #expect(EmbedPresentation.of(target: "contratto.docx", isWholeLine: true) == .chip)
    }

    @Test func aTargetThatIsANoteIsATransclusion() { // R-40
        #expect(EmbedPresentation.of(target: "Nota", isWholeLine: true) == .transclusion)
    }

    @Test func pdfImageAndUnknownTypesHaveDistinctSymbols() { // R-40
        let pdf = EmbedPresentation.symbolName(forTarget: "scheda.pdf")
        let image = EmbedPresentation.symbolName(forTarget: "foto.png")
        let unknown = EmbedPresentation.symbolName(forTarget: "contratto.docx")
        #expect(!pdf.isEmpty && !image.isEmpty && !unknown.isEmpty)
        #expect(Set([pdf, image, unknown]).count == 3, "\(pdf), \(image), \(unknown)")
    }
}
