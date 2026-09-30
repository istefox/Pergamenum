import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore), plan docs/plans/contenitore.md, Tasks 6 and 7 - the plan's red-suite
// cases the coder's suites name but do not assert: an old settings file (Task 6 "Settings
// default", R-26), an unreadable drop folder and an iCloud placeholder reaching the controller
// (R-08, R-26), the optional and the refused parts of «Classifica» (R-18), and rename, move and
// trash of a sub-container (R-19).

private func dropFolder(of vault: borrowing TemporaryVault) -> URL {
    vault.stateBase.appending(path: "Pergamenum Drop", directoryHint: .isDirectory)
}

// MARK: - Settings default (R-26)

@MainActor
@Test func aSettingsFileWithNoContenitoreKeyDecodesToTheDefaults() throws {
    let vault = try TemporaryVault()
    try vault.write("{\n  \"pratiche\": { \"rootFolder\": \"02 Clienti\" }\n}\n", to: ".pergamenum/settings.json")

    let settings = VaultSession.readSettings(in: vault.root).settings

    #expect(settings.contenitore == ContenitoreSettings.default)
    #expect(settings.contenitore.dropFolder == "~/Pergamenum Drop")
    #expect(settings.contenitore.root == "Contenitore")
    #expect(settings.pratiche.rootFolder == "02 Clienti", "the rest of the file is still read")
}

@MainActor
@Test func aContenitoreKeyMissingItsRootKeepsTheDropFolderAndDefaultsTheRoot() throws {
    let vault = try TemporaryVault()
    try vault.write(
        "{ \"contenitore\": { \"dropFolder\": \"~/Deposito\" } }\n", to: ".pergamenum/settings.json"
    )

    let settings = VaultSession.readSettings(in: vault.root).settings

    #expect(settings.contenitore.dropFolder == "~/Deposito")
    #expect(settings.contenitore.root == ContenitoreSettings.defaultRoot)
}

// MARK: - Notices through the controller (R-08, R-26)

@MainActor
@Test func anICloudPlaceholderInTheDropFolderIsNotImportedAndRaisesOneNotice() async throws {
    let vault = try TemporaryVault()
    let drop = dropFolder(of: vault)
    try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
    try Data().write(to: drop.appending(path: ".scansione.pdf.icloud"))
    try contenitorePDFBytes.write(to: drop.appending(path: ".nascosto.pdf"))
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let session = try #require(harness.vault.session)

    await harness.contenitore.start()
    defer { harness.contenitore.stop() }
    await harness.contenitore.observe()
    await harness.contenitore.observe()

    #expect(harness.contenitore.notices.filter { $0 == .placeholder(file: "scansione.pdf") }.count == 1)
    #expect(session.index.schede(underRoot: "Contenitore").isEmpty)
}

@MainActor
@Test func anUnreadableDropFolderShowsOneVisibleNoticeOnTheController() async throws {
    let vault = try TemporaryVault()
    let drop = dropFolder(of: vault)
    try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
    let path = drop.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)

    await harness.contenitore.start()
    defer { harness.contenitore.stop() }
    await harness.contenitore.observe()
    await harness.contenitore.observe()

    #expect(harness.contenitore.notices.filter { $0 == .unreadableDropFolder }.count == 1)
    #expect(!harness.contenitore.isDropFolderReadable)
}

// MARK: - «Classifica» (R-18)

private let folder = "Contenitore/2026"
private let stem = "20260929 Scansione"
private let scheda = "\(folder)/\(stem).md"

/// The session comes from a `VaultController`, which loads the vocabulary «Classifica» checks
/// the type against.
@MainActor
private func inspector(_ vault: borrowing TemporaryVault) async throws -> (ContenitoreInspectorModel, VaultSession) {
    try ContenitoreFixture.seed(stem: stem, in: folder, date: "2026-09-29", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let session = try #require(harness.vault.session)
    return (try #require(ContenitoreInspectorModel(session: session, schedaPath: scheda)), session)
}

@MainActor
@Test func theTypeIsOptionalAndClassifyStillLeavesTheInbox() async throws {
    let vault = try TemporaryVault()
    var (model, session) = try await inspector(vault)
    let topic = Tag(namespace: .topic, value: "utenze")

    let outcome = await model.classify(topics: [topic], type: nil)

    #expect(outcome == .saved)
    let text = try ContenitoreFixture.text(scheda, in: vault.root)
    #expect(Set(NoteDocument.parse(text).frontmatter.tags) == [ContenitoreFixture.typeNote, topic])
    #expect(session.violations(path: scheda, title: stem, text: text).isEmpty)
}

@MainActor
@Test func aTypeOutsideTheVocabularyAndATagThatIsNotATopicAreRefusedWithNothingWritten() async throws {
    let vault = try TemporaryVault()
    var (model, _) = try await inspector(vault)
    let before = try ContenitoreFixture.text(scheda, in: vault.root)
    let topic = Tag(namespace: .topic, value: "utenze")
    let unknown = Tag(namespace: .type, value: "zzzzzz")
    let stray = Tag(namespace: .area, value: "casa")

    #expect(await model.classify(topics: [topic], type: unknown) == .invalid(.unknownType(unknown)))
    #expect(await model.classify(topics: [topic, stray], type: nil) == .invalid(.notATopic(stray)))
    #expect(try ContenitoreFixture.text(scheda, in: vault.root) == before)
}

// MARK: - Sub-containers (R-19)

private func exists(_ path: String, in root: URL) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
}

@MainActor
@Test func aSubContainerRenamesCarryingItsDocumentsAndAYearNameIsRefused() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: stem, in: "Contenitore/Fatture/2026", date: "2026-09-29", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)

    #expect(await harness.actions.renameContainer("Contenitore/Fatture", to: "2026")
        == "Un nome di quattro cifre è riservato alle cartelle anno.")
    #expect(exists("Contenitore/Fatture/2026/\(stem).md", in: vault.root))

    #expect(await harness.actions.renameContainer("Contenitore/Fatture", to: "Utenze") == nil)

    #expect(!exists("Contenitore/Fatture", in: vault.root))
    #expect(exists("Contenitore/Utenze/2026/\(stem).md", in: vault.root))
    #expect(exists("Contenitore/Utenze/2026/\(stem).pdf", in: vault.root))
}

@MainActor
@Test func aSubContainerNestsUnderAnotherAtAnyDepthWithItsDocuments() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: stem, in: "Contenitore/Fatture/2026", date: "2026-09-29", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    #expect(await harness.actions.createContainer(named: "Utenze", in: "Contenitore") == nil)
    #expect(await harness.actions.createContainer(named: "Luce", in: "Contenitore/Utenze") == nil)
    #expect(await harness.actions.createContainer(named: "Enel", in: "Contenitore/Utenze/Luce") == nil)

    await harness.actions.moveContainer("Contenitore/Fatture", into: "Contenitore/Utenze/Luce/Enel", undo: nil)
    await harness.vault.rescan()

    #expect(exists("Contenitore/Utenze/Luce/Enel/Fatture/2026/\(stem).md", in: vault.root))
    #expect(!exists("Contenitore/Fatture", in: vault.root))
    let paths = ContenitoreListModel.allPaths(harness.contenitore.containers()).map(\.path)
    #expect(paths.contains("Contenitore/Utenze/Luce/Enel/Fatture"))
    #expect(!paths.contains { $0.hasSuffix("/2026") })
}

@MainActor
@Test func aSubContainerTrashesWithItsDocumentsAndLeavesNoRowBehind() async throws {
    let vault = try TemporaryVault()
    let name = "Prova-\(UUID().uuidString.prefix(8))"
    try ContenitoreFixture.seed(stem: stem, in: "Contenitore/\(name)/2026", date: "2026-09-29", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let session = try #require(harness.vault.session)
    harness.contenitore.scope = .container("Contenitore/\(name)")
    defer { try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash/\(name)")) }

    await harness.actions.trashContainer("Contenitore/\(name)")
    await harness.vault.rescan()

    #expect(!exists("Contenitore/\(name)", in: vault.root))
    #expect(session.index.schede(underRoot: "Contenitore").isEmpty)
    #expect(harness.contenitore.scope == .all, "the scope that pointed inside falls back")
}

// MARK: - A container verb settles the inspector first and the pane follows it (R-19, R-16)

@MainActor
private func openedContainerDocument(
    _ vault: borrowing TemporaryVault, description: String
) async throws -> (ContenitoreHarness, ContenitoreEditor) {
    try ContenitoreFixture.seed(stem: stem, in: "Contenitore/Fatture/2026", date: "2026-09-29", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let old = "Contenitore/Fatture/2026/\(stem).md"
    harness.contenitore.selection = old
    harness.contenitore.scope = .container("Contenitore/Fatture/2026")
    harness.contenitore.openEditor(for: old)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = description
    return (harness, editor)
}

@MainActor
@Test func renamingAContainerKeepsAnUnsavedDescriptionAndFollowsTheSelectionAndANestedScope() async throws {
    let vault = try TemporaryVault()
    let (harness, _) = try await openedContainerDocument(vault, description: "Scritta prima del cambio nome")

    #expect(await harness.actions.renameContainer("Contenitore/Fatture", to: "Utenze") == nil)

    let renamed = "Contenitore/Utenze/2026/\(stem).md"
    #expect(NoteDocument.parse(try ContenitoreFixture.text(renamed, in: vault.root)).body
        == "\nScritta prima del cambio nome\n")
    #expect(harness.contenitore.selection == renamed)
    #expect(harness.contenitore.scope == .container("Contenitore/Utenze/2026"), "a scope on a descendant follows too")
    #expect(!harness.contenitore.hasUnsettledEdits)
}

@MainActor
@Test func movingAContainerKeepsAnUnsavedDescriptionAndFollowsTheSelectionAndANestedScope() async throws {
    let vault = try TemporaryVault()
    let (harness, _) = try await openedContainerDocument(vault, description: "Scritta prima dello spostamento")
    #expect(await harness.actions.createContainer(named: "Utenze", in: "Contenitore") == nil)

    await harness.actions.moveContainer("Contenitore/Fatture", into: "Contenitore/Utenze", undo: nil)

    let moved = "Contenitore/Utenze/Fatture/2026/\(stem).md"
    #expect(NoteDocument.parse(try ContenitoreFixture.text(moved, in: vault.root)).body
        == "\nScritta prima dello spostamento\n")
    #expect(harness.contenitore.selection == moved)
    #expect(harness.contenitore.scope == .container("Contenitore/Utenze/Fatture/2026"))
    #expect(!harness.contenitore.hasUnsettledEdits)
}

@MainActor
@Test func trashingAContainerLeavesNoEditToSaveOnADeadPathAndClearsTheSelection() async throws {
    let vault = try TemporaryVault()
    let name = "Prova-\(UUID().uuidString.prefix(8))"
    try ContenitoreFixture.seed(stem: stem, in: "Contenitore/\(name)/2026", date: "2026-09-29", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let path = "Contenitore/\(name)/2026/\(stem).md"
    harness.contenitore.selection = path
    harness.contenitore.openEditor(for: path)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Destinata al Cestino"
    defer { try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash/\(name)")) }

    await harness.actions.trashContainer("Contenitore/\(name)")

    #expect(!exists("Contenitore/\(name)", in: vault.root))
    #expect(harness.contenitore.selection == nil)
    #expect(!harness.contenitore.hasUnsettledEdits, "the edit was written before the folder went, not left on a dead path")
}

@MainActor
@Test func aPathIsRemappedOnlyInsideTheContainerThatMoved() {
    #expect(ContenitoreCommandActions.remapped("A/B", from: "A/B", to: "C/B") == "C/B")
    #expect(ContenitoreCommandActions.remapped("A/B/2026", from: "A/B", to: "C/B") == "C/B/2026")
    #expect(ContenitoreCommandActions.remapped("A/Bar", from: "A/B", to: "C/B") == nil, "a sibling sharing a prefix is not inside")
    #expect(ContenitoreCommandActions.remapped("A", from: "A/B", to: "C/B") == nil)
}
