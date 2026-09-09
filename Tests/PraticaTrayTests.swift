import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 -
// R-30: "the tray lists proposals with subject, counterpart, date range and count,
// «Aggiungi» follows and imports, «Ignora» writes the conversation into
// `pergamenum-dossier-ignored` for this pratica only, and the strip is hidden when
// empty".
//
// `PraticaTrayModel.proposals(from:)`, `.ignoring(conversationID:in:)` and
// `.following(conversationID:in:)` are tester-declared boundaries (ADR-0155 §D1),
// stubbed to a wrong-but-safe constant so every assertion below fails on the
// assertion, never by crashing the process.

@Suite struct PraticaTrayModelTests {
    private static func row(
        rowID: Int, conversationID: Int, sender: String, subject: String, secondsFromEpoch: Double
    ) -> MailMessageRow {
        MailMessageRow(
            rowID: rowID, indexMessageIDHash: rowID, globalMessageID: rowID, subject: subject,
            sender: sender, dateSent: Date(timeIntervalSince1970: secondsFromEpoch), dateReceived: nil,
            mailbox: MailboxRef(rowID: 1, url: "ews://acct/INBOX"), conversationID: conversationID,
            deleted: false, messageID: "<\(rowID)@rossi-spa.it>"
        )
    }

    // MARK: - R-30: a proposal carries subject, counterpart, date range and count

    @Test func aProposalCarriesTheSubjectCounterpartDateRangeAndCountFromItsEntry() {
        let earliest = Self.row(
            rowID: 1, conversationID: 42, sender: "m.rossi@rossi-spa.it", subject: "Preventivo",
            secondsFromEpoch: 1_749_000_000
        )
        let latest = Self.row(
            rowID: 2, conversationID: 42, sender: "m.rossi@rossi-spa.it", subject: "Re: Preventivo",
            secondsFromEpoch: 1_749_100_000
        )
        let entry = MembershipRule.TrayEntry(conversationID: 42, messages: [earliest, latest])

        let proposals = PraticaTrayModel.proposals(from: [entry])
        #expect(proposals.count == 1)
        guard let proposal = proposals.first else { return }
        #expect(proposal.conversationID == 42)
        #expect(proposal.subject == "Re: Preventivo", "the most recent message's subject names the proposal")
        #expect(proposal.counterpart == "m.rossi@rossi-spa.it")
        #expect(proposal.dateRange == earliest.dateSent!...latest.dateSent!)
        #expect(proposal.messageCount == 2)
    }

    @Test func oneEntryPerConversationYieldsOneProposalEach() {
        let first = MembershipRule.TrayEntry(
            conversationID: 1,
            messages: [Self.row(
                rowID: 10, conversationID: 1, sender: "a@rossi-spa.it", subject: "A",
                secondsFromEpoch: 1_749_000_000
            )]
        )
        let second = MembershipRule.TrayEntry(
            conversationID: 2,
            messages: [Self.row(
                rowID: 11, conversationID: 2, sender: "b@bianchi.it", subject: "B",
                secondsFromEpoch: 1_749_000_100
            )]
        )
        let proposals = PraticaTrayModel.proposals(from: [first, second])
        #expect(Set(proposals.map(\.conversationID)) == [1, 2])
    }

    // MARK: - R-30: "the strip is hidden when empty"

    @Test func theStripIsHiddenExactlyWhenTheProposalListIsEmpty() {
        #expect(PraticaTrayModel.isHidden([]))

        let proposal = PraticaTrayModel.PraticaTrayProposal(
            conversationID: 1, subject: "A", counterpart: "a@rossi-spa.it",
            dateRange: Date()...Date(), messageCount: 1
        )
        #expect(!PraticaTrayModel.isHidden([proposal]))
    }

    // MARK: - R-30: «Ignora» writes only `pergamenum-dossier-ignored`, for this pratica

    private static let populatedDossier = Dossier(
        schemaVersion: 1, counterparts: ["m.rossi@rossi-spa.it"], conversations: [7],
        keywords: ["urgente"], included: ["<a@rossi-spa.it>"], excluded: ["<b@rossi-spa.it>"], ignored: [3]
    )

    @Test func ignoringAddsTheConversationIDToIgnoredAndNothingElse() {
        let updated = PraticaTrayModel.ignoring(conversationID: 42, in: Self.populatedDossier)
        #expect(updated.ignored.contains(42), "42 must join the existing ignored list")
        #expect(updated.ignored.contains(3), "the pre-existing ignored entry must survive")

        let originalOtherKeys = Dossier.render(Self.populatedDossier).filter { $0.name != Dossier.ignoredKey }
        let updatedOtherKeys = Dossier.render(updated).filter { $0.name != Dossier.ignoredKey }
        #expect(
            originalOtherKeys == updatedOtherKeys,
            "every rendered key besides pergamenum-dossier-ignored must be byte-for-byte unchanged"
        )
    }

    // MARK: - R-30: «Aggiungi» follows the conversation

    @Test func followingAddsTheConversationIDToConversations() {
        let updated = PraticaTrayModel.following(conversationID: 99, in: Self.populatedDossier)
        #expect(updated.conversations.contains(99))
        #expect(updated.conversations.contains(7), "the pre-existing followed conversation must survive")
    }
}
