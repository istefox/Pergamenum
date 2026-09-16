import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D15.
//
// `PraticaSyncPlan.workItems` and every `PraticaSyncEngine` method are declared-but-
// stubbed by this batch's tester (ADR-0155 §D1) - every test below is red because the
// stub does nothing, not because a symbol is missing. The coder fills in the bodies;
// these tests, unedited, are what proves the fill-in is correct.

// MARK: - `PraticaSyncPlan.workItems` (pure - no fixture needed)

@Suite struct PraticaSyncPlanTests {
    private typealias Fixtures = PraticaSyncFixtures

    @Test func ordersCandidatesNewestFirst() {
        let older = Fixtures.row(rowID: 1, messageID: "<older@rossi-spa.it>", date: Date(timeIntervalSince1970: 1000))
        let newer = Fixtures.row(rowID: 2, messageID: "<newer@rossi-spa.it>", date: Date(timeIntervalSince1970: 2000))
        let items = PraticaSyncPlan.workItems(
            dossier: Fixtures.sampleDossier(), candidates: [older, newer], onDisk: [], settings: .default
        )
        #expect(items.map(\.row.rowID) == [2, 1], "newest (rowID 2) must lead")
    }

    @Test func skipsMessageIDsAlreadyOnDisk() {
        let imported = Fixtures.row(rowID: 1, messageID: "<already@rossi-spa.it>")
        let items = PraticaSyncPlan.workItems(
            dossier: Fixtures.sampleDossier(), candidates: [imported],
            onDisk: ["<already@rossi-spa.it>"], settings: .default
        )
        #expect(items.isEmpty, "an already-imported Message-ID must not be queued again")
    }

    // ADR §D15
    @Test func resolvesTheSameMessageIdSeenInTwoMailboxesToExactlyOneItem() {
        let inTrash = Fixtures.row(rowID: 9, messageID: "<dup@rossi-spa.it>", mailboxURL: "ews://acct1/Trash")
        let inInbox = Fixtures.row(rowID: 3, messageID: "<dup@rossi-spa.it>", mailboxURL: "ews://acct1/INBOX")
        let items = PraticaSyncPlan.workItems(
            dossier: Fixtures.sampleDossier(), candidates: [inTrash, inInbox], onDisk: [], settings: .default
        )
        #expect(items.count == 1, "one Message-ID in two mailboxes must produce exactly one work item")
        #expect(items.first?.row.mailbox.url == "ews://acct1/INBOX", "the non-Trash/Junk copy survives")
    }
}
