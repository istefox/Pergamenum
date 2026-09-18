import Foundation
import Testing
@testable import Pergamenum

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 5 - R-06.
//
// `PraticheController.aggregatedNoteLinks`'s own rule: the union of the pratica's
// general note links and every message's own `linkedNote`, de-duplicated by title,
// with a per-message one attributable to its message.

@MainActor
@Suite struct PraticaLinkAggregationTests {
    private func controller(links: PraticaLinks, details: [String: PraticaRowDetail]) -> PraticheController {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        controller.links = links
        controller.details = details
        return controller
    }

    private func detail(notePath: String, linkedNote: String?) -> PraticaRowDetail {
        PraticaRowDetail(
            notePath: notePath, body: "", quotedHistory: nil, signature: nil, attachments: [],
            storeReferences: [], isPending: false, senderAddress: nil, linkedNote: linkedNote
        )
    }

    @Test func generalOnlyLinkHasNoMessageAttribution() {
        let controller = controller(links: PraticaLinks(notes: ["Offerta 2026"]), details: [:])
        #expect(
            controller.aggregatedNoteLinks == [PraticaAggregatedNoteLink(title: "Offerta 2026", messagePaths: [])]
        )
    }

    @Test func messageOnlyLinkIsAddedAndAttributedToItsMessage() {
        let controller = controller(
            links: .empty,
            details: ["Rossi/email/msg.md": detail(notePath: "Rossi/email/msg.md", linkedNote: "[[Follow-up]]")]
        )
        #expect(controller.aggregatedNoteLinks == [
            PraticaAggregatedNoteLink(title: "Follow-up", messagePaths: ["Rossi/email/msg.md"]),
        ])
    }

    @Test func aTitleLinkedBothGenerallyAndByAMessageIsUnionedOnceWithItsAttribution() {
        let controller = controller(
            links: PraticaLinks(notes: ["Offerta 2026"]),
            details: ["Rossi/email/msg.md": detail(notePath: "Rossi/email/msg.md", linkedNote: "[[Offerta 2026]]")]
        )
        #expect(controller.aggregatedNoteLinks == [
            PraticaAggregatedNoteLink(title: "Offerta 2026", messagePaths: ["Rossi/email/msg.md"]),
        ])
    }

    @Test func twoMessagesLinkingTheSameNoteBothAttributeToIt() {
        let controller = controller(
            links: .empty,
            details: [
                "Rossi/email/a.md": detail(notePath: "Rossi/email/a.md", linkedNote: "[[Follow-up]]"),
                "Rossi/email/b.md": detail(notePath: "Rossi/email/b.md", linkedNote: "[[Follow-up]]"),
            ]
        )
        #expect(controller.aggregatedNoteLinks == [
            PraticaAggregatedNoteLink(title: "Follow-up", messagePaths: ["Rossi/email/a.md", "Rossi/email/b.md"]),
        ])
    }

    @Test func aManualEntryWithNoLinkedNoteContributesNothing() {
        let controller = controller(
            links: .empty, details: ["Rossi/pratica.md": detail(notePath: "Rossi/pratica.md", linkedNote: nil)]
        )
        #expect(controller.aggregatedNoteLinks.isEmpty)
    }

    @Test func messageOnlyTitlesFollowTheGeneralOnesSortedAlphabetically() {
        let controller = controller(
            links: PraticaLinks(notes: ["Zeta"]),
            details: [
                "Rossi/email/a.md": detail(notePath: "Rossi/email/a.md", linkedNote: "[[Beta]]"),
                "Rossi/email/b.md": detail(notePath: "Rossi/email/b.md", linkedNote: "[[Alpha]]"),
            ]
        )
        #expect(controller.aggregatedNoteLinks.map(\.title) == ["Zeta", "Alpha", "Beta"])
    }
}

// MARK: - R-09: a per-message link write must never touch the pratica-level
// selection the inspector is gated on (ADR-0036 §D5, not reopened by this chain)
//
// `PratichePane+Inspector.swift`'s `inspector` reads `pratica.md` and appends
// `praticaLinksSection` under exactly one condition, `pratiche.selection != nil` -
// never a per-row/per-message state. `PraticaCommandActions.linkNote(_:toMessageAt:)`
// is the write a right-click on a timeline row drives (R-02); its own `reload()`
// refreshes `details`/`links` on the same beat, and this is the seam that proves it
// stops there - `selection` itself, the one property the inspector's content is
// gated on, is never assigned by any code path this write reaches.

private let praticaWithDossierForSelectionTest = """
---
pergamenum-dossier: 1
---

Corpo della pratica, non toccato.
"""

private let messageForSelectionTest = """
---
date: 2026-06-10
tags:
  - type-note
  - type-email
pergamenum-mail: 1
pergamenum-mail-message-id: "<abc@rossi-spa.it>"
pergamenum-mail-direction: received
pergamenum-mail-date: 2026-06-10T14:06:00+02:00
pergamenum-mail-from: "Mario Rossi <m.rossi@rossi-spa.it>"
pergamenum-mail-subject: "Richiesta offerta"
pergamenum-mail-body: complete
---

Buongiorno,
"""

@MainActor
@Suite struct PraticaInspectorSelectionStabilityTests {
    @Test func linkingAMessageNoteLeavesThePraticaSelectionUntouched() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithDossierForSelectionTest, to: "Rossi/pratica.md")
        try vault.write(messageForSelectionTest, to: "Rossi/email/msg.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.select("Rossi", in: vaultController)
        #expect(pratiche.selection == "Rossi")
        let actions = PraticaCommandActions(pratiche: pratiche, vault: vaultController, navigation: Navigation())

        await actions.linkNote("[[Offerta 2026]]", toMessageAt: "Rossi/email/msg.md")

        // The write's own `reload()` refreshes exactly `timeline`/`details`/`links` -
        // proven by the second assertion - and nothing else: `selection` is what the
        // inspector's `pratica.md` content and its new link sections are gated on
        // (R-09), and it must read back the same value a person never touched.
        #expect(pratiche.selection == "Rossi")
        #expect(pratiche.details["Rossi/email/msg.md"]?.linkedNote == "[[Offerta 2026]]")

        vaultController.close()
    }

    @Test func unlinkingAMessageNoteAlsoLeavesThePraticaSelectionUntouched() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithDossierForSelectionTest, to: "Rossi/pratica.md")
        let linked = messageForSelectionTest.replacingOccurrences(
            of: "pergamenum-mail-body: complete",
            with: "pergamenum-mail-note: \"[[Offerta 2026]]\"\npergamenum-mail-body: complete"
        )
        try vault.write(linked, to: "Rossi/email/msg.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.select("Rossi", in: vaultController)
        let actions = PraticaCommandActions(pratiche: pratiche, vault: vaultController, navigation: Navigation())

        await actions.linkNote(nil, toMessageAt: "Rossi/email/msg.md")

        #expect(pratiche.selection == "Rossi")
        #expect(pratiche.details["Rossi/email/msg.md"]?.linkedNote == nil)

        vaultController.close()
    }
}
