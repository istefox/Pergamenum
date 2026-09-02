import Foundation
import Testing
@testable import Pergamenum

// The one write a view makes (ADR-0009 §D5): a card dragged between two columns of a board.

private typealias VaultTag = Pergamenum.Tag

private func tag(_ raw: String) throws -> VaultTag {
    try #require(VaultTag(raw))
}

// MARK: - Il testo che il drop lascia

@Test func aDropBetweenTwoColumnsRenamesTheTag() throws {
    let text = "---\ndate: 2026-08-19\ntags:\n  - type-note\n  - topic-gomma\n---\n\nCorpo.\n"

    let rewritten = try #require(
        TagRename.move(from: try tag("topic-gomma"), to: try tag("topic-fune"), in: text)
    )

    #expect(rewritten.contains("  - topic-fune"))
    #expect(!rewritten.contains("topic-gomma"))
}

/// Dragging out of *Senza stato* adds, which is the case a rename cannot express.
@Test func aDropOutOfSenzaStatoAddsTheTagInItsOrderedPlace() throws {
    let text = "---\ndate: 2026-08-19\ntags:\n  - type-note\n  - topic-gomma\n---\n\nCorpo.\n"

    let rewritten = try #require(TagRename.move(from: nil, to: try tag("client-nexion"), in: text))

    // F-04 orders tags by namespace: `client` comes before `type` and `topic`.
    let lines = rewritten.components(separatedBy: "\n")
    #expect(lines[3] == "  - client-nexion")
    #expect(lines[4] == "  - type-note")
}

/// Dragging into it removes, which is what makes that column the only way to take a tag off a
/// note with a gesture.
@Test func aDropIntoSenzaStatoRemovesTheTag() throws {
    let text = "---\ndate: 2026-08-19\ntags:\n  - type-note\n  - status-inbox\n---\n\nCorpo.\n"

    let rewritten = try #require(TagRename.move(from: try tag("status-inbox"), to: nil, in: text))

    #expect(!rewritten.contains("status-inbox"))
    #expect(rewritten.contains("  - type-note"))
    #expect(rewritten.contains("tags:"))
}

/// A `tags:` key with nothing under it is a violation of its own, so the last tag takes the key.
@Test func removingTheOnlyTagTakesTheKeyWithIt() throws {
    let text = "---\ndate: 2026-08-19\ntags:\n  - status-inbox\n---\n\nCorpo.\n"

    let rewritten = try #require(TagRename.move(from: try tag("status-inbox"), to: nil, in: text))

    #expect(!rewritten.contains("tags:"))
    #expect(rewritten.contains("date: 2026-08-19"))
}

@Test func aNoteWithNoTagsKeyGetsOneAfterTheDate() throws {
    let text = "---\ndate: 2026-08-19\n---\n\nCorpo.\n"

    let rewritten = try #require(TagRename.move(from: nil, to: try tag("type-note"), in: text))

    #expect(rewritten.hasPrefix("---\ndate: 2026-08-19\ntags:\n  - type-note\n---"))
}

/// The inline form is refused rather than turned into a block list: that would be a conformance
/// edit arriving on the back of a drag.
@Test func anInlineTagListRefusesAnAddition() throws {
    let text = "---\ndate: 2026-08-19\ntags: [type-note]\n---\n\nCorpo.\n"

    #expect(TagRename.move(from: nil, to: try tag("topic-gomma"), in: text) == nil)
}

@Test func aTagAlreadyThereChangesNothing() throws {
    let text = "---\ntags:\n  - type-note\n---\n\nCorpo.\n"

    #expect(TagRename.move(from: nil, to: try tag("type-note"), in: text) == text)
}

// MARK: - Il payload del trascinamento

@Test func theDragPayloadCarriesTheColumnTheCardIsLeaving() throws {
    let payload = BoardDragPayload(path: "Clienti/Vibrofer.md", column: "status-active")
    let parsed = try #require(BoardDragPayload(text: payload.text))

    #expect(parsed.path == "Clienti/Vibrofer.md")
    #expect(parsed.column == "status-active")
}

@Test func aCardInSenzaStatoCarriesNoColumn() throws {
    let parsed = try #require(BoardDragPayload(text: BoardDragPayload(path: "Uno.md", column: nil).text))

    #expect(parsed.path == "Uno.md")
    #expect(parsed.column == nil)
}

// MARK: - La scrittura, con il suo guardrail

private func note(tags: [String]) -> String {
    "---\ndate: 2026-08-19\ntags:\n" + tags.map { "  - \($0)\n" }.joined() + "---\n\nCorpo.\n"
}

@MainActor
private func session(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(note(tags: ["type-note", "topic-gomma"]), to: "Uno.md")
    try vault.write(note(tags: ["type-note", "topic-gomma", "project-presse"]), to: "Due.md")
    let session = VaultSession(
        root: vault.root,
        stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()
    return session
}

@MainActor
@Test func aDropWritesTheNoteAndJournalsIt() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let outcome = session.moveOnBoard("Due.md", from: try tag("project-presse"), to: try tag("project-forni"))

    #expect(outcome.didWrite)
    #expect(outcome.introduced.isEmpty)
    #expect(outcome.problem == nil)
    #expect(try session.read("Due.md").text.contains("  - project-forni"))
    // Armed for this write and disarmed after it: ordinary editing keeps no undo log beside
    // the file (ADR-0007 §D6, narrowed by ADR-0012 D7 and again here).
    #expect(session.journal == nil)
}

@MainActor
@Test func aDropIsUndoneThroughTheJournal() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let before = try session.read("Due.md").text
    let outcome = session.moveOnBoard("Due.md", from: try tag("project-presse"), to: try tag("project-forni"))

    let undone = session.undoJournalledWrites([try #require(outcome.journalID)])

    #expect(undone.failures.isEmpty)
    #expect(try session.read("Due.md").text == before)
}

/// The guard that narrows §D5: the whole tag linter rather than the vocabulary table alone.
/// `status-final` on a note is refused by tag.md 5.1 (reserved for a Deliverable export,
/// naming.md 6.1) whatever the vocabulary says, and a gesture must not write what `perg lint`
/// then reports.
@MainActor
@Test func aDropThatWouldBreakTheTagRulesIsRefusedWithTheReason() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let outcome = session.moveOnBoard("Uno.md", from: nil, to: try tag("status-final"))

    #expect(!outcome.didWrite)
    #expect(outcome.introduced.contains(.statusNotAllowedOnNote(try tag("status-final"))))
    // Refused means untouched, not written and flagged afterwards.
    #expect(try session.read("Uno.md").text == note(tags: ["type-note", "topic-gomma"]))
}

/// tag.md 1.5: a note board grouped by `status-*` can now actually move a card between the
/// non-`final` columns (M11's own acceptance criterion, PG-030) - the drop is no longer refused
/// just because the destination is a status other than `inbox`.
@MainActor
@Test func aDropToANonFinalStatusIsAllowedOnANote() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let outcome = session.moveOnBoard("Uno.md", from: nil, to: try tag("status-active"))

    #expect(outcome.didWrite)
    #expect(outcome.introduced.isEmpty)
    #expect(try session.read("Uno.md").text.contains("  - status-active"))
}

/// Differential, not absolute: a note that was already non-conformant stays draggable, or the
/// board that showed the problem would be the one place unable to do anything about it.
@MainActor
@Test func aNoteAlreadyNonConformantIsStillMoved() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(tags: ["project-presse"]), to: "Tre.md")
    let session = try await session(vault)

    // `Tre.md` has no `type-note` and no `topic-*`: two violations before the drop, and the
    // same two after it.
    let outcome = session.moveOnBoard("Tre.md", from: try tag("project-presse"), to: try tag("project-forni"))

    #expect(outcome.didWrite)
    #expect(try session.read("Tre.md").text.contains("  - project-forni"))
}

@MainActor
@Test func droppingACardBackWhereItCameFromWritesNothing() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let outcome = session.moveOnBoard("Due.md", from: try tag("project-presse"), to: try tag("project-presse"))

    #expect(!outcome.didWrite)
    #expect(outcome.problem == nil)
}
