import Foundation
import Testing
@testable import Pergamenum

// ADR-0097 §D6, plan docs/plans/pg-399-rename-backlink-rule.md Task 1 (R-04).
//
// The rename and the index are two readers of the same link. Over one corpus of spellings, the
// rename rewrites a link exactly when the index lists the linking note as a backlink, and a
// rename leaves the source note's unresolved targets unchanged (app SPEC
// `docs/20260811_Pergamenum_SpecApp.md:114`). The index is built the way the app builds it:
// a vault on disk, `VaultScanner.scan()`, `IndexSnapshot.replaceAll(with:duration:)`.

private let frontmatter = """
---
date: 2026-10-16
tags:
  - type-note
---


"""

private func snapshot(of root: URL) -> IndexSnapshot {
    var snapshot = IndexSnapshot()
    snapshot.replaceAll(with: VaultScanner(root: root).scan(), duration: .zero)
    return snapshot
}

/// Every spelling ADR-0097 §D1 names, and the one that is neither (a link in an inline span).
private let corpus: [String] = [
    "Vedi [[Curva]].",
    "Vedi [[curva]].",
    "Vedi [[**Curva**]].",
    "Vedi [[~~Curva~~]].",
    "Vedi [[*Curva*]].",
    "Vedi [[**Curva**#Sez|alias]].",
    "Vedi ![[**Curva**]].",
    "Vedi [[** Curva **]].",
    "Vedi [[**Curva** vecchio]].",
    "Vedi [[Curvatura]].",
    "Vedi [[***Curva***]].",
    "Vedi `[[**Curva**]]` nel codice.",
]

@Test func theRenameRewritesALinkExactlyWhenTheIndexCountsItAsABacklink() throws {
    var rewritten = 0
    var left = 0
    for body in corpus {
        let vault = try TemporaryVault()
        try vault.write(frontmatter, to: "Curva.md")
        try vault.write(frontmatter + body + "\n", to: "Fonte.md")

        let index = snapshot(of: vault.root)
        let isBacklink = index.backlinks(toTitle: "Curva").contains { $0.relativePath == "Fonte.md" }
        let isRewritten = NoteRename.rewritingLinks(
            in: body, from: "Curva", to: "Nuovo", includeQuotedRelated: false
        ) != nil

        #expect(isRewritten == isBacklink, "rename e indice in disaccordo su: \(body) (rename \(isRewritten), indice \(isBacklink))")
        if isRewritten { rewritten += 1 } else { left += 1 }
    }

    // Not vacuous: the corpus holds links on both sides of the rule.
    #expect(rewritten > 0)
    #expect(left > 0)
}

@Test func aBoldLinkByNameIsBothRewrittenAndABacklink() throws {
    let vault = try TemporaryVault()
    try vault.write(frontmatter, to: "Curva.md")
    try vault.write(frontmatter + "Vedi [[**Curva**]].\n", to: "Fonte.md")

    let index = snapshot(of: vault.root)

    #expect(index.backlinks(toTitle: "Curva").map(\.relativePath) == ["Fonte.md"])
    #expect(NoteRename.rewritingLinks(
        in: "Vedi [[**Curva**]].", from: "Curva", to: "Nuovo", includeQuotedRelated: false
    ) == "Vedi [[**Nuovo**]].")
}

// MARK: - Through `related`

@Test func anEmphasisedRelatedLinkIsABacklinkAndAnEdgeOfTheNeighbourhood() throws {
    let vault = try TemporaryVault()
    try vault.write(frontmatter, to: "Curva.md")
    try vault.write("""
    ---
    date: 2026-10-16
    tags:
      - type-note
    related:
      - "[[**Curva**]]"
    ---

    Nessun link nel corpo.

    """, to: "Fonte.md")

    let index = snapshot(of: vault.root)

    #expect(index.backlinks(toTitle: "Curva").map(\.relativePath) == ["Fonte.md"])
    #expect(index.neighbourhood(ofTitle: "Curva").contains("Fonte.md"))
    #expect(index.neighbourhood(ofTitle: "Fonte").contains("Curva.md"))
}

// MARK: - The SPEC's rename invariant (line 114)

@Test func aRenameLeavesTheSourceNotesUnresolvedTargetsUnchanged() throws {
    let vault = try TemporaryVault()
    try vault.write(frontmatter, to: "Curva.md")
    try vault.write(frontmatter + "Vedi [[**Curva**]] e [[Assente]].\n", to: "Fonte.md")
    let root = vault.root

    #expect(snapshot(of: root).unresolvedTargets(of: "Fonte.md") == ["Assente"], "prima della rinomina")

    let operations = NoteFileOperations(store: NoteStore(root: root))
    let plan = try operations.renamePlan("Curva.md", to: "Nuovo", knownPaths: ["Curva.md", "Fonte.md"])
    let change = try #require(plan.noteChanges.first { $0.path == "Fonte.md" })
    #expect(change.after.contains("[[**Nuovo**]]"), "la rinomina segue il link in grassetto")

    try vault.remove("Curva.md")
    try vault.write(frontmatter, to: plan.newPath)
    try vault.write(change.after, to: "Fonte.md")

    #expect(snapshot(of: root).unresolvedTargets(of: "Fonte.md") == ["Assente"], "dopo la rinomina")
}

// MARK: - (coverage) the readers of the stored title (ADR-0097 §D2, §D3)

/// «Task collegati» is the reverse of the backlink relation: a task naming `[[**Curva**]]` is
/// found from `Curva`, through a real scan, the `StoredTask` re-parse route included.
@Test func aTaskNamingAnEmphasisedLinkIsATaskLinkingToItsTitle() throws {
    let vault = try TemporaryVault()
    try vault.write(frontmatter, to: "Curva.md")
    try vault.write(frontmatter + "- [ ] chiamare [[**Curva**]]\n", to: "Fonte.md")

    let tasks = snapshot(of: vault.root).tasks(linkingTo: "Curva")

    #expect(tasks.map(\.sourcePath) == ["Fonte.md"])
}

/// `tasks(linkingTo:)` folds both sides the way the rule does (trim, then lowercase), so a title
/// handed over with surrounding spaces and another case still finds the task.
@Test func tasksLinkingToATitleFoldSpacesAndCase() throws {
    let vault = try TemporaryVault()
    try vault.write(frontmatter, to: "Curva.md")
    try vault.write(frontmatter + "- [ ] chiamare [[Curva]]\n", to: "Fonte.md")

    let tasks = snapshot(of: vault.root).tasks(linkingTo: " curva ")

    #expect(tasks.map(\.sourcePath) == ["Fonte.md"])
}

/// The vault-wide «Link non risolti»: two spellings of one missing title are one entry, shown
/// as the title, with both notes as its sources.
@Test func anEmphasisedAndAPlainUnresolvedLinkAreOneEntryUnderTheTitle() throws {
    let vault = try TemporaryVault()
    try vault.write(frontmatter + "Vedi [[**Assente**]].\n", to: "Prima.md")
    try vault.write(frontmatter + "Vedi [[Assente]].\n", to: "Seconda.md")

    let unresolved = snapshot(of: vault.root).unresolvedLinks()

    #expect(unresolved.map(\.target) == ["Assente"])
    #expect(unresolved.first.map { Set($0.sources.map(\.relativePath)) } == ["Prima.md", "Seconda.md"])
}

/// The index writes and reads `backlinkIndex` through one fold: a plain target with spaces
/// inside the brackets is a backlink, and a query with spaces around the title finds it.
@Test func aSpacedPlainLinkIsFoundByTheTitleAndByASpacedQuery() throws {
    let vault = try TemporaryVault()
    try vault.write(frontmatter, to: "Curva.md")
    try vault.write(frontmatter + "Vedi [[ Curva ]].\n", to: "Fonte.md")

    let index = snapshot(of: vault.root)
    #expect(index.backlinks(toTitle: "Curva").map(\.relativePath) == ["Fonte.md"])
    #expect(index.backlinks(toTitle: " curva ").map(\.relativePath) == ["Fonte.md"])
    #expect(!index.orphans.contains("Curva.md"))
}

