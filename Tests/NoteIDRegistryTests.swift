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

// MARK: 12. iCloud conflict copy (PG-236/#524)

/// Two Macs minting an id at the same moment can leave an iCloud conflict copy beside
/// `note-ids.json` - `NoteIDStore.load()` never looks past the one file it reads, so
/// nothing previously reported this. `VaultSession` now runs the same detection
/// `migrateIfNeeded` already uses for `cache.db`/`thumbnails`/`history`/`ai-journal`.
@MainActor
@Test func aNoteIDsConflictCopyIsReportedAndLeftAlone() throws {
    let vault = try TemporaryVault()
    try vault.write(#"{"version":1,"notes":{}}"#, to: ".pergamenum/note-ids.json")
    try vault.write(#"{"version":1,"notes":{"\#(seedID)":"Nota.md"}}"#, to: ".pergamenum/note-ids 2.json")

    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)

    #expect(session.problems.contains { $0.contains("note-ids 2.json") })
    // Left alone, not merged or deleted: the same policy `conflictCopies` already
    // documents for the other files it detects (ADR-0017 §D3).
    #expect(FileManager.default.fileExists(
        atPath: vault.root.appending(path: ".pergamenum/note-ids 2.json").path(percentEncoded: false)
    ))
}

// MARK: 13-15. ADR-0059 "Implementation notes" 1-3 (PG-239)

/// Implementation note 1: a registry that is on disk and cannot be read is `.malformed`,
/// never `.absent` - `CategoryRegistryStore`'s shape would take it for absent, and an
/// absent registry is one the next door creates, over the file it could not read.
@MainActor
@Test func anExistingRegistryThatCannotBeReadIsMalformedAndNeverReplaced() throws {
    let vault = try TemporaryVault()
    try vault.write("contenuto", to: "a.md")
    let original = #"{"version":1,"notes":{"\#(seedID)":"b.md"}}"#
    try vault.write(original, to: ".pergamenum/note-ids.json")
    let store = NoteIDStore(root: vault.root)
    let path = store.file.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }
    #expect((try? Data(contentsOf: store.file)) == nil, "precondition: the file is there and cannot be read")

    let (registry, state) = store.load()
    #expect(state == .malformed)
    #expect(registry == .empty)

    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(session.mintNoteID(for: "a.md") == nil, "a door refuses an unreadable registry instead of creating one")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
    #expect(try String(contentsOf: store.file, encoding: .utf8) == original, "and the file was not replaced")
}

/// Implementation note 2: when a move's destination lies inside its own source, every
/// entry under the destination is also under the source, and the stale drop must not
/// discard what the same move is about to carry.
@Test func relocatingIntoItsOwnSubfolderCarriesTheEntriesAlreadyUnderTheDestination() {
    var registry = NoteIDRegistry.empty
    registry = registry.assigning("id-1", to: "Folder/A.md")
    registry = registry.assigning("id-2", to: "Folder/Sub/B.md")

    registry = registry.relocating([MovedNote(old: "Folder", new: "Folder/Sub")])

    #expect(registry.path(forID: "id-1") == "Folder/Sub/A.md")
    #expect(registry.path(forID: "id-2") == "Folder/Sub/Sub/B.md", "carried, not dropped as stale")
}

/// The other overlap, a destination that is an ancestor of the source: the entry the move
/// carries survives, and an entry at the destination that the move does not carry is still
/// stale and still dropped - §D4's intent, unchanged by the guard.
@Test func relocatingOntoAnAncestorCarriesTheSourceAndStillDropsTheStaleEntry() {
    var registry = NoteIDRegistry.empty
    registry = registry.assigning("id-carried", to: "Folder/Sub/x.md")
    registry = registry.assigning("id-stale", to: "Folder/y.md")

    registry = registry.relocating([MovedNote(old: "Folder/Sub", new: "Folder")])

    #expect(registry.path(forID: "id-carried") == "Folder/x.md")
    #expect(registry.path(forID: "id-stale") == nil)
}

/// Implementation note 3: a hand-edited file can map several ids to one path. The
/// smallest is answered, whatever order the file lists them in, and every other id still
/// resolves to the path.
@Test func severalIdsForOnePathAnswerTheSmallestWhateverTheFileOrder() throws {
    let ids = ["c-3", "a-1", "e-5", "b-2", "d-4"]
    let orders: [[String]] = [ids, Array(ids.reversed()), ids.sorted(), Array(ids.sorted().reversed())]
    for order in orders {
        let entries = order.map { #""\#($0)":"Nota.md""# }.joined(separator: ",")
        let json = #"{"version":1,"notes":{"# + entries + "}}"
        let registry = try JSONDecoder().decode(NoteIDRegistry.self, from: Data(json.utf8))

        #expect(registry.id(forPath: "Nota.md") == "a-1", "file order \(order)")
        for id in ids {
            #expect(registry.path(forID: id) == "Nota.md")
        }
    }
}

/// The tie-break above runs on one Dictionary layout per file order, and Swift's per-process
/// hash seeding means a `keys.first` regression only fails it by chance. This one removes the
/// chance: sixty registries with different id sets (each Dictionary is laid out on its own),
/// so a non-minimum choice (`keys.first`, `keys.max()`) would have to land on the minimum sixty
/// times running - a one-in-eight-to-the-sixtieth miss. The correct implementation cannot fail
/// it, whatever the seed.
@Test func theSmallestIdWinsOnManyDifferentTiedSets() throws {
    for round in 0..<60 {
        let ids = (0..<8).map { "id-\(round)-\(String($0 * 7 % 8))-\(round &* 31 &+ $0 * 13)" }
        let entries = ids.map { #""\#($0)":"Nota.md""# }.joined(separator: ",")
        let json = #"{"version":1,"notes":{"# + entries + "}}"
        let registry = try JSONDecoder().decode(NoteIDRegistry.self, from: Data(json.utf8))

        #expect(registry.id(forPath: "Nota.md") == ids.min(), "round \(round)")
    }
}
