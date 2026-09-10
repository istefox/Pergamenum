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

    // MARK: - ADR §D24 (PG-108): the keyword arm sees recipients, not only the sender

    @Test func theKeywordArmMatchesAMessageAddressedToACounterpartNotOnlyFromOne() {
        var dossier = Self.baseDossier
        dossier.conversations = []
        dossier.keywords = ["Offerta"]

        // Sent *by* someone who is not a counterpart, *to* the tracked counterpart -
        // today's rule 3 guard (`guard let sender = row.sender?.lowercased(),
        // counterparts.contains(sender)`) drops this outright. §D24.3's `touches`
        // predicate must also consult `recipients`, so this is red until the coder
        // wires it in.
        var outgoingMessage = Self.message(
            rowID: 7, conversationID: 500, messageID: "<to-counterpart@stefer.it>",
            sender: "stefano@stefer.it", subject: "Offerta finale"
        )
        outgoingMessage.recipients = ["m.rossi@rossi-spa.it"]
        let store = MembershipStoreSnapshot(
            conversations: [500: [outgoingMessage]],
            messagesByID: ["<to-counterpart@stefer.it>": outgoingMessage]
        )

        let candidates = MembershipRule.candidates(dossier: dossier, store: store, onDisk: [])
        #expect(candidates.messages.contains { $0.messageID == "<to-counterpart@stefer.it>" })
    }

    // MARK: - ADR §D22 (PG-106): the keyword arm sees the counterpart pool

    @Test func aKeywordMatchAutoFollowsAndImportsAConversationPresentOnlyInTheUnfollowedPool() {
        var dossier = Self.baseDossier
        dossier.conversations = []
        dossier.keywords = ["Offerta"]

        // Present only in `store.unfollowed` - the counterpart pool the tray already
        // loads, never in `store.conversations` or `store.messagesByID`. Today's rule
        // 3 scans `everyMessage(in:)`, which does not fold `unfollowed` in yet
        // (§D22.1 is coder work), so this is red until that lands.
        let unfollowedMessage = Self.message(
            rowID: 8, conversationID: 700, messageID: "<unfollowed@rossi-spa.it>",
            sender: "m.rossi@rossi-spa.it", subject: "Offerta speciale"
        )
        var store = MembershipStoreSnapshot(conversations: [:], messagesByID: [:])
        store.unfollowed = [700: [unfollowedMessage]]

        let candidates = MembershipRule.candidates(dossier: dossier, store: store, onDisk: [])
        #expect(candidates.autoFollowedConversations.contains(700))
        #expect(candidates.messages.contains { $0.messageID == "<unfollowed@rossi-spa.it>" })
    }

    @Test func aSecondEvaluationOverTheSameNowFollowedDossierAutoFollowsNothingNew() {
        // The fixed-point claim (§D22.3): once a conversation is in `dossier.conversations`,
        // rule 3's own `!dossier.conversations.contains(conversation)` guard already
        // skips it - regression guard for after the coder's two-pass evaluation change
        // in `runExclusive`, not required to be red today. A store built by hand, not
        // `Self.snapshot()`: that shared fixture's `includedMessage` (conversation 999,
        // sender `m.rossi@rossi-spa.it`, default subject "Offerta") is itself a live
        // keyword match unrelated to this test's own conversation, and would auto-follow
        // regardless of the fixed-point claim being tested here.
        var dossier = Self.baseDossier
        dossier.conversations = [Self.followedConversation]
        dossier.keywords = ["Offerta"]
        let store = MembershipStoreSnapshot(
            conversations: [Self.followedConversation: [Self.followedMessage]],
            messagesByID: ["<followed@rossi-spa.it>": Self.followedMessage]
        )
        let candidates = MembershipRule.candidates(dossier: dossier, store: store, onDisk: [])
        #expect(candidates.autoFollowedConversations.isEmpty)
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

    @Test func trayListsAConversationWhereTheTrackedPersonOnlySentToTheCounterpart() {
        // PG-108's own case: every message of this conversation was sent *by* the
        // tracked person *to* the counterpart, never received from them. Today's
        // sender-only check in `trayCandidates` (`guard let sender = row.sender?
        // .lowercased() … counterparts.contains(sender)`) never proposes it - this is
        // red until §D24.3's `touches` predicate (sender OR recipients) lands.
        var outgoingOnly = Self.message(
            rowID: 5, conversationID: 300, messageID: "<outgoing@stefer.it>",
            sender: "stefano@stefer.it"
        )
        outgoingOnly.recipients = ["m.rossi@rossi-spa.it"]
        let store = MembershipStoreSnapshot(
            conversations: [300: [outgoingOnly]],
            messagesByID: [:]
        )
        let dossier = Dossier(
            schemaVersion: 1, counterparts: ["m.rossi@rossi-spa.it"], conversations: [],
            keywords: [], included: [], excluded: [], ignored: []
        )
        let now = Date(timeIntervalSince1970: 1_749_657_170)
        let window = now.addingTimeInterval(-90 * 86_400)...now
        let tray = MembershipRule.trayCandidates(
            dossier: dossier, store: store, window: window, claimedByOtherPratiche: []
        )
        #expect(tray.contains { $0.conversationID == 300 })
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
