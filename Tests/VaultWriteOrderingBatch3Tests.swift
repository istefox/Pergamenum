import Foundation
import Testing
@testable import Pergamenum

// Behavioral source: the supplied ADR-0043 batch brief, Tasks 7-9 only.
// Required production contracts (the coder implements these, never test-side stubs):
// selfWrittenHashes: [String: [(sequence: UInt64, hash: String)]]
// write(_:to:expecting: String? = nil), throwing WriteRefusal.movedOn(path)
// Internal PraticaEntryComposer.handOff(_:notePath:result:), accepting WriteResult.
// Earlier batches supply IndexMutation, apply([mutation]) and async reconcile.

private func batch3Text(_ body: String) -> String {
    "---\ndate: 2026-09-13\ntags: [type-note]\n---\n\n\(body)\n"
}

private func batch3Hash(_ text: String) -> String {
    NoteStore.hash(Data(text.utf8))
}

@MainActor
private func batch3Session(_ vault: borrowing TemporaryVault) -> VaultSession {
    // No watcher is started: filesystem changes are reconciled explicitly.
    VaultSession(root: vault.root, stateBase: vault.stateBase)
}

// R-07, R-13: explicit clock values force both continuation orders without scheduling races.
@MainActor
@Test func aReconciliationBetweenTwoWritesAppliesInClockOrderNotCallOrder() throws {
    let vault = try TemporaryVault()
    let store = NoteStore(root: vault.root)
    let path = "N.md"
    let recordA = try store.record(from: Data(batch3Text("A").utf8), attributes: [:], at: path)
    let recordRead = try store.record(from: Data(batch3Text("Read").utf8), attributes: [:], at: path)
    let recordB = try store.record(from: Data(batch3Text("B").utf8), attributes: [:], at: path)
    let writeA = VaultDisk.IndexMutation(path: path, record: recordA, sequence: 1)
    let reconciliation = VaultDisk.IndexMutation(path: path, record: recordRead, sequence: 2)
    let writeB = VaultDisk.IndexMutation(path: path, record: recordB, sequence: 3)

    for order in [[writeA, writeB, reconciliation], [writeA, reconciliation, writeB]] {
        let session = batch3Session(vault)
        for mutation in order { _ = session.apply([mutation]) }
        #expect(session.index.note(at: path) == recordB)
    }
}

// R-07, R-13: exact prefix pruning, including first and last sequence boundaries.
@MainActor
@Test(arguments: [UInt64(1), 2, 3])
func matchedReconciliationPrunesOnlyHashesAtOrBelowItsSequence(matched: UInt64) async throws {
    let vault = try TemporaryVault()
    let session = batch3Session(vault)
    let texts = [batch3Text("A"), batch3Text("B"), batch3Text("C")]
    let entries: [(sequence: UInt64, hash: String)] = texts.enumerated().map {
        (UInt64($0.offset + 1), batch3Hash($0.element))
    }
    session.selfWrittenHashes["N.md"] = entries
    session.selfWrittenHashes["Other.md"] = [(1, entries[0].hash)]
    try vault.write(texts[Int(matched - 1)], to: "N.md")

    let changes = await session.reconcile(["N.md"])

    let remaining = session.selfWrittenHashes["N.md"] ?? []
    #expect(changes.isEmpty)
    #expect(remaining.map(\.sequence) == entries.filter { $0.sequence > matched }.map(\.sequence))
    #expect(remaining.map(\.hash) == entries.filter { $0.sequence > matched }.map(\.hash))
    #expect(session.selfWrittenHashes["Other.md"]?.map(\.sequence) == [1])
    #expect(session.selfWrittenHashes["Other.md"]?.map(\.hash) == [entries[0].hash])
}

// R-07, R-13: an unmatched external edit is not evidence that any queued hash was seen.
@MainActor
@Test func unmatchedReconciliationReportsExternalTextWithoutPruningOwnHashes() async throws {
    let vault = try TemporaryVault()
    let session = batch3Session(vault)
    let ownHash = batch3Hash(batch3Text("Own write"))
    session.selfWrittenHashes["N.md"] = [(1, ownHash)]
    let external = batch3Text("External edit")
    try vault.write(external, to: "N.md")

    let changes = await session.reconcile(["N.md"])

    #expect(changes.map(\.path) == ["N.md"])
    #expect(changes.first?.text == external)
    #expect(session.selfWrittenHashes["N.md"]?.map(\.sequence) == [1])
    #expect(session.selfWrittenHashes["N.md"]?.map(\.hash) == [ownHash])
}

// R-07: sequential writes append; reconciling the newest prunes coalesced predecessors.
@MainActor
@Test func writesAppendSequenceTaggedHashesUntilTheMatchingReconciliation() async throws {
    let vault = try TemporaryVault()
    let session = batch3Session(vault)
    let first = batch3Text("First")
    let second = batch3Text("Second")
    try await session.write(first, to: "N.md")
    try await session.write(second, to: "N.md")
    let entries = try #require(session.selfWrittenHashes["N.md"])
    #expect(entries.map(\.hash) == [batch3Hash(first), batch3Hash(second)])
    try #require(entries.count == 2)
    #expect(entries[0].sequence > 0)
    #expect(entries[1].sequence > entries[0].sequence)

    let changes = await session.reconcile(["N.md"])
    #expect(changes.isEmpty)
    #expect((session.selfWrittenHashes["N.md"] ?? []).isEmpty)
}

@MainActor
private func batch3Controller(_ vault: borrowing TemporaryVault) async -> VaultController {
    let controller = VaultController(recents: .volatile(), openTabs: .volatile(), pinnedTags: .volatile())
    await controller.open(vault.root)
    controller.openNote(at: "N.md")
    return controller
}

// R-08, R-09, R-14: no suspension between dirtying the buffer and handing off the result.
@MainActor
@Test func dirtyingTheBufferBetweenAWriteAndItsHandOffRaisesTheConflictPrompt() async throws {
    let vault = try TemporaryVault()
    let original = batch3Text("Saved")
    try vault.write(original, to: "N.md")
    let controller = await batch3Controller(vault)
    defer { controller.close() }
    let buffer = batch3Text("User's unsaved edits")
    controller.updateOpenNoteText(buffer)
    try #require(controller.openNote?.hasUnsavedChanges == true)
    let result = VaultSession.WriteResult(path: "N.md", text: batch3Text("Incoming write"))

    controller.syncOpenNote(with: result)

    #expect(controller.openNote?.externalChangePending == result.text)
    #expect(controller.openNote?.text == buffer)
    #expect(controller.openNote?.savedText == original)
}

// R-08, R-09, R-14: the common clean-buffer path still accepts the returned text.
@MainActor
@Test func aCleanBufferAcceptsTheReturnedWriteText() async throws {
    let vault = try TemporaryVault()
    try vault.write(batch3Text("Saved"), to: "N.md")
    let controller = await batch3Controller(vault)
    defer { controller.close() }
    try #require(controller.openNote?.hasUnsavedChanges == false)
    let result = VaultSession.WriteResult(path: "N.md", text: batch3Text("Written"))

    controller.syncOpenNote(with: result)

    #expect(controller.openNote?.text == result.text)
    #expect(controller.openNote?.savedText == result.text)
    #expect(controller.openNote?.externalChangePending == nil)
}

// R-08, R-09, R-14: recreate insert's write/handOff boundary with the actual write result.
// Calling handOff directly is the forcing mechanism requested by Task 8, not a sleep.
@MainActor
@Test func composerHandOffPreservesEditsMadeAfterTheWriteReturned() async throws {
    let vault = try TemporaryVault()
    let original = batch3Text("Saved")
    try vault.write(original, to: "N.md")
    let controller = await batch3Controller(vault)
    defer { controller.close() }
    let session = try #require(controller.session)
    let insertion = PraticaEntry.insert(
        kind: .note, at: Date(timeIntervalSince1970: 1_784_000_000), counterpart: "Test", in: original
    )
    let result = try await session.write(insertion.text, to: "N.md")
    let composer = PraticaEntryComposer(
        pratiche: PraticheController(probe: { .granted }, performSync: { _, _ in }),
        vault: controller, navigation: Navigation()
    )
    let buffer = batch3Text("Unsaved while insert awaited")
    controller.updateOpenNoteText(buffer)
    try #require(controller.openNote?.hasUnsavedChanges == true)

    composer.handOff(insertion, notePath: "N.md", result: result)

    #expect(controller.openNote?.externalChangePending == result.text)
    #expect(controller.openNote?.text == buffer)
}

// R-08, R-14: disk advancing again cannot replace the result being handed off.
@MainActor
@Test func composerHandOffUsesItsWriteResultInsteadOfRereadingDisk() async throws {
    let vault = try TemporaryVault()
    let original = batch3Text("Saved")
    try vault.write(original, to: "N.md")
    let controller = await batch3Controller(vault)
    defer { controller.close() }
    let insertion = PraticaEntry.insert(
        kind: .note, at: Date(timeIntervalSince1970: 1_784_000_000), counterpart: "Test", in: original
    )
    let session = try #require(controller.session)
    let result = try await session.write(insertion.text, to: "N.md")
    let composer = PraticaEntryComposer(
        pratiche: PraticheController(probe: { .granted }, performSync: { _, _ in }),
        vault: controller, navigation: Navigation()
    )
    // No await follows this external write, so the watcher cannot race the assertion.
    try vault.write(batch3Text("Later writer"), to: "N.md")
    composer.handOff(insertion, notePath: "N.md", result: result)

    #expect(controller.openNote?.text == result.text)
}

// R-10, R-15: refusal is explicit and has no disk, index, history, journal or hash side effects.
@MainActor
@Test func aWriteWithAStaleExpectedHashIsRefusedAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    let session = batch3Session(vault)
    session.journal = session.journalOnDisk
    let path = "Notes/Nota è.md"
    let first = batch3Text("First")
    let second = batch3Text("Second")
    try await session.write(first, to: path)
    let staleHash = batch3Hash(first)
    try await session.write(second, to: path)
    let journalBefore = session.journalOnDisk.entries().map(\.id)
    let historyBefore = session.history.snapshots(for: path).map(\.text)
    let hashesBefore = session.selfWrittenHashes[path] ?? []
    let indexedBefore = session.index.note(at: path)

    await #expect(throws: VaultSession.WriteRefusal.movedOn(path)) {
        try await session.write(batch3Text("Stale replacement"), to: path, expecting: staleHash)
    }

    #expect(try Data(contentsOf: vault.root.appending(path: path)) == Data(second.utf8))
    #expect(session.journalOnDisk.entries().map(\.id) == journalBefore)
    #expect(session.history.snapshots(for: path).map(\.text) == historyBefore)
    #expect((session.selfWrittenHashes[path] ?? []).map(\.sequence) == hashesBefore.map(\.sequence))
    #expect((session.selfWrittenHashes[path] ?? []).map(\.hash) == hashesBefore.map(\.hash))
    #expect(session.index.note(at: path) == indexedBefore)
    #expect(VaultSession.WriteRefusal.movedOn(path).description.contains(path))
}

// R-10, R-15: matching precondition follows the normal write pipeline.
@MainActor
@Test func aWriteWithTheCurrentExpectedHashSucceedsNormally() async throws {
    let vault = try TemporaryVault()
    let session = batch3Session(vault)
    session.journal = session.journalOnDisk
    let first = batch3Text("Current")
    let replacement = batch3Text("Replacement")
    try await session.write(first, to: "N.md")
    let journalCount = session.journalOnDisk.entries().count

    let result = try await session.write(replacement, to: "N.md", expecting: batch3Hash(first))

    #expect(result == VaultSession.WriteResult(path: "N.md", text: replacement))
    #expect(try Data(contentsOf: vault.root.appending(path: "N.md")) == Data(replacement.utf8))
    #expect(session.index.note(at: "N.md")?.contentHash == batch3Hash(replacement))
    #expect(session.journalOnDisk.entries().count == journalCount + 1)
    #expect(session.history.snapshots(for: "N.md").contains { $0.text == first })
    #expect(session.selfWrittenHashes["N.md"]?.last?.hash == batch3Hash(replacement))
}

// R-10, R-15: nil permits both creating a note and overwriting text that has moved on.
@MainActor
@Test func omittedAndExplicitNilExpectedHashesAllowUnconditionalWrites() async throws {
    let vault = try TemporaryVault()
    let session = batch3Session(vault)
    let path = "New.md"
    let first = batch3Text("New note")
    let replacement = batch3Text("Unconditional replacement")
    let created = try await session.write(first, to: path)
    #expect(created.text == first)
    #expect(try Data(contentsOf: vault.root.appending(path: path)) == Data(first.utf8))
    try vault.write(batch3Text("Another writer"), to: path)

    let overwritten = try await session.write(replacement, to: path, expecting: nil)
    #expect(overwritten.text == replacement)
    #expect(try Data(contentsOf: vault.root.appending(path: path)) == Data(replacement.utf8))

    try vault.write(batch3Text("Changed again"), to: path)
    let defaultWrite = try await session.write(first, to: path)
    #expect(defaultWrite.text == first)
    #expect(try Data(contentsOf: vault.root.appending(path: path)) == Data(first.utf8))
}

// PG-168 / #313: `requiringExistingFolder` is the container-side sibling of `expecting:`.
// A write that asks for it never brings its parent folder into existence.
@MainActor
@Test func aWriteRequiringAnExistingFolderIsRefusedAndCreatesNothing() async throws {
    let vault = try TemporaryVault()
    let session = batch3Session(vault)
    let path = "Vacated/email/Message.md"

    await #expect(throws: VaultSession.WriteRefusal.folderVanished("Vacated/email")) {
        try await session.write(batch3Text("Late"), to: path, requiringExistingFolder: true)
    }

    #expect(!FileManager.default.fileExists(atPath: vault.root.appending(path: "Vacated").path(percentEncoded: false)))
    #expect(session.index.note(at: path) == nil)
    #expect((session.selfWrittenHashes[path] ?? []).isEmpty, "a refusal leaves no provisional hash behind")
    #expect(VaultSession.WriteRefusal.folderVanished("Vacated/email").description.contains("Vacated/email"))
}

@MainActor
@Test func aWriteRequiringAnExistingFolderSucceedsWhenTheFolderIsThere() async throws {
    let vault = try TemporaryVault()
    let session = batch3Session(vault)
    try FileManager.default.createDirectory(
        at: vault.root.appending(path: "Live", directoryHint: .isDirectory), withIntermediateDirectories: true
    )
    let text = batch3Text("Present")

    let result = try await session.write(text, to: "Live/N.md", requiringExistingFolder: true)

    #expect(result.text == text)
    #expect(session.index.note(at: "Live/N.md")?.contentHash == batch3Hash(text))
}

@MainActor
@Test func theDefaultWriteStillCreatesItsFolder() async throws {
    let vault = try TemporaryVault()
    let session = batch3Session(vault)
    let text = batch3Text("Creates")

    try await session.write(text, to: "Fresh/Deep/N.md")

    #expect(try Data(contentsOf: vault.root.appending(path: "Fresh/Deep/N.md")) == Data(text.utf8))
}

@MainActor
@Test func aLaterLegitimateWriteToARefusedPathStillReconciles() async throws {
    let vault = try TemporaryVault()
    let session = batch3Session(vault)
    let path = "Later/N.md"
    await #expect(throws: VaultSession.WriteRefusal.folderVanished("Later")) {
        try await session.write(batch3Text("Refused"), to: path, requiringExistingFolder: true)
    }

    let text = batch3Text("Accepted")
    try await session.write(text, to: path)

    #expect(session.index.note(at: path)?.contentHash == batch3Hash(text))
    #expect(try Data(contentsOf: vault.root.appending(path: path)) == Data(text.utf8))
}
