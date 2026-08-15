import Foundation
import Testing
@testable import Pergamenum

/// A throwaway vault on disk, so the file-touching layers are tested against a real
/// file system rather than a mock that cannot reproduce atomic writes or enumeration.
/// Shared with `VaultSessionTests`, which needs the same throwaway vault.
struct TemporaryVault: ~Copyable {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-vault-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func write(_ contents: String, to relativePath: String) throws -> URL {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        return url
    }
}

private let sampleNote = """
---
date: 2026-08-11
tags:
  - type-note
  - topic-vibration-isolation
---

Corpo con un [[Altro titolo]] e un ![[schema.pdf]].
"""

// MARK: - Store

@Test func readsANoteAndDerivesItsRecord() throws {
    let vault = try TemporaryVault()
    try vault.write(sampleNote, to: "01 Progetti/Nota di prova.md")

    let (record, text) = try NoteStore(root: vault.root).read("01 Progetti/Nota di prova.md")
    #expect(record.title == "Nota di prova")
    #expect(record.folder == "01 Progetti")
    #expect(record.frontmatter.tags.map(\.description) == ["type-note", "topic-vibration-isolation"])
    // The embed is a file reference, not a note link, so it must not appear here.
    #expect(record.linkTargets == ["Altro titolo"])
    #expect(text == sampleNote)
    #expect(record.contentHash.count == 64)
}

@Test func writesAtomicallyAndReportsTheHashItWrote() throws {
    let vault = try TemporaryVault()
    let store = NoteStore(root: vault.root)

    let hash = try store.write(sampleNote, to: "Nuova nota.md")
    let (record, text) = try store.read("Nuova nota.md")
    #expect(text == sampleNote)
    #expect(record.contentHash == hash)
}

@Test func createsMissingFoldersOnWrite() throws {
    let vault = try TemporaryVault()
    try NoteStore(root: vault.root).write("corpo", to: "a/b/c/Nota.md")
    #expect(FileManager.default.fileExists(atPath: vault.root.appending(path: "a/b/c/Nota.md").path(percentEncoded: false)))
}

@Test func refusesToWriteOutsideTheVault() throws {
    let vault = try TemporaryVault()
    let store = NoteStore(root: vault.root)
    // Wikilinks and pergamenum:// arguments are user-supplied text; without this
    // guard a crafted path would write anywhere on disk.
    #expect(throws: NoteStore.StoreError.self) {
        try store.write("x", to: "../fuori.md")
    }
    #expect(throws: NoteStore.StoreError.self) {
        try store.read("../../etc/passwd")
    }
}

@Test func rejectsNonUTF8Files() throws {
    let vault = try TemporaryVault()
    let url = vault.root.appending(path: "binaria.md")
    try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: url)
    #expect(throws: NoteStore.StoreError.self) {
        try NoteStore(root: vault.root).read("binaria.md")
    }
}

// MARK: - Scanner

@Test func scansMarkdownAndSkipsEverythingElse() throws {
    let vault = try TemporaryVault()
    try vault.write(sampleNote, to: "Uno.md")
    try vault.write(sampleNote, to: "01 Progetti/Due.md")
    try vault.write(sampleNote, to: "Calendar/20260811.md")
    try vault.write("non una nota", to: "allegato.pdf")
    try vault.write(sampleNote, to: ".obsidian/plugin/Tre.md")
    try vault.write(sampleNote, to: ".pergamenum/cache/Quattro.md")

    let outcome = VaultScanner(root: vault.root).scan()
    #expect(outcome.failures.isEmpty)
    #expect(Set(outcome.records.map(\.relativePath)) == ["Uno.md", "01 Progetti/Due.md", "Calendar/20260811.md"])
}

@Test func reportsUnreadableNotesInsteadOfSkippingThem() throws {
    let vault = try TemporaryVault()
    try vault.write(sampleNote, to: "Buona.md")
    try Data([0xFF, 0xFE]).write(to: vault.root.appending(path: "Rotta.md"))

    let outcome = VaultScanner(root: vault.root).scan()
    #expect(outcome.records.map(\.relativePath) == ["Buona.md"])
    // A note missing from the index is invisible in search and backlinks, and the
    // user has no way to notice on their own.
    #expect(outcome.failures.map(\.path) == ["Rotta.md"])
}

// MARK: - Index

@MainActor
private func populatedIndex() throws -> IndexSnapshot {
    var index = IndexSnapshot()
    let records = [
        makeRecord(path: "A.md", title: "Alfa", links: ["Beta", "Mancante"]),
        makeRecord(path: "B.md", title: "Beta", links: ["Alfa"]),
        makeRecord(path: "sub/C.md", title: "Gamma", links: ["Beta"], aliases: ["Terzo"]),
    ]
    index.replaceAll(with: .init(records: records, failures: []), duration: .zero)
    return index
}

private func makeRecord(
    path: String, title: String, links: [String] = [], aliases: [String] = [],
    related: [String] = [], tasks: [TaskItem] = []
) -> NoteRecord {
    var frontmatter = Frontmatter.empty
    frontmatter.date = CalendarDate(iso: "2026-08-11")
    frontmatter.tags = [Tag("type-note")!]
    frontmatter.aliases = aliases
    frontmatter.related = related
    return NoteRecord(
        relativePath: path, title: title, frontmatter: frontmatter, linkTargets: links,
        tasks: tasks, modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
}

@MainActor
@Test func resolvesTitlesAndBacklinks() throws {
    let index = try populatedIndex()
    #expect(index.resolve(title: "beta") == ["B.md"])
    #expect(index.backlinks(toTitle: "Beta").map(\.title) == ["Alfa", "Gamma"])
    #expect(index.backlinks(toTitle: "Alfa").map(\.title) == ["Beta"])
}

@MainActor
@Test func reportsAmbiguousTitles() {
    var index = IndexSnapshot()
    index.replaceAll(with: .init(records: [
        makeRecord(path: "uno/Doppio.md", title: "Doppio"),
        makeRecord(path: "due/Doppio.md", title: "Doppio"),
    ], failures: []), duration: .zero)
    // Two notes may legitimately share a title; a link to it is ambiguous and the UI
    // has to say so rather than silently picking one.
    #expect(index.resolve(title: "Doppio").count == 2)
}

@MainActor
@Test func listsUnresolvedLinksWithTheirSources() throws {
    let index = try populatedIndex()
    let unresolved = index.unresolvedLinks()
    #expect(unresolved.map(\.target) == ["Mancante"])
    #expect(unresolved[0].sources.map(\.title) == ["Alfa"])
}

@MainActor
@Test func countsStructuralLinksAsBacklinksToo() {
    var index = IndexSnapshot()
    index.replaceAll(with: .init(records: [
        makeRecord(path: "A.md", title: "Alfa", related: ["\"[[Beta]]\""]),
        makeRecord(path: "B.md", title: "Beta"),
    ], failures: []), duration: .zero)
    // W-03 distinguishes structural links from inline citations; the backlink panel
    // shows both, so `related` has to feed the index.
    #expect(index.backlinks(toTitle: "Beta").map(\.title) == ["Alfa"])
}

@MainActor
@Test func removingANoteClearsTheBacklinksItProduced() throws {
    var index = try populatedIndex()
    index.update(nil, at: "A.md")

    #expect(index.count == 2)
    #expect(index.backlinks(toTitle: "Beta").map(\.title) == ["Gamma"])
    // "Mancante" went with A.md, and "Alfa" became unresolved because the note that
    // answered to it is the one that was removed.
    #expect(index.unresolvedLinks().map(\.target) == ["Alfa"])
}

@MainActor
@Test func searchesTitlesAndAliases() throws {
    let index = try populatedIndex()
    #expect(index.search("gam").first?.title == "Gamma")
    // Aliases serve search (F-07) even though they are never a link target.
    #expect(index.search("terzo").first?.title == "Gamma")
    #expect(index.search("zzz").isEmpty)
}

// MARK: - Fuzzy matching

@Test func fuzzyMatchFindsInitialsAcrossWords() {
    let score = FuzzyMatch.score(query: "trf", candidate: "Trasmissibilità e rapporto di frequenza")
    #expect(score != nil)
}

@Test func fuzzyMatchPrefersContiguousAndWordStartMatches() throws {
    let contiguous = try #require(FuzzyMatch.score(query: "rap", candidate: "rapporto"))
    let scattered = try #require(FuzzyMatch.score(query: "rap", candidate: "risultato apparente"))
    #expect(contiguous > scattered)
}

@Test func fuzzyMatchRejectsCharactersNotPresent() {
    #expect(FuzzyMatch.score(query: "xyz", candidate: "rapporto") == nil)
    #expect(FuzzyMatch.score(query: "toolongforthis", candidate: "breve") == nil)
}

// MARK: - Controller

@MainActor
@Test func opensAVaultAndIndexesIt() async throws {
    let vault = try TemporaryVault()
    try vault.write(sampleNote, to: "Uno.md")
    try vault.write(sampleNote, to: "Calendar/20260811.md")

    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    #expect(controller.index.count == 2)
    #expect(controller.problems.isEmpty, "\(controller.problems)")
    // The vocabulary replica is seeded from the bundle on first open (SPEC §4.6).
    #expect(controller.vocabulary.type.contains("note"))
    #expect(FileManager.default.fileExists(
        atPath: vault.root.appending(path: ".pergamenum/vocabolari.json").path(percentEncoded: false)
    ))
    controller.close()
}

@MainActor
@Test func editsAndSavesANoteWithoutCorruptingIt() async throws {
    let vault = try TemporaryVault()
    try vault.write(sampleNote, to: "Uno.md")

    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)
    controller.openNote(at: "Uno.md")

    #expect(controller.openNote?.hasUnsavedChanges == false)
    controller.updateOpenNoteText(sampleNote + "\n\nRiga aggiunta.")
    #expect(controller.openNote?.hasUnsavedChanges == true)

    controller.saveOpenNote()
    #expect(controller.openNote?.hasUnsavedChanges == false)

    let onDisk = try String(contentsOf: vault.root.appending(path: "Uno.md"), encoding: .utf8)
    #expect(onDisk.hasSuffix("Riga aggiunta."))
    // Everything that was there before is still there: the save appended, it did not
    // rewrite the note through the parser.
    #expect(onDisk.hasPrefix(sampleNote))
    controller.close()
}

@MainActor
@Test func reportsViolationsOfTheOpenNote() async throws {
    let vault = try TemporaryVault()
    try vault.write("""
    ---
    date: 2026-08-11
    tags:
      - type-note
    status: bozza
    ---
    corpo senza topic
    """, to: "Nota v2.md")

    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)
    controller.openNote(at: "Nota v2.md")
    let note = try #require(controller.openNote)
    let violations = controller.violations(for: note)

    #expect(violations.frontmatter.contains(.foreignKey("status")))
    #expect(violations.tags.contains(.missingRequiredTag("topic-*")))
    #expect(violations.name.contains { if case .hasVersionSuffix = $0 { true } else { false } })
    controller.close()
}

@MainActor
@Test func importsConventionsFromTheHarnessCheckout() async throws {
    let vault = try TemporaryVault()
    let repository = try TemporaryVault()
    try repository.write("""
    ### 4.4 Vocabolario chiuso: type

    | Tag | Contenuto |
    |---|---|
    | type-note | nota |

    ### 4.6 Vocabolario chiuso: status

    | Tag | Significato |
    |---|---|
    | status-inbox | acquisito |

    ### 4.7 Vocabolario chiuso: area

    | Tag | Copre |
    |---|---|
    | area-engineering | calcoli |

    ### 4.8 Vocabolario chiuso: source

    | Tag | Copre |
    |---|---|
    | source-web | dal web |
    """, to: "convenzioni/tag.md")
    try repository.write("""
    ### 6.1 Tipo deliverable

    | Tipo | Uso |
    |---|---|
    | Offerta | offerta |
    """, to: "convenzioni/naming.md")

    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)
    controller.importConventions(from: repository.root)

    #expect(controller.vocabulary.type == ["note"])
    #expect(controller.vocabulary.deliverableKind == ["Offerta"])
    // Written back into the vault, so the replica survives a relaunch.
    let written = try Data(contentsOf: vault.root.appending(path: ".pergamenum/vocabolari.json"))
    #expect(try JSONDecoder().decode(Vocabulary.self, from: written).type == ["note"])
    controller.close()
}

@MainActor
@Test func reportsAnUnreadableHarnessCheckoutInsteadOfClearingTheVocabulary() async throws {
    let vault = try TemporaryVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)
    let before = controller.vocabulary

    controller.importConventions(from: vault.root.appending(path: "non-esiste"))
    #expect(controller.vocabulary == before)
    #expect(controller.problems.contains { $0.contains("could not be read") })
    controller.close()
}

// MARK: - Note creation

@MainActor
@Test func createsANoteWithAConformantFrontmatter() async throws {
    let vault = try TemporaryVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    let path = try controller.createNote(
        title: "Nota nuova",
        in: "01 Progetti",
        date: CalendarDate(iso: "2026-08-11")!,
        topics: [Tag("topic-acoustics")!]
    )
    #expect(path == "01 Progetti/Nota nuova.md")

    // Written out escape by escape: a multiline literal hides whether the blank line
    // separating the block from the body is actually there.
    let text = try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
    #expect(text == "---\ndate: 2026-08-11\ntags:\n  - type-note\n  - topic-acoustics\n---\n\n")

    // The note it just wrote must satisfy the rules it will later be judged by.
    let note = try #require(controller.openNote)
    #expect(controller.violations(for: note).isEmpty, "\(controller.violations(for: note))")
    controller.close()
}

@MainActor
@Test func createsAnInboxCaptureWithStatusInbox() async throws {
    let vault = try TemporaryVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    let path = try controller.createNote(
        title: "Capture", date: CalendarDate(iso: "2026-08-11")!, category: .capture
    )
    let text = try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
    // tag.md 5.1: a capture carries type-note and status-inbox, and needs no topic.
    #expect(text.contains("  - type-note"))
    #expect(text.contains("  - status-inbox"))
    controller.close()
}

@MainActor
@Test func refusesToCreateANoteWithANonConformantTitle() async throws {
    let vault = try TemporaryVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    // Sanitising silently is how a vault fills with titles nobody chose.
    #expect(throws: VaultController.CreationError.self) {
        try controller.createNote(title: "Nota/con/slash", date: CalendarDate(iso: "2026-08-11")!)
    }
    #expect(throws: VaultController.CreationError.self) {
        try controller.createNote(title: "Relazione v2", date: CalendarDate(iso: "2026-08-11")!)
    }
    controller.close()
}

@MainActor
@Test func refusesToOverwriteAnExistingNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(sampleNote, to: "Esistente.md")
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    #expect(throws: VaultController.CreationError.self) {
        try controller.createNote(title: "Esistente", date: CalendarDate(iso: "2026-08-11")!)
    }
    // The original is untouched.
    let onDisk = try String(contentsOf: vault.root.appending(path: "Esistente.md"), encoding: .utf8)
    #expect(onDisk == sampleNote)
    controller.close()
}

@MainActor
@Test func opensOrCreatesTheDailyNoteInTheConfiguredFolder() async throws {
    let vault = try TemporaryVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    let date = CalendarDate(iso: "2026-08-11")!
    let path = try controller.openDailyNote(for: date)
    // naming.md 4.6: the compact form, never the hyphenated one.
    #expect(path == "Calendar/20260811.md")

    let text = try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
    #expect(text.contains("  - type-note"))
    #expect(!text.contains("topic-"))

    // Calling again opens the same note rather than failing or making a second one.
    #expect(try controller.openDailyNote(for: date) == path)
    #expect(controller.index.count == 1)
    controller.close()
}

@Test func writesIntoAVaultReachedThroughASymlink() throws {
    // Found by using the app, not by a test: `/tmp` is a symlink to `/private/tmp`,
    // and `appending(path:)` resolved it on one side only, so the vault-boundary
    // guard rejected every write with "outside the vault". Any symlinked vault path
    // does the same, and the earlier tests missed it because `temporaryDirectory`
    // hands back an already-resolved `/var/folders/…`.
    let real = try TemporaryVault()
    let link = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-link-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real.root)
    defer { try? FileManager.default.removeItem(at: link) }

    let store = NoteStore(root: link)
    try store.write(sampleNote, to: "Calendar/20260811.md")

    let (record, text) = try store.read("Calendar/20260811.md")
    #expect(text == sampleNote)
    #expect(record.title == "20260811")
}

@Test func stillRefusesToEscapeAVaultReachedThroughASymlink() throws {
    // The fix must not weaken the guard it fixes.
    let real = try TemporaryVault()
    let link = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-link-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real.root)
    defer { try? FileManager.default.removeItem(at: link) }

    let store = NoteStore(root: link)
    #expect(throws: NoteStore.StoreError.self) {
        try store.write("x", to: "../fuori.md")
    }
}

// MARK: Settings

/// A settings file written before a key existed must not lose the rest of the file for
/// it, and a hand-edited value must not be able to make every time block zero minutes
/// long - which is to say invisible.
@Test func settingsDecodeKeyByKeyAndClampTheBlockDuration() throws {
    let older = Data("""
    {"dailyFolder":"Diario","copyDroppedFiles":false}
    """.utf8)
    let settings = try JSONDecoder().decode(VaultSettings.self, from: older)
    #expect(settings.dailyFolder == "Diario")
    #expect(!settings.copyDroppedFiles)
    #expect(settings.blockMinutes == TimeBlock.defaultDuration)

    let broken = Data(#"{"blockMinutes":0}"#.utf8)
    #expect(try JSONDecoder().decode(VaultSettings.self, from: broken).blockMinutes == 5)

    let chosen = Data(#"{"blockMinutes":45}"#.utf8)
    #expect(try JSONDecoder().decode(VaultSettings.self, from: chosen).blockMinutes == 45)
}
