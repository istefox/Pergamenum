import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - R-13,
// R-14.
//
// `MembershipStoreSnapshot` is a plain value type built by hand here - the pure rule
// evaluation is unit-tested without ever touching `~/Library/Mail` or standing up a
// fixture SQLite database (R-13's own success criterion).

@Suite struct MembershipRuleTests {
    private static func message(
        rowID: Int, conversationID: Int, messageID: String?, sender: String, subject: String = "Offerta",
        deleted: Bool = false
    ) -> MailMessageRow {
        MailMessageRow(
            rowID: rowID, indexMessageIDHash: rowID, globalMessageID: rowID, subject: subject,
            sender: sender, dateSent: Date(timeIntervalSince1970: 1_749_557_170 + Double(rowID)),
            dateReceived: Date(timeIntervalSince1970: 1_749_557_191 + Double(rowID)),
            mailbox: MailboxRef(rowID: 1, url: "ews://acct/INBOX"),
            conversationID: conversationID, deleted: deleted, messageID: messageID
        )
    }

    private static let followedConversation = 100
    private static let includedMessage = Self.message(
        rowID: 2, conversationID: 999, messageID: "<included@rossi-spa.it>", sender: "m.rossi@rossi-spa.it"
    )
    private static let excludedMessage = Self.message(
        rowID: 3, conversationID: Self.followedConversation, messageID: "<excluded@rossi-spa.it>",
        sender: "m.rossi@rossi-spa.it"
    )
    private static let followedMessage = Self.message(
        rowID: 1, conversationID: Self.followedConversation, messageID: "<followed@rossi-spa.it>",
        sender: "m.rossi@rossi-spa.it"
    )

    private static func snapshot() -> MembershipStoreSnapshot {
        MembershipStoreSnapshot(
            conversations: [Self.followedConversation: [Self.followedMessage, Self.excludedMessage]],
            messagesByID: [
                "<included@rossi-spa.it>": Self.includedMessage,
                "<excluded@rossi-spa.it>": Self.excludedMessage,
                "<followed@rossi-spa.it>": Self.followedMessage,
            ]
        )
    }

    private static let baseDossier = Dossier(
        schemaVersion: 1, counterparts: ["m.rossi@rossi-spa.it"], conversations: [Self.followedConversation],
        keywords: [], included: [], excluded: [], ignored: []
    )

    // MARK: - R-13: candidate set

    @Test func includesEveryMessageOfAFollowedConversation() {
        let candidates = MembershipRule.candidates(dossier: Self.baseDossier, store: Self.snapshot(), onDisk: [])
        #expect(candidates.messages.contains { $0.messageID == "<followed@rossi-spa.it>" })
    }

    @Test func includesAMessageAddedByHandOutsideAnyFollowedConversation() {
        var dossier = Self.baseDossier
        dossier.included = ["<included@rossi-spa.it>"]
        let candidates = MembershipRule.candidates(dossier: dossier, store: Self.snapshot(), onDisk: [])
        #expect(candidates.messages.contains { $0.messageID == "<included@rossi-spa.it>" })
    }

    @Test func excludesAMessageRemovedByHandEvenInAFollowedConversation() {
        var dossier = Self.baseDossier
        dossier.excluded = ["<excluded@rossi-spa.it>"]
        let candidates = MembershipRule.candidates(dossier: dossier, store: Self.snapshot(), onDisk: [])
        #expect(!candidates.messages.contains { $0.messageID == "<excluded@rossi-spa.it>" })
    }

    @Test func excludesAMessageAlreadyOnDisk() {
        let candidates = MembershipRule.candidates(
            dossier: Self.baseDossier, store: Self.snapshot(), onDisk: ["<followed@rossi-spa.it>"]
        )
        #expect(!candidates.messages.contains { $0.messageID == "<followed@rossi-spa.it>" })
    }

    @Test func aKeywordMatchAutoFollowsItsConversation() {
        var dossier = Self.baseDossier
        dossier.conversations = []
        dossier.keywords = ["Offerta"]
        let candidates = MembershipRule.candidates(dossier: dossier, store: Self.snapshot(), onDisk: [])
        #expect(candidates.autoFollowedConversations.contains(Self.followedConversation))
    }

    // MARK: - R-13: tray set

    @Test func trayListsASameCounterpartConversationNotAlreadyFollowed() {
        let claimedElsewhere = MembershipStoreSnapshot(
            conversations: [
                Self.followedConversation: [Self.followedMessage, Self.excludedMessage],
                200: [Self.message(
                    rowID: 4, conversationID: 200, messageID: "<other@rossi-spa.it>",
                    sender: "m.rossi@rossi-spa.it"
                )],
            ],
            messagesByID: [:]
        )
        let dossier = Dossier(
            schemaVersion: 1, counterparts: ["m.rossi@rossi-spa.it"], conversations: [],
            keywords: [], included: [], excluded: [], ignored: []
        )
        let now = Date(timeIntervalSince1970: 1_749_657_170)
        let window = now.addingTimeInterval(-90 * 86_400)...now
        let tray = MembershipRule.trayCandidates(
            dossier: dossier, store: claimedElsewhere, window: window, claimedByOtherPratiche: []
        )
        #expect(tray.contains { $0.conversationID == 200 })
    }

    @Test func trayExcludesAConversationClaimedByAnotherPratica() {
        let dossier = Dossier(
            schemaVersion: 1, counterparts: ["m.rossi@rossi-spa.it"], conversations: [],
            keywords: [], included: [], excluded: [], ignored: []
        )
        let now = Date(timeIntervalSince1970: 1_749_657_170)
        let window = now.addingTimeInterval(-90 * 86_400)...now
        let tray = MembershipRule.trayCandidates(
            dossier: dossier, store: Self.snapshot(), window: window,
            claimedByOtherPratiche: [Self.followedConversation]
        )
        #expect(!tray.contains { $0.conversationID == Self.followedConversation })
    }

    // MARK: - R-14: conversation id recovery

    @Test func recoversAConversationIDFromAMemberMessageID() {
        let recovery = MembershipRule.recoverConversationID(
            knownMemberMessageIDs: ["<followed@rossi-spa.it>"], store: Self.snapshot()
        )
        #expect(recovery == .recovered(Self.followedConversation))
    }

    @Test func reportsAConversationWithNoRecoverableMemberRatherThanDroppingIt() {
        let recovery = MembershipRule.recoverConversationID(
            knownMemberMessageIDs: ["<gone-forever@rossi-spa.it>"], store: Self.snapshot()
        )
        #expect(recovery == .unrecoverable)
    }
}
