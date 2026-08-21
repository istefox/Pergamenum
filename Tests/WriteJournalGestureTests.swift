import Foundation
import Testing
@testable import Pergamenum

// The journal's gesture fields (ADR-0016 §D1, §D2). The claim worth pinning hardest is the one
// the ADR makes in passing - «no migration is written» - because it is true only for as long as
// every new field stays optional, and the failure mode is silent: `entries()` skips a line it
// cannot decode, so a journal written before this change would simply appear to be empty.

@MainActor
private func journal() throws -> (WriteJournal, URL) {
    let root = URL(filePath: NSTemporaryDirectory())
        .appending(path: "JournalTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (WriteJournal(root: root), root)
}

private func entry(
    id: String, path: String, operation: String? = nil,
    kind: WriteJournal.Kind? = nil, pathBefore: String? = nil
) -> WriteJournal.Entry {
    WriteJournal.Entry(
        id: id, timestamp: Date(timeIntervalSince1970: 1_755_000_000), path: path,
        hashBefore: "before", hashAfter: "after", textBefore: "il testo di prima",
        command: "note rename", operation: operation, kind: kind, pathBefore: pathBefore
    )
}

// MARK: - The line already on disk

@MainActor
@Test func aLineWrittenBeforeTheGestureFieldsStillReads() throws {
    let (journal, _) = try journal()
    try FileManager.default.createDirectory(at: journal.directory, withIntermediateDirectories: true)

    // Byte for byte the shape this app wrote until ADR-0016: no operation, no kind, no
    // pathBefore. A non-optional field would make this line undecodable, and `entries()` skips
    // what it cannot decode - so the whole safety net would go quiet rather than fail loudly.
    let old = """
    {"command":"note append","hashAfter":"aaa","hashBefore":"bbb",\
    "id":"20260820-101500-ab12","path":"Note/lavoro.md",\
    "textBefore":"prima","timestamp":"2026-08-20T10:15:00Z"}
    """
    try (old + "\n").write(
        to: journal.directory.appending(path: "journal.jsonl"), atomically: true, encoding: .utf8
    )

    let entries = journal.entries()
    #expect(entries.count == 1)
    #expect(entries.first?.id == "20260820-101500-ab12")
    #expect(entries.first?.operation == nil)
    #expect(entries.first?.pathBefore == nil)
    // Absent means a text replacement, which is what every entry written before ADR-0016 was.
    #expect(entries.first?.kind == .textReplacement)
}

// MARK: - The three kinds

@MainActor
@Test func aMoveAndARemovalSurviveTheRoundTrip() throws {
    let (journal, _) = try journal()
    journal.record(entry(
        id: "a", path: "Note/nuovo.md", operation: "op-1", kind: .move, pathBefore: "Note/vecchio.md"
    ))
    journal.record(entry(id: "b", path: "Note/andata.md", operation: "op-1", kind: .removal))

    let entries = journal.entries()
    #expect(entries.count == 2)
    #expect(entries[0].kind == .move)
    #expect(entries[0].pathBefore == "Note/vecchio.md")
    #expect(entries[1].kind == .removal)
    #expect(entries[1].pathBefore == nil)
}

@MainActor
@Test func theKindIsStoredUnderItsOwnName() throws {
    let (journal, _) = try journal()
    journal.record(entry(id: "a", path: "Note/x.md", kind: .move, pathBefore: "Note/y.md"))

    let text = try String(
        contentsOf: journal.directory.appending(path: "journal.jsonl"), encoding: .utf8
    )
    // `storedKind` is an implementation detail of reading it; the file says `kind`, so a person
    // reading the journal by eye sees the word the ADR uses.
    #expect(text.contains("\"kind\":\"move\""))
    #expect(!text.contains("storedKind"))
}

// MARK: - The gesture

@MainActor
@Test func entriesOfOneGestureComeBackInTheOrderTheyHappened() throws {
    let (journal, _) = try journal()
    journal.record(entry(id: "a", path: "Note/altra.md", operation: "op-1"))
    journal.record(entry(id: "b", path: "Note/terza.md", operation: "op-2"))
    journal.record(entry(id: "c", path: "Note/nuova.md", operation: "op-1",
                         kind: .move, pathBefore: "Note/vecchia.md"))

    let gesture = journal.entries(operation: "op-1")
    // Oldest first, which is the order they happened in - `undo` walks it backwards, so the
    // move recorded last is the first thing reversed.
    #expect(gesture.map(\.id) == ["a", "c"])
    #expect(journal.entries(operation: "op-2").map(\.id) == ["b"])
    #expect(journal.entries(operation: "op-mai-esistita").isEmpty)
}

@MainActor
@Test func aWriteThatStandsAloneBelongsToNoGesture() throws {
    let (journal, _) = try journal()
    journal.record(entry(id: "a", path: "Note/x.md"))

    #expect(journal.entry(id: "a")?.operation == nil)
    // The entry's own id stays the unit for a write that was its own whole gesture, which is
    // what keeps `undo <entry-id>` meaning exactly what it meant before ADR-0016.
    #expect(journal.entries(operation: "a").isEmpty)
}
