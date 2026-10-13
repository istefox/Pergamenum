import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D7-§D9 and ADR-0086 §D4/§D5, plan docs/plans/pg-387-n4-birth-of-note.md,
// Task 4 - R-11, R-12: the composer as one naming surface in three hosts. What it composes from a
// draft (tags, the template body resolved, the caret), what each host fixes, what blocks «Crea»,
// and what the pane host's creation does (a tab with the caret, the creation offer).
//
// «Crea» is pressed the way the hosted harness allows: Return handed to the hosting view as a key
// equivalent reaches the `.defaultAction` button (`HostedViewSupport.swift`). No window is shown
// and no event is sent.

private typealias VaultTag = Pergamenum.Tag

private let topic = VaultTag("topic-x")!

private let vocabulary = Vocabulary(
    type: ["note", "invoice"], status: ["inbox", "active"], area: ["sales"], source: ["email"],
    deliverableKind: []
)

private let template = """
---
date: 2026-01-01
tags:
  - type-note
  - topic-modello
---

Inizio {{title}} {{cursor}}fine
"""

/// What `perform` was handed, kept where the test can read it back inside its own task.
@MainActor
private final class Captured {
    var compositions: [NoteComposition] = []
}

@MainActor
private func composer(
    app: NoteBirthApp, draft: VaultController.NoteDraft, host: NewNoteComposer.Host, captured: Captured
) -> HostedView<some View> {
    app.hosted(
        NewNoteComposer(
            draft: draft, host: host,
            perform: { composition in
                captured.compositions.append(composition)
                return "\(composition.title).md"
            },
            onCreated: { _ in }, onCancel: {}
        ),
        size: CGSize(width: 520, height: 560)
    )
}

private func draft(
    title: String = "Verbale", folder: String = "", template: String = "", tags: [VaultTag] = []
) -> VaultController.NoteDraft {
    var draft = VaultController.NoteDraft()
    draft.title = title
    draft.folder = folder
    draft.template = template
    draft.tags = tags
    return draft
}

@MainActor
private func makeApp(_ vault: borrowing TemporaryVault) async throws -> NoteBirthApp {
    try vault.write(template, to: "Templates/Riunione.md")
    return try await NoteBirthApp.make(vault)
}

private func create(_ host: HostedView<some View>) async throws {
    try await host.key("\r", keyCode: 36)
}

// MARK: - What the composer composes (R-11, R-12, ADR-0086 §D4/§D5)

@MainActor
@Test func theCompositionCarriesTheDraftsTagsTheResolvedTemplateBodyAndTheCaret() async throws {
    let vault = try TemporaryVault()
    let app = try await makeApp(vault)
    let captured = Captured()
    let host = composer(
        app: app, draft: draft(template: "Templates/Riunione.md", tags: [topic]), host: .pane, captured: captured
    )
    defer { host.tearDown() }
    await host.settle()

    try await create(host)

    let composition = try #require(captured.compositions.first, "Return did not press «Crea»")
    #expect(composition.title == "Verbale")
    #expect(composition.tags.contains(topic)) // R-12: the tags the field resolved travel with it
    #expect(composition.body.contains("Inizio Verbale "), "the title placeholder is resolved") // ADR-0086 §D5
    #expect(!composition.body.contains("{{"), "no placeholder reaches the written note")
    let fine = (composition.body as NSString).range(of: "fine").location
    #expect(composition.bodyCaret == fine, "the caret is where {{cursor}} was") // R-08

    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
}

@MainActor
@Test func aNoteWithoutATemplateHasAnEmptyBodyAndNoCaret() async throws {
    let vault = try TemporaryVault()
    let app = try await makeApp(vault)
    let captured = Captured()
    let host = composer(app: app, draft: draft(), host: .pane, captured: captured)
    defer { host.tearDown() }
    await host.settle()

    try await create(host)

    let composition = try #require(captured.compositions.first)
    #expect(composition.body.isEmpty)
    #expect(composition.bodyCaret == nil)
    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
}

// MARK: - What each host fixes (R-11)

@MainActor
@Test func theSheetHostFixesTheFolderWhateverTheDraftSaid() async throws {
    let vault = try TemporaryVault()
    let app = try await makeApp(vault)
    let captured = Captured()
    let host = composer(
        app: app, draft: draft(folder: "Altra cartella"), host: .sheet(folder: "Progetti/Board"), captured: captured
    )
    defer { host.tearDown() }
    await host.settle()

    try await create(host)

    let composition = try #require(captured.compositions.first, "Return did not press «Crea»")
    #expect(composition.folder == "Progetti/Board") // R-11: the board's folder is fixed
    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
}

@MainActor
@Test func theExtractHostHidesTheTemplateAndComposesTheSelectionAsTheBody() async throws {
    let vault = try TemporaryVault()
    let app = try await makeApp(vault)
    let captured = Captured()
    let extraction = VaultController.ExtractionDraft(
        id: UUID(), tabID: UUID(), sourcePath: "Progetti/Sorgente.md", range: NSRange(location: 40, length: 24),
        text: "Due righe\ndi appunti.", title: "Due righe", folder: "Progetti", sourceIsDirty: false
    )
    let host = composer(
        app: app, draft: draft(title: "", template: "Templates/Riunione.md"), host: .extract(extraction),
        captured: captured
    )
    defer { host.tearDown() }
    await host.settle()

    try await create(host)

    let composition = try #require(captured.compositions.first, "Return did not press «Crea»")
    #expect(composition.title == "Due righe", "the title is the one proposed from the first line") // R-13
    #expect(composition.folder == "Progetti", "the folder defaults to the source note's")
    #expect(composition.body == "Due righe\ndi appunti.", "the body is the selection") // ADR-0085 §D8
    #expect(!composition.body.contains("Inizio"), "the template menu is hidden, so the template never applies")
    #expect(composition.bodyCaret == nil)
    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
}

@MainActor
@Test func theComposerBuildsInAllThreeHosts() async throws {
    let vault = try TemporaryVault()
    let app = try await makeApp(vault)
    let extraction = VaultController.ExtractionDraft(
        id: UUID(), tabID: UUID(), sourcePath: "Sorgente.md", range: NSRange(location: 0, length: 5),
        text: "Testo", title: "Testo", folder: "", sourceIsDirty: false
    )

    for hosting in [NewNoteComposer.Host.pane, .sheet(folder: "Progetti"), .extract(extraction)] {
        let host = composer(app: app, draft: draft(), host: hosting, captured: Captured())
        await host.settle()
        #expect(host.snapshot().map { $0.distinctColors > 1 } == true, "\(hosting) drew nothing")
        #expect(host.neverShown)
        #expect(host.refusals.isEmpty)
        host.tearDown()
    }
}

@MainActor
@Test func inTheSheetHostTheComposerFitsTheSheetsFiveHundredTwentyPoints() async throws {
    let vault = try TemporaryVault()
    let app = try await makeApp(vault)
    let host = composer(
        app: app, draft: draft(template: "Templates/Riunione.md"), host: .sheet(folder: "Progetti"),
        captured: Captured()
    )
    defer { host.tearDown() }
    await host.settle()

    #expect(host.hosting.fittingSize.width <= 520, "the sheet is 520 pt wide (ADR-0003 §D1)") // R-11
    #expect(host.hosting.fittingSize.width > 0)
    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
}

// MARK: - What blocks «Crea» (R-12)

@Test func aValidCompositionBlocksNothing() {
    let composition = NoteComposition(title: "Verbale", folder: "", tags: [topic])

    #expect(composition.blockingProblems(vocabulary: vocabulary).isEmpty)
}

@Test func aClosedFamilyValueOutsideTheVocabularyBlocks() throws {
    let stray = try #require(VaultTag("area-inesistente"))
    let composition = NoteComposition(title: "Verbale", folder: "", tags: [stray])

    #expect(!composition.blockingProblems(vocabulary: vocabulary).isEmpty) // R-12
}

@Test func aValueInsideTheVocabularyDoesNotBlock() throws {
    let composition = NoteComposition(title: "Verbale", folder: "", tags: [try #require(VaultTag("area-sales"))])

    #expect(composition.blockingProblems(vocabulary: vocabulary).isEmpty)
}

@Test func aTypeTagBlocksBecauseTheInitialTagsRuleOwnsIt() throws {
    let composition = NoteComposition(title: "Verbale", folder: "", tags: [try #require(VaultTag("type-invoice"))])

    #expect(!composition.blockingProblems(vocabulary: vocabulary).isEmpty) // R-12
}

@Test func aStatusTagBlocks() throws {
    let composition = NoteComposition(title: "Verbale", folder: "", tags: [try #require(VaultTag("status-active"))])

    #expect(!composition.blockingProblems(vocabulary: vocabulary).isEmpty) // R-12
}

@Test func moreTagsThanTheRuleAllowsBlocks() throws {
    let tags = try (1...8).map { try #require(VaultTag("topic-t\($0)")) }
    let composition = NoteComposition(title: "Verbale", folder: "", tags: tags)

    #expect(!composition.blockingProblems(vocabulary: vocabulary).isEmpty) // R-12: "validate"
}

// MARK: - The pane host's creation (R-08, R-16)

@MainActor
@Test func creatingFromThePaneOpensANewTabWithTheAbsoluteCaretAndOffersTheUndo() async throws {
    let vault = try TemporaryVault()
    let app = try await makeApp(vault)
    let controller = app.vault
    let tabsBefore = controller.columns.flatMap(\.tabs).count
    let composition = NoteComposition(
        title: "Verbale", folder: "", tags: [topic], body: "Prima riga.\nSeconda riga.", bodyCaret: 12
    )

    let path = try await controller.createComposedNote(composition)

    #expect(path == "Verbale.md")
    #expect(controller.columns.flatMap(\.tabs).count == tabsBefore + 1)
    let written = try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
    let seconda = (written as NSString).range(of: "Seconda riga.").location
    #expect(controller.focusedTab?.pendingCaret == seconda, "the caret is absolute in the written text") // R-08
    let offer = try #require(controller.creationUndo, "a pane-host creation offers the undo") // R-16
    #expect(offer.path == "Verbale.md")
    #expect(offer.createdHash == NoteStore.hash(Data(written.utf8)))
    controller.close()
}

@MainActor
@Test func aCompositionWithoutACaretLeavesNoPendingCaret() async throws {
    let vault = try TemporaryVault()
    let app = try await makeApp(vault)

    _ = try await app.vault.createComposedNote(NoteComposition(title: "Senza cursore", folder: ""))

    #expect(app.vault.focusedTab?.pendingCaret == nil)
    app.vault.close()
}
