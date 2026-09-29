import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D4/§D5, plan docs/plans/contenitore.md, Task 4 - R-01 to R-08 and the
// engine half of R-26. A temporary drop folder beside a temporary vault; the engine never calls an
// extractor and never sleeps, so every stability rule is driven by calling `observe()` again.

private let pdfBytes = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 0x0A, 0xFF, 0x00, 0xE2])

/// A vault, a drop folder outside it, and an engine on both.
@MainActor
private final class IngestFixture {
    let session: VaultSession
    let drop: URL
    let engine: ContenitoreIngestEngine
    var importedCallbacks: [String] = []

    init(_ vault: borrowing TemporaryVault, createDrop: Bool = true) async throws {
        drop = vault.stateBase.appending(path: "Deposito", directoryHint: .isDirectory)
        if createDrop {
            try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
        }
        session = VaultSession(
            root: vault.root, stateBase: vault.stateBase,
            bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
        )
        await session.rescan()
        let day = try #require(CalendarDate(year: 2026, month: 9, day: 29))
        var sink: ((String) -> Void)?
        engine = ContenitoreIngestEngine(
            session: session,
            settings: ContenitoreSettings(dropFolder: drop.path(percentEncoded: false), root: "Contenitore"),
            home: vault.stateBase,
            today: { day },
            onImported: { sink?($0) }
        )
        sink = { [weak self] in self?.importedCallbacks.append($0) }
    }

    @discardableResult
    func drop(_ name: String, _ data: Data = pdfBytes) throws -> URL {
        let url = drop.appending(path: name, directoryHint: .notDirectory)
        try data.write(to: url)
        return url
    }

    var dropContents: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: drop.path(percentEncoded: false))) ?? []).sorted()
    }

    func text(_ relativePath: String) throws -> String {
        try String(contentsOf: session.root.appending(path: relativePath), encoding: .utf8)
    }
}

// MARK: - Import (R-01, R-02)

@MainActor
@Test func aStableFileImportsAsAPairAndLeavesTheDropFolderEmpty() async throws {
    let vault = try TemporaryVault()
    let fixture = try await IngestFixture(vault)
    try fixture.drop("Preventivo fornitura.pdf")

    _ = await fixture.engine.observe()
    let report = await fixture.engine.observe()

    let scheda = "Contenitore/2026/20260929 Preventivo fornitura.md"
    let file = "Contenitore/2026/20260929 Preventivo fornitura.pdf"
    #expect(report.imported == [scheda])
    #expect(report.notices.isEmpty)
    #expect(fixture.importedCallbacks == [scheda])
    #expect(fixture.session.exists(file))
    #expect(fixture.dropContents.isEmpty)

    let text = try fixture.text(scheda)
    #expect(text.contains("pergamenum-contenitore: 1\n"))
    #expect(text.contains("pergamenum-contenitore-file: \"[[20260929 Preventivo fornitura.pdf]]\""))
    #expect(text.contains("pergamenum-contenitore-original: \"Preventivo fornitura.pdf\""))
    let hash = try await ContenitoreIngestEngine.sha256(
        of: fixture.session.root.appending(path: file)
    )
    #expect(text.contains("pergamenum-contenitore-sha256: \"\(hash)\""))
    #expect(fixture.session.index.note(at: scheda)?.contenitore?.sha256 == hash)

    let violations = fixture.session.violations(path: scheda, title: "20260929 Preventivo fornitura", text: text)
    #expect(violations.isEmpty, "\(violations)")
}

@Test func theStreamedHashIsTheKnownSHA256() async throws {
    let vault = try TemporaryVault()
    let url = vault.stateBase.appending(path: "abc.txt")
    try Data("abc".utf8).write(to: url)

    let hash = try await ContenitoreIngestEngine.sha256(of: url)

    #expect(hash == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

// MARK: - Stability (R-03), catch-up (R-04)

@MainActor
@Test func aFileWaitsUntilTwoObservationsAgreeOnItsSize() async throws {
    let vault = try TemporaryVault()
    let fixture = try await IngestFixture(vault)
    let url = try fixture.drop("scansione.pdf", Data(repeating: 1, count: 10))

    let first = await fixture.engine.observe()
    #expect(first.imported.isEmpty)
    #expect(first.waiting == ["scansione.pdf"])

    try Data(repeating: 1, count: 20).write(to: url)
    let second = await fixture.engine.observe()
    #expect(second.imported.isEmpty)
    #expect(second.waiting == ["scansione.pdf"])

    let third = await fixture.engine.observe()
    #expect(third.imported == ["Contenitore/2026/20260929 scansione.md"])
}

@MainActor
@Test func filesAlreadyInTheDropFolderImportOnTheFirstTwoObservations() async throws {
    let vault = try TemporaryVault()
    let drop = vault.stateBase.appending(path: "Deposito", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
    try pdfBytes.write(to: drop.appending(path: "a.pdf"))
    try Data("b".utf8).write(to: drop.appending(path: "b.txt"))
    let fixture = try await IngestFixture(vault)

    _ = await fixture.engine.observe()
    let report = await fixture.engine.observe()

    #expect(report.imported == ["Contenitore/2026/20260929 a.md", "Contenitore/2026/20260929 b.md"])
    #expect(fixture.dropContents.isEmpty)
}

// MARK: - Duplicate (R-05), collision (R-06)

@MainActor
@Test func aDuplicateStaysInTheDropFolderAndNamesTheExistingDocument() async throws {
    let vault = try TemporaryVault()
    let fixture = try await IngestFixture(vault)
    try fixture.drop("originale.pdf")
    _ = await fixture.engine.observe()
    _ = await fixture.engine.observe()

    try fixture.drop("copia.pdf")
    _ = await fixture.engine.observe()
    let report = await fixture.engine.observe()

    #expect(report.imported.isEmpty)
    #expect(report.notices == [.duplicate(file: "copia.pdf", existing: "Contenitore/2026/20260929 originale.md")])
    #expect(fixture.dropContents == ["copia.pdf"])
}

@MainActor
@Test func aTakenStemGivesBothFilesTheSameSuffix() async throws {
    let vault = try TemporaryVault()
    try vault.write("x", to: "Contenitore/2026/20260929 fattura.pdf")
    let fixture = try await IngestFixture(vault)
    try fixture.drop("fattura.pdf")

    _ = await fixture.engine.observe()
    let report = await fixture.engine.observe()

    #expect(report.imported == ["Contenitore/2026/20260929 fattura-2.md"])
    #expect(fixture.session.exists("Contenitore/2026/20260929 fattura-2.pdf"))
    #expect(try fixture.text("Contenitore/2026/20260929 fattura-2.md").contains("[[20260929 fattura-2.pdf]]"))
}

@MainActor
@Test func aNoteTitleAnywhereInTheVaultTakesTheStem() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ndate: 2026-09-29\ntags:\n  - type-note\n---\n\nx\n", to: "Altrove/20260929 fattura.md")
    let fixture = try await IngestFixture(vault)
    try fixture.drop("fattura.pdf")

    _ = await fixture.engine.observe()
    let report = await fixture.engine.observe()

    #expect(report.imported == ["Contenitore/2026/20260929 fattura-2.md"])
}

// MARK: - Half-way failure (R-07)

@MainActor
@Test func aSchedaWriteRefusedAfterTheMoveReturnsTheFileToTheDropFolder() async throws {
    let vault = try TemporaryVault()
    let fixture = try await IngestFixture(vault)
    try fixture.drop("contratto.pdf")
    let root = vault.root
    // Something lands at the scheda's path between the naming and the write: the write's own
    // `expectingAbsent` refuses, for real.
    fixture.engine.beforeSchedaWrite = { path in
        try Data("intruso".utf8).write(to: root.appending(path: path))
    }

    _ = await fixture.engine.observe()
    let report = await fixture.engine.observe()

    #expect(report.imported.isEmpty)
    #expect(report.notices.count == 1)
    if case .failed(let file, _) = report.notices.first {
        #expect(file == "contratto.pdf")
    } else {
        Issue.record("expected a failed notice, got \(report.notices)")
    }
    #expect(fixture.dropContents == ["contratto.pdf"])
    #expect(!fixture.session.exists("Contenitore/2026/20260929 contratto.pdf"))
    // The intruder is not the pair's and is left alone.
    #expect(try fixture.text("Contenitore/2026/20260929 contratto.md") == "intruso")
}

// MARK: - A file already answered is left alone until it changes

@MainActor
@Test func aRolledBackFileIsNotImportedAgainWhileItsSizeAndDateStand() async throws {
    let vault = try TemporaryVault()
    let fixture = try await IngestFixture(vault)
    try fixture.drop("contratto.pdf")
    let root = vault.root
    var refusals = 0
    fixture.engine.beforeSchedaWrite = { path in
        refusals += 1
        try? FileManager.default.removeItem(at: root.appending(path: path))
        try Data("intruso".utf8).write(to: root.appending(path: path))
    }

    _ = await fixture.engine.observe()
    let first = await fixture.engine.observe()
    let second = await fixture.engine.observe()
    let third = await fixture.engine.observe()

    #expect(refusals == 1, "the file went in and out of the vault again")
    #expect(first.notices.count == 1)
    // The notice is raised once, when the answer is given, and not repeated.
    #expect(second.notices.isEmpty)
    #expect(third.notices.isEmpty)
    #expect(fixture.dropContents == ["contratto.pdf"])
}

@MainActor
@Test func aRolledBackFileIsTriedAgainOnceItChanges() async throws {
    let vault = try TemporaryVault()
    let fixture = try await IngestFixture(vault)
    let url = try fixture.drop("contratto.pdf")
    let root = vault.root
    var failing = true
    fixture.engine.beforeSchedaWrite = { path in
        if failing { try Data("intruso".utf8).write(to: root.appending(path: path)) }
    }
    _ = await fixture.engine.observe()
    _ = await fixture.engine.observe()
    failing = false
    try FileManager.default.removeItem(at: root.appending(path: "Contenitore/2026/20260929 contratto.md"))

    // Unchanged: still declined.
    let unchanged = await fixture.engine.observe()
    #expect(unchanged.imported.isEmpty)

    // Its size changes: it waits, then imports.
    try Data(pdfBytes + Data([0x01])).write(to: url)
    let waiting = await fixture.engine.observe()
    #expect(waiting.waiting == ["contratto.pdf"])
    let report = await fixture.engine.observe()
    #expect(report.imported == ["Contenitore/2026/20260929 contratto.md"])
    #expect(fixture.dropContents.isEmpty)
}

@MainActor
@Test func aDuplicateIsNotHashedOrReportedAgainWhileItStands() async throws {
    let vault = try TemporaryVault()
    let fixture = try await IngestFixture(vault)
    try fixture.drop("originale.pdf")
    _ = await fixture.engine.observe()
    _ = await fixture.engine.observe()
    try fixture.drop("copia.pdf")
    _ = await fixture.engine.observe()

    let first = await fixture.engine.observe()
    let second = await fixture.engine.observe()

    #expect(first.notices == [.duplicate(file: "copia.pdf", existing: "Contenitore/2026/20260929 originale.md")])
    #expect(second.notices.isEmpty)
    #expect(fixture.dropContents == ["copia.pdf"])
}

@MainActor
@Test func aDuplicateTakenAwayAndDroppedAgainIsReportedAgain() async throws {
    let vault = try TemporaryVault()
    let fixture = try await IngestFixture(vault)
    try fixture.drop("originale.pdf")
    _ = await fixture.engine.observe()
    _ = await fixture.engine.observe()
    let url = try fixture.drop("copia.pdf")
    _ = await fixture.engine.observe()
    _ = await fixture.engine.observe()
    try FileManager.default.removeItem(at: url)
    _ = await fixture.engine.observe()

    try fixture.drop("copia.pdf")
    _ = await fixture.engine.observe()
    let report = await fixture.engine.observe()

    #expect(report.notices == [.duplicate(file: "copia.pdf", existing: "Contenitore/2026/20260929 originale.md")])
}

// MARK: - Things never imported (R-08)

@MainActor
@Test func hiddenFilesSubfoldersPlaceholdersAndNotesAreNeverImported() async throws {
    let vault = try TemporaryVault()
    let fixture = try await IngestFixture(vault)
    try fixture.drop(".DS_Store")
    try fixture.drop(".scansione.pdf.icloud")
    try fixture.drop("appunti.md", Data("# x\n".utf8))
    try FileManager.default.createDirectory(
        at: fixture.drop.appending(path: "Sottocartella"), withIntermediateDirectories: true
    )

    let first = await fixture.engine.observe()
    let second = await fixture.engine.observe()
    let third = await fixture.engine.observe()

    for report in [first, second, third] {
        #expect(report.imported.isEmpty)
        #expect(report.notices.contains(.placeholder(file: "scansione.pdf")))
        #expect(report.notices.contains(.refusedNote(file: "appunti.md")))
    }
    let allNotices = first.notices + second.notices + third.notices
    let subfolderNotices = allNotices.filter { $0 == .subfolder(name: "Sottocartella") }
    #expect(subfolderNotices.count == 1)
    #expect(fixture.dropContents.contains("appunti.md"))
    #expect(fixture.session.index.allNotes.isEmpty)
}

/// A `.canvas` would pass for a board and split the pair: refused like a `.md`, in any case (G3).
@MainActor
@Test func aDroppedCanvasIsRefusedInAnyCase() async throws {
    let vault = try TemporaryVault()
    let fixture = try await IngestFixture(vault)
    let names = ["Schema.CANVAS", "lavagna.canvas"]
    for name in names { try fixture.drop(name, Data("{}".utf8)) }

    for report in [await fixture.engine.observe(), await fixture.engine.observe()] {
        #expect(report.imported.isEmpty)
        #expect(report.waiting.isEmpty)
        #expect(report.notices == names.map { .refusedNote(file: $0) })
    }
    #expect(fixture.dropContents == names)
    #expect(fixture.session.index.allNotes.isEmpty)
}

@Test func theListingRecognisesTheICloudStubBeforeTheHiddenRule() {
    var listing = DropFolderListing()
    let result = listing.classify([
        .init(name: ".a.pdf.icloud"), .init(name: ".hidden"), .init(name: "b.MD"),
        .init(name: "c", isDirectory: true), .init(name: "d.pdf", isDataless: true),
        .init(name: "e.pdf", size: 3),
    ])

    #expect(result.map { $0.classification } == [
        .placeholder(name: "a.pdf"), .hidden, .refused, .subfolder, .placeholder(name: "d.pdf"), .waiting,
    ])
    let again = listing.classify([.init(name: "e.pdf", size: 3)])
    #expect(again.map { $0.classification } == [.ready])
}

// MARK: - Drop folder states (R-26, engine half)

@MainActor
@Test func aMissingDropFolderIsCreated() async throws {
    let vault = try TemporaryVault()
    let fixture = try await IngestFixture(vault, createDrop: false)

    let report = await fixture.engine.observe()

    #expect(report.notices.isEmpty)
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: fixture.drop.path(percentEncoded: false), isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
}

@MainActor
@Test func anUnreadableDropFolderGivesOneNoticeAndImportsNothing() async throws {
    let vault = try TemporaryVault()
    let fixture = try await IngestFixture(vault)
    try fixture.drop("a.pdf")
    let path = fixture.drop.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }

    let first = await fixture.engine.observe()
    let second = await fixture.engine.observe()

    #expect(first.notices == [.unreadableDropFolder])
    #expect(first.imported.isEmpty)
    #expect(second.notices.isEmpty)
    #expect(second.imported.isEmpty)
}
