import AppKit
import Testing
@testable import Pergamenum

// PG-263: the table grid's «Riga»/«Colonna» captions used to be built from a hand-named
// `NSFont.systemFont(ofSize: 9, weight: .semibold)`. They now read `font.control.label`
// through `TableGridView.controlLabelFont`, born from `Theme.emergency` and pushed in by
// `update(with:theme:)` on every pass, so a theme that changes the token reaches a grid
// whose shape has not moved. `controlLabelTokenResolvesToTheFaceItReplaces`
// (`DesignSystemTests.swift`) pins the token's value; these pin that the view reads it.
@MainActor
@Suite struct TableGridControlLabelTests {
    /// A theme inheriting everything from `.emergency` except `font.control.label`.
    private static func theme(size: CGFloat, weight: Int) throws -> Theme {
        let json = """
        {
          "font": {
            "control": {
              "label": {
                "$type": "typography",
                "$value": { "fontFamily": "system", "fontSize": \(size), "fontWeight": \(weight), "lineHeight": 1.0 }
              }
            }
          }
        }
        """
        let document = try DesignTokenDocument(data: Data(json.utf8), fallbackName: "control-label-test")
        return Theme(document: document, id: "control-label-test", inheriting: .emergency)
    }

    private static func table() throws -> GFMTable {
        try #require(GFMTable.parse(["| a | b |", "|---|---|", "| 1 | 2 |"][...]))
    }

    /// A grid built and never updated already draws the captions in the token's face, not in a
    /// size of the view's own.
    @Test func aGridNeverUpdatedDrawsItsCaptionsInTheEmergencyTokenFace() {
        let grid = TableGridView()
        let expected = Theme.emergency.nsFont(.controlLabel)
        #expect(grid.controlLabelFont.pointSize == expected.pointSize)
        #expect(grid.controlLabelFont.fontName == expected.fontName)
        for label in grid.controlLabels {
            #expect(label.font?.pointSize == expected.pointSize, "\(label.stringValue)")
            #expect(label.font?.fontName == expected.fontName, "\(label.stringValue)")
        }
    }

    /// Both captions follow the theme on every update, including a second one on a grid whose
    /// shape has not changed (and so is never rebuilt).
    @Test func bothCaptionsFollowTheThemesControlLabelTokenOnEveryUpdate() throws {
        let grid = TableGridView()
        let table = try Self.table()

        let first = try Self.theme(size: 14, weight: 700)
        grid.update(with: table, theme: first)
        let firstFont = first.nsFont(.controlLabel)
        #expect(firstFont.pointSize == 14, "the fixture theme must differ from the 9 pt default")
        for label in grid.controlLabels {
            #expect(label.font?.pointSize == 14, "\(label.stringValue) after the first update")
            #expect(label.font?.fontName == firstFont.fontName, "\(label.stringValue) after the first update")
        }

        let second = try Self.theme(size: 11, weight: 400)
        grid.update(with: table, theme: second)
        for label in grid.controlLabels {
            #expect(label.font?.pointSize == 11, "\(label.stringValue) after a same-shape update")
        }
        #expect(grid.controlLabelFont.pointSize == 11)
    }

    /// The captions stay the two the grid has.
    @Test func theGridHasExactlyTheRowAndColumnCaptions() {
        let grid = TableGridView()
        #expect(grid.controlLabels.map(\.stringValue) == ["Riga", "Colonna"])
    }
}
