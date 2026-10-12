import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D1 (rows with context), §D2 (the open note's own unresolved links), §D4
// («Rendi strutturale» preselects) and §D6 («Dove compare» memo), SPEC R-24, R-25, R-27 and
// R-28, plan docs/plans/note-workflow-n3.md Task 5.
//
// The inspector's SwiftUI rows cannot be pressed in-process (PG-380), so what is tested is
// everything the rows call: the controller's row builders and the doors behind the buttons.
// A temporary vault, no timer, no sleep.

private func note(_ body: String) -> String {
    "---\ndate: 2026-10-07\ntags:\n  - type-note\n---\n\n\(body)\n"
}

/// «Curva» is the note whose inspector is read. «Origine» links it structurally, «Altra» links it
/// twice in prose, and «Curva» itself has dangling links.
@MainActor
private func openController(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    let origine = try RelatedLink.add(
        target: "Curva", reason: "usa i dati", to: note("Origine."), selfTitle: "Origine"
    )
    try vault.write(origine, to: "Origine.md")
    try vault.write(note("Prima.\nVedi [[Curva]] qui.\nE ancora [[Curva]]."), to: "Altra.md")
    try vault.write(
        note("Prima [[Altra]].\nPoi [[Mancante]] e [[Nuova Idea]].\nAncora [[mancante]] e [[Piano.md]]."),
        to: "Curva.md"
    )
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

// MARK: - backlinkRows(toTitle:)

@MainActor
@Test func theBacklinkRowsGiveTheLineTheCountAndTheBadgeFromTheFiles() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }

    let rows = controller.backlinkRows(toTitle: "Curva")

    #expect(rows.map(\.path) == ["Altra.md", "Origine.md"], "one row per note, in the index's title order")
    let altra = try #require(rows.first { $0.path == "Altra.md" })
    #expect(altra.title == "Altra")
    #expect(altra.firstLine == "Vedi [[Curva]] qui.")
    #expect(altra.count == 2)
    #expect(!altra.isStructural)
    let origine = try #require(rows.first { $0.path == "Origine.md" })
    #expect(origine.isStructural, "Origine's `related` names Curva")
    #expect(origine.count == 1, "the «Note correlate» bullet is its one link")
    #expect(origine.firstLine?.contains("[[Curva]]") == true, "the bullet's line is its context")
}

@MainActor
@Test func aWriteThatMovesTheIndexGenerationRefreshesTheLine() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    let session = try #require(controller.session)
    let before = controller.backlinkRows(toTitle: "Curva")
    try #require(before.first { $0.path == "Altra.md" }?.firstLine == "Vedi [[Curva]] qui.")
    let generation = controller.indexGeneration

    try await session.write(note("Riscritta, vedi [[Curva]] adesso."), to: "Altra.md")

    try #require(controller.indexGeneration != generation, "the write has to move the index generation")
    let altra = try #require(controller.backlinkRows(toTitle: "Curva").first { $0.path == "Altra.md" })
    #expect(altra.firstLine == "Riscritta, vedi [[Curva]] adesso.")
    #expect(altra.count == 1)
}

@MainActor
@Test func buildingTheRowsLeavesTheIndexRecordUntouched() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    let recordBefore = try #require(controller.index.note(at: "Altra.md"))

    let rows = controller.backlinkRows(toTitle: "Curva")

    try #require(!rows.isEmpty)
    #expect(controller.index.note(at: "Altra.md") == recordBefore, "the index stores paths only (SPEC R-24)")
}

@MainActor
@Test func aTitleNobodyLinksHasNoRows() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }

    #expect(controller.backlinkRows(toTitle: "Altra").map(\.path) == ["Curva.md"], "the control case has a row")
    #expect(controller.backlinkRows(toTitle: "Origine").isEmpty)
}

@MainActor
@Test func aBacklinkWhoseFileCannotBeReadStillHasItsRowWithoutALine() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    // The index still holds the note (no rescan ran); the file is gone from under it.
    try FileManager.default.removeItem(at: vault.root.appending(path: "Altra.md"))

    let rows = controller.backlinkRows(toTitle: "Curva")

    #expect(rows.map(\.path) == ["Altra.md", "Origine.md"], "the unreadable note is still listed")
    let altra = try #require(rows.first { $0.path == "Altra.md" })
    #expect(altra.title == "Altra")
    #expect(altra.firstLine == nil, "no line to show, but the row stays")
    #expect(try #require(rows.first { $0.path == "Origine.md" }).isStructural, "the others are read as before")
}

/// An unreadable row still knows whether its link is structural, from the index's own `related`,
/// so the menu does not offer «Rendi strutturale» for a link that already is.
@MainActor
@Test func anUnreadableBacklinkKeepsItsStructuralBadgeFromTheIndex() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    try FileManager.default.removeItem(at: vault.root.appending(path: "Origine.md"))

    let origine = try #require(controller.backlinkRows(toTitle: "Curva").first { $0.path == "Origine.md" })

    #expect(origine.firstLine == nil, "the file is gone, so is its line")
    #expect(origine.isStructural, "the index still holds Origine's `related`")
    #expect(!BacklinkCommand.available(for: origine).contains(.makeStructural))
}

// MARK: - linkableMentions(ofNoteAt:) and sharedTitle(ofNoteAt:)

/// «A/Riunione» has the alias «Incontro», and `homonym` adds a «B/Riunione». «Titolo» names the
/// title, «Alias» names only the alias.
@MainActor
private func openMentionVault(_ vault: borrowing TemporaryVault, homonym: Bool) async throws -> VaultController {
    let aliased = "---\ndate: 2026-10-07\ntags:\n  - type-note\naliases:\n  - Incontro\n---\n\nCorpo.\n"
    try vault.write(aliased, to: "A/Riunione.md")
    if homonym { try vault.write(note("Altro corpo."), to: "B/Riunione.md") }
    try vault.write(note("Ne parla la Riunione di ieri."), to: "Titolo.md")
    try vault.write(note("Un Incontro breve."), to: "Alias.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

@MainActor
@Test func onASharedTitleAnAliasOnlyMentionStaysBesideTheTitleOne() async throws {
    let vault = try TemporaryVault()
    let controller = try await openMentionVault(vault, homonym: true)
    defer { controller.close() }
    let scanned = Set(controller.unlinkedMentions(for: "A/Riunione.md").map(\.path))
    try #require(scanned == ["Titolo.md", "Alias.md"], "the scan finds both")

    // No «Collega» is offered on a shared title, so no row needs to be linkable to be listed.
    #expect(Set(controller.linkableMentions(ofNoteAt: "A/Riunione.md").map(\.path)) == scanned)
    #expect(controller.sharedTitle(ofNoteAt: "A/Riunione.md") == "Riunione")
}

@MainActor
@Test func onASharedTitleAnAliasOnlyMentionAloneIsNotAnEmptyList() async throws {
    let vault = try TemporaryVault()
    let aliased = "---\ndate: 2026-10-07\ntags:\n  - type-note\naliases:\n  - Incontro\n---\n\nCorpo.\n"
    try vault.write(aliased, to: "A/Riunione.md")
    try vault.write(note("Altro corpo."), to: "B/Riunione.md")
    try vault.write(note("Un Incontro breve."), to: "Alias.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }

    #expect(controller.linkableMentions(ofNoteAt: "A/Riunione.md").map(\.path) == ["Alias.md"],
            "the section would otherwise print «Nessuna nota nomina questa senza linkarla.»")
}

@MainActor
@Test func onATitleOneNoteCarriesAnAliasOnlyMentionStays() async throws {
    let vault = try TemporaryVault()
    let controller = try await openMentionVault(vault, homonym: false)
    defer { controller.close() }

    #expect(Set(controller.linkableMentions(ofNoteAt: "A/Riunione.md").map(\.path)) == ["Titolo.md", "Alias.md"])
    #expect(controller.sharedTitle(ofNoteAt: "A/Riunione.md") == nil, "«Collega» is offered")
}

// MARK: - unlinkStructuralLink(from:toNoteAt:)

@MainActor
@Test func unlinkingAStructuralLinkAnswersNilWhenItIsGone() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }

    let refusal = await controller.unlinkStructuralLink(from: "Curva.md", toNoteAt: "Origine.md")

    #expect(refusal == nil)
    let origine = try #require(controller.session).read("Origine.md").text
    #expect(!origine.contains("[[Curva]]"))
}

@MainActor
@Test func unlinkingTwoNotesThatAreNotStructurallyLinkedNamesWhy() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }

    let refusal = await controller.unlinkStructuralLink(from: "Curva.md", toNoteAt: "Altra.md")

    #expect(refusal == "nessun legame strutturale fra «Curva» e «Altra»")
}

@MainActor
@Test func unlinkingOnASharedTitleNamesTheHomonymInsteadOfDoingNothing() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    try vault.write(note("Un'omonima."), to: "Altrove/Origine.md")
    await controller.rescan()

    let refusal = try #require(await controller.unlinkStructuralLink(from: "Curva.md", toNoteAt: "Origine.md"))

    #expect(refusal.contains("«Origine»"))
    #expect(refusal.contains("rinomina una delle omonime"))
    let origine = try #require(controller.session).read("Origine.md").text
    #expect(origine.contains("[[Curva]]"), "a refusal writes nothing")
}

// MARK: - unresolvedLinkRows(ofNoteAt:)

@MainActor
@Test func theUnresolvedRowsAreTheOpenNotesOwnDanglingTargetsDeduplicatedIgnoringCase() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }

    let rows = controller.unresolvedLinkRows(ofNoteAt: "Curva.md")

    #expect(rows.map(\.id) == ["mancante", "nuova idea", "piano.md"], "in the order the note links them")
    #expect(rows.first?.target == "Mancante", "the first spelling is the one shown")
}

@MainActor
@Test func aTargetThatIsNotATitleIsNotCreatable() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }

    let rows = controller.unresolvedLinkRows(ofNoteAt: "Curva.md")

    #expect(rows.first { $0.id == "piano.md" }?.isCreatable == false, "`[[Piano.md]]` names a path")
    #expect(rows.first { $0.id == "mancante" }?.isCreatable == true)
    #expect(rows.first { $0.id == "nuova idea" }?.isCreatable == true)
}

@MainActor
@Test func otherNotesDanglingLinksAreNotThisNotes() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    try vault.write(note("Solo qui [[Altrove]]."), to: "Lontana.md")
    await controller.rescan()

    #expect(controller.unresolvedLinkRows(ofNoteAt: "Lontana.md").map(\.target) == ["Altrove"])
    #expect(!controller.unresolvedLinkRows(ofNoteAt: "Curva.md").contains { $0.target == "Altrove" })
    #expect(controller.unresolvedLinkRows(ofNoteAt: "Origine.md").isEmpty)
}

// MARK: - goToLink(target:)

@MainActor
@Test func goToLinkSetsTheJumpForTheFirstLineHoldingTheLink() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        note("Prima [[Altra]].\nPoi [[Mancante]] e [[Nuova Idea]].\nAncora [[Mancante]]."), to: "Curva.md"
    )
    try vault.write(note("Altra."), to: "Altra.md")
    let actions = await LinkFixtures.actions(root: vault.root)
    defer { actions.vault.close() }
    actions.vault.openNote(at: "Curva.md")
    let text = try #require(actions.vault.openNote?.text)
    let lines = text.components(separatedBy: "\n")
    let lineIndex = try #require(lines.firstIndex { $0.contains("[[Mancante]]") })
    let range = try #require(NoteJump.lineRange(lineIndex, in: text))
    actions.navigation.pane = .tasks

    actions.goToLink(target: "Mancante")

    let jump = try #require(actions.navigation.outlineJump)
    #expect(jump.range == NSRange(range, in: text), "the first line holding [[Mancante]], not the second")
    #expect(jump.ordinal == NoteJump.ordinal(of: range.lowerBound, in: text))
    #expect(actions.navigation.pane == .notes, "the jump brings the Note pane forward")
}

@MainActor
@Test func twoJumpsToTheSameLinkAreTwoEvents() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Poi [[Mancante]]."), to: "Curva.md")
    let actions = await LinkFixtures.actions(root: vault.root)
    defer { actions.vault.close() }
    actions.vault.openNote(at: "Curva.md")

    actions.goToLink(target: "Mancante")
    let first = try #require(actions.navigation.outlineJump)
    actions.goToLink(target: "Mancante")

    #expect(try #require(actions.navigation.outlineJump).id != first.id)
}

// MARK: - beginStructuralLink(preselecting:)

@MainActor
@Test func beginningAStructuralLinkSetsThePreselectionAndRaisesTheSheet() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    try #require(!controller.isAddingRelatedLink)

    controller.beginStructuralLink(preselecting: "Altra.md")

    #expect(controller.isAddingRelatedLink)
    #expect(controller.structuralLinkPreselection == "Altra.md")
}

@MainActor
@Test func thePreselectionIsHandedOverOnce() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    controller.beginStructuralLink(preselecting: "Altra.md")

    #expect(controller.takeStructuralLinkPreselection() == "Altra.md")
    #expect(controller.takeStructuralLinkPreselection() == nil)
    #expect(controller.structuralLinkPreselection == nil)
}

@MainActor
@Test func beginningWithoutAPathRaisesTheSheetAndLeavesNoOldPreselectionBehind() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    controller.beginStructuralLink(preselecting: "Altra.md")
    controller.isAddingRelatedLink = false

    controller.beginStructuralLink(preselecting: nil)

    #expect(controller.isAddingRelatedLink, "«Nota correlata…» opens the same sheet")
    #expect(controller.takeStructuralLinkPreselection() == nil, "the earlier row's choice does not leak")
}

// MARK: - noteAppearances(ofNoteAt:rescan:)

private func board(withFilesAt paths: [String]) -> String {
    let nodes = paths.enumerated().map { index, path in
        "{\"id\":\"n\(index)\",\"type\":\"file\",\"file\":\"\(path)\",\"x\":0,\"y\":0,\"width\":260,\"height\":180}"
    }
    return "{\"nodes\":[\(nodes.joined(separator: ","))],\"edges\":[]}"
}

@MainActor
private func controllerWithBoard(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(note("Corpo."), to: "Tecnica/Curva.md")
    try vault.write(note("Altra."), to: "Tecnica/Altra.md")
    try vault.write(board(withFilesAt: ["Tecnica/Curva.md"]), to: "Lavagne/Taratura.canvas")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

@MainActor
@Test func theAppearancesAreReadOffTheFiles() async throws {
    let vault = try TemporaryVault()
    let controller = try await controllerWithBoard(vault)
    defer { controller.close() }

    let appearances = controller.noteAppearances(ofNoteAt: "Tecnica/Curva.md", rescan: false)

    #expect(appearances.boards.map(\.path) == ["Lavagne/Taratura.canvas"])
    #expect(controller.noteAppearances(ofNoteAt: "Tecnica/Altra.md", rescan: false).boards.isEmpty)
}

@MainActor
@Test func withoutRescanAnUnchangedGenerationAnswersFromTheMemoAndRescanSeesTheBoardSavedSince() async throws {
    let vault = try TemporaryVault()
    let controller = try await controllerWithBoard(vault)
    defer { controller.close() }
    let first = controller.noteAppearances(ofNoteAt: "Tecnica/Curva.md", rescan: false)
    try #require(first.boards.map(\.path) == ["Lavagne/Taratura.canvas"])
    let generation = controller.indexGeneration

    // A board save does not move the index generation: the node goes, the memo's key stays.
    try vault.write(board(withFilesAt: []), to: "Lavagne/Taratura.canvas")
    try #require(controller.indexGeneration == generation, "a board save must not move the generation")

    #expect(
        controller.noteAppearances(ofNoteAt: "Tecnica/Curva.md", rescan: false) == first,
        "the same generation answers from the memo"
    )
    #expect(
        controller.noteAppearances(ofNoteAt: "Tecnica/Curva.md", rescan: true).boards.isEmpty,
        "«Cerca di nuovo» reads the files again"
    )
}

@MainActor
@Test func theMemoIsKeyedByThePathToo() async throws {
    let vault = try TemporaryVault()
    let controller = try await controllerWithBoard(vault)
    defer { controller.close() }
    try #require(controller.noteAppearances(ofNoteAt: "Tecnica/Altra.md", rescan: false).boards.isEmpty)

    let curva = controller.noteAppearances(ofNoteAt: "Tecnica/Curva.md", rescan: false)

    #expect(curva.boards.map(\.path) == ["Lavagne/Taratura.canvas"], "another note's memo is not this one's")
}
