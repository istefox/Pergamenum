import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 8 -
// R-20, R-21; screens 1d, 1e.
//
// `WizardState` and `AddToPraticaOrdering` are tester-declared boundaries
// (ADR-0155 §D1): `makeDossier()` and `recentFirst(_:)` are stubbed to a
// wrong-but-safe constant, never `fatalError`.

@Suite struct WizardStateTests {
    // MARK: - Step 1's gate (R-20)

    @Test func cannotContinueFromNameAndClientWithABlankTitleOrClient() {
        var state = WizardState()
        state.clientFolder = "Rossi"
        #expect(!state.canContinueFromNameAndClient, "a blank title must block «Continua»")

        state.title = "Offerta 2026"
        state.clientFolder = ""
        #expect(!state.canContinueFromNameAndClient, "a blank client must block «Continua»")
    }

    @Test func canContinueFromNameAndClientOnceBothAreFilled() {
        var state = WizardState()
        state.title = "Offerta 2026"
        state.clientFolder = "Rossi"
        #expect(state.canContinueFromNameAndClient)
    }

    @Test func canAdvanceHasNoFurtherGateOnSeedOrProposals() {
        var state = WizardState()
        state.title = "Offerta 2026"
        state.clientFolder = "Rossi"
        state.step = .seed
        #expect(state.canAdvance, "an untouched seed («più tardi») is a legitimate state")
        state.step = .proposals
        #expect(state.canAdvance, "an empty proposals selection is a legitimate state")
    }

    // MARK: - «Crea» (R-20)

    @Test func canCreateOnlyFromTheLastStepWithTheStepOneGateStillHolding() {
        var state = WizardState()
        state.title = "Offerta 2026"
        state.clientFolder = "Rossi"
        state.step = .seed
        #expect(!state.canCreate, "«Crea» does not exist before the last step")

        state.step = .proposals
        #expect(state.canCreate)

        state.title = ""
        #expect(!state.canCreate, "clearing the title after advancing still blocks «Crea»")
    }

    // MARK: - The pratica's path

    @Test func relativePathJoinsRootClientAndTitle() {
        var state = WizardState()
        state.rootFolder = "01 Progetti"
        state.clientFolder = "Rossi"
        state.title = "Offerta 2026"
        #expect(state.relativePath == "01 Progetti/Rossi/Offerta 2026")
    }

    @Test func relativePathDropsABlankRootFolder() {
        var state = WizardState()
        state.clientFolder = "Rossi"
        state.title = "Offerta 2026"
        #expect(state.relativePath == "Rossi/Offerta 2026")
    }

    // MARK: - Keywords (R-20/ADR §D12)

    @Test func keywordListSplitsOnCommasAndNewlinesAndDropsBlanks() {
        var state = WizardState()
        state.keywords = "urgente, contratto\n\n  rinnovo  "
        #expect(state.keywordList == ["urgente", "contratto", "rinnovo"])
    }

    @Test func keywordListIsEmptyForBlankInput() {
        var state = WizardState()
        state.keywords = "   "
        #expect(state.keywordList.isEmpty)
    }

    // MARK: - `makeDossier()` (R-20: "writes a conformant pratica.md")

    @Test func makeDossierCollectsExactlyTheSelectedProposalsConversationIDsAndKeywords() {
        var state = WizardState()
        state.title = "Offerta 2026"
        state.clientFolder = "Rossi"
        state.keywords = "urgente, contratto"
        state.proposals = [
            WizardState.Proposal(
                id: "10", subject: "Offerta", counterpart: "Mario Rossi",
                dateRange: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 3600),
                messageCount: 3
            ),
            WizardState.Proposal(
                id: "11", subject: "Follow up", counterpart: "Mario Rossi",
                dateRange: Date(timeIntervalSince1970: 3600)...Date(timeIntervalSince1970: 7200),
                messageCount: 1
            ),
        ]
        state.selectedProposalIDs = ["10"]

        let dossier = state.makeDossier()
        #expect(dossier.schemaVersion == 1)
        #expect(dossier.conversations == [10])
        #expect(dossier.keywords == ["urgente", "contratto"])
    }

    @Test func makeDossierIgnoresAProposalNotTicked() {
        var state = WizardState()
        state.proposals = [
            WizardState.Proposal(
                id: "10", subject: "Offerta", counterpart: "Mario Rossi",
                dateRange: Date()...Date().addingTimeInterval(60), messageCount: 1
            )
        ]
        state.selectedProposalIDs = []
        #expect(state.makeDossier().conversations.isEmpty)
    }

    // MARK: - The new-counterparts step (SPEC "Rilevazione di nuove controparti
    // nella wizard «Nuova pratica»", R-01, R-02, R-09)

    private static func row(sender: String, conversationID: Int) -> MailMessageRow {
        MailMessageRow(
            rowID: 1, indexMessageIDHash: 1, globalMessageID: 1, subject: "S", sender: sender,
            dateSent: Date(), dateReceived: nil, mailbox: MailboxRef(rowID: 1, url: "ews://acct/INBOX"),
            conversationID: conversationID, deleted: false, messageID: "<1@rossi-spa.it>", recipients: []
        )
    }

    @Test func proposalsIsStillTheLastStepWhenNoNewCounterpartIsFound() {
        var state = WizardState()
        state.title = "Offerta 2026"
        state.clientFolder = "Rossi"
        state.step = .proposals
        #expect(state.isLastStep, "R-02: an empty candidate list changes nothing")
        #expect(state.canCreate)
    }

    @Test func proposalsIsNotTheLastStepOnceANewCounterpartIsFound() {
        var state = WizardState()
        state.title = "Offerta 2026"
        state.clientFolder = "Rossi"
        state.step = .proposals
        state.conversationMessages = [10: [Self.row(sender: "tecnico@tifone.com", conversationID: 10)]]
        state.selectedProposalIDs = ["10"]
        state.refreshNewCounterpartCandidates(ownAddresses: [])
        #expect(!state.newCounterpartCandidates.isEmpty)
        #expect(!state.isLastStep, "R-01: a found candidate moves «Crea» to the new step")
        #expect(!state.canCreate, "«Crea» is not reachable from .proposals once there is a new step")

        state.step = .newCounterparts
        #expect(state.isLastStep)
        #expect(state.canCreate)
    }

    @Test func refreshingDropsAStaleSelectionWhenACandidateNoLongerAppears() {
        var state = WizardState()
        state.conversationMessages = [10: [Self.row(sender: "tecnico@tifone.com", conversationID: 10)]]
        state.selectedProposalIDs = ["10"]
        state.refreshNewCounterpartCandidates(ownAddresses: [])
        state.selectedNewCounterpartAddresses = ["tecnico@tifone.com"]

        state.selectedProposalIDs = []
        state.refreshNewCounterpartCandidates(ownAddresses: [])
        #expect(state.newCounterpartCandidates.isEmpty)
        #expect(
            state.selectedNewCounterpartAddresses.isEmpty,
            "a candidate that dropped out of the list must not stay ticked"
        )
    }
}

@Suite struct AddToPraticaOrderingTests {
    private static func item(_ id: String, daysAgo: Double) -> PraticaListItem {
        PraticaListItem(
            id: id, title: id, client: "Rossi", status: "active",
            lastActivity: Date().addingTimeInterval(-daysAgo * 86_400),
            messagesSinceLastOpen: 0, hasNonEmptyTray: false
        )
    }

    // MARK: - R-21: "list of pratiche (recent first, filter field)"

    @Test func recentFirstOrdersByMostRecentLastActivity() {
        let oldest = Self.item("oldest", daysAgo: 30)
        let newest = Self.item("newest", daysAgo: 1)
        let middle = Self.item("middle", daysAgo: 10)

        let ordered = AddToPraticaOrdering.recentFirst([oldest, newest, middle])
        #expect(ordered.map(\.id) == ["newest", "middle", "oldest"])
    }

    @Test func recentFirstBreaksATieOnLastActivityByID() {
        let now = Date()
        let a = PraticaListItem(
            id: "a", title: "a", client: "Rossi", status: "active", lastActivity: now,
            messagesSinceLastOpen: 0, hasNonEmptyTray: false
        )
        let b = PraticaListItem(
            id: "b", title: "b", client: "Rossi", status: "active", lastActivity: now,
            messagesSinceLastOpen: 0, hasNonEmptyTray: false
        )
        #expect(AddToPraticaOrdering.recentFirst([b, a]).map(\.id) == ["a", "b"])
    }
}
