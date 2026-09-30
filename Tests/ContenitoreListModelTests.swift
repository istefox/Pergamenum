import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D7 and §D11, plan docs/plans/contenitore.md, Task 7 - R-13, R-14, R-15,
// R-19, R-25. What the pane lists is a pure function of the index: the schede under the root,
// narrowed by the scope and the filter; the container column is the folders under the root with
// the year folders left out.

private let root = "Contenitore"
private let fatture = "Contenitore/Fatture/2026/20260314 Fattura"
private let arrivo = "Contenitore/2026/20260929 Scansione"
private let topic = Tag(namespace: .topic, value: "fatture")

@MainActor
private func openSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

/// One classified red document in «Fatture», one in the inbox at the root's year folder, a
/// scheda outside the root and an ordinary note under it.
@MainActor
private func seededSession(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try ContenitoreFixture.seed(
        stem: "20260314 Fattura", in: "Contenitore/Fatture/2026", tags: ContenitoreFixture.classified,
        colour: .rosso, sha256: String(repeating: "aa", count: 32), vault: vault
    )
    try ContenitoreFixture.seed(
        stem: "20260929 Scansione", in: "Contenitore/2026", date: "2026-09-29",
        sha256: String(repeating: "bb", count: 32), vault: vault
    )
    try ContenitoreFixture.seed(stem: "20260101 Fuori", in: "Altrove", vault: vault)
    try vault.write("---\ndate: 2026-09-29\ntags:\n  - type-note\n---\n\nNota.\n", to: "Contenitore/Nota.md")
    return await openSession(vault)
}

@MainActor
private func rows(
    _ session: VaultSession, filter: ContenitoreFilter = ContenitoreFilter(), scope: ContenitoreScope = .all,
    extraction: (String) -> ExtractedText? = { _ in nil }
) -> [ContenitoreRow] {
    ContenitoreListModel.rows(
        index: session.index, root: root, filter: filter, container: scope,
        fileExists: session.exists,
        status: { extraction($0).map(ExtractionSummary.init) }, text: { extraction($0)?.text }
    )
}

// MARK: - Rows (R-13)

@MainActor
@Test func everySchedaUnderTheRootIsARowAndNothingElseIs() async throws {
    let vault = try TemporaryVault()
    let session = try await seededSession(vault)
    let done = ExtractedText(method: .textLayer, status: .done, text: "Importo 120 euro")

    let listed = rows(session) { $0 == String(repeating: "aa", count: 32) ? done : nil }

    #expect(listed.map(\.schedaPath) == ["\(arrivo).md", "\(fatture).md"], "newest first")
    let fattura = try #require(listed.last)
    #expect(fattura.name == "20260314 Fattura")
    #expect(fattura.date == CalendarDate(iso: "2026-03-14"))
    #expect(fattura.colour == .rosso)
    #expect(fattura.tags == ContenitoreFixture.classified)
    #expect(fattura.extractionLabel == "testo")
    #expect(fattura.container == "Contenitore/Fatture")
    #expect(fattura.filePath == "\(fatture).pdf")
    #expect(!fattura.isFileMissing)
    #expect(listed.first?.extractionLabel == "in attesa")
    #expect(listed.first?.colour == nil)
    #expect(listed.first?.container == root)
}

@MainActor
@Test func theSearchFieldMatchesTheExtractedTextWithoutCaseOrAccents() async throws {
    let vault = try TemporaryVault()
    let session = try await seededSession(vault)
    let done = ExtractedText(method: .ocr, status: .done, text: "Società Elettrica")
    var filter = ContenitoreFilter()
    filter.query = "societa"

    let listed = rows(session, filter: filter) { $0 == String(repeating: "bb", count: 32) ? done : nil }

    #expect(listed.map(\.schedaPath) == ["\(arrivo).md"])
}

// MARK: - «Da classificare» (R-14)

@MainActor
@Test func theInboxHoldsExactlyTheStatusInboxSchedeAndCountsThem() async throws {
    let vault = try TemporaryVault()
    let session = try await seededSession(vault)

    #expect(rows(session, scope: .inbox).map(\.schedaPath) == ["\(arrivo).md"])
    #expect(ContenitoreListModel.inboxCount(index: session.index, root: root) == 1)
    #expect(rows(session, scope: .container("Contenitore/Fatture")).map(\.schedaPath) == ["\(fatture).md"])
}

// MARK: - Filters (R-15)

@MainActor
@Test func theColourAndTagFiltersNarrowTheRows() async throws {
    let vault = try TemporaryVault()
    let session = try await seededSession(vault)

    var red = ContenitoreFilter()
    red.colours = [.rosso]
    #expect(rows(session, filter: red).map(\.schedaPath) == ["\(fatture).md"])

    var green = ContenitoreFilter()
    green.colours = [.verde]
    #expect(rows(session, filter: green).isEmpty)

    var tagged = ContenitoreFilter()
    tagged.tags = [topic]
    #expect(rows(session, filter: tagged).map(\.schedaPath) == ["\(fatture).md"])

    var inbox = ContenitoreFilter()
    inbox.tags = [ContenitoreFixture.inbox]
    #expect(rows(session, filter: inbox).map(\.schedaPath) == ["\(arrivo).md"])
    #expect(inbox.isActive)
}

// MARK: - «file mancante» (R-25)

@MainActor
@Test func aSchedaWhoseFileIsGoneIsARowMarkedFileMissing() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: "20260314 Persa", in: "Contenitore/2026", withFile: false, vault: vault)
    let session = await openSession(vault)

    let row = try #require(rows(session).first)

    #expect(row.isFileMissing)
    #expect(row.name == "20260314 Persa")
    #expect(row.filePath == "Contenitore/2026/20260314 Persa.pdf")
}

@MainActor
@Test func aSchedaRenamedAloneInTheFinderReadsFileMissingLikeApriDoes() async throws {
    let vault = try TemporaryVault()
    let old = try ContenitoreFixture.seed(stem: "20260314 Fattura", in: "Contenitore/2026", vault: vault)
    let text = try ContenitoreFixture.text(old, in: vault.root)
    try vault.remove(old)
    let renamed = "Contenitore/2026/20260314 Altro.md"
    try vault.write(text, to: renamed)
    let session = await openSession(vault)

    let row = try #require(rows(session).first)

    // Its key still names `20260314 Fattura.pdf`, which sits beside it, but under another stem
    // the scheda no longer owns that file: the rule `companion(ofScheda:)` applies to «Apri».
    #expect(session.companion(ofScheda: renamed) == nil)
    #expect(row.schedaPath == renamed)
    #expect(row.isFileMissing)
    #expect(row.filePath == nil)
}

@Test func companionPathAppliesTheStemRuleAndNeverNamesANoteOrAPath() {
    let scheda = "Contenitore/2026/20260314 Fattura.md"
    #expect(ContenitoreScheda.companionPath(ofSchedaAt: scheda, fileName: "20260314 Fattura.pdf")
        == "Contenitore/2026/20260314 Fattura.pdf")
    #expect(ContenitoreScheda.companionPath(ofSchedaAt: scheda, fileName: "20260314 FATTURA.PDF")
        == "Contenitore/2026/20260314 FATTURA.PDF")
    #expect(ContenitoreScheda.companionPath(ofSchedaAt: "Nota.md", fileName: "Nota.pdf") == "Nota.pdf")
    #expect(ContenitoreScheda.companionPath(ofSchedaAt: scheda, fileName: "Altro.pdf") == nil)
    #expect(ContenitoreScheda.companionPath(ofSchedaAt: scheda, fileName: "20260314 Fattura.md") == nil)
    #expect(ContenitoreScheda.companionPath(ofSchedaAt: scheda, fileName: "../20260314 Fattura.pdf") == nil)
    #expect(ContenitoreScheda.companionPath(ofSchedaAt: scheda, fileName: "") == nil)
}

// MARK: - The container tree (R-19)

@Test func yearAndHiddenFoldersAreNotNodesAndNestedContainersAre() {
    let tree = ContenitoreListModel.containerTree(root: root, folders: [
        "Contenitore/Fatture/2026", "Contenitore/Fatture", "Contenitore/Fatture/Luce",
        "Contenitore/Fatture/Luce/2025", "Contenitore/2025", "Contenitore/.nascosta", "Altrove/Fatture",
    ])

    #expect(tree.map(\.path) == ["Contenitore/Fatture"])
    #expect(tree.first?.children.map(\.path) == ["Contenitore/Fatture/Luce"])
    #expect(tree.first?.children.first?.depth == 1)
    #expect(tree.first?.children.first?.children.isEmpty == true)
    #expect(ContenitoreListModel.flattened(tree, expanded: []).map(\.path) == ["Contenitore/Fatture"])
    #expect(ContenitoreListModel.flattened(tree, expanded: ["Contenitore/Fatture"]).map(\.path)
        == ["Contenitore/Fatture", "Contenitore/Fatture/Luce"])
    #expect(ContenitoreListModel.container(ofFolder: "Contenitore/Fatture/2026", root: root) == "Contenitore/Fatture")
    #expect(ContenitoreListModel.container(ofFolder: "Contenitore/2026", root: root) == root)
}

@MainActor
@Test func theControllerReadsTheTreeFromTheDiskWithoutYearFolders() async throws {
    let vault = try TemporaryVault()
    for folder in ["Contenitore/Fatture/2026", "Contenitore/Fatture/Luce", "Contenitore/2025"] {
        try FileManager.default.createDirectory(
            at: vault.root.appending(path: folder, directoryHint: .isDirectory), withIntermediateDirectories: true
        )
    }
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)

    let tree = harness.contenitore.containers()

    #expect(ContenitoreListModel.allPaths(tree).map(\.path) == ["Contenitore/Fatture", "Contenitore/Fatture/Luce"])
}
