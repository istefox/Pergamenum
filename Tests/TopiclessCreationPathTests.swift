import Foundation
import Testing
@testable import Pergamenum

// PG-384 (N1 seams), ADR-0080 §D1 and §D2: a note born with no `topic-*` is a capture on every
// creation path, lints clean the day it is born, and the notes that already carried
// `status-inbox` (or none, for the daily) are byte-identical to what they were.
//
// `TopiclessNoteRuleTests` pins the rule on `TagRules.initialTags`; this file pins that the
// paths a person and a model reach actually go through it. The vocabulary is the bundled one,
// the way `CategoryLintTests` loads it: without it the linter has nothing to judge against
// and a clean verdict means less than it looks (`ConnectorTests.aVaultWithoutItsVocabularies…`).

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

private let day = CalendarDate(iso: "2026-08-18")!

private func tags(in text: String) -> [String] {
    NoteDocument.parse(text).frontmatter.tags.map(\.description)
}

private func onDisk(_ vault: borrowing TemporaryVault, _ path: String) throws -> String {
    try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
}

/// What the linter says about `path`, both through the session and through the door
/// `perg lint` and the MCP `lint` tool share.
@MainActor
private func expectLintsClean(_ session: VaultSession, _ path: String) throws {
    let violations = try #require(session.violations(forRecordAt: path))
    #expect(violations.isEmpty, "\(path): \(violations)")

    let report = try VaultAPI.lint(session, at: path)
    #expect(report.warning == nil, "senza vocabolario il verdetto non vale")
    #expect(report.checked == 1)
    #expect(report.findings.isEmpty, "\(path): \(report.findings)")
}

// MARK: - Creation paths (R-01, R-02)

// (n1-seams R-01, R-02)
@MainActor
@Test func aTopiclessNoteCreatedThroughTheSessionIsACaptureAndLintsClean() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)

    let path = try await session.createNote(title: "Nota senza topic", date: day).path

    let written = tags(in: try onDisk(vault, path))
    #expect(written == ["type-note", "status-inbox"])
    try expectLintsClean(session, path)
}

// (n1-seams R-01, R-02)
@MainActor
@Test func aTopiclessNoteCreatedThroughTheControllerIsACaptureAndLintsClean() async throws {
    // The door the Cmd+N composer, Quick Open and the «Documento» sheet share.
    let vault = try TemporaryVault()
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }
    let session = try #require(controller.session)

    let path = try await controller.createNote(title: "Nota dal compositore", date: day)

    let written = tags(in: try onDisk(vault, path))
    #expect(written == ["type-note", "status-inbox"])
    #expect(
        controller.violations(forRecordAt: path)?.isEmpty == true,
        "\(String(describing: controller.violations(forRecordAt: path)))"
    )
    try expectLintsClean(session, path)
}

// (n1-seams R-01, R-02)
@MainActor
@Test func aTopiclessNoteCreatedThroughTheConnectorsIsACaptureAndLintsClean() async throws {
    // `perg note create` and the MCP `create_note` tool both call `VaultAPI.createNote`.
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    VaultAPI.arm(session, command: "create_note", dryRun: false)

    let summary = try await VaultAPI.createNote(
        session, title: "Nota dal connettore", folder: nil, topic: nil, date: "2026-08-18"
    )

    #expect(summary.applied)
    let written = tags(in: try onDisk(vault, summary.path))
    #expect(written == ["type-note", "status-inbox"])
    try expectLintsClean(session, summary.path)
}

// (n1-seams R-01, R-02)
@MainActor
@Test func aNoteCapturedAsANewNoteIsACaptureAndLintsClean() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let summary = try await VaultAPI.capture(
        session, to: .newNote(folder: nil), text: "Appunto senza argomento\nCorpo."
    )

    let written = tags(in: try onDisk(vault, summary.path))
    #expect(written == ["type-note", "status-inbox"])
    try expectLintsClean(session, summary.path)
}

// MARK: - The topic case (R-01)

private let praticaFolder = "01 Progetti/Rossi/Offerta"

private let minimalPraticaNote = """
---
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
---

Appunti pratica.
"""

private let praticaMessage = """
---
date: 2026-06-10
tags:
  - type-note
  - type-email
pergamenum-mail: 1
pergamenum-mail-message-id: "<abc@rossi-spa.it>"
pergamenum-mail-direction: received
pergamenum-mail-date: 2026-06-10T14:06:00+02:00
pergamenum-mail-from: "Mario Rossi <m.rossi@rossi-spa.it>"
pergamenum-mail-subject: "Richiesta offerta"
pergamenum-mail-body: complete
---

Buongiorno,
"""

// (n1-seams R-01)
@MainActor
@Test func aPraticaNoteCreatedAndLinkedKeepsItsTopicAndGainsNoStatusInbox() async throws {
    let vault = try TemporaryVault()
    try vault.write(minimalPraticaNote, to: "\(praticaFolder)/pratica.md")
    try vault.write(praticaMessage, to: "\(praticaFolder)/email/msg.md")
    let session = await openSession(vault)
    VaultAPI.arm(session, command: "pratica_create_note", dryRun: false)

    _ = try await VaultAPI.createAndLinkPraticaNote(
        session, pratica: praticaFolder, title: "Preventivo 2026", folder: nil
    )

    let written = tags(in: try onDisk(vault, "Preventivo 2026.md"))
    #expect(written.contains("topic-pratica"))
    #expect(!written.contains("status-inbox"))
}

// (n1-seams R-01)
@MainActor
@Test func aNoteCreatedWithStatusInboxAsItsTopicIsBornOnceAndLintsClean() async throws {
    // `--topic status-inbox` reaches `initialTags` as a topic: the status must not be doubled.
    let vault = try TemporaryVault()
    let session = await openSession(vault)

    let path = try await session.createNote(
        title: "Topic inbox", date: day, topics: [Tag("status-inbox")!]
    ).path

    let written = tags(in: try onDisk(vault, path))
    #expect(written == ["type-note", "status-inbox"])
    try expectLintsClean(session, path)
}

// (n1-seams R-01)
@MainActor
@Test func aNoteCreatedWithATopicIsNotACaptureOnAnyDoor() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    VaultAPI.arm(session, command: "create_note", dryRun: false)

    let viaSession = try await session.createNote(
        title: "Con topic", date: day, topics: [Tag("topic-acustica")!]
    ).path
    let viaConnector = try await VaultAPI.createNote(
        session, title: "Con topic connettore", folder: nil, topic: "topic-acustica", date: "2026-08-18"
    ).path

    let writtenBySession = tags(in: try onDisk(vault, viaSession))
    #expect(writtenBySession == ["type-note", "topic-acustica"])
    let writtenByConnector = tags(in: try onDisk(vault, viaConnector))
    #expect(writtenByConnector == ["type-note", "topic-acustica"])
}

// MARK: - The MCP diff (R-02)

// (n1-seams R-02)
@MainActor
@Test func theDryRunDiffOfATopiclessCreateShowsTheAddedTag() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    VaultAPI.arm(session, command: "create_note", dryRun: true)

    let summary = try await VaultAPI.createNote(
        session, title: "Solo una prova", folder: nil, topic: nil, date: "2026-08-18"
    )

    #expect(!summary.applied)
    let diff = try #require(summary.diff)
    #expect(diff.contains("+  - status-inbox"), "il diff non mostra il tag aggiunto:\n\(diff)")
    #expect(diff.contains("+  - type-note"))
    #expect(!session.exists(summary.path), "una prova non deve scrivere")
}

// MARK: - Byte pins, green before and after (R-02)

// (n1-seams R-02)
@MainActor
@Test func theDailyNoteIsByteIdenticalToToday() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)

    let path = try await session.dailyNote(for: day)

    #expect(try onDisk(vault, path) == "---\ndate: 2026-08-18\ntags:\n  - type-note\n---\n\n")
}

// (n1-seams R-02)
@MainActor
@Test func theEventNoteIsByteIdenticalToToday() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    let thursday = CalendarDate(iso: "2026-08-20")!

    let created = try #require(await session.eventNote(for: "Riunione tecnica", on: thursday))

    let expected = "---\ndate: 2026-08-20\ntags:\n  - type-note\n  - status-inbox\n---\n\n"
        + EventNote.body(eventTitle: "Riunione tecnica", start: nil, end: nil, attendees: [], day: thursday)
    #expect(try onDisk(vault, created.path) == expected)
}

// (n1-seams R-02)
@Test func theContenitoreSchedaIsByteIdenticalToToday() {
    let text = ContenitoreScheda.render(
        date: CalendarDate(iso: "2026-09-29")!,
        fileName: "20260929 a.pdf",
        originalName: "a.pdf",
        sha256: String(repeating: "ab", count: 32)
    )

    #expect(text.hasPrefix("---\ndate: 2026-09-29\ntags:\n  - type-note\n  - status-inbox\n"))
    #expect(text.components(separatedBy: "status-inbox").count == 2, "una sola volta")
    #expect(text.hasSuffix("---\n"))
}

// (n1-seams R-02)
@MainActor
@Test func theInboxTaskNoteIsByteIdenticalToToday() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)

    let result = try #require(await session.captureTask(VaultSession.TaskDraft(text: "Un task")))

    // The date line is today's, so the pin starts at `tags:`.
    #expect(result.text.hasPrefix("---\ndate: "))
    #expect(result.text.contains("\ntags:\n  - type-note\n  - status-inbox\n---\n\n- [ ] Un task"))
    #expect(tags(in: result.text) == ["type-note", "status-inbox"])
}
