import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0082 §D8, plan docs/plans/pg-385-n2-page.md, Task 2 (PG-385, R-19).
//
// A `pergamenum-view` fence renders in the Oggi and Diario panes: the source `EditorColumnView`
// builds moves into one factory, `ViewQuerySource.live(for:)`, and the three hosts pass it. Red
// until Task 4: the stub answers a source with no rows, no `move`, no `undo` and generation 0, and
// neither `TodayView` nor `DiaryView` passes `queries`.

private let note = "---\ndate: 2026-10-06\ntags:\n  - type-note\n---\n\nCorpo della nota.\n"
private let fenced = "prima\n```pergamenum-view\nrender: list\n```\ndopo\n"

@MainActor
@Suite(.serialized) struct DailySurfaceQueries {
    private func opened(_ vault: borrowing TemporaryVault) async throws -> VaultController {
        try vault.write(note, to: "Note/N.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        return controller
    }

    // (n2-page R-19) The factory's generation is the editor's own, and follows the index.
    @Test func theLiveSourceCarriesTheEditorsGeneration() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        defer { controller.close() }

        let before = ViewQuerySource.live(for: controller).generation
        #expect(before == EditorColumnView.viewQueryGeneration(for: controller))

        try vault.write(note + "\nAltro.\n", to: "Note/N.md")
        await controller.reconcile(["Note/N.md"])
        let after = ViewQuerySource.live(for: controller).generation

        #expect(after == EditorColumnView.viewQueryGeneration(for: controller))
        #expect(after != before, "the generation did not move with the index")
    }

    // (n2-page R-19) `render: list` returns the note's row, and the two writes are wired.
    @Test func theLiveSourceEvaluatesAListAndOffersMoveAndUndo() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        defer { controller.close() }

        let source = ViewQuerySource.live(for: controller)
        let block = try ViewBlock.parse("render: list")
        let paths = source.evaluate(block).groups.flatMap(\.rows).map(\.record.relativePath)

        #expect(paths.contains("Note/N.md"), "the list returned \(paths)")
        #expect(source.move != nil, "no `move`: a board in Oggi or Diario could not write")
        #expect(source.undo != nil, "no `undo`")
    }

    // (n2-page R-19) A hosted editor given the source forms a host that has one.
    @Test func aHostedEditorGivenTheLiveSourceFormsAHostWithAQuerySource() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        defer { controller.close() }
        let source = ViewQuerySource.live(for: controller)

        let fixture = ScrolledEditorFixture(text: fenced, queries: source)
        defer { fixture.window.orderOut(nil) }

        #expect(fixture.coordinator.parent.vault.queries != nil, "the editor's inputs carry no query source")
        #expect(fixture.coordinator.viewBlocks.drawn[6]?.source == "render: list", "the fence is not drawn")
        _ = fixture.coordinator.viewBlocks.hosts.host(for: 0, in: fixture.textView)
        // The stub's source has no `move`: the source the host forms around must be the live one.
        #expect(fixture.coordinator.parent.vault.queries?.move != nil, "the source handed to the host is not the live one")
    }

    // (n2-page R-19) Source guards: Oggi and Diario pass the live source, and neither offers
    // "Modifica query" (ADR-0082 §D8: the control is not drawn there).
    @Test(arguments: ["Sources/Features/Today/TodayView.swift", "Sources/Features/Diary/DiaryView.swift"])
    func theDailyPanesPassTheLiveSourceAndNoEditQuery(_ relativePath: String) throws {
        let root = try resolvedRepoRoot()
        let source = try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)

        #expect(source.contains("queries: .live(for: vault)"), "\(relativePath) does not pass `queries: .live(for: vault)`")
        #expect(!source.contains("onEditQuery"), "\(relativePath) mentions `onEditQuery`")
    }
}
