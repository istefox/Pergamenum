import Foundation
import Testing
@testable import Pergamenum

// ADR-0047 §D10 (R-06, R-10), plan `docs/plans/task-categories.md`, Task 6: the two
// advisory `pergamenum-category` lint findings (`unknownSlug`, `duplicateHome`), and the
// link/unlink writers `VaultSession+Categories.swift` gained to serve them.
//
// `TaskMarkerLintTests.swift`'s own shape: a `session(root:stateBase:)` for a test that
// only needs the registry (loaded synchronously at `init`, never at `rescan()`), and an
// `openSession(root:stateBase:)` for one that needs the index too - `duplicateHome` and
// the inheritance check cannot answer from one note's own text alone.

@MainActor
private func session(root: URL, stateBase: URL) -> VaultSession {
    VaultSession(
        root: root, stateBase: stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
}

@MainActor
private func openSession(root: URL, stateBase: URL) async -> VaultSession {
    let opened = session(root: root, stateBase: stateBase)
    await opened.rescan()
    return opened
}

private func note(category slug: String? = nil, _ body: String) -> String {
    let categoryLine = slug.map { "pergamenum-category: \($0)\n" } ?? ""
    return """
    ---
    date: 2026-08-11
    tags:
      - type-note
    \(categoryLine)---

    \(body)
    """
}

// MARK: - `unknownSlug`

@MainActor
@Test func unknownSlugFiresWhenTheLinkedSlugIsNotInTheRegistry() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let text = note(category: "fantasma", "- [ ] Un task qualsiasi")

    let violations = s.violations(path: "Nota.md", title: "Nota", text: text)

    #expect(violations.categories == [.unknownSlug("fantasma")])
}

@MainActor
@Test func noUnknownSlugFindingWhenTheSlugIsRegistered() throws {
    let vault = try TemporaryVault()
    let registry = CategoryRegistry(
        version: CategoryRegistry.currentVersion,
        entries: [Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")]
    )
    CategoryRegistryStore(root: vault.root).save(registry)
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let text = note(category: "vibrofer", "- [ ] Un task qualsiasi")

    let violations = s.violations(path: "Nota.md", title: "Nota", text: text)

    #expect(violations.categories.isEmpty)
}

/// SPEC edge case: "`pergamenum-category` naming an implicit slug: inheritance works;
/// the lint finding says the slug is unregistered, not that the key is wrong." A slug
/// is implicit once some task's own `#project-*` tag makes it real - here that task
/// lives in the very note carrying the key, which is enough to prove both halves at
/// once: the key still inherits (`effectiveCategory`) and the note still reports it.
@MainActor
@Test func anImplicitSlugStillInheritsAndReportsUnknownSlug() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(category: "fantasma", "- [ ] Uno #project-fantasma"), to: "Nota.md")
    let s = await openSession(root: vault.root, stateBase: vault.stateBase)

    #expect(s.index.implicitCategories(registry: s.categories).contains("fantasma"))
    let violations = try #require(s.violations(forRecordAt: "Nota.md"))
    #expect(violations.categories == [.unknownSlug("fantasma")])
}

// MARK: - `duplicateHome`

@MainActor
@Test func aSecondNoteNamingTheSameSlugIsADuplicateHomeFindingAndTheHomeIsFirstInVaultOrder() async throws {
    let vault = try TemporaryVault()
    let registry = CategoryRegistry(
        version: CategoryRegistry.currentVersion,
        entries: [Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")]
    )
    CategoryRegistryStore(root: vault.root).save(registry)
    try vault.write(note(category: "vibrofer", "Corpo A."), to: "Alfa.md")
    try vault.write(note(category: "vibrofer", "Corpo B."), to: "Beta.md")
    let s = await openSession(root: vault.root, stateBase: vault.stateBase)

    let homeViolations = try #require(s.violations(forRecordAt: "Alfa.md"))
    #expect(homeViolations.categories.isEmpty, "\(homeViolations.categories)")

    let duplicateViolations = try #require(s.violations(forRecordAt: "Beta.md"))
    #expect(duplicateViolations.categories == [.duplicateHome("vibrofer", home: "Alfa.md")])
}

// MARK: - Inheritance, tied to the home note (R-06)

@MainActor
@Test func theHomesUntaggedTasksInheritTheCategoryWhileAnExplicitTagOnAnotherNoteWins() async throws {
    let vault = try TemporaryVault()
    let registry = CategoryRegistry(
        version: CategoryRegistry.currentVersion,
        entries: [Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")]
    )
    CategoryRegistryStore(root: vault.root).save(registry)
    try vault.write(note(category: "vibrofer", "- [ ] Preventivo senza tag"), to: "Casa.md")
    try vault.write(note("- [ ] Preventivo con tag esplicito #project-diverso"), to: "Altro.md")
    let s = await openSession(root: vault.root, stateBase: vault.stateBase)

    let homeTask = try #require(s.index.allTasks.first { $0.sourcePath == "Casa.md" })
    let taggedTask = try #require(s.index.allTasks.first { $0.sourcePath == "Altro.md" })

    #expect(s.index.effectiveCategory(of: homeTask) == "vibrofer")
    #expect(s.index.effectiveCategory(of: taggedTask) == "diverso")
}

// MARK: - Deleting the home note (SPEC edge case: "no registry change")

@MainActor
@Test func aDeletedHomeNoteLeavesTheCategoryUnlinkedWithNoRegistryChange() async throws {
    let vault = try TemporaryVault()
    let registry = CategoryRegistry(
        version: CategoryRegistry.currentVersion,
        entries: [Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")]
    )
    CategoryRegistryStore(root: vault.root).save(registry)
    let noteURL = try vault.write(note(category: "vibrofer", "Corpo."), to: "Casa.md")
    let s = await openSession(root: vault.root, stateBase: vault.stateBase)
    let before = s.categories

    try FileManager.default.removeItem(at: noteURL)
    await s.rescan()

    #expect(s.categories == before)
    #expect(s.index.allNotes.contains { $0.relativePath == "Casa.md" } == false)
}

// MARK: - The link/unlink writers (`VaultSession+Categories.swift`)

@MainActor
@Test func linkCategoryWritesTheFrontmatterKeyReplacingAnyExistingOne() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(category: "vecchia", "Corpo."), to: "Nota.md")
    let s = await openSession(root: vault.root, stateBase: vault.stateBase)

    guard case .written = await s.linkCategory("nuova", toNoteAt: "Nota.md") else {
        Issue.record("linkCategory non ha scritto")
        return
    }
    let (_, text) = try s.read("Nota.md")
    let document = NoteDocument.parse(text)

    #expect(CategoryFrontmatter.slug(in: document.frontmatter.foreignKeys) == "nuova")
    // Nothing else in the note changed: exactly one `pergamenum-category` line, still
    // one `date` and one `tags` block.
    #expect(document.frontmatter.foreignKeys.filter { $0.name == CategoryFrontmatter.key }.count == 1)
}

@MainActor
@Test func unlinkCategoryRemovesTheKeyAndLeavesEverythingElseUntouched() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(category: "vibrofer", "- [ ] Un task"), to: "Nota.md")
    let s = await openSession(root: vault.root, stateBase: vault.stateBase)

    guard case .written = await s.unlinkCategory(fromNoteAt: "Nota.md") else {
        Issue.record("unlinkCategory non ha scritto")
        return
    }
    let (_, text) = try s.read("Nota.md")
    let document = NoteDocument.parse(text)

    #expect(CategoryFrontmatter.slug(in: document.frontmatter.foreignKeys) == nil)
    #expect(document.frontmatter.date != nil)
    #expect(document.frontmatter.tags.map(\.description) == ["type-note"])
}
