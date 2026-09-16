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

// MARK: - `updateCategory`, `reorderCategories`, `reparentCategory` (R-01)

@MainActor
@Test func updateCategoryChangesEveryEditableFieldButKeepsTheSlugImmutable() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(session.createCategory(Category(slug: "offerte", name: "Offerte", color: "rosso")) == nil)

    let refusal = session.updateCategory(
        Category(
            slug: "offerte", name: "Offerte EMEA", color: "blu", symbol: "tag",
            description: "Preventivi EMEA", deadline: CalendarDate(iso: "2026-12-01"), order: 3
        )
    )

    #expect(refusal == nil)
    #expect(session.categories.entries.count == 1)
    let updated = try #require(session.categories.entries.first)
    #expect(updated.slug == "offerte")
    #expect(updated.name == "Offerte EMEA")
    #expect(updated.color == "blu")
    #expect(updated.symbol == "tag")
    #expect(updated.description == "Preventivi EMEA")
    #expect(updated.deadline == CalendarDate(iso: "2026-12-01"))
    #expect(updated.order == 3)
}

@MainActor
@Test func reorderCategoriesReassignsOrderOnlyAmongTheGivenParentsSiblings() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(session.createCategory(Category(slug: "a", name: "A", color: "rosso", order: 0)) == nil)
    #expect(session.createCategory(Category(slug: "b", name: "B", color: "blu", order: 1)) == nil)
    #expect(session.createCategory(
        Category(slug: "figlio", name: "Figlio", color: "verde", parent: "a", order: 0)
    ) == nil)

    #expect(session.reorderCategories(["b", "a"], parent: nil) == nil)

    let bySlug = Dictionary(uniqueKeysWithValues: session.categories.entries.map { ($0.slug, $0) })
    #expect(bySlug["b"]?.order == 0)
    #expect(bySlug["a"]?.order == 1)
    // Not a sibling of the reordered pair: a top-level reorder leaves it alone.
    #expect(bySlug["figlio"]?.order == 0)
}

@MainActor
@Test func reparentCategoryMovesAChildUnderAnotherTopLevelParent() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(session.createCategory(Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")) == nil)
    #expect(session.createCategory(Category(slug: "altra", name: "Altra", color: "blu")) == nil)
    #expect(session.createCategory(
        Category(slug: "offerte", name: "Offerte", color: "verde", parent: "vibrofer")
    ) == nil)

    #expect(session.reparentCategory("offerte", to: "altra") == nil)

    #expect(session.categories.entries.first { $0.slug == "offerte" }?.parent == "altra")
}

@MainActor
@Test func reparentingUnderANonTopLevelCategoryIsRefusedAndNothingChanges() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(session.createCategory(Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")) == nil)
    #expect(session.createCategory(
        Category(slug: "offerte", name: "Offerte", color: "blu", parent: "vibrofer")
    ) == nil)
    #expect(session.createCategory(Category(slug: "altra", name: "Altra", color: "verde")) == nil)

    let refusal = session.reparentCategory("altra", to: "offerte")

    #expect(refusal == .parentNotTopLevel("offerte"))
    #expect(session.categories.entries.first { $0.slug == "altra" }?.parent == nil)
}

// MARK: - `deleteCategory` and `promoteImplicitCategory` (R-04, R-07)

@MainActor
@Test func deletingACategoryTouchesOnlyTheRegistryAndItsTaskReappearsAsImplicit() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        """
        ---
        date: 2026-08-11
        tags:
          - type-note
        ---

        - [ ] Preventivo #project-offerte
        """,
        to: "Nota.md"
    )
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(session.createCategory(Category(slug: "offerte", name: "Offerte", color: "rosso")) == nil)
    await session.rescan()
    #expect(session.index.implicitCategories(registry: session.categories).contains("offerte") == false)

    session.deleteCategory("offerte")

    #expect(session.categories.entries.contains { $0.slug == "offerte" } == false)
    // Delete never rewrites a task line (SPEC "Decisions"): the tag is still on the
    // line, on disk, before the index has even caught up.
    #expect(try session.read("Nota.md").text.contains("#project-offerte"))

    await session.rescan()

    #expect(session.index.implicitCategories(registry: session.categories).contains("offerte"))
}

@MainActor
@Test func promotingAnImplicitCategoryRegistersItWithNoChangeToTheExistingTask() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        """
        ---
        date: 2026-08-11
        tags:
          - type-note
        ---

        - [ ] Preventivo #project-fantasma
        """,
        to: "Nota.md"
    )
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    #expect(session.index.implicitCategories(registry: session.categories) == ["fantasma"])
    let textBefore = try session.read("Nota.md").text

    #expect(session.promoteImplicitCategory("fantasma", color: "rosso") == nil)

    let registered = try #require(session.categories.entries.first { $0.slug == "fantasma" })
    #expect(registered.name == "fantasma")
    #expect(registered.color == "rosso")
    #expect(try session.read("Nota.md").text == textBefore)
}

// MARK: - Archiving hides the assignment picker's entry, not the task (R-07)

@MainActor
@Test func archivingACategoryExcludesItFromAssignableGroupsWhileItsTaskStaysInTheIndex() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        """
        ---
        date: 2026-08-11
        tags:
          - type-note
        ---

        - [ ] Preventivo #project-offerte
        """,
        to: "Nota.md"
    )
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(session.createCategory(Category(slug: "offerte", name: "Offerte", color: "rosso")) == nil)
    await session.rescan()

    #expect(session.archiveCategory("offerte") == nil)

    #expect(session.categories.assignableGroups.contains { $0.parent.slug == "offerte" } == false)
    // Archiving is a registry-only edit: the task itself is untouched and still
    // resolves to the category (SPEC edge case: "tasks stay visible in Oggi, Prossimi
    // and Tutti" - nothing in the task-view derivation filters on `archived`).
    let task = try #require(session.index.allTasks.first { $0.text == "Preventivo" })
    #expect(session.index.effectiveCategory(of: task) == "offerte")
}

// MARK: - `assignableGroups` (R-03's assignment-gesture edge case: never offer archived)

@Test func assignableGroupsAreOrderedParentThenChildAndExcludeArchivedEntries() {
    let registry = CategoryRegistry(
        version: CategoryRegistry.currentVersion,
        entries: [
            Category(slug: "b", name: "B", color: "blu", order: 1),
            Category(slug: "a", name: "A", color: "rosso", order: 0),
            Category(slug: "archiviata", name: "Archiviata", color: "grigio", order: 2, archived: true),
            Category(slug: "figlio-b", name: "Figlio B", color: "verde", parent: "b", order: 1),
            Category(slug: "figlio-a", name: "Figlio A", color: "giallo", parent: "b", order: 0),
        ]
    )

    let groups = registry.assignableGroups

    #expect(groups.map(\.parent.slug) == ["a", "b"])
    #expect(groups.first { $0.parent.slug == "b" }?.children.map(\.slug) == ["figlio-a", "figlio-b"])
    #expect(groups.contains { $0.parent.slug == "archiviata" } == false)
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
