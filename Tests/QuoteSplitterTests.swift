import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - R-07.
//
// A fixture corpus of six styles (SPEC/R-07 asks for "at least five"):
// `Tests/EmailFixtureCorpus.swift`.

@Suite struct QuoteSplitterTests {
    @Test func cutsOnTheItalianMailSeparator() {
        let split = QuoteSplitter.split(EmailFixtureCorpus.italianMailQuote)
        #expect(split.newText.trimmingCharacters(in: .whitespacesAndNewlines) == "Va bene, grazie mille.")
        #expect(split.quotedHistory?.contains("ha scritto:") == true)
    }

    @Test func cutsOnTheItalianOutlookHeaderBlock() {
        let split = QuoteSplitter.split(EmailFixtureCorpus.italianOutlookQuote)
        #expect(split.newText.trimmingCharacters(in: .whitespacesAndNewlines) == "Confermo per giovedì.")
        #expect(split.quotedHistory?.contains("Da: Mario Rossi") == true)
    }

    @Test func cutsOnTheEnglishGmailSeparator() {
        let split = QuoteSplitter.split(EmailFixtureCorpus.englishGmailQuote)
        #expect(split.newText.trimmingCharacters(in: .whitespacesAndNewlines) == "Sounds good, thank you.")
        #expect(split.quotedHistory?.contains("wrote:") == true)
    }

    @Test func cutsOnABareAngleBracketTail() {
        let split = QuoteSplitter.split(EmailFixtureCorpus.bareAngleBracketQuote)
        #expect(split.newText.trimmingCharacters(in: .whitespacesAndNewlines) == "Perfetto, a giovedì allora.")
        #expect(split.quotedHistory?.contains("Fatemi sapere") == true)
    }

    @Test func cutsOnTheOutlookUnderscoreDivider() {
        let split = QuoteSplitter.split(EmailFixtureCorpus.outlookUnderscoreDividerQuote)
        #expect(split.newText.trimmingCharacters(in: .whitespacesAndNewlines) == "Confermo ricevuto.")
        #expect(split.quotedHistory?.contains("________") == true)
    }

    @Test func leavesTheBodyWholeWhenNoSeparatorMatches() {
        let split = QuoteSplitter.split(EmailFixtureCorpus.noQuoteAtAll)
        #expect(split.newText == EmailFixtureCorpus.noQuoteAtAll)
        #expect(split.quotedHistory == nil)
    }

    @Test func movesTheSignatureAfterDashDashSpaceIntoItsOwnBlock() {
        let split = QuoteSplitter.split(EmailFixtureCorpus.signatureOnlyNoQuote)
        #expect(split.newText.trimmingCharacters(in: .whitespacesAndNewlines)
            == "Buongiorno, confermo la disponibilità per giovedì.")
        #expect(split.signature?.contains("Mario Rossi") == true)
        #expect(split.signature?.contains("Rossi S.p.A.") == true)
        #expect(split.newText.contains("Mario Rossi") == false)
    }
}
