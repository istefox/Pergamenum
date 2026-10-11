import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0091 §D8 and §D9, plan docs/plans/per-paragraph-restyle.md, Task 3 (R-11).
//
// The kill switch is the host's to set, and the three hosts of `NoteTextView` (the editor column,
// Oggi and Diario) do not: the switch is read from the launch arguments and the defaults, in one
// place, and no surface carries a flag of its own. A surface that draws a `pergamenum-view` fence
// with the live query source takes the incremental path and ends where a full restyle does.
//
// The source guards pin that no surface sets the flag; the hosted tests pin that an editor built as
// Oggi and Diario build it takes the incremental path.

private let fenced = "prima riga di prosa\n\n```pergamenum-view\nrender: list\n```\n\ndopo la vista\n"
private let note = "---\ndate: 2026-10-06\ntags:\n  - type-note\n---\n\nCorpo della nota.\n"

/// What each daily pane hands its `NoteTextView`: Oggi the daily note's whole text, frontmatter
/// included (`vault.openNote?.text`), Diario the day's prose (`controller.prose`).
private enum DailyPane: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case today
    case diary

    var text: String {
        switch self {
        case .today: "---\ndate: 2026-10-11\ntags:\n  - type-note\n---\n\n" + fenced
        case .diary: fenced
        }
    }

    var notePath: String {
        switch self {
        case .today: "Note/2026-10-11.md"
        case .diary: "Diario/2026-10-11.md"
        }
    }

    var testDescription: String { rawValue }
}

@MainActor
@Suite(.serialized) struct IncrementalRestyleSurfaces {
    // (R-11) Oggi and Diario build a `NoteTextView` and set no restyle flag on it.
    @Test(arguments: ["Sources/Features/Today/TodayView.swift", "Sources/Features/Diary/DiaryView.swift"])
    func theDailyPanesBuildAnEditorAndSetNoRestyleFlag(_ relativePath: String) throws {
        let root = try resolvedRepoRoot()
        let source = try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)

        #expect(source.contains("NoteTextView("), "\(relativePath) does not build a NoteTextView")
        #expect(!source.contains("forcesFullRestyle"), "\(relativePath) sets `forcesFullRestyle`")
        #expect(!source.contains("EditorRestyleSwitch"), "\(relativePath) reads the switch itself")
    }

    // (R-11) A fixture with the live query source, as Oggi and Diario give it: a prose keystroke is
    // restyled by the dirty range, the fence stays drawn, and the editor equals its twin.
    @Test func aSurfaceWithTheLiveQuerySourceTakesTheIncrementalPath() async throws {
        let vault = try TemporaryVault()
        try vault.write(note, to: "Note/N.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        defer { controller.close() }
        let source = ViewQuerySource.live(for: controller)

        let incremental = ScrolledEditorFixture(text: fenced, queries: source)
        let full = ScrolledEditorFixture(text: fenced, queries: source, forcesFullRestyle: true)
        let twin = RestyleTwin(incremental: incremental, full: full)
        defer { twin.tearDown() }
        twin.both { $0.runPasses() }
        #expect(!incremental.coordinator.viewBlocks.drawn.isEmpty, "the fence is not drawn")
        #expect(incremental.coordinator.parent.vault.queries?.move != nil, "the source is not the live one")

        let before = incremental.coordinator.restyleLog
        twin.type("x", at: 4)
        twin.type("y", at: 5)

        let log = incremental.coordinator.restyleLog
        #expect(log.incremental >= before.incremental + 2, "a prose keystroke was not restyled by the dirty range: \(before) then \(log)")
        #expect(full.coordinator.restyleLog.incremental == 0)
        #expect(!incremental.coordinator.viewBlocks.drawn.isEmpty, "the fence stopped being drawn")
        #expect(twin.differences().isEmpty, "\(twin.differences())")
        #expect(!incremental.coordinator.derivedStateSnapshot().viewBlocksDrawn.isEmpty)
    }

    // (R-11) The editor built the way Oggi and Diario build it: the vault's root, its thumbnails and
    // the live query source, no transclusion source, and no restyle flag set on the coordinator, which
    // keeps what `EditorRestyleSwitch` read at `init`. One prose keystroke is one incremental restyle,
    // and the editor ends where a full restyle does.
    @Test(arguments: DailyPane.allCases)
    fileprivate func aDailyPaneEditorWithNoFlagSetTakesTheIncrementalPath(_ pane: DailyPane) async throws {
        let vault = try TemporaryVault()
        try vault.write(note, to: "Note/N.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        defer { controller.close() }
        let inputs = NoteTextView.VaultInputs(
            vaultRoot: controller.root, notePath: pane.notePath, thumbnails: controller.thumbnails,
            queries: .live(for: controller), onOpenTag: { _ in }, onOpenDay: { _ in }
        )

        let editor = ScrolledEditorFixture(text: pane.text, vault: inputs, forcesFullRestyle: nil)
        let oracle = ScrolledEditorFixture(text: pane.text, vault: inputs, forcesFullRestyle: true)
        let twin = RestyleTwin(incremental: editor, full: oracle)
        defer { twin.tearDown() }
        // The flag is the one the coordinator read, not one the fixture set, and it is off here.
        let read = EditorRestyleSwitch.forcesFullRestyle(
            arguments: ProcessInfo.processInfo.arguments, defaults: .standard
        )
        #expect(editor.coordinator.forcesFullRestyle == read)
        try #require(!editor.coordinator.forcesFullRestyle, "the kill switch is on in this test process")

        twin.both { $0.runPasses() }
        #expect(!editor.coordinator.viewBlocks.drawn.isEmpty, "the fence is not drawn")
        let before = editor.coordinator.restyleLog
        #expect(before.incremental == 0)

        let prose = (pane.text as NSString).range(of: "prima riga")
        try #require(prose.location != NSNotFound)
        twin.type("x", at: prose.location + 5)

        let after = editor.coordinator.restyleLog
        #expect(after.incremental == 1, "a prose keystroke was not one incremental restyle: \(before) then \(after)")
        #expect(after.full == before.full, "a prose keystroke was restyled in full: \(before) then \(after)")
        #expect(!editor.coordinator.viewBlocks.drawn.isEmpty, "the fence stopped being drawn")
        #expect(twin.differences().isEmpty, "\(twin.differences())")
    }
}
