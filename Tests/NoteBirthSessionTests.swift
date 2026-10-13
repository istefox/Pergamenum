import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D4/§D8 and ADR-0086 §D3, plan docs/plans/pg-387-n4-birth-of-note.md,
// Task 2 - R-03, R-06, R-13, R-14: the session doors `classifyNote`, `extractToNote` and
// `dailyNoteBirth`, against a temporary vault and a temporary state base.
//
// What is not drivable here, and is reported rather than faked: a *stale* `expecting:` on the one
// write `classifyNote` makes. The file is read and written on one main-actor turn with no
// suspension between them (the same in-process atomicity `VaultSessionTests` documents for the
// board writer), so a test cannot land a second writer in the gap without a timing race
// (ADR-0046 §D11). The extract half-done case, whose second write is separated from its read by
// the first, is driven deterministically both ways below.

private let capture = """
---
date: 2026-10-01
tags:
  - type-note
  - status-inbox
---

Pensiero.
"""

private let today = CalendarDate(iso: "2026-10-12")!

private func tag(_ raw: String) -> Pergamenum.Tag { Pergamenum.Tag(raw)! }

@MainActor
private final class ChangeRecorder {
    private(set) var changes: [VaultSession.LandedChange] = []

    init(_ session: VaultSession) {
        session.landedChangeSubscriber = { [weak self] change in self?.changes.append(change) }
    }

    var writtenPaths: [String] {
        changes.compactMap { change -> String? in
            if case .written(let result, _) = change { return result.path }
            return nil
        }
    }
}

@MainActor
private func openSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
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

// MARK: - classifyNote

@MainActor
@Test func classifyingWritesTheFrontmatterOnceAndLandsOneWrittenChange() async throws {
    let vault = try TemporaryVault()
    try vault.write(capture, to: "00 Inbox/Idea.md")
    let session = await openSession(vault)
    let recorder = ChangeRecorder(session)

    let outcome = try await session.classifyNote(
        at: "00 Inbox/Idea.md", topics: [tag("topic-materiali")], toFolder: nil
    )

    #expect(outcome.written.path == "00 Inbox/Idea.md")
    #expect(outcome.movedTo == nil)
    #expect(outcome.moveProblem == nil)
    #expect(tags(of: outcome.written.text) == ["type-note", "topic-materiali"])
    #expect(NoteDocument.parse(outcome.written.text).body.contains("Pensiero."))
    #expect(try disk("00 Inbox/Idea.md", in: vault.root) == outcome.written.text)
    #expect(recorder.changes.count == 1)
    #expect(recorder.writtenPaths == ["00 Inbox/Idea.md"])
}

@MainActor
@Test func classifyingWithAFolderWritesFirstThenMovesAndLandsBothChangesInThatOrder() async throws {
    let vault = try TemporaryVault()
    try vault.write(capture, to: "00 Inbox/Idea.md")
    try vault.write("---\ndate: 2026-10-01\ntags:\n  - type-note\n  - topic-a\n---\n\nGià qui.\n", to: "03 Risorse/Altra.md")
    let session = await openSession(vault)
    let recorder = ChangeRecorder(session)

    let outcome = try await session.classifyNote(
        at: "00 Inbox/Idea.md", topics: [tag("topic-materiali")], toFolder: "03 Risorse"
    )

    #expect(outcome.movedTo == "03 Risorse/Idea.md")
    #expect(outcome.moveProblem == nil)
    #expect(recorder.changes == [
        .written(outcome.written, origin: nil),
        .moved(from: "00 Inbox/Idea.md", to: "03 Risorse/Idea.md"),
    ])
    #expect(!existsOnDisk("00 Inbox/Idea.md", in: vault.root))
    #expect(tags(of: try disk("03 Risorse/Idea.md", in: vault.root)) == ["type-note", "topic-materiali"])
}

@MainActor
@Test func aDestinationHoldingTheNameLeavesTheClassificationWrittenAndReportsTheMove() async throws {
    let vault = try TemporaryVault()
    try vault.write(capture, to: "00 Inbox/Idea.md")
    let occupant = "---\ndate: 2026-10-01\ntags:\n  - type-note\n  - topic-a\n---\n\nGià qui.\n"
    try vault.write(occupant, to: "03 Risorse/Idea.md")
    let session = await openSession(vault)
    let recorder = ChangeRecorder(session)

    // Not thrown: the write landed, and a classified note where it was is harmless.
    let outcome = try await session.classifyNote(
        at: "00 Inbox/Idea.md", topics: [tag("topic-materiali")], toFolder: "03 Risorse"
    )

    #expect(outcome.movedTo == nil)
    #expect(outcome.moveProblem?.isEmpty == false)
    #expect(tags(of: try disk("00 Inbox/Idea.md", in: vault.root)) == ["type-note", "topic-materiali"])
    #expect(try disk("03 Risorse/Idea.md", in: vault.root) == occupant)
    #expect(recorder.changes == [.written(outcome.written, origin: nil)])
}

@MainActor
@Test func aFolderTheNoteIsAlreadyInMovesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(capture, to: "00 Inbox/Idea.md")
    let session = await openSession(vault)
    let recorder = ChangeRecorder(session)

    let outcome = try await session.classifyNote(
        at: "00 Inbox/Idea.md", topics: [tag("topic-materiali")], toFolder: "00 Inbox"
    )

    #expect(outcome.movedTo == nil)
    #expect(outcome.moveProblem == nil)
    #expect(recorder.changes.count == 1)
}

@MainActor
@Test func aWriteThatFailsMovesNothingAndLeavesTheNoteInTheInbox() async throws {
    let vault = try TemporaryVault()
    try vault.write(capture, to: "00 Inbox/Idea.md")
    try vault.write(capture, to: "01 Libera/Controllo.md")
    try vault.write("---\ndate: 2026-10-01\ntags:\n  - type-note\n  - topic-a\n---\n\nQui.\n", to: "03 Risorse/Altra.md")
    let session = await openSession(vault)
    let recorder = ChangeRecorder(session)

    // The control: the same call on a writable folder works, so the failure below is the folder's.
    _ = try await session.classifyNote(at: "01 Libera/Controllo.md", topics: [tag("topic-a")], toFolder: nil)
    #expect(recorder.changes.count == 1)

    let inbox = vault.root.appending(path: "00 Inbox", directoryHint: .isDirectory)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: inbox.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: inbox.path) }

    await #expect(throws: (any Error).self) {
        try await session.classifyNote(at: "00 Inbox/Idea.md", topics: [tag("topic-a")], toFolder: "03 Risorse")
    }

    #expect(try disk("00 Inbox/Idea.md", in: vault.root) == capture)
    #expect(!existsOnDisk("03 Risorse/Idea.md", in: vault.root))
    #expect(recorder.changes.count == 1)
}

@MainActor
@Test func theRuleRefusesBeforeAnythingIsWritten() async throws {
    let vault = try TemporaryVault()
    try vault.write(capture, to: "00 Inbox/Idea.md")
    let session = await openSession(vault)
    let recorder = ChangeRecorder(session)

    await #expect(throws: ClassificationRefusal.noTopic) {
        try await session.classifyNote(at: "00 Inbox/Idea.md", topics: [], toFolder: nil)
    }
    await #expect(throws: ClassificationRefusal.dateTopic(tag("topic-2026"))) {
        try await session.classifyNote(at: "00 Inbox/Idea.md", topics: [tag("topic-2026")], toFolder: nil)
    }

    #expect(try disk("00 Inbox/Idea.md", in: vault.root) == capture)
    #expect(recorder.changes.isEmpty)
}

// MARK: - classifyNote on a scheda (gate G-S, decided: refuse)

private let schedaFolder = "Contenitore/Fatture"
private let schedaStem = "20260314 Fattura"
private var scheda: String { "\(schedaFolder)/\(schedaStem).md" }
private var schedaFile: String { "\(schedaFolder)/\(schedaStem).pdf" }

private func seedScheda(in vault: borrowing TemporaryVault) throws -> String {
    let text = ContenitoreScheda.render(
        date: CalendarDate(iso: "2026-03-14")!, fileName: "\(schedaStem).pdf",
        originalName: "Scansione.pdf", sha256: String(repeating: "ab", count: 32)
    )
    try vault.write(text, to: scheda)
    let pdf = vault.root.appending(path: schedaFile, directoryHint: .notDirectory)
    try Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 0x0A, 0xFF]).write(to: pdf)
    return text
}

@MainActor
@Test func aFolderOnASchedaPathIsRefusedBeforeAnyWriteWithTheContenitoreSentence() async throws {
    let vault = try TemporaryVault()
    let original = try seedScheda(in: vault)
    let session = await openSession(vault)
    let recorder = ChangeRecorder(session)
    let sentence = "Un documento del Contenitore resta nel Contenitore: classificalo senza cartella."

    do {
        _ = try await session.classifyNote(at: scheda, topics: [tag("topic-fatture")], toFolder: "03 Risorse")
        Issue.record("a folder on a scheda path was accepted")
    } catch {
        #expect(String(describing: error).contains(sentence))
    }

    #expect(try disk(scheda, in: vault.root) == original)
    #expect(existsOnDisk(schedaFile, in: vault.root))
    #expect(!existsOnDisk("03 Risorse/\(schedaStem).md", in: vault.root))
    #expect(recorder.changes.isEmpty)
}

@MainActor
@Test func aSchedaWithNoFolderIsClassifiedByTheSameRuleAndKeepsItsContenitoreKeys() async throws {
    let vault = try TemporaryVault()
    _ = try seedScheda(in: vault)
    let session = await openSession(vault)

    let outcome = try await session.classifyNote(at: scheda, topics: [tag("topic-fatture")], toFolder: nil)

    #expect(outcome.movedTo == nil)
    #expect(tags(of: outcome.written.text) == ["type-note", "topic-fatture"])
    #expect(outcome.written.text.contains("pergamenum-contenitore"))
}

// MARK: - extractToNote

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

private func range(of fragment: String, in text: String = source) -> NSRange {
    (text as NSString).range(of: fragment)
}

private func extract(
    _ session: VaultSession, _ fragment: String, expected: String? = nil, title: String = "Estratto",
    in folder: String = "02 Estratti"
) async throws -> VaultSession.ExtractOutcome {
    try await session.extractToNote(
        from: "Fonte.md", range: range(of: fragment), expectedText: expected ?? fragment,
        title: title, in: folder, topics: [tag("topic-b")], date: today
    )
}

@MainActor
@Test func extractingCreatesTheNoteWithTheSelectionAndReplacesItWithTheLink() async throws {
    let vault = try TemporaryVault()
    try vault.write(source, to: "Fonte.md")
    let session = await openSession(vault)
    let recorder = ChangeRecorder(session)

    let outcome = try await extract(session, "Due")

    #expect(outcome.created.path == "02 Estratti/Estratto.md")
    #expect(NoteDocument.parse(outcome.created.text).body.contains("Due"))
    #expect(tags(of: outcome.created.text).contains("topic-b"))
    guard case .replaced(let replaced) = outcome.source else {
        Issue.record("expected the source to be replaced, got \(outcome.source)")
        return
    }
    #expect(replaced.path == "Fonte.md")
    #expect(replaced.text == source.replacingOccurrences(of: "Due", with: "[[Estratto]]"))
    #expect(try disk("Fonte.md", in: vault.root) == replaced.text)
    // The source frontmatter is byte-identical by construction.
    #expect(replaced.text.hasPrefix("---\ndate: 2026-10-01\ntags:\n  - type-note\n  - topic-a\n---\n"))
    #expect(recorder.writtenPaths == ["02 Estratti/Estratto.md", "Fonte.md"])
}

@MainActor
@Test func aTakenTitleThrowsAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(source, to: "Fonte.md")
    try vault.write("---\ndate: 2026-10-01\ntags:\n  - type-note\n  - topic-a\n---\n\nGià qui.\n", to: "02 Estratti/Estratto.md")
    let session = await openSession(vault)
    let recorder = ChangeRecorder(session)

    await #expect(throws: VaultSession.CreationError.self) {
        try await extract(session, "Due")
    }

    #expect(try disk("Fonte.md", in: vault.root) == source)
    #expect(recorder.changes.isEmpty)
}

@MainActor
@Test func aSelectionThatIsNotWhatTheCallerSawThrowsAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(source, to: "Fonte.md")
    let session = await openSession(vault)
    let recorder = ChangeRecorder(session)

    await #expect(throws: NoteExtraction.Refusal.textChanged) {
        try await extract(session, "Due", expected: "Altro")
    }

    #expect(try disk("Fonte.md", in: vault.root) == source)
    #expect(!existsOnDisk("02 Estratti/Estratto.md", in: vault.root))
    #expect(recorder.changes.isEmpty)
}

@MainActor
@Test func aRangeInTheFrontmatterIsRefusedAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(source, to: "Fonte.md")
    let session = await openSession(vault)
    let recorder = ChangeRecorder(session)

    await #expect(throws: NoteExtraction.Refusal.touchesFrontmatter) {
        try await extract(session, "topic-a")
    }

    #expect(try disk("Fonte.md", in: vault.root) == source)
    #expect(!existsOnDisk("02 Estratti/Estratto.md", in: vault.root))
    #expect(recorder.changes.isEmpty)
}

@MainActor
@Test func aRefusedSecondWriteKeepsTheNewNoteAndNamesTheRefusal() async throws {
    let vault = try TemporaryVault()
    try vault.write(source, to: "Fonte.md")
    let session = await openSession(vault)
    // Deterministic, no timing: the moment the new note has landed, another writer changes the
    // source, so the second write's `expecting:` no longer matches (ADR-0046 §D11).
    let sourceURL = vault.root.appending(path: "Fonte.md", directoryHint: .notDirectory)
    let moved = source + "\n\nQuarto\n"
    session.landedChangeSubscriber = { change in
        if case .written(let result, _) = change, result.path == "02 Estratti/Estratto.md" {
            try? Data(moved.utf8).write(to: sourceURL)
        }
    }

    let outcome = try await extract(session, "Due")

    guard case .refused(let sentence) = outcome.source else {
        Issue.record("expected the second write to be refused, got \(outcome.source)")
        return
    }
    #expect(!sentence.isEmpty)
    #expect(try disk("02 Estratti/Estratto.md", in: vault.root) == outcome.created.text)
    // The other writer's text is intact: nothing was clobbered.
    #expect(try disk("Fonte.md", in: vault.root) == moved)
}

@MainActor
@Test func aSecondWriteThatFailsOnDiskIsRefusedWithTheNewNoteKept() async throws {
    let vault = try TemporaryVault()
    try vault.write(source, to: "Fonte.md")
    let session = await openSession(vault)
    // The session has read the source (its folder is the vault root, which stays writable for the
    // new note in `02 Estratti`); the source's own folder then refuses a new file, so the replace
    // fails. Permissions are restored in `defer` (ADR-0046 §D11: deterministic, no timing).
    let root = vault.root
    session.landedChangeSubscriber = { change in
        if case .written(let result, _) = change, result.path == "02 Estratti/Estratto.md" {
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        }
    }
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }

    let outcome = try await extract(session, "Due")

    guard case .refused(let sentence) = outcome.source else {
        Issue.record("expected the second write to be refused, got \(outcome.source)")
        return
    }
    #expect(!sentence.isEmpty)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
    #expect(existsOnDisk("02 Estratti/Estratto.md", in: root))
    #expect(try disk("Fonte.md", in: root) == source)
}

// MARK: - dailyNoteBirth

private let dailyTemplate = """
---
date: 2026-01-01
tags:
  - type-note
  - topic-modello
---

# {{title}}

Data {{date}}, ora {{time}}.

{{cursor}}
"""

/// 09:05 on 2026-10-12 in the machine's own calendar, which is the one the door reads.
private var nineOhFive: Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9, minute: 5))!
}

private let bareDay = "---\ndate: 2026-10-12\ntags:\n  - type-note\n---\n\n"

@MainActor
@Test func withNoSettingTheDayIsBornWithTodaysBytes() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)

    let birth = try await session.dailyNoteBirth(for: today, at: nineOhFive)

    #expect(birth == VaultSession.DailyNoteBirth(path: session.dailyNotePath(for: today), created: true, caret: nil))
    #expect(try disk(birth.path, in: vault.root) == bareDay)
}

@MainActor
@Test func aSettingMakesTheDayFromTheTemplateResolvedAtTheInjectedTime() async throws {
    let vault = try TemporaryVault()
    try vault.write(dailyTemplate, to: "Templates/Giorno.md")
    let session = await openSession(vault)
    session.updateSettings { $0.dailyTemplate = "Templates/Giorno.md" }

    let birth = try await session.dailyNoteBirth(for: today, at: nineOhFive)

    let expected = bareDay + "# 20261012\n\nData 2026-10-12, ora 09:05.\n\n"
    #expect(birth.created)
    #expect(try disk(birth.path, in: vault.root) == expected)
    #expect(birth.caret == expected.utf16.count)
    // The template's own frontmatter never travels.
    #expect(!expected.contains("topic-modello"))
}

@MainActor
@Test func anExistingDayIsReturnedUntouchedWithNoCaret() async throws {
    let vault = try TemporaryVault()
    try vault.write(dailyTemplate, to: "Templates/Giorno.md")
    let existing = bareDay + "Già scritto.\n"
    try vault.write(existing, to: "Calendar/20261012.md")
    let session = await openSession(vault)
    session.updateSettings { $0.dailyTemplate = "Templates/Giorno.md" }

    let birth = try await session.dailyNoteBirth(for: today, at: nineOhFive)

    #expect(birth == VaultSession.DailyNoteBirth(path: "Calendar/20261012.md", created: false, caret: nil))
    #expect(try disk("Calendar/20261012.md", in: vault.root) == existing)
}

@MainActor
@Test func aTemplateThatIsMissingCreatesTheBareDayAndRecordsAProblem() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    session.updateSettings { $0.dailyTemplate = "Templates/Assente.md" }

    let birth = try await session.dailyNoteBirth(for: today, at: nineOhFive)

    #expect(birth.created)
    #expect(birth.caret == nil)
    #expect(try disk(birth.path, in: vault.root) == bareDay)
    #expect(!session.problems.isEmpty)
}

@MainActor
@Test func aSettingOutsideTheTemplatesFolderIsIgnoredWithAProblem() async throws {
    let vault = try TemporaryVault()
    try vault.write(dailyTemplate, to: "Altrove/Giorno.md")
    let session = await openSession(vault)
    session.updateSettings { $0.dailyTemplate = "Altrove/Giorno.md" }

    let birth = try await session.dailyNoteBirth(for: today, at: nineOhFive)

    #expect(birth.created)
    #expect(birth.caret == nil)
    #expect(try disk(birth.path, in: vault.root) == bareDay)
    #expect(!session.problems.isEmpty)
}

@MainActor
@Test func anEmptySettingMeansNoTemplateAndRecordsNoProblem() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    session.updateSettings { $0.dailyTemplate = "" }
    // `openSession` gives the session no bundled vocabulary, so it opens already holding the
    // «nessun vocabolario» warning; the claim is that the birth adds nothing to what was there.
    let before = session.problems

    let birth = try await session.dailyNoteBirth(for: today, at: nineOhFive)

    #expect(birth.created)
    #expect(try disk(birth.path, in: vault.root) == bareDay)
    #expect(session.problems == before)
    #expect(!session.problems.contains { $0.contains("modello della nota del giorno") })
}

@MainActor
@Test func dailyNoteForKeepsItsSignatureReturnsTheSamePathAndInheritsTheTemplate() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ntags:\n  - type-note\n---\n\n# {{title}}\n\nDal modello.\n", to: "Templates/Giorno.md")
    let session = await openSession(vault)
    session.updateSettings { $0.dailyTemplate = "Templates/Giorno.md" }

    let path = try await session.dailyNote(for: today)

    #expect(path == session.dailyNotePath(for: today))
    #expect(try disk(path, in: vault.root) == bareDay + "# 20261012\n\nDal modello.\n")
    // And reopening it is the same path, created once.
    let again = try await session.dailyNoteBirth(for: today, at: nineOhFive)
    #expect(again == VaultSession.DailyNoteBirth(path: path, created: false, caret: nil))
}

// MARK: - VaultSettings.dailyTemplate

@Test func anAbsentDailyTemplateDecodesAsNil() throws {
    let settings = try JSONDecoder().decode(VaultSettings.self, from: Data(#"{"dailyFolder": "Calendar"}"#.utf8))

    #expect(settings.dailyTemplate == nil)
    #expect(VaultSettings.default.dailyTemplate == nil)
}

@Test func aPresentDailyTemplateRoundTripsThroughTheCodable() throws {
    var settings = VaultSettings.default
    settings.dailyTemplate = "Templates/Giorno.md"

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(VaultSettings.self, from: data)

    #expect(decoded.dailyTemplate == "Templates/Giorno.md")
    #expect(decoded == settings)
}

@MainActor
@Test func theDailyTemplateSurvivesThroughSettingsJSON() throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)

    session.updateSettings { $0.dailyTemplate = "Templates/Giorno.md" }

    #expect(VaultSession.readSettings(in: vault.root).settings.dailyTemplate == "Templates/Giorno.md")
}
