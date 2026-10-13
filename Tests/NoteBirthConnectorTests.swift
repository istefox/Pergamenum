import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D10 and ADR-0086 §D5/§D6, plan docs/plans/pg-387-n4-birth-of-note.md,
// Task 2 - R-05, R-10, R-15: the connector doors `VaultAPI.classifyNote`, `extractToNote` and the
// `template:` argument of `createNote` and `capture`, armed through `VaultAPI.arm`, rehearsal first.
//
// Not driven here: a stale `expecting:` on `classifyNote`'s one write (no suspension separates its
// read from its write, so no deterministic interleaving exists - ADR-0046 §D11). The extract
// half-done case is driven below by changing the source the moment the new note has landed.

private let capture = """
---
date: 2026-10-01
tags:
  - type-note
  - status-inbox
---

Pensiero.
"""

/// Line 1 is the opening delimiter, lines 2 to 5 the keys, line 6 the closing delimiter, line 7 a
/// blank one; the body is "Uno" (8), blank (9), "Due" (10), blank (11), "Tre" (12).
private let source = """
---
date: 2026-10-01
tags:
  - type-note
  - topic-a
---

Uno

Due

Tre
"""

private let riunione = """
---
date: 2026-01-01
tags:
  - type-note
---

# {{title}}

Data: {{date}}

{{cursor}}Fine
"""

@MainActor
private func openVault(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

private func disk(_ path: String, in root: URL) throws -> String {
    try String(contentsOf: root.appending(path: path, directoryHint: .notDirectory), encoding: .utf8)
}

private func existsOnDisk(_ path: String, in root: URL) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: path, directoryHint: .notDirectory).path)
}

private func tags(of text: String) -> [String] {
    NoteDocument.parse(text).frontmatter.tags.map(\.description)
}

// MARK: - classify

@MainActor
@Test func aRehearsedClassifyChangesNothingAndReturnsTheDiff() async throws {
    let vault = try TemporaryVault()
    try vault.write(capture, to: "00 Inbox/Idea.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "classify_note", dryRun: true)

    let summary = try await VaultAPI.classifyNote(session, at: "00 Inbox/Idea.md", topics: "x", folder: nil)

    #expect(summary.path == "00 Inbox/Idea.md")
    #expect(summary.applied == false)
    let diff = try #require(summary.diff)
    #expect(diff.contains("-  - status-inbox"))
    #expect(diff.contains("+  - topic-x"))
    #expect(try disk("00 Inbox/Idea.md", in: vault.root) == capture)
}

@MainActor
@Test func aRealClassifyAppliesAndReturnsTheDiff() async throws {
    let vault = try TemporaryVault()
    try vault.write(capture, to: "00 Inbox/Idea.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "classify_note", dryRun: false)

    let summary = try await VaultAPI.classifyNote(session, at: "00 Inbox/Idea.md", topics: "x", folder: nil)

    #expect(summary.applied)
    #expect(summary.movedTo == nil)
    #expect(summary.diff?.contains("+  - topic-x") == true)
    #expect(tags(of: try disk("00 Inbox/Idea.md", in: vault.root)) == ["type-note", "topic-x"])
}

@MainActor
@Test func aRealClassifyWithAFolderMovesTheNoteAndSaysWhere() async throws {
    let vault = try TemporaryVault()
    try vault.write(capture, to: "00 Inbox/Idea.md")
    try vault.write("---\ndate: 2026-10-01\ntags:\n  - type-note\n  - topic-a\n---\n\nQui.\n", to: "03 Risorse/Altra.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "classify_note", dryRun: false)

    let summary = try await VaultAPI.classifyNote(session, at: "00 Inbox/Idea.md", topics: "x", folder: "03 Risorse")

    #expect(summary.movedTo == "03 Risorse/Idea.md")
    #expect(!existsOnDisk("00 Inbox/Idea.md", in: vault.root))
    #expect(tags(of: try disk("03 Risorse/Idea.md", in: vault.root)) == ["type-note", "topic-x"])
}

@MainActor
@Test func aCommaSeparatedTopicStringIsTwoTopics() async throws {
    let vault = try TemporaryVault()
    try vault.write(capture, to: "00 Inbox/Idea.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "classify_note", dryRun: false)

    _ = try await VaultAPI.classifyNote(session, at: "00 Inbox/Idea.md", topics: "a,b", folder: nil)

    #expect(tags(of: try disk("00 Inbox/Idea.md", in: vault.root)) == ["type-note", "topic-a", "topic-b"])
}

@MainActor
@Test func aMalformedTopicIsAUsageErrorAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(capture, to: "00 Inbox/Idea.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "classify_note", dryRun: false)

    do {
        _ = try await VaultAPI.classifyNote(session, at: "00 Inbox/Idea.md", topics: "Topic Bad", folder: nil)
        Issue.record("a malformed topic was accepted")
    } catch let error as ConnectorError {
        #expect(error.isUsage)
    }
    #expect(try disk("00 Inbox/Idea.md", in: vault.root) == capture)
}

@MainActor
@Test func noTopicAtAllIsAUsageErrorWithTheRulesOwnSentence() async throws {
    let vault = try TemporaryVault()
    try vault.write(capture, to: "00 Inbox/Idea.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "classify_note", dryRun: false)

    do {
        _ = try await VaultAPI.classifyNote(session, at: "00 Inbox/Idea.md", topics: "", folder: nil)
        Issue.record("an empty topic list was accepted")
    } catch let error as ConnectorError {
        #expect(error.isUsage)
        #expect(error.description.contains(ClassificationRefusal.noTopic.sentence))
    }
    #expect(try disk("00 Inbox/Idea.md", in: vault.root) == capture)
}

// MARK: - extract

@MainActor
@Test func aRehearsedExtractShowsTwoDiffsAndChangesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(source, to: "Fonte.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "extract_to_note", dryRun: true)

    let summary = try await VaultAPI.extractToNote(
        session, at: "Fonte.md", fromLine: 10, toLine: 10, title: "Estratto", folder: "02 Estratti", topics: nil
    )

    #expect(summary.created == "02 Estratti/Estratto.md")
    #expect(summary.applied == false)
    #expect(summary.sourceRefused == nil)
    #expect(try #require(summary.createdDiff).contains("+Due"))
    let sourceDiff = try #require(summary.sourceDiff)
    #expect(sourceDiff.contains("-Due"))
    #expect(sourceDiff.contains("+[[Estratto]]"))
    #expect(try disk("Fonte.md", in: vault.root) == source)
    #expect(!existsOnDisk("02 Estratti/Estratto.md", in: vault.root))
}

@MainActor
@Test func aRealExtractAppliesBothWrites() async throws {
    let vault = try TemporaryVault()
    try vault.write(source, to: "Fonte.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "extract_to_note", dryRun: false)

    let summary = try await VaultAPI.extractToNote(
        session, at: "Fonte.md", fromLine: 10, toLine: 10, title: "Estratto", folder: "02 Estratti", topics: "b"
    )

    #expect(summary.applied)
    #expect(summary.sourceRefused == nil)
    #expect(try disk("Fonte.md", in: vault.root) == source.replacingOccurrences(of: "Due", with: "[[Estratto]]"))
    let created = try disk("02 Estratti/Estratto.md", in: vault.root)
    #expect(NoteDocument.parse(created).body.contains("Due"))
    #expect(tags(of: created).contains("topic-b"))
}

@MainActor
@Test func aRangeTouchingTheFrontmatterIsAUsageErrorOnARehearsalAndOnARealRun() async throws {
    let vault = try TemporaryVault()
    try vault.write(source, to: "Fonte.md")
    let session = await openVault(vault)

    for dryRun in [true, false] {
        VaultAPI.arm(session, command: "extract_to_note", dryRun: dryRun)
        do {
            _ = try await VaultAPI.extractToNote(
                session, at: "Fonte.md", fromLine: 3, toLine: 5, title: "Estratto", folder: "02 Estratti", topics: nil
            )
            Issue.record("a range inside the frontmatter was accepted (dryRun: \(dryRun))")
        } catch let error as ConnectorError {
            #expect(error.isUsage)
        }
    }
    #expect(try disk("Fonte.md", in: vault.root) == source)
    #expect(!existsOnDisk("02 Estratti/Estratto.md", in: vault.root))
}

@MainActor
@Test func aBackwardsOrOutOfBoundsLineRangeIsAUsageErrorNotACrash() async throws {
    let vault = try TemporaryVault()
    try vault.write(source, to: "Fonte.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "extract_to_note", dryRun: false)

    for (from, to) in [(12, 10), (50, 51)] {
        do {
            _ = try await VaultAPI.extractToNote(
                session, at: "Fonte.md", fromLine: from, toLine: to, title: "Estratto", folder: "02 Estratti", topics: nil
            )
            Issue.record("lines \(from)-\(to) were accepted")
        } catch let error as ConnectorError {
            #expect(error.isUsage)
        }
    }
    #expect(try disk("Fonte.md", in: vault.root) == source)
}

@MainActor
@Test func undoReversesTheSourceRewriteAndDeclinesTheCreation() async throws {
    let vault = try TemporaryVault()
    try vault.write(source, to: "Fonte.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "extract_to_note", dryRun: false)
    _ = try await VaultAPI.extractToNote(
        session, at: "Fonte.md", fromLine: 10, toLine: 10, title: "Estratto", folder: "02 Estratti", topics: nil
    )
    let rows = try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil)
    let creation = try #require(rows.first { $0.created })
    let rewrite = try #require(rows.first { !$0.created && $0.path == "Fonte.md" })

    VaultAPI.arm(session, command: "undo_write", dryRun: false)
    // The journal never deletes: the creation is declined, and the new note stays.
    await #expect(throws: ConnectorError.self) { try await VaultAPI.undo(session, id: creation.id) }
    #expect(existsOnDisk("02 Estratti/Estratto.md", in: vault.root))

    _ = try await VaultAPI.undo(session, id: rewrite.id)
    #expect(try disk("Fonte.md", in: vault.root) == source)
    #expect(existsOnDisk("02 Estratti/Estratto.md", in: vault.root))
}

@MainActor
@Test func aSourceThatMovedOnAfterTheNoteLandedReportsTheRefusalAndKeepsTheNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(source, to: "Fonte.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "extract_to_note", dryRun: false)
    let sourceURL = vault.root.appending(path: "Fonte.md", directoryHint: .notDirectory)
    let moved = source + "\n\nQuarto\n"
    session.landedChangeSubscriber = { change in
        if case .written(let result, _) = change, result.path == "02 Estratti/Estratto.md" {
            try? Data(moved.utf8).write(to: sourceURL)
        }
    }

    let summary = try await VaultAPI.extractToNote(
        session, at: "Fonte.md", fromLine: 10, toLine: 10, title: "Estratto", folder: "02 Estratti", topics: nil
    )

    #expect(summary.created == "02 Estratti/Estratto.md")
    #expect(summary.sourceRefused?.isEmpty == false)
    #expect(existsOnDisk("02 Estratti/Estratto.md", in: vault.root))
    #expect(try disk("Fonte.md", in: vault.root) == moved)
}

// MARK: - createNote with a template

@MainActor
@Test func aNoteCreatedFromATemplateIsWrittenWithTheResolvedBodyAndNoCursorMarker() async throws {
    for reference in ["Riunione", "Templates/Riunione.md", "Riunione.md"] {
        let vault = try TemporaryVault()
        try vault.write(riunione, to: "Templates/Riunione.md")
        let session = await openVault(vault)
        VaultAPI.arm(session, command: "create_note", dryRun: false)

        let summary = try await VaultAPI.createNote(
            session, title: "Riunione con Rossi", folder: nil, topic: nil, date: "2026-10-12", template: reference
        )

        let text = try disk(summary.path, in: vault.root)
        #expect(text == "---\ndate: 2026-10-12\ntags:\n  - type-note\n  - status-inbox\n---\n\n"
            + "# Riunione con Rossi\n\nData: 2026-10-12\n\nFine", "«\(reference)»")
        #expect(!text.contains("{{cursor}}"))
    }
}

@MainActor
@Test func anUnknownTemplateIsRefusedListingTheOnesThatExistAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(riunione, to: "Templates/Riunione.md")
    try vault.write(riunione, to: "Templates/Verbale.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "create_note", dryRun: false)

    do {
        _ = try await VaultAPI.createNote(
            session, title: "Nuova", folder: nil, topic: nil, date: "2026-10-12", template: "Assente"
        )
        Issue.record("an unknown template was accepted")
    } catch let error as ConnectorError {
        #expect(error.description.contains("Riunione"))
        #expect(error.description.contains("Verbale"))
    }
    #expect(!existsOnDisk("Nuova.md", in: vault.root))
}

@MainActor
@Test func anAmbiguousTemplateIsRefusedNamingItsCandidates() async throws {
    let vault = try TemporaryVault()
    try vault.write(riunione, to: "Templates/A/Riunione.md")
    try vault.write(riunione, to: "Templates/B/Riunione.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "create_note", dryRun: false)

    do {
        _ = try await VaultAPI.createNote(
            session, title: "Nuova", folder: nil, topic: nil, date: "2026-10-12", template: "Riunione"
        )
        Issue.record("an ambiguous template was accepted")
    } catch let error as ConnectorError {
        #expect(error.description.contains("Templates/A/Riunione.md"))
        #expect(error.description.contains("Templates/B/Riunione.md"))
    }
    #expect(!existsOnDisk("Nuova.md", in: vault.root))
}

// MARK: - capture with a template

@MainActor
@Test func aCapturedNewNoteWithATemplateIsOneNoteWithTheTextAtTheMarker() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ntags:\n  - type-note\n---\n\n# {{title}}\n\n{{cursor}}\n\nFooter", to: "Templates/Riunione.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    _ = try await VaultAPI.capture(
        session, to: .newNote(folder: nil), text: "Idea\nResto del pensiero", template: "Riunione"
    )

    let inbox = vault.root.appending(path: "00 Inbox", directoryHint: .isDirectory)
    let written = try FileManager.default.contentsOfDirectory(atPath: inbox.path).filter { $0.hasSuffix(".md") }
    #expect(written == ["Idea.md"])
    let text = try disk("00 Inbox/Idea.md", in: vault.root)
    #expect(!text.contains("{{cursor}}"))
    #expect(text.contains("# Idea"))
    let captured = try #require(text.range(of: "Resto del pensiero"))
    let footer = try #require(text.range(of: "Footer"))
    #expect(captured.upperBound <= footer.lowerBound)
}

@MainActor
@Test func aTemplateOnAnyDestinationButANewNoteIsAUsageError() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ntags:\n  - type-note\n---\n\n# {{title}}\n", to: "Templates/Riunione.md")
    try vault.write(capture, to: "Nota.md")
    let session = await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let destinations: [VaultAPI.CaptureDestination] = [.today, .task(note: nil), .note("Nota.md")]
    for destination in destinations {
        do {
            _ = try await VaultAPI.capture(session, to: destination, text: "Pensiero", template: "Riunione")
            Issue.record("a template was accepted on \(destination)")
        } catch let error as ConnectorError {
            #expect(error.isUsage, "\(destination)")
        }
    }
    #expect(try disk("Nota.md", in: vault.root) == capture)
    #expect(!session.exists(session.dailyNotePath(for: .today)))
}

// MARK: - PG-398: classify and extract take an indexed note and nothing else

/// Vault files that exist and are readable but are not indexed notes.
private let nonNotePaths = ["Lavagna.canvas", ".pergamenum/appunti.json"]

@MainActor
private func openVaultWithNonNotes(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(#"{"nodes":[],"edges":[]}"#, to: "Lavagna.canvas")
    try vault.write("{\"testo\": \"Uno\"}\n{\"testo\": \"Due\"}\n", to: ".pergamenum/appunti.json")
    return await openVault(vault)
}

@MainActor
@Test(arguments: nonNotePaths)
func aClassifyOfAFileThatIsNotANoteIsRefusedAndWritesNothing(path: String) async throws {
    let vault = try TemporaryVault()
    let session = try await openVaultWithNonNotes(vault)
    let before = try disk(path, in: vault.root)
    let journalBefore = session.journalOnDisk.entries().count

    VaultAPI.arm(session, command: "classify_note", dryRun: false)
    let error = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.classifyNote(session, at: path, topics: "x", folder: nil)
    }

    #expect(error?.description == "«\(path)» non è una nota del vault")
    #expect(error?.isUsage == false)
    #expect(try disk(path, in: vault.root) == before)
    #expect(session.journalOnDisk.entries().count == journalBefore)
}

@MainActor
@Test(arguments: nonNotePaths)
func anExtractFromAFileThatIsNotANoteIsRefusedAndCreatesNothing(path: String) async throws {
    let vault = try TemporaryVault()
    let session = try await openVaultWithNonNotes(vault)
    let before = try disk(path, in: vault.root)
    let journalBefore = session.journalOnDisk.entries().count

    VaultAPI.arm(session, command: "extract_to_note", dryRun: false)
    let error = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.extractToNote(
            session, at: path, fromLine: 1, toLine: 1, title: "Estratto", folder: "02 Estratti", topics: nil
        )
    }

    #expect(error?.description == "«\(path)» non è una nota del vault")
    #expect(error?.isUsage == false)
    #expect(try disk(path, in: vault.root) == before)
    #expect(!existsOnDisk("02 Estratti/Estratto.md", in: vault.root), "il rifiuto viene prima della creazione")
    #expect(session.journalOnDisk.entries().count == journalBefore)
}

@MainActor
@Test func classifyAndExtractRefuseAMissingPathWithTheSessionsSentence() async throws {
    let vault = try TemporaryVault()
    let session = await openVault(vault)
    let sentence = "nessuna nota in «Assente.md»"
    #expect(session.linkEndRefusal("Assente.md") == sentence)

    VaultAPI.arm(session, command: "classify_note", dryRun: false)
    let classify = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.classifyNote(session, at: "Assente.md", topics: "x", folder: nil)
    }
    VaultAPI.arm(session, command: "extract_to_note", dryRun: false)
    let extract = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.extractToNote(
            session, at: "Assente.md", fromLine: 1, toLine: 1, title: "Estratto", folder: nil, topics: nil
        )
    }

    #expect(classify?.description == sentence)
    #expect(extract?.description == sentence)
    #expect(!existsOnDisk("Estratto.md", in: vault.root))
}

/// The usage guards still answer first, whatever the path is: an empty path on both doors, and on
/// extract an empty title and a backwards range.
@MainActor
@Test func classifyAndExtractUsageErrorsComeBeforeThePathIsLookedAt() async throws {
    let vault = try TemporaryVault()
    let session = try await openVaultWithNonNotes(vault)

    VaultAPI.arm(session, command: "classify_note", dryRun: false)
    let noPath = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.classifyNote(session, at: "", topics: "x", folder: nil)
    }
    VaultAPI.arm(session, command: "extract_to_note", dryRun: false)
    let noTitle = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.extractToNote(
            session, at: "Lavagna.canvas", fromLine: 1, toLine: 1, title: "", folder: nil, topics: nil
        )
    }
    let backwards = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.extractToNote(
            session, at: "Lavagna.canvas", fromLine: 2, toLine: 1, title: "Estratto", folder: nil, topics: nil
        )
    }

    for error in [noPath, noTitle, backwards] {
        #expect(error?.isUsage == true)
    }
}
