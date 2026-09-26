import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - R-04.
//
// Every fixture is synthetic, built by `Tests/EmailFixtureCorpus.swift` - no test here
// reads `~/Library/Mail`.

@Suite struct EMLXReaderTests {
    @Test func stripsTheByteCountLineAndReturnsTheRFC822Bytes() throws {
        let container = EmailFixtureCorpus.emlxContainer(rfc822: EmailFixtureCorpus.completeMessageRFC822)
        let document = try EMLXReader.parse(container)
        #expect(document.rfc822 == Data(EmailFixtureCorpus.completeMessageRFC822.utf8))
    }

    @Test func returnsTheTrailingPlist() throws {
        let container = EmailFixtureCorpus.emlxContainer(rfc822: EmailFixtureCorpus.completeMessageRFC822)
        let document = try EMLXReader.parse(container)
        #expect(document.plistData == EmailFixtureCorpus.samplePlist)
    }

    @Test func reportsACompleteMessageAsComplete() throws {
        let container = EmailFixtureCorpus.emlxContainer(rfc822: EmailFixtureCorpus.completeMessageRFC822)
        let document = try EMLXReader.parse(container)
        #expect(document.bodyState == .complete)
    }

    @Test func reportsAHeadersOnlyFileAsBodyNotDownloaded() throws {
        let container = EmailFixtureCorpus.emlxContainer(rfc822: EmailFixtureCorpus.headersOnlyMessageRFC822)
        let document = try EMLXReader.parse(container)
        #expect(document.bodyState == .pending)
    }

    @Test func locatesTheSiblingAttachmentsDirectory() {
        let emlxURL = URL(
            fileURLWithPath: "/tmp/pergamenum-fixture/V10/acct/INBOX.mbox/Data/3/Messages/4123.emlx"
        )
        let directory = EMLXReader.attachmentsDirectory(forMessageAt: emlxURL, rowID: 4123, part: "2")
        #expect(directory.path(percentEncoded: false)
            == "/tmp/pergamenum-fixture/V10/acct/INBOX.mbox/Data/3/Attachments/4123/2")
    }

    @Test func readingAMissingFileFails() {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-does-not-exist-\(UUID().uuidString).emlx")
        #expect(throws: EMLXReader.ReadError.self) {
            try EMLXReader.read(contentsOf: missing)
        }
    }
}
