import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D4 and §D13, plan docs/plans/contenitore.md, Task 6 - R-04, R-08, R-26.
// The controller drives the ingest engine end to end: it is built un-isolated, with its home
// folder inside the test's own state base, no FSEvents watcher and no follow-up timer, so every
// observation here is one the test drives.

private func dropFolder(of vault: borrowing TemporaryVault) -> URL {
    vault.stateBase.appending(path: "Pergamenum Drop", directoryHint: .isDirectory)
}

private func contents(of folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted()
}

// MARK: - Catch-up import (R-04)

@MainActor
@Test func filesAlreadyInTheDropFolderImportAfterStartAndOneMoreObservation() async throws {
    let vault = try TemporaryVault()
    let drop = dropFolder(of: vault)
    try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
    try contenitorePDFBytes.write(to: drop.appending(path: "a.pdf"))
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let session = try #require(harness.vault.session)

    await harness.contenitore.start()
    defer { harness.contenitore.stop() }
    #expect(session.index.schede(underRoot: "Contenitore").isEmpty, "one observation is not a stable file yet")
    #expect(harness.contenitore.lastImportAt == nil)

    let report = await harness.contenitore.observe()

    #expect(report.imported == ["Contenitore/2026/20260929 a.md"])
    #expect(session.index.schede(underRoot: "Contenitore").map(\.relativePath) == ["Contenitore/2026/20260929 a.md"])
    #expect(session.exists("Contenitore/2026/20260929 a.pdf"))
    #expect(contents(of: drop).isEmpty)
    #expect(harness.contenitore.lastImportAt != nil)
    #expect(harness.contenitore.isDropFolderReadable)
}

@MainActor
@Test func theDropFolderIsCreatedAtTheFirstStart() async throws {
    let vault = try TemporaryVault()
    let drop = dropFolder(of: vault)
    #expect(!FileManager.default.fileExists(atPath: drop.path(percentEncoded: false)))
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)

    await harness.contenitore.start()
    defer { harness.contenitore.stop() }

    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: drop.path(percentEncoded: false), isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
    #expect(harness.contenitore.notices.isEmpty)
    #expect(harness.contenitore.dropFolderRefusal == nil)
}

// MARK: - Notices (R-08)

@MainActor
@Test func theEngineNoticesSurfaceOnTheControllerOnceEach() async throws {
    let vault = try TemporaryVault()
    let drop = dropFolder(of: vault)
    try FileManager.default.createDirectory(
        at: drop.appending(path: "Cartella", directoryHint: .isDirectory), withIntermediateDirectories: true
    )
    try Data("# Nota".utf8).write(to: drop.appending(path: "appunto.md"))
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)

    await harness.contenitore.start()
    defer { harness.contenitore.stop() }
    await harness.contenitore.observe()
    await harness.contenitore.observe()

    let notices = harness.contenitore.notices
    #expect(notices.filter { $0 == .subfolder(name: "Cartella") }.count == 1)
    #expect(notices.filter { $0 == .refusedNote(file: "appunto.md") }.count == 1)

    harness.contenitore.dismiss(.subfolder(name: "Cartella"))
    #expect(!harness.contenitore.notices.contains(.subfolder(name: "Cartella")))
}

// MARK: - Settings › Contenitore (R-26)

@MainActor
@Test func aDropFolderUnderHomeIsStoredWithTildeAndSurvivesAReopen() async throws {
    let vault = try TemporaryVault()
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let chosen = vault.stateBase.appending(path: "Deposito", directoryHint: .isDirectory)

    #expect(harness.contenitore.setDropFolder(chosen) == nil)
    #expect(harness.vault.session?.settings.contenitore.dropFolder == "~/Deposito")
    #expect(harness.contenitore.resolvedDropFolder?.standardizedFileURL == chosen.standardizedFileURL)

    let reopened = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(reopened.settings.contenitore.dropFolder == "~/Deposito")
    #expect(reopened.settings.contenitore.root == ContenitoreSettings.defaultRoot)
}

@MainActor
@Test func aDropFolderInsideTheVaultIsRefusedWithItsSentenceAndNothingIsStored() async throws {
    let vault = try TemporaryVault()
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)

    let refusal = harness.contenitore.setDropFolder(vault.root.appending(path: "Dentro", directoryHint: .isDirectory))

    #expect(refusal == .insideVault)
    #expect(refusal?.sentence == "La cartella di deposito deve stare fuori dalla vault.")
    #expect(harness.vault.session?.settings.contenitore.dropFolder == ContenitoreSettings.defaultDropFolder)
}

@MainActor
@Test func startRefusesAStoredDropFolderThatIsTheVaultAndImportsNothing() async throws {
    let vault = try TemporaryVault()
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    harness.vault.updateSettings { $0.contenitore.dropFolder = vault.root.path(percentEncoded: false) }

    await harness.contenitore.start()
    defer { harness.contenitore.stop() }

    #expect(harness.contenitore.dropFolderRefusal == .vault)
    #expect(!harness.contenitore.isDropFolderReadable)
    #expect(await harness.contenitore.observe() == IngestReport())
}

// MARK: - A restart during an observation

/// Written by a `withObservationTracking` change handler, which is `@Sendable`.
private final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    var isRaised: Bool {
        lock.lock()
        defer { lock.unlock() }
        return raised
    }

    func raise() {
        lock.lock()
        raised = true
        lock.unlock()
    }
}

@MainActor
@Test func aRestartDuringAnObservationWatchesTheNewFolderAndObservesItToo() async throws {
    let vault = try TemporaryVault()
    let newDrop = vault.stateBase.appending(path: "Altro", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: newDrop, withIntermediateDirectories: true)
    try contenitorePDFBytes.write(to: newDrop.appending(path: "b.pdf"))
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let contenitore = harness.contenitore
    let reached = Gate()
    let release = Gate()
    var observations = 0
    contenitore.observationGate = {
        observations += 1
        if observations == 1 {
            reached.open()
            await release.wait()
        }
    }

    // The first start is inside its catch-up observation of the old folder when the settings
    // change and `.task(id:)` starts again.
    let first = Task { await contenitore.start() }
    await reached.wait()
    harness.vault.updateSettings { $0.contenitore.dropFolder = "~/Altro" }
    await contenitore.start()
    release.open()
    await first.value
    defer { contenitore.stop() }

    #expect(contenitore.watchedFolder?.standardizedFileURL == newDrop.standardizedFileURL,
            "the replaced start must not re-arm the old folder over the new one")
    // The new engine's catch-up observation was not lost: `b.pdf` was seen once already, so this
    // second sight of it is the one that finds it stable.
    let report = await contenitore.observe()
    #expect(report.imported == ["Contenitore/2026/20260929 b.md"])
    #expect(!FileManager.default.fileExists(atPath: newDrop.appending(path: "b.pdf").path(percentEncoded: false)))
}

// MARK: - The extraction label follows the queue

@MainActor
@Test func aRecordedExtractionRedrawsTheRowsThatShowItsLabelAndMatchTheSearch() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: "20260314 Fattura", in: "Contenitore/2026", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let contenitore = harness.contenitore
    #expect(ContenitoreDocuments.rows(vault: harness.vault, contenitore: contenitore).first?.extractionLabel
        == "in attesa")

    // What `ContenitoreView.body` does: compute the rows, and so register what they read.
    let redraw = ObservationFlag()
    withObservationTracking {
        _ = ContenitoreDocuments.rows(vault: harness.vault, contenitore: contenitore)
    } onChange: {
        redraw.raise()
    }
    contenitore.recordExtraction(
        ExtractedText(method: .ocr, status: .done, text: "Società Elettrica", pagesDone: 1, pageCount: 1),
        sha256: ContenitoreFixture.hash
    )

    #expect(redraw.isRaised, "computing the rows must register the extraction cache's revision")
    #expect(ContenitoreDocuments.rows(vault: harness.vault, contenitore: contenitore).first?.extractionLabel
        == "testo da OCR")
    contenitore.filter.query = "societa"
    #expect(ContenitoreDocuments.rows(vault: harness.vault, contenitore: contenitore).map(\.name)
        == ["20260314 Fattura"], "the search reads the same cache")
}

/// Listing the archive and restarting the controller read each extraction's status only; the
/// full record, text included, is loaded for a row only when a search query needs its text.
@MainActor
@Test func labelsAndTheStartCatchUpReadTheStatusAndOnlyASearchLoadsTheText() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: "20260314 Fattura", in: "Contenitore/2026", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let contenitore = harness.contenitore
    let session = try #require(harness.vault.session)
    try session.extractedTexts.write(
        ExtractedText(method: .ocr, status: .done, text: "Società Elettrica", pagesDone: 1, pageCount: 1),
        sha256: ContenitoreFixture.hash
    )

    await contenitore.start()
    defer { contenitore.stop() }
    #expect(ContenitoreDocuments.rows(vault: harness.vault, contenitore: contenitore).first?.extractionLabel
        == "testo da OCR")
    #expect(contenitore.caches.extractions.isEmpty, "neither the catch-up nor the label decoded the text")
    #expect(contenitore.caches.summaries[ContenitoreFixture.hash] == .some(ExtractionSummary(method: .ocr, status: .done)))

    contenitore.filter.query = "Fattura"
    #expect(ContenitoreDocuments.rows(vault: harness.vault, contenitore: contenitore).count == 1)
    #expect(contenitore.caches.extractions.isEmpty, "a match by name needs no text")

    contenitore.filter.query = "societa"
    #expect(ContenitoreDocuments.rows(vault: harness.vault, contenitore: contenitore).map(\.name)
        == ["20260314 Fattura"])
    #expect(contenitore.caches.extractions[ContenitoreFixture.hash] != nil, "the text search loads the record")
}

@MainActor
@Test func aFinishedExtractionJobChangesTheRowLabel() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: "20260314 Fattura", in: "Contenitore/2026", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let contenitore = harness.contenitore

    await contenitore.start()
    defer { contenitore.stop() }
    try await waitUntil {
        ContenitoreDocuments.rows(vault: harness.vault, contenitore: contenitore).first?.extractionLabel
            == "nessun testo"
    }
}

// MARK: - What a closed vault leaves behind

@MainActor
@Test func aClosedVaultLeavesNoQueueNoticeSelectionOrCacheBehind() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: "20260314 Fattura", in: "Contenitore/2026", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let contenitore = harness.contenitore
    await contenitore.start()
    defer { contenitore.stop() }
    let old = try #require(contenitore.queue)
    contenitore.selection = "Contenitore/2026/20260314 Fattura.md"
    contenitore.recordExtraction(
        ExtractedText(method: .textLayer, status: .done, text: "x", pagesDone: 1, pageCount: 1),
        sha256: ContenitoreFixture.hash
    )
    old.onFailed?(URL(filePath: "/tmp/Fattura.pdf"))
    #expect(contenitore.notices.contains(.extractionFailed(file: "Fattura.pdf")))

    harness.vault.close()
    await contenitore.start()

    #expect(contenitore.queue == nil)
    #expect(contenitore.notices.isEmpty)
    #expect(contenitore.selection == nil)
    #expect(contenitore.editor == nil)
    #expect(old.onFailed == nil && old.onRecorded == nil, "the old queue can raise nothing into the next vault")
    #expect(contenitore.extraction(sha256: ContenitoreFixture.hash) == nil)
}

@MainActor
@Test func openingAnotherVaultDropsTheOldOnesQueueNoticesAndSelection() async throws {
    let vault = try TemporaryVault()
    let second = try TemporaryVault()
    try ContenitoreFixture.seed(stem: "20260314 Fattura", in: "Contenitore/2026", vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let contenitore = harness.contenitore
    await contenitore.start()
    defer { contenitore.stop() }
    let old = try #require(contenitore.queue)
    contenitore.selection = "Contenitore/2026/20260314 Fattura.md"
    old.onFailed?(URL(filePath: "/tmp/Fattura.pdf"))

    await harness.vault.open(second.root)
    await contenitore.start()

    let fresh = try #require(contenitore.queue)
    #expect(fresh !== old)
    #expect(old.onFailed == nil && old.onRecorded == nil)
    #expect(!contenitore.notices.contains(.extractionFailed(file: "Fattura.pdf")))
    #expect(contenitore.selection == nil)
}

@MainActor
@Test func aRestartOnTheSameVaultKeepsTheQueueAndTheNotices() async throws {
    let vault = try TemporaryVault()
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let contenitore = harness.contenitore
    await contenitore.start()
    defer { contenitore.stop() }
    let queue = try #require(contenitore.queue)
    queue.onFailed?(URL(filePath: "/tmp/Fattura.pdf"))

    await contenitore.start()

    #expect(contenitore.queue === queue, "one queue, so two restarts never run two extractions at once")
    #expect(contenitore.notices.contains(.extractionFailed(file: "Fattura.pdf")))
}
