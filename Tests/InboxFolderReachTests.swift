import Foundation
import Testing
@testable import Pergamenum

// PG-384 (N1 seams), ADR-0080 §D5: every place that names the inbox folder reads the
// setting, resolved at the moment it is read, with no relaunch. Four readers: the capture
// default, the task inbox file, the session's own path questions, and file import.
//
// What is deliberately absent: the Settings field and the in-app strings. Those are a
// hand check (plan Task 8); this file pins what a test can reach.

@MainActor
private func openSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(
        root: vault.root,
        stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()
    return session
}

private func read(_ vault: borrowing TemporaryVault, _ path: String) throws -> String {
    try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
}

/// What an inbox note written by the app starts with, so a pre-existing one can be told
/// apart from a freshly created one by its bytes.
private let oldInboxNote = "---\ndate: 2026-08-11\ntags:\n  - type-note\n  - status-inbox\n---\n\n- [ ] Vecchio\n"

// MARK: - The capture default

// (n1-seams R-16, R-17)
@MainActor
@Test func aCaptureWithNoFolderLandsInTheConfiguredInboxFolderWithoutAReopen() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    session.updateSettings { $0.inboxFolder = "Triage" }
    let summary = try await VaultAPI.capture(
        session, to: .newNote(folder: nil), text: "Mescola per il distretto"
    )

    #expect(summary.path == "Triage/Mescola per il distretto.md")
}

// (n1-seams R-16)
@MainActor
@Test func aCaptureThatNamesAFolderStillGoesThere() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)
    session.updateSettings { $0.inboxFolder = "Triage" }

    let summary = try await VaultAPI.capture(
        session, to: .newNote(folder: "01 Progetti"), text: "Mescola per il distretto"
    )

    #expect(summary.path == "01 Progetti/Mescola per il distretto.md")
}

// MARK: - The task inbox file

// (n1-seams R-16, R-17)
@MainActor
@Test func aTaskCapturedIntoTheInboxCreatesTheConfiguredFoldersCaptureNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(oldInboxNote, to: "00 Inbox/Capture.md")
    let session = await openSession(vault)

    session.updateSettings { $0.inboxFolder = "Triage" }
    let result = try #require(await session.captureTask(
        VaultSession.TaskDraft(text: "Richiamare Rossi")
    ))

    #expect(result.path == "Triage/Capture.md")
    #expect(try read(vault, "Triage/Capture.md").contains("- [ ] Richiamare Rossi"))
    // Changing the setting moves nothing (ADR-0080 §D5): the old note is left as it was.
    #expect(try read(vault, "00 Inbox/Capture.md") == oldInboxNote)
}

// (n1-seams R-16)
@MainActor
@Test func theInboxTaskNoteInTheConfiguredFolderIsBornConformant() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    session.updateSettings { $0.inboxFolder = "Triage" }

    let result = try #require(await session.captureTask(VaultSession.TaskDraft(text: "Un task")))

    #expect(result.path == "Triage/Capture.md")
    #expect(result.text.contains("- status-inbox"))
    let violations = try #require(session.violations(forRecordAt: result.path))
    #expect(violations.isEmpty, "\(violations)")
}

// MARK: - The session's own answers

// (n1-seams R-16, R-17)
@MainActor
@Test func theSessionAnswersTheInboxFolderAndItsNotePathFromTheSettingAtEveryRead() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)

    #expect(session.inboxFolder == "00 Inbox")
    #expect(session.inboxNotePath == "00 Inbox/Capture.md")
    #expect(session.inboxNotePath == VaultSession.TaskDestination.inboxPath)

    session.updateSettings { $0.inboxFolder = "Triage" }

    #expect(session.inboxFolder == "Triage")
    #expect(session.inboxNotePath == "Triage/Capture.md")
}

// The Settings field stores what is typed (a setter that trimmed per keystroke made «00 Inbox»
// untypeable: the trailing space vanished before the next letter), so the trim is the read's job.
// (n1-seams R-16, R-17)
@MainActor
@Test(arguments: ["Triage ", " Triage", "00 Inbox "])
func aValueStoredWithStrayWhitespaceIsKeptAsTypedAndReadTrimmed(stored: String) async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)

    session.updateSettings { $0.inboxFolder = stored }

    #expect(session.settings.inboxFolder == stored)
    #expect(session.inboxFolder == stored.trimmingCharacters(in: .whitespaces), "«\(stored)»")
    #expect(session.inboxNotePath == "\(stored.trimmingCharacters(in: .whitespaces))/Capture.md")
}

// (n1-seams R-16, R-17)
@MainActor
@Test func theRelativePathOfADestinationReadsTheSetting() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    #expect(session.relativePath(of: .inbox) == "00 Inbox/Capture.md")

    session.updateSettings { $0.inboxFolder = "Triage" }

    #expect(session.relativePath(of: .inbox) == "Triage/Capture.md")
    // A named note is its own path, whatever the inbox says.
    #expect(session.relativePath(of: .note("01 Progetti/Nota.md")) == "01 Progetti/Nota.md")
}

// MARK: - File import

// (n1-seams R-16, R-17)
@MainActor
@Test func theImportProposalLandsInTheConfiguredInboxFolder() async throws {
    let vault = try TemporaryVault()
    let source = FileManager.default.temporaryDirectory
        .appending(path: "scheda-\(UUID().uuidString).pdf")
    try Data("%PDF-1.4".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }
    let session = try #require(controller.session)

    session.updateSettings { $0.inboxFolder = "Triage" }
    let proposal = try #require(controller.proposeImport([source]).first)
    let path = try #require(controller.commitImport(proposal))

    #expect(path.hasPrefix("Triage/"), "«\(path)» non è nella cartella inbox impostata")
    #expect(FileManager.default.fileExists(atPath: vault.root.appending(path: path).path(percentEncoded: false)))
}

// MARK: - A refused stored value falls back, on all four

// (n1-seams R-16)
@MainActor
@Test(arguments: ["", "/abs", "..", "../x", "a/../b", ".", "./", "/", " . ", "a/ ../b", "//x"])
func aRefusedStoredValueFallsBackToTheDefaultOnEveryReader(stored: String) async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)
    session.updateSettings { $0.inboxFolder = stored }

    // The session's own answers.
    #expect(session.inboxFolder == "00 Inbox", "«\(stored)»")
    #expect(session.inboxNotePath == "00 Inbox/Capture.md", "«\(stored)»")

    // The capture default.
    let note = try await VaultAPI.capture(session, to: .newNote(folder: nil), text: "Appunto uno")
    #expect(note.path == "00 Inbox/Appunto uno.md", "«\(stored)»")

    // The task inbox file.
    let task = try #require(await session.captureTask(VaultSession.TaskDraft(text: "Un task")))
    #expect(task.path == "00 Inbox/Capture.md", "«\(stored)»")
}

// (n1-seams R-16)
@MainActor
@Test func aRefusedStoredValueFallsBackToTheDefaultOnImport() async throws {
    let vault = try TemporaryVault()
    let source = FileManager.default.temporaryDirectory
        .appending(path: "scheda-\(UUID().uuidString).pdf")
    try Data("%PDF-1.4".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }
    let session = try #require(controller.session)

    session.updateSettings { $0.inboxFolder = "../fuori" }
    let proposal = try #require(controller.proposeImport([source]).first)
    let path = try #require(controller.commitImport(proposal))

    #expect(path.hasPrefix("00 Inbox/"), "«\(path)»")
}
