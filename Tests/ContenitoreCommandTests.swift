import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D7, §D11 and §D12, plan docs/plans/contenitore.md, Task 7 - R-18, R-19,
// R-22, R-27. Every action on a document is named once in `ContenitoreCommand` and read by the
// inspector, the row menu and the menu bar (ADR-0023 §D1); while the pane is on screen, File's
// «Copia link Pergamenum» and «Mostra nel Finder» act on its selection.

private let folder = "Contenitore/2026"
private let stem = "20260929 Scansione"
private var scheda: String { "\(folder)/\(stem).md" }
private var pdf: String { "\(folder)/\(stem).pdf" }

// MARK: - «Classifica» (R-18)

@MainActor
@Test func classifyWithNoTopicIsRefusedAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: stem, in: folder, date: "2026-09-29", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let session = try #require(harness.vault.session)
    let before = try ContenitoreFixture.text(scheda, in: vault.root)
    var model = try #require(ContenitoreInspectorModel(session: session, schedaPath: scheda))

    let outcome = await model.classify(topics: [], type: Tag(namespace: .type, value: "invoice"))

    #expect(outcome == .invalid(.noTopic))
    #expect(try ContenitoreFixture.text(scheda, in: vault.root) == before)
}

@MainActor
@Test func classifyWithATopicAndATypeLeavesTheInboxAndLintsClean() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: stem, in: folder, date: "2026-09-29", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let session = try #require(harness.vault.session)
    var model = try #require(ContenitoreInspectorModel(session: session, schedaPath: scheda))
    let topic = Tag(namespace: .topic, value: "utenze")
    let type = Tag(namespace: .type, value: "invoice")
    #expect(ContenitoreListModel.inboxCount(index: session.index, root: "Contenitore") == 1)

    let outcome = await model.classify(topics: [topic], type: type)

    #expect(outcome == .saved)
    let text = try ContenitoreFixture.text(scheda, in: vault.root)
    let tags = NoteDocument.parse(text).frontmatter.tags
    #expect(!tags.contains(ContenitoreFixture.inbox))
    #expect(Set(tags) == [ContenitoreFixture.typeNote, topic, type])
    #expect(session.violations(path: scheda, title: stem, text: text).isEmpty)
    #expect(ContenitoreListModel.inboxCount(index: session.index, root: "Contenitore") == 0)
}

// MARK: - «Sposta nel Cestino» (R-22)

@MainActor
@Test func trashSendsTheSchedaAndItsFileToTheTrashTogether() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: stem, in: folder, date: "2026-09-29", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let session = try #require(harness.vault.session)
    harness.contenitore.selection = scheda

    let trashed = try #require(await harness.actions.trash(scheda))
    defer { ContenitoreFixture.removeFromTrash(trashed) }

    #expect(trashed.count == 2)
    #expect(!session.exists(scheda))
    #expect(!session.exists(pdf))
    #expect(session.index.schede(underRoot: "Contenitore").isEmpty)
    #expect(harness.contenitore.selection == nil)
}

// MARK: - Containers (R-19)

@MainActor
@Test func aContainerWithAFourDigitNameIsRefusedAndAnOrdinaryOneIsCreated() async throws {
    let vault = try TemporaryVault()
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let root = vault.root.appending(path: "Contenitore", directoryHint: .isDirectory)

    let refusal = await harness.actions.createContainer(named: "2026", in: "Contenitore")

    #expect(refusal == "Un nome di quattro cifre è riservato alle cartelle anno.")
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "2026").path(percentEncoded: false)))

    #expect(await harness.actions.createContainer(named: "Utenze", in: "Contenitore") == nil)
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(
        atPath: root.appending(path: "Utenze").path(percentEncoded: false), isDirectory: &isDirectory
    ))
    #expect(isDirectory.boolValue)
    #expect(ContenitoreListModel.allPaths(harness.contenitore.containers()).map(\.path) == ["Contenitore/Utenze"])
}

// MARK: - One catalogue, three surfaces (R-27)

@Test func everyCommandIsOnTheInspectorTheRowMenuAndTheMenuBar() {
    let all = Set(ContenitoreCommand.allCases)
    let menuBar = [ContenitoreCommand.MenuBarMenu.documento, .file, .modifica].flatMap(ContenitoreCommand.menuBar)

    #expect(Set(ContenitoreCommand.inspectorActions(isInbox: true)) == all)
    #expect(Set(ContenitoreCommand.inspectorActions(isInbox: false)) == all)
    #expect(ContenitoreCommand.inspectorActions(isInbox: true).first == .classify)
    #expect(ContenitoreCommand.rowMenu == ContenitoreCommand.allCases)
    #expect(Set(menuBar) == all)
    #expect(menuBar.count == all.count, "each command sits in exactly one menu-bar menu")
    #expect(Set(ContenitoreCommand.allCases.map(\.identifier)).count == all.count)
    #expect(ContenitoreCommand.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
    #expect(ContenitoreCommand.menuBar(.file) == [.revealInFinder, .copyLink])
    #expect(ContenitoreCommand.menuBar(.modifica) == [.trash])
}

// MARK: - File's commands follow the pane (R-23, R-27)

@MainActor
@Test func copyLinkAndRevealInFinderActOnTheSelectedDocumentWhileThePaneIsShown() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: stem, in: folder, date: "2026-09-29", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let session = try #require(harness.vault.session)
    let commands = harness.commandActions()
    harness.navigation.pane = .contenitore

    #expect(!commands.canRun(.copyLink), "nothing selected, nothing to link")
    harness.contenitore.selection = scheda
    #expect(commands.canRun(.copyLink))
    #expect(commands.canRun(.revealInFinder))

    commands.run(.copyLink)
    let id = try #require(session.mintNoteID(for: scheda))
    #expect(harness.contenitore.pasteboard.string(forType: .string) == PergamenumLink.contenitore(id: id)?.absoluteString)

    commands.run(.revealInFinder)
    #expect(harness.recorder.revealed == [[try session.store.url(for: pdf)]])
    #expect(harness.vault.openNote == nil, "the Note pane's behaviour never ran")
}

@MainActor
@Test func awayFromThePaneFileCommandsIgnoreTheContenitoreSelection() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: stem, in: folder, date: "2026-09-29", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let commands = harness.commandActions()
    harness.contenitore.selection = scheda
    harness.navigation.pane = .notes

    #expect(!commands.canRun(.copyLink), "no open note")
    #expect(!commands.canTrashContenitoreSelection)
    // With a note open this would reveal it in the real Finder: never let it get that far.
    try #require(harness.vault.openNote == nil)
    commands.run(.revealInFinder)

    #expect(harness.recorder.revealed.isEmpty)
    #expect(harness.contenitore.pasteboard.string(forType: .string) == nil)
}
