import Foundation
import Testing
@testable import Pergamenum

// SPEC "Rilevazione di nuove controparti nella wizard «Nuova pratica»", R-01…R-07,
// R-10 - `NewCounterpartDetector.candidates(in:counterparts:ownAddresses:)`.
@Suite struct NewCounterpartDetectorTests {
    private static func row(
        rowID: Int, conversationID: Int, sender: String, secondsFromEpoch: Double,
        recipients: [String] = []
    ) -> MailMessageRow {
        MailMessageRow(
            rowID: rowID, indexMessageIDHash: rowID, globalMessageID: rowID, subject: "S",
            sender: sender, dateSent: Date(timeIntervalSince1970: secondsFromEpoch), dateReceived: nil,
            mailbox: MailboxRef(rowID: 1, url: "ews://acct/INBOX"), conversationID: conversationID,
            deleted: false, messageID: "<\(rowID)@rossi-spa.it>", recipients: recipients
        )
    }

    // MARK: - R-01/R-06: a new sender is offered, known counterparts and own addresses are not

    @Test func anAddressThatSentAMessageAndIsNotYetKnownIsOfferedAsAWriter() {
        let messages = [
            Self.row(rowID: 1, conversationID: 1, sender: "tecnico@tifone.com", secondsFromEpoch: 0),
        ]
        let candidates = NewCounterpartDetector.candidates(
            in: messages, counterparts: ["altro@tifone.com"], ownAddresses: ["me@vibrofer.it"]
        )
        #expect(candidates.count == 1)
        #expect(candidates.first?.address == "tecnico@tifone.com")
        #expect(candidates.first?.wroteAtLeastOnce == true)
        #expect(candidates.first?.messageCount == 1)
    }

    @Test func anExistingCounterpartIsNeverOfferedAsACandidate() {
        let messages = [
            Self.row(rowID: 1, conversationID: 1, sender: "tecnico@tifone.com", secondsFromEpoch: 0),
        ]
        let candidates = NewCounterpartDetector.candidates(
            in: messages, counterparts: ["tecnico@tifone.com"], ownAddresses: []
        )
        #expect(candidates.isEmpty)
    }

    @Test func theOwnAddressIsNeverOfferedAsACandidate() {
        let messages = [
            Self.row(
                rowID: 1, conversationID: 1, sender: "tecnico@tifone.com", secondsFromEpoch: 0,
                recipients: ["me@vibrofer.it"]
            ),
        ]
        let candidates = NewCounterpartDetector.candidates(
            in: messages, counterparts: [], ownAddresses: ["me@vibrofer.it"]
        )
        #expect(candidates.map(\.address) == ["tecnico@tifone.com"], "the own address must not appear")
    }

    // MARK: - R-03/R-04: Cc-only shown too, senders ranked above Cc-only

    @Test func aCcOnlyAddressIsOfferedButNeverFlaggedAsHavingWritten() {
        let messages = [
            Self.row(
                rowID: 1, conversationID: 1, sender: "tecnico@tifone.com", secondsFromEpoch: 0,
                recipients: ["colleague-a@tifone.com", "me@vibrofer.it"]
            ),
        ]
        let candidates = NewCounterpartDetector.candidates(
            in: messages, counterparts: ["tecnico@tifone.com"], ownAddresses: ["me@vibrofer.it"]
        )
        #expect(candidates.count == 1)
        #expect(candidates.first?.address == "colleague-a@tifone.com")
        #expect(candidates.first?.wroteAtLeastOnce == false)
    }

    @Test func writersAreRankedAboveCcOnlyRegardlessOfMessageCount() {
        let messages = [
            // colleague-cc appears in 3 messages, never as sender.
            Self.row(
                rowID: 1, conversationID: 1, sender: "tecnico@tifone.com", secondsFromEpoch: 0,
                recipients: ["colleague-cc@tifone.com"]
            ),
            Self.row(
                rowID: 2, conversationID: 1, sender: "tecnico@tifone.com", secondsFromEpoch: 1,
                recipients: ["colleague-cc@tifone.com"]
            ),
            Self.row(
                rowID: 3, conversationID: 1, sender: "tecnico@tifone.com", secondsFromEpoch: 2,
                recipients: ["colleague-cc@tifone.com"]
            ),
            // colleague-b wrote exactly once.
            Self.row(rowID: 4, conversationID: 1, sender: "colleague-b@tifone.com", secondsFromEpoch: 3),
        ]
        let candidates = NewCounterpartDetector.candidates(
            in: messages, counterparts: ["tecnico@tifone.com"], ownAddresses: []
        )
        #expect(
            candidates.map(\.address) == ["colleague-b@tifone.com", "colleague-cc@tifone.com"],
            "a writer with fewer messages still ranks above a Cc-only address with more"
        )
    }

    @Test func withinAGroupRankingIsByMessageCountDescending() {
        let messages = [
            Self.row(rowID: 1, conversationID: 1, sender: "a@tifone.com", secondsFromEpoch: 0),
            Self.row(rowID: 2, conversationID: 1, sender: "b@tifone.com", secondsFromEpoch: 1),
            Self.row(rowID: 3, conversationID: 1, sender: "b@tifone.com", secondsFromEpoch: 2),
        ]
        let candidates = NewCounterpartDetector.candidates(in: messages, counterparts: [], ownAddresses: [])
        #expect(candidates.map(\.address) == ["b@tifone.com", "a@tifone.com"])
    }

    // MARK: - R-04 edge case: sender-and-Cc-both counts as a writer, count summed

    @Test func anAddressThatIsBothASenderAndACcRecipientCountsAsAWriterWithASummedCount() {
        let messages = [
            Self.row(rowID: 1, conversationID: 1, sender: "colleague-b@tifone.com", secondsFromEpoch: 0),
            Self.row(
                rowID: 2, conversationID: 1, sender: "tecnico@tifone.com", secondsFromEpoch: 1,
                recipients: ["colleague-b@tifone.com"]
            ),
        ]
        let candidates = NewCounterpartDetector.candidates(
            in: messages, counterparts: ["tecnico@tifone.com"], ownAddresses: []
        )
        #expect(candidates.count == 1)
        #expect(candidates.first?.wroteAtLeastOnce == true)
        #expect(candidates.first?.messageCount == 2)
    }

    // MARK: - R-07: dedup across conversations (a flat message array, since the caller unions them)

    @Test func theSameAddressAcrossMultipleConversationsIsOneCandidateWithASummedCount() {
        let messages = [
            Self.row(rowID: 1, conversationID: 1, sender: "colleague-b@tifone.com", secondsFromEpoch: 0),
            Self.row(rowID: 2, conversationID: 2, sender: "colleague-b@tifone.com", secondsFromEpoch: 1),
        ]
        let candidates = NewCounterpartDetector.candidates(in: messages, counterparts: [], ownAddresses: [])
        #expect(candidates.count == 1)
        #expect(candidates.first?.messageCount == 2)
    }

    // MARK: - R-10: case and whitespace normalization

    @Test func addressComparisonsAreCaseInsensitiveAndWhitespaceTrimmed() {
        let messages = [
            Self.row(rowID: 1, conversationID: 1, sender: "  Tecnico@Tifone.com ", secondsFromEpoch: 0),
        ]
        let candidates = NewCounterpartDetector.candidates(
            in: messages, counterparts: ["tecnico@tifone.com"], ownAddresses: []
        )
        #expect(candidates.isEmpty, "the known counterpart must match despite case/whitespace differences")
    }

    // MARK: - Empty input

    @Test func noMessagesYieldsNoCandidates() {
        #expect(NewCounterpartDetector.candidates(in: [], counterparts: [], ownAddresses: []).isEmpty)
    }
}
