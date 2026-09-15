import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - R-01,
// R-08.
//
// `PraticaNaming.messageFileName` is a protected interface
// (`.claude/protected-interfaces`); its stub is tester-declared (ADR-0155), coder
// fills the body.

@Suite struct PraticaNamingTests {
    // MARK: - R-08: message file name

    @Test func buildsTheDateTimeCounterpartSlugName() {
        let name = PraticaNaming.messageFileName(
            date: CalendarDate(iso: "2026-06-10")!,
            time: TaskTime(hour: 14, minute: 6),
            counterpart: "Rossi",
            subject: "Richiesta offerta staffe antivibranti"
        )
        #expect(name == "20260610_1406_Rossi_richiesta-offerta-staffe-antivibranti.md")
    }

    @Test(arguments: ["Re: ", "R: ", "Fwd: ", "I: ", "AW: "])
    func dropsAReplyOrForwardPrefixBeforeSlugging(_ prefix: String) {
        let name = PraticaNaming.messageFileName(
            date: CalendarDate(iso: "2026-06-11")!,
            time: TaskTime(hour: 9, minute: 12),
            counterpart: "Rossi",
            subject: "\(prefix)Richiesta offerta"
        )
        #expect(name == "20260611_0912_Rossi_richiesta-offerta.md")
    }

    @Test func capsTheSlugAtFortyCharacters() {
        let longSubject = "Richiesta di offerta per la fornitura di staffe antivibranti in gomma e metallo"
        let name = PraticaNaming.messageFileName(
            date: CalendarDate(iso: "2026-06-10")!,
            time: TaskTime(hour: 14, minute: 6),
            counterpart: "Rossi",
            subject: longSubject
        )
        let slug = name
            .replacingOccurrences(of: "20260610_1406_Rossi_", with: "")
            .replacingOccurrences(of: ".md", with: "")
        #expect(slug.count > 0)
        #expect(slug.count <= 40)
    }

    @Test func aSingleWordSubjectLongerThanTheLimitLeavesNoSlugAtAll() {
        // The same edge `ImportNaming.recordingNoteTitle` pins (`Tests/ConventionsTests.swift`):
        // a subject that slugs to one word already over the 40-character limit keeps no
        // slug at all, rather than a truncated fragment of that one word.
        let name = PraticaNaming.messageFileName(
            date: CalendarDate(iso: "2026-06-10")!,
            time: TaskTime(hour: 14, minute: 6),
            counterpart: "Rossi",
            subject: String(repeating: "a", count: 80)
        )
        #expect(name == "20260610_1406_Rossi.md")
    }

    @Test func truncatedAtWordBoundaryReturnsEmptyForANonPositiveBudget() {
        // ADR-0045 §D5: the shared truncator's own guard, pinned directly here too -
        // `messageFileName`'s own `slugLimit` is a fixed positive constant and can never
        // reach this edge on its own.
        #expect(ImportNaming.truncatedAtWordBoundary("qualcosa", toFit: 0).isEmpty)
        #expect(ImportNaming.truncatedAtWordBoundary("qualcosa", toFit: -5).isEmpty)
    }

    @Test func collidesToANumericSuffixOnlyWhenTheMessageIDDiffers() {
        let date = CalendarDate(iso: "2026-06-10")!
        let time = TaskTime(hour: 14, minute: 6)
        let base = PraticaNaming.messageFileName(
            date: date, time: time, counterpart: "Rossi", subject: "Richiesta offerta"
        )

        // A different Message-ID at the same computed name collides to "-2".
        let collided = PraticaNaming.uniqueMessageFileName(
            date: date, time: time, counterpart: "Rossi", subject: "Richiesta offerta",
            messageID: "<second@rossi-spa.it>",
            existing: [(fileName: base, messageID: "<first@rossi-spa.it>")]
        )
        #expect(collided != base)
        #expect(collided.contains("-2"))

        // The *same* Message-ID at the same computed name is a re-sync, not a
        // collision - no suffix.
        let resynced = PraticaNaming.uniqueMessageFileName(
            date: date, time: time, counterpart: "Rossi", subject: "Richiesta offerta",
            messageID: "<first@rossi-spa.it>",
            existing: [(fileName: base, messageID: "<first@rossi-spa.it>")]
        )
        #expect(resynced == base)
    }

    // MARK: - R-01: the client is the parent folder under the configured root

    @Test func theClientIsTheParentFolderUnderTheConfiguredRoot() {
        let client = PraticaNaming.client(
            forPraticaAt: "01 Progetti/Rossi/Offerta staffe 2026", root: "01 Progetti"
        )
        #expect(client == "Rossi")
    }

    @Test func hasNoClientOutsideTheConfiguredRoot() {
        let client = PraticaNaming.client(forPraticaAt: "Altro/Rossi/Offerta", root: "01 Progetti")
        #expect(client == nil)
    }

    @Test func theClientTagIsSlugged() {
        let tag = PraticaNaming.clientTag(
            forPraticaAt: "01 Progetti/Rossi/Offerta staffe 2026", root: "01 Progetti"
        )
        #expect(tag == Tag("client-rossi"))
    }
}
