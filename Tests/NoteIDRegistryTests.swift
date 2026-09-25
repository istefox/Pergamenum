import Foundation
import Testing
@testable import Pergamenum

// ADR-0059 (stable note ids live in `.pergamenum/note-ids.json`, not the index),
// Acceptance tests 1-11: the pure value type (`NoteIDRegistry`) and the store
// (`NoteIDStore`) on their own, with no session involved.
//
// RED at Task 1 (tester/coder split, plan `docs/plans/pg-130-stable-note-id.md`):
// `NoteIDRegistry`'s methods and `NoteIDStore.load()`/`save(_:)` are stubs, so every
// assertion below fails on its own equality or `#require`, not on a build error - Task 2
// fills the bodies in. The exception is the format-pin half of test 8, which is already
// green: the `Codable` conformance is real from Task 1.

private let seedID = "3f2c9a4e-8b1d-4c67-9e2a-5d1b7c0e4f13"

// MARK: 1. `makeID()`

@Test func makeIDReturnsALowercaseVersion4UUID() throws {
    let id = NoteIDRegistry.makeID()

    #expect(id == id.lowercased())
    let uuid = try #require(UUID(uuidString: id))
    // The version nibble is the first character of the third hyphen-separated group.
    let versionNibble = uuid.uuidString.split(separator: "-")[2].first
    #expect(versionNibble == "4")
}

// MARK: 2-3. `assigning`

@Test func assigningRoundTripsThroughBothLookupsAndAnUpperCaseIdResolves() {
    let registry = NoteIDRegistry.empty.assigning("ABC-123", to: "Nota.md")

    #expect(registry.path(forID: "abc-123") == "Nota.md")
    #expect(registry.id(forPath: "Nota.md") == "abc-123")
}

@Test func assigningASecondIdToAPathDropsTheFirstOnePerPath() {
    var registry = NoteIDRegistry.empty
    registry = registry.assigning("id-one", to: "Nota.md")
    registry = registry.assigning("id-two", to: "Nota.md")

    #expect(registry.id(forPath: "Nota.md") == "id-two")
    #expect(registry.path(forID: "id-one") == nil)
}

// MARK: 4-6. `relocating`

@Test func relocatingMovesAnExactEntryAndLeavesTheOthersAlone() {
    var registry = NoteIDRegistry.empty
    registry = registry.assigning("id-a", to: "A.md")
    registry = registry.assigning("id-b", to: "B.md")

    registry = registry.relocating([MovedNote(old: "A.md", new: "A2.md")])

    #expect(registry.path(forID: "id-a") == "A2.md")
    #expect(registry.path(forID: "id-b") == "B.md")
}

@Test func relocatingAFolderPairMovesEveryNestedEntryButNotALookalikeName() {
    var registry = NoteIDRegistry.empty
    registry = registry.assigning("id-1", to: "Folder/A.md")
    registry = registry.assigning("id-2", to: "Folder/Sub/B.md")
    registry = registry.assigning("id-3", to: "Folder 2/x.md")
    registry = registry.assigning("id-4", to: "Folder.md")

    registry = registry.relocating([MovedNote(old: "Folder", new: "Renamed")])

    #expect(registry.path(forID: "id-1") == "Renamed/A.md")
    #expect(registry.path(forID: "id-2") == "Renamed/Sub/B.md")
    #expect(registry.path(forID: "id-3") == "Folder 2/x.md")
    #expect(registry.path(forID: "id-4") == "Folder.md")
}

@Test func relocatingOntoADestinationHoldingAStaleEntryDropsTheStaleEntry() {
    var registry = NoteIDRegistry.empty
    registry = registry.assigning("id-old", to: "Dest.md")
    registry = registry.assigning("id-move", to: "Source.md")

    registry = registry.relocating([MovedNote(old: "Source.md", new: "Dest.md")])

    #expect(registry.path(forID: "id-old") == nil)
    #expect(registry.path(forID: "id-move") == "Dest.md")
}

// MARK: 7. `removing`

@Test func removingDropsExactlyWhatItCoversAndAnEmptyPathMatchesNothing() {
    var registry = NoteIDRegistry.empty
    registry = registry.assigning("id-1", to: "A.md")
    registry = registry.assigning("id-2", to: "Folder/B.md")
    registry = registry.assigning("id-3", to: "Other.md")

    let afterRemoving = registry.removing(["A.md", "Folder"])
    #expect(afterRemoving.path(forID: "id-1") == nil)
    #expect(afterRemoving.path(forID: "id-2") == nil)
    #expect(afterRemoving.path(forID: "id-3") == "Other.md")

    let unchanged = registry.removing([""])
    #expect(unchanged == registry)
}

// MARK: 8. The on-disk format is pinned

@Test func theVersion1FormatDecodesAndReencodesToTheSameBytes() throws {
    let json = """
    {
      "notes" : {
        "\(seedID)" : "Nota.md"
      },
      "version" : 1
    }
    """
    let data = Data(json.utf8)

    let registry = try JSONDecoder().decode(NoteIDRegistry.self, from: data)
    #expect(registry.version == 1)
    #expect(registry.notes[seedID] == "Nota.md")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let reencoded = try encoder.encode(registry)
    #expect(String(data: reencoded, encoding: .utf8) == json)
}

// MARK: 9-11. The store

@Test func aVaultWithNoRegistryAndNoPlaceholderIsAbsentAndSaveCreatesTheFile() throws {
    let vault = try TemporaryVault()
    let store = NoteIDStore(root: vault.root)

    let (registry, state) = store.load()
    #expect(state == .absent)
    #expect(registry == .empty)

    let seeded = NoteIDRegistry(version: 1, notes: [seedID: "Nota.md"])
    #expect(store.save(seeded) == nil)

    #expect(FileManager.default.fileExists(atPath: store.file.path(percentEncoded: false)))
    let written = try JSONDecoder().decode(NoteIDRegistry.self, from: Data(contentsOf: store.file))
    #expect(written == seeded)
}

@Test func undecodableBytesOrAnUnknownVersionGiveMalformed() throws {
    let vault = try TemporaryVault()
    try vault.write("non è json", to: ".pergamenum/note-ids.json")
    #expect(NoteIDStore(root: vault.root).load().state == .malformed)

    let vault2 = try TemporaryVault()
    try vault2.write(#"{"version":2,"notes":{}}"#, to: ".pergamenum/note-ids.json")
    #expect(NoteIDStore(root: vault2.root).load().state == .malformed)
}

@Test func onlyAnICloudPlaceholderGivesEvicted() throws {
    let vault = try TemporaryVault()
    try vault.write("", to: ".pergamenum/.note-ids.json.icloud")

    #expect(NoteIDStore(root: vault.root).load().state == .evicted)
}
