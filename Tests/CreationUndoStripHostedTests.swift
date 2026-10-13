import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D9, plan docs/plans/pg-387-n4-birth-of-note.md, Task 6 -
// R-16: «Nota creata · Annulla» keeps one height whatever it says. A refusal replaces the line
// inside the same height, so the strip never pushes the editor (ADR-0075's rule against a layout
// row above the split view). Hosted, never shown.

@MainActor
private func height(of strip: CreationUndoStrip) async -> (CGFloat, Bool, [String]) {
    let host = HostedView(
        strip.environment(\.theme, .emergency),
        size: CGSize(width: 480, height: 80)
    )
    defer { host.tearDown() }
    await host.settle()
    return (host.hosting.fittingSize.height, host.neverShown, host.refusals)
}

@MainActor
@Test func theStripHasItsOneHeightWithoutARefusal() async {
    let (measured, neverShown, refusals) = await height(of: CreationUndoStrip(refusal: nil, onUndo: {}))

    #expect(measured == CreationUndoStrip.height) // R-16
    #expect(neverShown)
    #expect(refusals.isEmpty)
}

@MainActor
@Test func aRefusalSentenceKeepsTheSameHeight() async {
    let long = "La nota ha modifiche non salvate: non eliminata. " + String(repeating: "Ancora testo. ", count: 20)
    let (measured, neverShown, refusals) = await height(of: CreationUndoStrip(refusal: long, onUndo: {}))

    #expect(measured == CreationUndoStrip.height, "the refusal stays on one line in the same height") // R-16
    #expect(neverShown)
    #expect(refusals.isEmpty)
}
