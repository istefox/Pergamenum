import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D10, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 6 - R-18.
//
// The snap a drag captures once must answer, for every translation, what `updateDrag` computed
// per tick before it (`WorkspaceController+Gestures.swift`): `BoardGeometry.snapped` of the anchor
// moved by the translation, against the cards not being dragged, with a threshold of six screen
// points in board units, translated back to an offset from the anchor.

struct DragSnapCase: Sendable, CustomStringConvertible {
    let anchor: CGRect
    let grid: Bool
    let zoom: CGFloat
    var description: String { "anchor \(anchor) grid \(grid) zoom \(zoom)" }
}

@Suite struct BoardDragSnapTests {
    private static let others: [CGRect] = [
        CGRect(x: 300, y: 0, width: 200, height: 100),
        CGRect(x: 0, y: 300, width: 100, height: 100),
        CGRect(x: 600, y: 0, width: 400, height: 400),
        CGRect(x: 1200, y: 1200, width: 150, height: 90),
    ]

    private static let anchors: [CGRect] = [
        CGRect(x: 0, y: 0, width: 200, height: 100),
        CGRect(x: 17.5, y: -40, width: 120, height: 60),
    ]

    static let cases: [DragSnapCase] = anchors.flatMap { anchor in
        [false, true].flatMap { grid in
            ([0.5, 1, 2] as [CGFloat]).map { DragSnapCase(anchor: anchor, grid: grid, zoom: $0) }
        }
    }

    private static let translations: [CGSize] = [
        CGSize(width: 3, height: 2),
        CGSize(width: 95, height: -1),
        CGSize(width: 298, height: 4),
        CGSize(width: 301.5, height: 99),
        CGSize(width: -7, height: 305),
        CGSize(width: 0, height: 0),
        CGSize(width: 410, height: 197),
        CGSize(width: 55.25, height: 12.75),
    ]

    /// Today's formula, per tick.
    private static func reference(
        anchor: CGRect, translation: CGSize, zoom: CGFloat, gridStep: CGFloat?
    ) -> (translation: CGSize, guides: [BoardGeometry.Guide]) {
        let (snapped, guides) = BoardGeometry.snapped(
            anchor.offsetBy(dx: translation.width, dy: translation.height), to: others,
            threshold: 6 / max(zoom, 0.01), gridStep: gridStep
        )
        return (CGSize(width: snapped.minX - anchor.minX, height: snapped.minY - anchor.minY), guides)
    }

    @MainActor @Test(arguments: cases)
    func theCapturedSnapAnswersAsTheFormulaPerTick(_ snapCase: DragSnapCase) {
        let snap = BoardDragSnap(anchorID: "aaaa000000000001", anchor: snapCase.anchor, others: Self.others)
        let gridStep = snapCase.grid ? WorkspaceController.gridStep : nil

        for translation in Self.translations {
            let expected = Self.reference(
                anchor: snapCase.anchor, translation: translation, zoom: snapCase.zoom, gridStep: gridStep
            )
            let actual = snap.snapped(translation: translation, zoom: snapCase.zoom, gridStep: gridStep)
            #expect(actual.translation == expected.translation, "\(translation)")
            #expect(actual.guides == expected.guides, "\(translation)")
        }
    }

    @Test func aTranslationNearACardIsPulledOntoIt() {
        let anchor = CGRect(x: 0, y: 0, width: 200, height: 100)
        let snap = BoardDragSnap(anchorID: "aaaa000000000001", anchor: anchor, others: Self.others)

        let actual = snap.snapped(translation: CGSize(width: 97, height: 3), zoom: 1, gridStep: nil)

        #expect(actual.translation == Self.reference(
            anchor: anchor, translation: CGSize(width: 97, height: 3), zoom: 1, gridStep: nil
        ).translation)
        #expect(!actual.guides.isEmpty, "the anchor's right edge lines up with the next card's left edge")
    }
}
