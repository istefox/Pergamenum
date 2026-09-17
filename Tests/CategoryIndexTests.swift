import Foundation
import Testing
@testable import Pergamenum

// The index derivations of ADR-0047 §D4/§D5: effective category per task, implicit
// categories, rollup and progress, and the cache round-trip that §D5 exists to protect.

private func makeRecord(
    path: String, title: String, categorySlug: String? = nil, tasks: [TaskItem] = []
) -> NoteRecord {
    var frontmatter = Frontmatter.empty
    frontmatter.date = CalendarDate(iso: "2026-08-11")
    frontmatter.tags = [Tag("type-note")!]
    return NoteRecord(
        relativePath: path, title: title, frontmatter: frontmatter, linkTargets: [],
        categorySlug: categorySlug, tasks: tasks, modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
}

private func task(_ line: String, sourcePath: String = "Nota.md", lineIndex: Int = 0) -> TaskItem {
    TaskParser.parse(line: line, sourcePath: sourcePath, lineIndex: lineIndex)!
}

@MainActor
@Test func anExplicitTagBeatsTheLinkedNotesKey() throws {
    let taggedTask = task("- [ ] Preventivo #project-offerte")
    var index = IndexSnapshot()
    index.replaceAll(
        with: .init(
            records: [makeRecord(path: "Nota.md", title: "Nota", categorySlug: "vibrofer", tasks: [taggedTask])],
            failures: []
        ),
        duration: .zero
    )

    #expect(index.effectiveCategory(of: taggedTask) == "offerte")
}

@MainActor
@Test func theLinkedNotesKeyBeatsNothing() throws {
    let untaggedTask = task("- [ ] Preventivo")
    var index = IndexSnapshot()
    index.replaceAll(
        with: .init(
            records: [makeRecord(path: "Nota.md", title: "Nota", categorySlug: "vibrofer", tasks: [untaggedTask])],
            failures: []
        ),
        duration: .zero
    )

    #expect(index.effectiveCategory(of: untaggedTask) == "vibrofer")
}

@MainActor
@Test func noTagAndNoLinkedNoteIsNoCategoryAtAll() throws {
    let untaggedTask = task("- [ ] Preventivo")
    var index = IndexSnapshot()
    index.replaceAll(
        with: .init(records: [makeRecord(path: "Nota.md", title: "Nota", tasks: [untaggedTask])], failures: []),
        duration: .zero
    )

    #expect(index.effectiveCategory(of: untaggedTask) == nil)
}

@MainActor
@Test func aBoardTaskInheritsNothingEvenWithNoExplicitTag() throws {
    let boardTask = task("- [ ] Beta", sourcePath: "Lavagna.canvas")
    var index = IndexSnapshot()
    index.replaceAll(
        with: .init(
            records: [],
            failures: [],
            boardTaskRecords: [
                BoardTaskRecord(
                    relativePath: "Lavagna.canvas", tasks: [boardTask],
                    modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
                ),
            ]
        ),
        duration: .zero
    )

    // A board has no frontmatter and so no `pergamenum-category` - `notes["Lavagna.canvas"]`
    // is simply absent, never a note wrongly matched by path.
    #expect(index.effectiveCategory(of: boardTask) == nil)
}

@MainActor
@Test func implicitCategoriesAreExactlyTheProjectValuesAbsentFromTheRegistry() throws {
    let registered = task("- [ ] Uno #project-vibrofer")
    let unregistered = task("- [ ] Due #project-fantasma", lineIndex: 1)
    var index = IndexSnapshot()
    index.replaceAll(
        with: .init(
            records: [makeRecord(path: "Nota.md", title: "Nota", tasks: [registered, unregistered])],
            failures: []
        ),
        duration: .zero
    )
    let registry = CategoryRegistry(
        version: CategoryRegistry.currentVersion,
        entries: [Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")]
    )

    #expect(index.implicitCategories(registry: registry) == ["fantasma"])
}

@MainActor
@Test func rollupCountsTheWholeSubtree() throws {
    let parentTask = task("- [ ] Diretto #project-vibrofer")
    let childTask = task("- [ ] Figlio #project-offerte", lineIndex: 1)
    let unrelatedTask = task("- [ ] Altro #project-fantasma", lineIndex: 2)
    var index = IndexSnapshot()
    index.replaceAll(
        with: .init(
            records: [makeRecord(path: "Nota.md", title: "Nota", tasks: [parentTask, childTask, unrelatedTask])],
            failures: []
        ),
        duration: .zero
    )
    let registry = CategoryRegistry(
        version: CategoryRegistry.currentVersion,
        entries: [
            Category(slug: "vibrofer", name: "Vibrofer", color: "rosso"),
            Category(slug: "offerte", name: "Offerte", color: "blu", parent: "vibrofer"),
        ]
    )

    let rolledUp = index.tasks(inCategory: "vibrofer", registry: registry, rolledUp: true)
    #expect(Set(rolledUp.map(\.text)) == ["Diretto", "Figlio"])

    let direct = index.tasks(inCategory: "vibrofer", registry: registry, rolledUp: false)
    #expect(direct.map(\.text) == ["Diretto"])
}

@MainActor
@Test func progressCountsDoneAndOpenAndExcludesCancelled() throws {
    let done = task("- [x] Fatto #project-vibrofer")
    let open = task("- [ ] Aperto #project-vibrofer", lineIndex: 1)
    let rescheduled = task("- [>] Rimandato #project-vibrofer", lineIndex: 2)
    let cancelled = task("- [-] Annullato #project-vibrofer", lineIndex: 3)
    var index = IndexSnapshot()
    index.replaceAll(
        with: .init(
            records: [makeRecord(path: "Nota.md", title: "Nota", tasks: [done, open, rescheduled, cancelled])],
            failures: []
        ),
        duration: .zero
    )
    let registry = CategoryRegistry(
        version: CategoryRegistry.currentVersion,
        entries: [Category(slug: "vibrofer", name: "Vibrofer", color: "rosso")]
    )

    let progress = index.progress(ofCategory: "vibrofer", registry: registry)

    // done=1, open=2 (`[ ]` and `[>]`), cancelled excluded from both sides.
    #expect(progress.done == 1)
    #expect(progress.total == 3)
}

// MARK: - Cache round-trip (ADR-0047 §D5)

@MainActor
@Test func categorySlugSurvivesASaveAndLoadCacheRoundTrip() throws {
    let vault = try TemporaryVault()
    try vault.write(
        """
        ---
        date: 2026-08-11
        tags:
          - type-note
        pergamenum-category: vibrofer
        ---

        Corpo.
        """,
        to: "Nota.md"
    )
    let cacheFile = VaultState(id: "category-index-test", base: vault.stateBase).cacheFile
    let cache = IndexCache(url: cacheFile)

    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    let loaded = try #require(cache.load()["Nota.md"])
    #expect(loaded.record.record.categorySlug == "vibrofer")
}
