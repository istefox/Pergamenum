import Foundation
import Testing
@testable import Pergamenum

// Renaming a tag across the vault (ADR-0012 D7): the surgical rewrite of one note's tag lines,
// and the journalled group of writes that applies it to all of them.

private typealias VaultTag = Pergamenum.Tag

private func tag(_ raw: String) throws -> VaultTag {
    try #require(VaultTag(raw))
}

// MARK: One note's text

@Test func aTagInABlockListIsRenamedInPlace() throws {
    let text = """
    ---
    date: 2026-08-19
    tags:
      - type-note
      - topic-gomma
    ---

    Corpo.
    """

    let rewritten = try #require(TagRename.apply(try tag("topic-gomma"), to: try tag("topic-gomma-metallo"), in: text))

    #expect(rewritten.contains("  - topic-gomma-metallo"))
    #expect(rewritten.contains("  - type-note"))
    #expect(rewritten.hasSuffix("\n\nCorpo."))
}

@Test func theInlineFormIsRenamedToo() throws {
    let text = "---\ndate: 2026-08-19\ntags: [topic-gomma, client-nexion]\n---\n\nCorpo.\n"

    let rewritten = try #require(TagRename.apply(try tag("topic-gomma"), to: try tag("topic-fune"), in: text))

    #expect(rewritten.contains("tags: [topic-fune, client-nexion]"))
}

@Test func aLongerTagStartingWithTheSameWordsIsLeftAlone() throws {
    let text = "---\ntags:\n  - topic-gomma-metallo\n---\n\nCorpo.\n"

    // `topic-gomma` is not a prefix of a tag, it is a different tag.
    #expect(TagRename.apply(try tag("topic-gomma"), to: try tag("topic-fune"), in: text) == nil)
}

@Test func theBodyIsNeverTouched() throws {
    let text = "---\ntags:\n  - topic-gomma\n---\n\nQui si parla di topic-gomma nel corpo.\n"

    let rewritten = try #require(TagRename.apply(try tag("topic-gomma"), to: try tag("topic-fune"), in: text))

    #expect(rewritten.contains("  - topic-fune"))
    // The frontmatter is the schema; the body is prose, and rewriting prose is not this
    // command's business.
    #expect(rewritten.contains("di topic-gomma nel corpo"))
}

@Test func aNoteWithoutTheTagIsNotAWrite() throws {
    let text = "---\ntags:\n  - type-note\n---\n\nCorpo.\n"

    // Nil rather than the same text back: the caller skips it instead of writing an identical
    // file, which would put a pointless entry in the journal and a snapshot in the history.
    #expect(TagRename.apply(try tag("topic-gomma"), to: try tag("topic-fune"), in: text) == nil)
}

@Test func aNoteWithNoFrontmatterBlockIsLeftAlone() throws {
    let text = "# Titolo\n\ntopic-gomma nel testo.\n"

    #expect(TagRename.apply(try tag("topic-gomma"), to: try tag("topic-fune"), in: text) == nil)
}

@Test func aKeyAfterTheTagsEndsTheList() throws {
    let text = "---\ntags:\n  - topic-gomma\nrelated:\n  - \"[[topic-gomma]]\"\n---\n\nCorpo.\n"

    let rewritten = try #require(TagRename.apply(try tag("topic-gomma"), to: try tag("topic-fune"), in: text))

    #expect(rewritten.contains("  - topic-fune"))
    // `related` is a list of note titles, not of tags: a title that happens to read like a tag
    // is still a title.
    #expect(rewritten.contains("\"[[topic-gomma]]\""))
}

// MARK: The whole vault

private func note(tags: [String], body: String = "Corpo.") -> String {
    "---\ndate: 2026-08-19\ntags:\n" + tags.map { "  - \($0)\n" }.joined() + "---\n\n\(body)\n"
}

@MainActor
private func session(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(note(tags: ["type-note", "topic-gomma"]), to: "Uno.md")
    try vault.write(note(tags: ["type-note", "topic-gomma", "client-nexion"]), to: "Due.md")
    try vault.write(note(tags: ["type-note", "topic-gomma-metallo"]), to: "Tre.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

@MainActor
@Test func thePreviewNamesEveryNoteCarryingTheTagAndNoOther() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let changes = session.tagRenamePreview(try tag("topic-gomma"), to: try tag("topic-fune"))

    #expect(changes.map(\.path) == ["Due.md", "Uno.md"])
    #expect(changes.allSatisfy { $0.after.contains("topic-fune") })
    // Computed, not written: the files on disk still say what they said.
    #expect(try session.read("Uno.md").text.contains("topic-gomma"))
}

@MainActor
@Test func renamingWritesEveryNoteAndJournalsEachWrite() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let outcome = await session.renameTag(try tag("topic-gomma"), to: try tag("topic-fune"))

    #expect(outcome.changed.sorted() == ["Due.md", "Uno.md"])
    #expect(outcome.failures.isEmpty)
    #expect(outcome.journalIDs.count == 2)
    #expect(try session.read("Uno.md").text.contains("  - topic-fune"))
    #expect(try session.read("Tre.md").text.contains("  - topic-gomma-metallo"))
    // The journal is armed for the operation and disarmed after it: ordinary editing in the app
    // still keeps no undo log beside the file (ADR-0007 §D6, narrowed by ADR-0012 D7).
    #expect(session.journal == nil)
}

@MainActor
@Test func undoingTheGroupPutsEveryNoteBack() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let before = try session.read("Due.md").text
    let outcome = await session.renameTag(try tag("topic-gomma"), to: try tag("topic-fune"))

    let undone = await session.undoJournalledWrites(outcome.journalIDs)

    #expect(undone.changed.count == 2)
    #expect(undone.failures.isEmpty)
    #expect(try session.read("Due.md").text == before)
    #expect(try session.read("Uno.md").text.contains("  - topic-gomma"))
}

@MainActor
@Test func aNoteEditedAfterTheRenameMakesTheWholeUndoRefuse() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let outcome = await session.renameTag(try tag("topic-gomma"), to: try tag("topic-fune"))

    // Somebody, or something, writes over one of them afterwards.
    // ADR-0041 Task 8: `VaultSession.write` gained an async overload.
    try await session.write(note(tags: ["type-note", "topic-fune"], body: "Riscritta a mano."), to: "Due.md")

    let undone = await session.undoJournalledWrites(outcome.journalIDs)

    // All-or-nothing (ADR-0016 §D5): one note that moved on refuses the whole group rather than
    // restoring eleven of twelve and reporting the twelfth.
    #expect(undone.changed.isEmpty)
    #expect(undone.failures.contains { $0.contains("Due.md") })
    // Uno.md is not touched either, even though nothing changed under it.
    #expect(try session.read("Uno.md").text.contains("topic-fune"))
    // The later edit survives: undoing onto it would destroy work the journal knows nothing of.
    #expect(try session.read("Due.md").text.contains("Riscritta a mano."))
}

@MainActor
@Test func renamingATagNobodyUsesChangesNothing() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let outcome = await session.renameTag(try tag("topic-ceramica"), to: try tag("topic-fune"))

    #expect(outcome.changed.isEmpty)
    #expect(outcome.journalIDs.isEmpty)
    #expect(outcome.failures.isEmpty)
}

// MARK: - Task 3 (R-01, R-02, R-04, R-05, R-08): the batch-scope write guard

@MainActor
@Test func aNoteWhoseBytesMovedOnIsRefusedWhileTheOthersAreStillWritten() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    // Deliberately disagrees with what is on disk for "Due.md" only - the acceptance test
    // ADR-0046 §D11 asks for, driven straight at the writer seam rather than through
    // `renameTag`'s own fresh preview (which cannot be made stale in-process, ADR-0046 §D2's
    // own Context).
    let changes = [
        VaultFileChange(path: "Uno.md", before: try session.read("Uno.md").text, after: "Uno riscritta."),
        VaultFileChange(path: "Due.md", before: "questo prima non c'era", after: "Non deve arrivare."),
        VaultFileChange(path: "Tre.md", before: try session.read("Tre.md").text, after: "Tre riscritta."),
    ]
    let dueBefore = try session.read("Due.md").text

    let outcome = await VaultPlanApplication.apply(changes, writing: session.writeGuarded)

    #expect(outcome.rewrittenPaths.sorted() == ["Tre.md", "Uno.md"])
    #expect(outcome.refusals == ["Due.md"])
    #expect(outcome.failures.isEmpty)
    #expect(try session.read("Uno.md").text == "Uno riscritta.")
    #expect(try session.read("Tre.md").text == "Tre riscritta.")
    // The refused note keeps its own bytes, untouched.
    #expect(try session.read("Due.md").text == dueBefore)
}

@MainActor
@Test func renameTagEndToEndWithNothingConcurrentLeavesRefusalsEmpty() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let outcome = await session.renameTag(try tag("topic-gomma"), to: try tag("topic-fune"))

    #expect(outcome.changed.sorted() == ["Due.md", "Uno.md"])
    #expect(outcome.failures.isEmpty)
    #expect(outcome.refusals.isEmpty)
    #expect(outcome.journalIDs.count == 2)
}

@MainActor
@Test func aNoteDeletedBetweenThePreviewAndTheWriteIsRefusedNotRecreated() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    // "Sparita.md" is in the plan (its `before` was read while the file still existed) but is
    // gone by the time the writer runs - `VaultDisk.write`'s `hashBefore` reads `nil`, which
    // never equals a non-nil `expecting` (§D8).
    let changes = [
        VaultFileChange(path: "Sparita.md", before: "testo che c'era", after: "Non deve tornare."),
    ]

    let outcome = await VaultPlanApplication.apply(changes, writing: session.writeGuarded)

    #expect(outcome.refusals == ["Sparita.md"])
    #expect(outcome.rewrittenPaths.isEmpty)
    #expect(!session.exists("Sparita.md"))
}

@MainActor
@Test func theJournalHoldsNoEntryForARefusedPathSoUndoPutsBackOnlyWhatWasWritten() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    session.journal = session.journalOnDisk
    let entriesBefore = Set(session.journalOnDisk.entries().map(\.id))
    let changes = [
        VaultFileChange(path: "Uno.md", before: try session.read("Uno.md").text, after: "Uno riscritta."),
        VaultFileChange(path: "Due.md", before: "non è quello che c'è su disco", after: "Non deve arrivare."),
    ]

    let result = await VaultPlanApplication.apply(changes, writing: session.writeGuarded)
    let journalIDs = session.journalOnDisk.entries()
        .filter { !entriesBefore.contains($0.id) }
        .map(\.id)

    #expect(result.refusals == ["Due.md"])
    #expect(journalIDs.count == 1, "solo la scrittura riuscita deve finire nel journal")

    let undone = await session.undoJournalledWrites(journalIDs)

    #expect(undone.changed == ["Uno.md"])
    #expect(undone.failures.isEmpty)
    #expect(try session.read("Uno.md").text.contains("topic-gomma"))
}

// MARK: CRLF (ADR-0064 §D3, G1.3)

@Test func tagRenameReachesACRLFNote() throws {
    let text = FormatEdgeCorpus.crlfWithFrontmatter.text

    let rewritten = try #require(TagRename.apply(try tag("type-note"), to: try tag("type-verbale"), in: text))

    #expect(rewritten == text.replacingOccurrences(of: "type-note", with: "type-verbale"))
    #expect(rewritten.components(separatedBy: "\n").dropLast().allSatisfy { $0.hasSuffix("\r") })
}
