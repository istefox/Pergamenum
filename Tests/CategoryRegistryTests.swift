import Foundation
import Testing
@testable import Pergamenum

// The category registry of ADR-0047 §D2/§D3: `.pergamenum/categories.json`, an ordered
// list of `Category` plus a format version, and the one pure validation door every
// mutation goes through.

@Test func aCategoryRoundTripsThroughJSON() throws {
    let entry = Category(
        slug: "offerte", name: "Offerte", color: "rosso", symbol: "tag",
        description: "Preventivi in corso", deadline: CalendarDate(year: 2026, month: 12, day: 1),
        parent: "vibrofer", order: 2, archived: false
    )
    let registry = CategoryRegistry(version: CategoryRegistry.currentVersion, entries: [entry])

    let data = try JSONEncoder().encode(registry)
    let decoded = try JSONDecoder().decode(CategoryRegistry.self, from: data)

    #expect(decoded == registry)
}

@Test func anUnknownVersionReadsAsMalformed() throws {
    let vault = try TemporaryVault()
    let store = CategoryRegistryStore(root: vault.root)
    try FileManager.default.createDirectory(
        at: store.file.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try #"{"version": 999, "entries": []}"#.write(to: store.file, atomically: true, encoding: .utf8)

    let loaded = store.load()

    #expect(loaded.state == .malformed)
    #expect(loaded.registry.entries.isEmpty)
}

@MainActor
@Test func duplicateSlugAcrossBothLevelsIsRefusedBeforeAnyWrite() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)

    #expect(session.createCategory(Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")) == nil)
    let bytesBefore = try Data(contentsOf: session.categoryStore.file)

    // Same slug, a different level entirely - the duplicate check is not level-scoped.
    let refusal = session.createCategory(
        Category(slug: "vibrofer", name: "Duplicato", color: "blu", parent: nil)
    )

    #expect(refusal == .duplicateSlug("vibrofer"))
    #expect(try Data(contentsOf: session.categoryStore.file) == bytesBefore)
    #expect(session.categories.entries.count == 1)
}

@MainActor
@Test func aParentThatIsItselfAChildIsRefused() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(session.createCategory(Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")) == nil)
    #expect(session.createCategory(
        Category(slug: "offerte", name: "Offerte", color: "blu", parent: "vibrofer")
    ) == nil)

    let refusal = session.createCategory(
        Category(slug: "preventivi", name: "Preventivi", color: "verde", parent: "offerte")
    )

    #expect(refusal == .parentNotTopLevel("offerte"))
    #expect(session.categories.entries.map(\.slug).sorted() == ["offerte", "vibrofer"])
}

@MainActor
@Test func archivingAParentCascadesToItsChildren() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(session.createCategory(Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")) == nil)
    #expect(session.createCategory(
        Category(slug: "offerte", name: "Offerte", color: "blu", parent: "vibrofer")
    ) == nil)

    #expect(session.archiveCategory("vibrofer") == nil)

    let bySlug = Dictionary(uniqueKeysWithValues: session.categories.entries.map { ($0.slug, $0) })
    #expect(bySlug["vibrofer"]?.archived == true)
    #expect(bySlug["offerte"]?.archived == true)
}

@MainActor
@Test func unarchivingAChildUnarchivesItsParentToo() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(session.createCategory(Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")) == nil)
    #expect(session.createCategory(
        Category(slug: "offerte", name: "Offerte", color: "blu", parent: "vibrofer")
    ) == nil)
    #expect(session.archiveCategory("vibrofer") == nil)

    #expect(session.unarchiveCategory("offerte") == nil)

    let bySlug = Dictionary(uniqueKeysWithValues: session.categories.entries.map { ($0.slug, $0) })
    #expect(bySlug["offerte"]?.archived == false)
    #expect(bySlug["vibrofer"]?.archived == false)
}

@MainActor
@Test func aMalformedFileLoadsEmptyReportsAndIsNeverOverwritten() async throws {
    let vault = try TemporaryVault()
    let store = CategoryRegistryStore(root: vault.root)
    try FileManager.default.createDirectory(
        at: store.file.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try "non è json".write(to: store.file, atomically: true, encoding: .utf8)

    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)

    #expect(session.categories.entries.isEmpty)
    #expect(session.categoryRegistryMalformed)
    #expect(session.problems.contains { $0.contains(VaultLayout.categoriesFile) })

    let bytesBefore = try Data(contentsOf: store.file)
    let refusal = session.createCategory(Category(slug: "vibrofer", name: "Vibrofer", color: "rosso"))

    #expect(refusal == .registryUnreadable)
    #expect(try Data(contentsOf: store.file) == bytesBefore)
}
