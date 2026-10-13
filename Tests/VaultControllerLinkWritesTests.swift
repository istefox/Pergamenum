import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D5 (a dirty source still raises the conflict prompt, PG-233 kept), SPEC R-27 and
// R-26, plan docs/plans/note-workflow-n3.md Task 1.
//
// «Scollega» and «Collega» write to disk through the session, whatever a tab holds. A tab with
// unsaved edits is asked (ADR-0001 §D3.4, through ADR-0067's landed-change door) and its buffer
// is never saved or replaced; a clean tab adopts the new text. The three places a copy of the
// note can be are the three of ADR-0058 §D2: the focused tab, a background tab of the same
// column, and the other column. No timer, no sleep.

private func note(_ body: String) -> String {
    "---\ndate: 2026-10-07\ntags:\n  - type-note\n---\n\n\(body)\n"
}

enum LinkWritesPlacement: CaseIterable, Sendable, CustomStringConvertible {
    case focused, background, otherColumn

    var description: String {
        switch self {
        case .focused: "scheda a fuoco"
        case .background: "scheda in secondo piano"
        case .otherColumn: "altra colonna"
        }
    }
}

/// A vault with a structural pair, a note with a mention and a free note to open beside.
@MainActor
private func openController(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    let origine = try RelatedLink.add(
        target: "Destinazione", reason: "usa i dati", to: note("Origine."), selfTitle: "Origine"
    )
    let destinazione = try RelatedLink.add(
        target: "Origine", reason: "fornisce i dati", to: note("Destinazione."), selfTitle: "Destinazione"
    )
    try vault.write(origine, to: "Origine.md")
    try vault.write(destinazione, to: "Destinazione.md")
    try vault.write(note("Corpo."), to: "Curva.md")
    try vault.write(note("Si parla di Curva e di altro."), to: "Altra.md")
    try vault.write(note("Libera."), to: "Libera.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

/// Shows `path` in `placement` and returns the tab that holds the copy under test, dirty with
/// `unsaved` when one is given. The other copy, where there is one, stays clean.
@MainActor
private func show(
    _ path: String, in placement: LinkWritesPlacement, unsaved: String?, controller: VaultController
) throws -> NoteTab.ID {
    controller.openNote(at: path)
    switch placement {
    case .focused:
        let id = try #require(controller.focusedTab?.id)
        if let unsaved { controller.updateOpenNoteText(unsaved) }
        return id
    case .background:
        let id = try #require(controller.focusedTab?.id)
        controller.openNoteInNewTab(at: "Libera.md")
        try #require(controller.focusedTab?.note.relativePath == "Libera.md")
        if let unsaved { controller.updateTab(id) { $0.note.text = unsaved } }
        return id
    case .otherColumn:
        controller.splitEditor()
        controller.focusColumn(0)
        let id = try #require(controller.columns[1].tabs.first { $0.note.relativePath == path }?.id)
        try #require(controller.focusedColumnIndex == 0)
        // `updateTab` only finds a tab of the focused column: type into the second column
        // through the focus, the way the write catch-up tests do, then give the focus back.
        if let unsaved {
            controller.focusColumn(1)
            controller.updateOpenNoteText(unsaved)
            controller.focusColumn(0)
        }
        return id
    }
}

@MainActor
private func tab(_ id: NoteTab.ID, in controller: VaultController) throws -> NoteTab {
    try #require(controller.columns.flatMap(\.tabs).first { $0.id == id })
}

private func disk(_ vault: borrowing TemporaryVault, _ path: String) throws -> String {
    try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
}

// MARK: - «Scollega» on a source open dirty

@MainActor
@Test(arguments: LinkWritesPlacement.allCases)
func unlinkingASourceOpenDirtyRaisesThePromptAndNeverSavesTheBuffer(placement: LinkWritesPlacement) async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    let unsaved = try disk(vault, "Origine.md") + "\nNon salvato."
    let id = try show("Origine.md", in: placement, unsaved: unsaved, controller: controller)

    let removed = await controller.removeStructuralLink(from: "Origine.md", toNoteAt: "Destinazione.md")

    #expect(removed, "\(placement)")
    let onDisk = try disk(vault, "Origine.md")
    #expect(!onDisk.contains("[[Destinazione]]"), "\(placement): il legame è tolto dal disco")
    #expect(!onDisk.contains("Non salvato."), "\(placement): il buffer non viene mai salvato")
    let dirty = try tab(id, in: controller)
    #expect(dirty.note.externalChangePending == .text(onDisk), "\(placement): il prompt dell'ADR-0001 §D3.4")
    #expect(dirty.note.text == unsaved, "\(placement): le modifiche non salvate restano")
}

@MainActor
@Test func unlinkingATargetOpenDirtyRaisesThePromptToo() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    let unsaved = try disk(vault, "Destinazione.md") + "\nNon salvato."
    let id = try show("Destinazione.md", in: .focused, unsaved: unsaved, controller: controller)

    #expect(await controller.removeStructuralLink(from: "Origine.md", toNoteAt: "Destinazione.md"))

    let onDisk = try disk(vault, "Destinazione.md")
    #expect(!onDisk.contains("[[Origine]]"))
    let dirty = try tab(id, in: controller)
    #expect(dirty.note.externalChangePending == .text(onDisk))
    #expect(dirty.note.text == unsaved)
}

@MainActor
@Test(arguments: LinkWritesPlacement.allCases)
func unlinkingASourceOpenCleanAdoptsTheNewText(placement: LinkWritesPlacement) async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    let id = try show("Origine.md", in: placement, unsaved: nil, controller: controller)

    #expect(await controller.removeStructuralLink(from: "Origine.md", toNoteAt: "Destinazione.md"))

    let onDisk = try disk(vault, "Origine.md")
    try #require(!onDisk.contains("[[Destinazione]]"))
    let clean = try tab(id, in: controller)
    #expect(clean.note.text == onDisk, "\(placement)")
    #expect(clean.note.savedText == onDisk, "\(placement)")
    #expect(clean.note.externalChangePending == nil, "\(placement)")
}

@MainActor
@Test func unlinkingAnUnlinkedPairReportsFalseAndDisturbsNoTab() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    let unsaved = try disk(vault, "Altra.md") + "\nNon salvato."
    let id = try show("Altra.md", in: .focused, unsaved: unsaved, controller: controller)

    #expect(await !controller.removeStructuralLink(from: "Altra.md", toNoteAt: "Libera.md"))

    let untouched = try tab(id, in: controller)
    #expect(untouched.note.text == unsaved)
    #expect(untouched.note.externalChangePending == nil, "nessuna scrittura, nessun prompt")
    #expect(controller.problems.contains { $0.contains("nessun legame strutturale") })
}

// MARK: - «Collega» on a note open dirty

@MainActor
private func planned(_ controller: VaultController) throws -> (before: String, after: String, hash: String) {
    let session = try #require(controller.session)
    return try #require(session.planLinkMention(in: "Altra.md", to: "Curva"))
}

@MainActor
@Test(arguments: LinkWritesPlacement.allCases)
func linkingAMentionInANoteOpenDirtyRaisesThePromptAndNeverSavesTheBuffer(placement: LinkWritesPlacement) async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    let unsaved = try disk(vault, "Altra.md") + "\nNon salvato."
    let id = try show("Altra.md", in: placement, unsaved: unsaved, controller: controller)
    let plan = try planned(controller)

    let outcome = await controller.linkMention(in: "Altra.md", to: "Curva", expecting: plan.hash)

    guard case .linked = outcome else {
        Issue.record("\(placement): atteso .linked, ottenuto \(outcome)")
        return
    }
    let onDisk = try disk(vault, "Altra.md")
    #expect(onDisk == plan.after, "\(placement): arriva sul disco esattamente ciò che il diff ha mostrato")
    #expect(!onDisk.contains("Non salvato."), "\(placement): il buffer non viene mai salvato")
    let dirty = try tab(id, in: controller)
    #expect(dirty.note.externalChangePending == .text(onDisk), "\(placement)")
    #expect(dirty.note.text == unsaved, "\(placement)")
}

@MainActor
@Test(arguments: LinkWritesPlacement.allCases)
func linkingAMentionInANoteOpenCleanAdoptsTheNewText(placement: LinkWritesPlacement) async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    let id = try show("Altra.md", in: placement, unsaved: nil, controller: controller)
    let plan = try planned(controller)

    let outcome = await controller.linkMention(in: "Altra.md", to: "Curva", expecting: plan.hash)

    guard case .linked = outcome else {
        Issue.record("\(placement): atteso .linked, ottenuto \(outcome)")
        return
    }
    let clean = try tab(id, in: controller)
    #expect(clean.note.text == plan.after, "\(placement)")
    #expect(clean.note.savedText == plan.after, "\(placement)")
    #expect(clean.note.externalChangePending == nil, "\(placement)")
}

@MainActor
@Test func aMovedOnMentionLeavesTheOpenBufferAndTheDiskAlone() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    _ = try show("Altra.md", in: .focused, unsaved: nil, controller: controller)
    let plan = try planned(controller)
    let changed = note("Si parla di Curva e di altro.\n\nRiga di un altro scrittore.")
    try vault.write(changed, to: "Altra.md")

    let outcome = await controller.linkMention(in: "Altra.md", to: "Curva", expecting: plan.hash)

    #expect(outcome == .movedOn)
    #expect(try disk(vault, "Altra.md") == changed)
}

// MARK: - (coverage) a controller with no vault open

/// (coverage) The controller's wrappers answer without a session instead of reaching for one.
@MainActor
@Test func theLinkWritesWithNoVaultOpenAnswerRefusedAndWriteNothing() async {
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())

    #expect(await !controller.removeStructuralLink(from: "A.md", toNoteAt: "B.md"))
    #expect(await controller.linkMention(in: "A.md", to: "B", expecting: "hash") == .failed("nessun vault aperto"))
}
