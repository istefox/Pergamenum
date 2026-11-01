import Foundation
import Testing
@testable import Pergamenum

// PG-436 (audit 2026-10-31 R-02: SEC-01, SEC-02, S05-10), ADR-0048's 2026-10-31
// amendment. An attachment's name is the email's own: a name that walks out of Mail's
// `Attachments/<rowID>/<part>/` directory must never make the sync stat, read or copy
// the file it names, nor record it as a `storePath`.

@Suite struct MailAttachmentPathTests {
    private typealias Fixtures = PraticaSyncFixtures

    private static let directory = URL(filePath: "/mail/V10/acct/INBOX.mbox/Data/1/Attachments/7/2", directoryHint: .isDirectory)
    private static let fourKilobyteName = String(repeating: "a", count: 4096) + ".pdf"

    // MARK: - The name: refused or reduced to one component

    @Test(arguments: ["", "/", ".", "..", "../", "a\u{0}b", "a\u{0}b/c.pdf", fourKilobyteName])
    func aNameThatCannotBeOneComponentIsRefused(name: String) {
        #expect(MailAttachmentPath.component(of: name) == nil)
        #expect(MailAttachmentPath.file(named: name, in: Self.directory) == nil)
    }

    @Test(arguments: [
        ("../../x", "x"),
        ("/etc/hosts", "hosts"),
        ("../../../../.ssh/id_ed25519", "id_ed25519"),
        ("offerta.pdf", "offerta.pdf"),
    ])
    func aPathIsReducedToItsLastComponentInsideTheDirectory(name: String, expected: String) throws {
        #expect(MailAttachmentPath.component(of: name) == expected)
        let url = try #require(MailAttachmentPath.file(named: name, in: Self.directory))
        #expect(url.deletingLastPathComponent().standardizedFileURL.path == Self.directory.standardizedFileURL.path)
        #expect(url.lastPathComponent == expected)
    }

    @Test func aNameAtTheVolumeLimitIsAcceptedAndOneByteMoreIsNot() {
        let atLimit = String(repeating: "à", count: 127) + "a" // 2 * 127 + 1 = 255 bytes
        #expect(MailAttachmentPath.component(of: atLimit) == atLimit)
        #expect(MailAttachmentPath.component(of: atLimit + "a") == nil)
    }

    // MARK: - Containment

    @Test func containmentComparesComponentsNotAStringPrefix() {
        let root = URL(filePath: "/mail/V10", directoryHint: .isDirectory)
        #expect(MailAttachmentPath.contained(URL(filePath: "/mail/V10/a/b.emlx"), in: root) != nil)
        #expect(MailAttachmentPath.contained(URL(filePath: "/mail/V10evil/b.emlx"), in: root) == nil)
        #expect(MailAttachmentPath.contained(URL(filePath: "/mail/V10/../x"), in: root) == nil)
        #expect(MailAttachmentPath.contained(root, in: root) == nil, "the root itself is not a file inside it")
    }

    @Test func aSymbolicLinkInsideTheRootThatPointsOutsideIsRefused() throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-mail-attachment-path-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appending(path: "store", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = base.appending(path: "secret.txt", directoryHint: .notDirectory)
        try Data("x".utf8).write(to: outside)
        let link = root.appending(path: "link.txt", directoryHint: .notDirectory)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        #expect(MailAttachmentPath.contained(link, in: root) == nil)
    }

    /// A symbolic link to a directory outside, mid-path, followed by `..`: the kernel walks
    /// the link first and lands beside its target, outside the root. When the file there
    /// exists the resolution follows the kernel and refuses it; when it does not,
    /// standardizing drops the `..` lexically, so the answer must be that resolved URL,
    /// with no `..` left for the kernel to walk differently, never the URL as given.
    @Test func aSymbolicLinkedDirectoryMidPathFollowedByDotDotNeverEscapes() throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-mail-attachment-path-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appending(path: "store", directoryHint: .isDirectory)
        let inner = root.appending(path: "a", directoryHint: .isDirectory)
        let deep = base.appending(path: "elsewhere/deep", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: base.appending(path: "elsewhere/secret.txt", directoryHint: .notDirectory))
        try FileManager.default.createSymbolicLink(
            at: inner.appending(path: "link", directoryHint: .isDirectory), withDestinationURL: deep
        )

        let escaping = URL(fileURLWithPath: inner.path(percentEncoded: false) + "/link/../secret.txt")
        #expect(FileManager.default.fileExists(atPath: escaping.path(percentEncoded: false)), "the kernel reaches the planted file")
        #expect(MailAttachmentPath.contained(escaping, in: root) == nil)

        let dangling = URL(fileURLWithPath: inner.path(percentEncoded: false) + "/link/../missing.txt")
        if let answered = MailAttachmentPath.contained(dangling, in: root) {
            let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            #expect(!answered.pathComponents.contains(".."), "the URL handed back is the one checked, not the one given")
            #expect(Array(answered.pathComponents.prefix(resolvedRoot.count)) == resolvedRoot)
            #expect(answered != dangling)
        }
    }

    // MARK: - S05-10: the name written into `allegati/` is capped

    @Test func aFourKilobyteAttachmentNameIsCappedAndKeepsItsExtension() throws {
        let day = try #require(CalendarDate(year: 2026, month: 6, day: 10))
        let name = PraticaNaming.attachmentFileName(date: day, name: Self.fourKilobyteName)

        #expect(name.utf8.count <= MailAttachmentPath.maximumNameBytes - PraticaNaming.attachmentSuffixReserve)
        #expect(name.hasPrefix("20260610_aaa"))
        #expect(name.hasSuffix(".pdf"))
    }

    @Test func aLongAccentedNameIsCutOnACharacterNeverInsideOne() throws {
        let day = try #require(CalendarDate(year: 2026, month: 6, day: 10))
        let name = PraticaNaming.attachmentFileName(date: day, name: String(repeating: "è", count: 300) + ".docx")

        #expect(name.utf8.count <= MailAttachmentPath.maximumNameBytes - PraticaNaming.attachmentSuffixReserve)
        #expect(name.hasSuffix(".docx"))
        #expect(name.dropFirst("20260610_".count).dropLast(".docx".count).allSatisfy { $0 == "è" })
    }

    @Test func aShortAttachmentNameIsUnchanged() throws {
        let day = try #require(CalendarDate(year: 2026, month: 6, day: 10))
        #expect(PraticaNaming.attachmentFileName(date: day, name: "offerta.pdf") == "20260610_offerta.pdf")
    }

    // MARK: - End to end: an empty inline part whose name walks out (SEC-01)

    /// Writes `bytes` where `name` would land if it were joined to the part's directory
    /// verbatim - outside `Attachments/1/2/` - so a sync that followed the name would find
    /// a real file there. Uses the ADR-0048 fixture helper, which joins verbatim on purpose.
    private static func plantOutside(
        _ bytes: Data, named name: String, into fixture: MailStoreFixture.Built
    ) throws {
        try Fixtures.writeExternalizedAttachment(bytes, named: name, rowID: 1, part: "2", into: fixture)
    }

    private static func fixture(messageID: String, rfc822: String) throws -> MailStoreFixture.Built {
        try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Allegato ostile", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: rfc822
            )]
        )
    }

    private static func sync(
        _ fixture: MailStoreFixture.Built, messageID: String, settings: PraticheSettings = .default
    ) async throws -> URL {
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<\(messageID)>")],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)
        return vaultRoot
    }

    @Test func anEmptyPartNamedOutsideItsDirectoryIsNeverCopiedAndStaysPending() async throws {
        let name = "../../../secret.pdf"
        let messageID = "traversal@rossi-spa.it"
        let fixture = try Self.fixture(
            messageID: messageID,
            rfc822: EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(messageID: messageID, filename: name)
        )
        try Self.plantOutside(EmailFixtureCorpus.pdfBytes(), named: name, into: fixture)

        let vaultRoot = try await Self.sync(fixture, messageID: messageID)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty, "the planted file outside Attachments/1/2/ is never read")
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.linkedAttachmentNames.isEmpty)
        #expect(doc.frontmatter.storeReferences.isEmpty)
        #expect(doc.frontmatter.pendingAttachmentNames == ["20260610_secret.pdf"])
    }

    @Test func anOverThresholdEmptyPartNamedOutsideItsDirectoryIsNeverRecordedAsAStorePath() async throws {
        let name = "../../../disegno.dwg"
        let messageID = "traversal-big@rossi-spa.it"
        let fixture = try Self.fixture(
            messageID: messageID,
            rfc822: EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(messageID: messageID, filename: name)
        )
        try Self.plantOutside(Data(repeating: 0x41, count: 2 * 1024 * 1024), named: name, into: fixture)
        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1

        let vaultRoot = try await Self.sync(fixture, messageID: messageID, settings: settings)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty)
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.storeReferences.isEmpty, "a path outside the part's directory is never a storePath")
        #expect(doc.frontmatter.pendingAttachmentNames == ["20260610_disegno.dwg"])
    }

    @Test func anOverThresholdInlinePartNamedOutsideItsDirectoryPointsAtTheEmlxNotTheNamedFile() async throws {
        let name = "../../../disegno.dwg"
        let messageID = "traversal-inline@rossi-spa.it"
        let bigBytes = Data(repeating: 0x41, count: 2 * 1024 * 1024)
        let fixture = try Self.fixture(
            messageID: messageID,
            rfc822: EmailFixtureCorpus.singleAttachmentMessageRFC822(
                messageID: messageID, attachmentFilename: name, attachmentBytes: bigBytes
            )
        )
        try Self.plantOutside(Data("planted".utf8), named: name, into: fixture)
        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1

        let vaultRoot = try await Self.sync(fixture, messageID: messageID, settings: settings)

        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        let reference = try #require(doc.frontmatter.storeReferences.first)
        #expect(reference.storePath.hasSuffix("/Messages/1.emlx"), "the refused name falls back to the .emlx")
        #expect(!reference.storePath.hasSuffix("disegno.dwg"))
    }

    @Test func anEmptyPartWithAFourKilobyteNameStaysPendingUnderACappedName() async throws {
        let messageID = "longname@rossi-spa.it"
        let fixture = try Self.fixture(
            messageID: messageID,
            rfc822: EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(
                messageID: messageID, filename: Self.fourKilobyteName
            )
        )

        let vaultRoot = try await Self.sync(fixture, messageID: messageID)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty)
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        let pending = try #require(doc.frontmatter.pendingAttachmentNames.first)
        #expect(pending.utf8.count <= MailAttachmentPath.maximumNameBytes)
        #expect(pending.hasSuffix(".pdf"))
    }

    // MARK: - (coverage) The inline-image path joins the email's name the same way

    /// (coverage) `resolveInlineImage` calls `resolveExternalized` with `part.filename`,
    /// the email's own name. A hostile one must leave the image deferred, never embedded
    /// from the file it walks to.
    @Test func anEmptyInlineImageNamedOutsideItsDirectoryIsNeverEmbedded() async throws {
        let name = "../../../img1.png"
        let messageID = "traversal-image@rossi-spa.it"
        let fixture = try Self.fixture(
            messageID: messageID,
            rfc822: EmailFixtureCorpus.singleInlineImageMessageRFC822(
                messageID: messageID, contentID: "img1", imageBytes: Data(), filename: name
            )
        )
        try Self.plantOutside(EmailFixtureCorpus.noisyPNG(width: 200, height: 200), named: name, into: fixture)

        let vaultRoot = try await Self.sync(fixture, messageID: messageID)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty, "the planted image outside Attachments/1/2/ is never read")
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingInlineImages == ["img1"])
        #expect(!doc.newText.contains("![["))
    }

    // MARK: - (coverage) storePath: the extracted copy, or the .emlx

    private static func withMailLayout(_ body: (_ emlx: URL, _ attachments: URL, _ data: URL) throws -> Void) throws {
        let data = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-store-path-\(UUID().uuidString)/Data/1", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: data.deletingLastPathComponent().deletingLastPathComponent()) }
        let emlx = data.appending(path: "Messages/7.emlx", directoryHint: .notDirectory)
        let attachments = EMLXReader.attachmentsDirectory(forMessageAt: emlx, rowID: 7, part: "2")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        try body(emlx, attachments, data)
    }

    private static func path(_ url: URL) -> String { url.path(percentEncoded: false) }

    @Test func storePathIsTheExtractedCopyWhenItExistsAndTheEmlxWhenItDoesNot() throws {
        try Self.withMailLayout { emlx, attachments, _ in
            let copy = attachments.appending(path: "disegno.dwg", directoryHint: .notDirectory)
            try Data("x".utf8).write(to: copy)

            #expect(PraticaSyncEngine.storePath(of: "disegno.dwg", at: emlx, rowID: 7, part: "2") == Self.path(copy))
            #expect(PraticaSyncEngine.storePath(of: "altro.dwg", at: emlx, rowID: 7, part: "2") == Self.path(emlx))
        }
    }

    @Test(arguments: ["a\u{0}b", "", "..", "/", String(repeating: "a", count: 300)])
    func storePathFallsBackToTheEmlxForARefusedName(name: String) throws {
        try Self.withMailLayout { emlx, _, _ in
            #expect(PraticaSyncEngine.storePath(of: name, at: emlx, rowID: 7, part: "2") == Self.path(emlx))
        }
    }

    /// Not a refused name but a reduced one: the file a verbatim join would reach
    /// (`Data/1/secret.txt`) is never the answer; the component is looked for in the part
    /// directory, where it is absent, so the `.emlx` is.
    @Test(arguments: ["../../../secret.txt", "/etc/secret.txt"])
    func storePathNeverPointsAtTheFileAnEscapingNameWalksTo(name: String) throws {
        try Self.withMailLayout { emlx, _, data in
            try Data("x".utf8).write(to: data.appending(path: "secret.txt", directoryHint: .notDirectory))

            #expect(PraticaSyncEngine.storePath(of: name, at: emlx, rowID: 7, part: "2") == Self.path(emlx))
        }
    }

    // MARK: - (coverage) PraticaNaming.attachmentFileName: the cap

    private static let cap = MailAttachmentPath.maximumNameBytes - PraticaNaming.attachmentSuffixReserve
    private static let prefix = "20260610_"

    private static func capped(_ name: String) throws -> String {
        let day = try #require(CalendarDate(year: 2026, month: 6, day: 10))
        return PraticaNaming.attachmentFileName(date: day, name: name)
    }

    @Test func aNameExactlyAtTheCapIsUntouchedAndOneByteMoreIsCutToIt() throws {
        let fits = String(repeating: "a", count: Self.cap - Self.prefix.utf8.count)
        #expect(try Self.capped(fits) == Self.prefix + fits)
        let over = try Self.capped(fits + "a")
        #expect(over == Self.prefix + fits)
        #expect(over.utf8.count == Self.cap)
    }

    @Test func aCutNeverSplitsAFourByteCharacterAndFillsTheBudget() throws {
        let name = try Self.capped(String(repeating: "\u{1F600}", count: 100) + ".txt")
        let middle = String(name.dropFirst(Self.prefix.count).dropLast(".txt".count))

        #expect(name.utf8.count <= Self.cap)
        #expect(name.hasPrefix(Self.prefix) && name.hasSuffix(".txt"))
        #expect(!middle.isEmpty && middle.allSatisfy { $0 == "\u{1F600}" }, "whole characters only")
        #expect(name.utf8.count + 4 > Self.cap, "the cut keeps as many whole characters as fit")
    }

    /// A flag is one Character of two scalars (eight bytes). The ZWJ-sequence case is
    /// `PraticaNamingTests.aCutNeverSplitsAZWJSequence`.
    @Test func aCutNeverSplitsAGraphemeClusterMadeOfSeveralScalars() throws {
        let flag = "\u{1F1EE}\u{1F1F9}"
        let name = try Self.capped(String(repeating: flag, count: 40) + ".pdf")
        let middle = String(name.dropFirst(Self.prefix.count).dropLast(".pdf".count))

        #expect(name.utf8.count <= Self.cap)
        #expect(!middle.isEmpty)
        #expect(middle.allSatisfy { String($0) == flag }, "no lone regional indicator at the cut")
        #expect(name.utf8.count + 8 > Self.cap, "the cut keeps as many whole clusters as fit")
    }

    @Test func anExtensionThatIsItselfTheLongPartIsCutAsPartOfTheWholeName() throws {
        let full = Self.prefix + "report." + String(repeating: "x", count: 300)
        #expect(try Self.capped("report." + String(repeating: "x", count: 300)) == String(full.prefix(Self.cap)))
    }

    @Test func whitespaceLeftAtTheCutIsTrimmedBeforeTheExtension() throws {
        let stemRoom = Self.cap - Self.prefix.utf8.count - ".pdf".utf8.count
        let name = try Self.capped(String(repeating: "a", count: stemRoom - 1) + " " + String(repeating: "b", count: 50) + ".pdf")
        #expect(name == Self.prefix + String(repeating: "a", count: stemRoom - 1) + ".pdf")
    }

    @Test func aCappedNameStillFitsTheVolumeOnceTheCollisionSuffixIsAdded() throws {
        let name = try Self.capped(Self.fourKilobyteName)
        var taken: Set<String> = [name]
        for _ in 0..<12 {
            let next = PraticaSyncEngine.uniqueAttachmentName(name, taken: taken)
            #expect(next.utf8.count <= MailAttachmentPath.maximumNameBytes)
            taken.insert(next)
        }
    }

    // MARK: - (coverage) EMLXReader.attachmentFile

    @Test func attachmentFileJoinsOnlyAnInnocentNameToThePartDirectory() throws {
        try Self.withMailLayout { emlx, attachments, _ in
            let ok = try #require(EMLXReader.attachmentFile(named: "offerta.pdf", forMessageAt: emlx, rowID: 7, part: "2"))
            #expect(ok.deletingLastPathComponent().standardizedFileURL.path == attachments.standardizedFileURL.path)
            #expect(EMLXReader.attachmentFile(named: "..", forMessageAt: emlx, rowID: 7, part: "2") == nil)
            #expect(EMLXReader.attachmentFile(named: "", forMessageAt: emlx, rowID: 7, part: "2") == nil)
        }
    }

    // MARK: - (coverage) a symlinked file inside the part directory is not followed out

    @Test func aSymbolicLinkNamedInsideThePartDirectoryIsRefusedWhenItPointsOutside() throws {
        try Self.withMailLayout { _, attachments, data in
            let outside = data.appending(path: "secret.txt", directoryHint: .notDirectory)
            try Data("x".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(
                at: attachments.appending(path: "link.pdf", directoryHint: .notDirectory), withDestinationURL: outside
            )
            #expect(MailAttachmentPath.file(named: "link.pdf", in: attachments) == nil)
        }
    }
}
