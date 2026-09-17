import Foundation
import Testing
@testable import Pergamenum

// The two category reads of ADR-0047 §D9 (R-09), split out of `ConnectorTests.swift`
// itself (PG-035/ADR-0045's pure code motion) once that file crossed SwiftLint's
// `file_length` warning - moved verbatim, nothing about either test changed. This file
// keeps its own fixture rather than sharing `ConnectorTests.swift`'s `note`: every other
// test file in this target names its own top-level fixture `note` too, `private` (which
// at file scope means file-confined) - widening one to `internal` so a second file could
// read it collided with every other file's own `private let note` (compile error,
// caught before the fix landed), not just the one this file wants.

@MainActor
@Test func categoriesPayloadCarriesTheImplicitAndArchivedFlagsTheParentAndTheProgress() async throws {
    let vault = try TemporaryVault()
    let registry = CategoryRegistry(
        version: CategoryRegistry.currentVersion,
        entries: [
            Category(slug: "vibrofer", name: "Vibrofer", color: "rosso"),
            Category(slug: "archiviata", name: "Archiviata", color: "grigio", archived: true),
        ]
    )
    CategoryRegistryStore(root: vault.root).save(registry)
    let note = """
        ---
        date: 2026-08-11
        tags:
          - type-note
        ---

        Corpo, con un [[Link che non esiste]].

        - [ ] Alfa #project-vibrofer >2026-08-20
        - [ ] Beta !2026-08-21
        - [x] Gamma #project-vibrofer

        - [ ] Fuori registro #project-fantasma
        """
    try vault.write(note, to: "Nota.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    let categories = VaultAPI.categories(session)
    let bySlug = Dictionary(uniqueKeysWithValues: categories.map { ($0.slug, $0) })

    let vibrofer = try #require(bySlug["vibrofer"])
    #expect(vibrofer.implicit == false)
    #expect(vibrofer.archived == false)
    #expect(vibrofer.progress.done == 1)
    #expect(vibrofer.progress.total == 2)

    let archived = try #require(bySlug["archiviata"])
    #expect(archived.implicit == false)
    #expect(archived.archived == true)

    let implicit = try #require(bySlug["fantasma"])
    #expect(implicit.implicit == true)
    #expect(implicit.name == "fantasma")
}

@MainActor
@Test func categoryTasksRollsUpTheSubtreeAndGroupsItAsTheAppViewDoes() async throws {
    let vault = try TemporaryVault()
    let registry = CategoryRegistry(
        version: CategoryRegistry.currentVersion,
        entries: [
            Category(slug: "vibrofer", name: "Vibrofer", color: "rosso"),
            Category(slug: "offerte", name: "Offerte", color: "blu", parent: "vibrofer"),
        ]
    )
    CategoryRegistryStore(root: vault.root).save(registry)
    try vault.write(
        """
        ---
        date: 2026-08-11
        tags:
          - type-note
        ---

        - [ ] Diretto #project-vibrofer
        - [ ] Figlio #project-offerte
        """,
        to: "Nota.md"
    )
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    let payload = try VaultAPI.categoryTasks(session, slug: "vibrofer")
    let rolledUpTexts = Set(payload.groups.flatMap(\.tasks).map(\.text))

    // The rollup in the payload equals the index's own (SPEC "Rollup").
    let expected = Set(
        session.index.tasks(inCategory: "vibrofer", registry: registry, rolledUp: true).map(\.text)
    )
    #expect(rolledUpTexts == expected)
    #expect(rolledUpTexts == ["Diretto", "Figlio"])

    #expect(throws: ConnectorError.self) { try VaultAPI.categoryTasks(session, slug: "non-esiste") }
}

// `ToolCatalogue.reading`/`.writing` live in `Sources/MCPServer/`, excluded from the
// `Pergamenum` app target this test bundle links (CLAUDE.md: "a module may contain only
// one `main.swift`"), so "reading grew by two and writing by none" cannot be asserted
// from here - `scripts/mcp-smoke.py`'s `categories()` stage checks it against the real
// server instead, over `tools/list`, the same way `read_only()` already checks every
// listed tool's `readOnlyHint`.
