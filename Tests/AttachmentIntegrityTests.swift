import Foundation
import Testing
@testable import Pergamenum

// ADR-0040 (Pratiche attachment reliability bugs) §D1, §D2, plan
// docs/superpowers/plans/2026-09-11-pratiche-attachment-reliability-bugs.md, Task 1 -
// R-01, R-02, R-03.
//
// `AttachmentIntegrity` is a tester-declared boundary (ADR-0155 §D1): the signature and
// the `Verdict` cases are final, the bodies (`Sources/Core/Email/AttachmentIntegrity.swift`)
// are placeholders that always answer `.usable` until the coder fills in §D2's six-rule
// table. Every assertion below that expects something other than `.usable` is red for
// that reason, not because the fixture is wrong.
@Suite struct AttachmentIntegrityTests {
    // MARK: - Fixture bytes, built by hand against ADR-0040 §D2's table

    /// `%PDF` head, `%%EOF` terminator, both well inside their windows (2048 bytes for
    /// the tail).
    private static let pdfUsableBytes = Data("%PDF-1.7\nsome content, several lines\nmore content\n%%EOF".utf8)

    /// A valid PDF head with no `%%EOF` anywhere in the file.
    private static let pdfTruncatedBytes = Data(
        "%PDF-1.7\nsome content that never reaches a terminator at all, just filler text".utf8
    )

    /// A valid, complete PDF followed by 40 bytes of trailing whitespace after `%%EOF` -
    /// the terminator window is searched, not suffix-compared, so this must still read
    /// `.usable` (ADR-0040 §D2 rule 5's own worked example: a linearisation remnant).
    private static let pdfWithTrailingWhitespaceBytes = pdfUsableBytes + Data(repeating: 0x20, count: 40)

    /// JPEG head (`FF D8 FF`) + filler + JPEG terminator (`FF D9`), both inside the
    /// 32-byte tail window.
    private static let jpegUsableBytes = Data([0xFF, 0xD8, 0xFF]) + Data(repeating: 0x00, count: 50) + Data([0xFF, 0xD9])

    /// JPEG head with no `FF D9` terminator anywhere in the file.
    private static let jpegTruncatedBytes = Data([0xFF, 0xD8, 0xFF]) + Data(repeating: 0x00, count: 50)

    /// ZIP head (`50 4B 03 04`) + filler + ZIP end-of-central-directory terminator
    /// (`50 4B 05 06`), both inside the 66_000-byte tail window.
    private static let zipUsableBytes = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0x00, count: 100) + Data([0x50, 0x4B, 0x05, 0x06])

    /// ZIP head with no end-of-central-directory record anywhere in the file.
    private static let zipTruncatedBytes = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0x00, count: 100)

    /// Only the four-byte ZIP head, nothing else - the 66_000-byte tail window is far
    /// longer than the whole file. Must resolve to `.truncated`, not crash.
    private static let zipHeaderOnlyBytes = Data([0x50, 0x4B, 0x03, 0x04])

    // MARK: - R-01: empty bytes always win, regardless of what is declared

    @Test func emptyBytesWithKnownContentTypeAreEmpty() {
        #expect(
            AttachmentIntegrity.verdict(of: Data(), named: nil, contentType: "application/pdf") == .empty
        )
    }

    @Test func emptyBytesWithUnknownContentTypeAreEmpty() {
        #expect(
            AttachmentIntegrity.verdict(of: Data(), named: "x.dwg", contentType: "application/octet-stream") == .empty
        )
    }

    @Test func emptyBytesWithNoNameAndNoContentTypeAreEmpty() {
        #expect(AttachmentIntegrity.verdict(of: Data(), named: nil, contentType: nil) == .empty)
    }

    // MARK: - R-02, R-03: a real PDF is usable however it is declared

    @Test func validPDFDeclaredByContentTypeIsUsable() {
        #expect(
            AttachmentIntegrity.verdict(of: Self.pdfUsableBytes, named: nil, contentType: "application/pdf") == .usable
        )
    }

    @Test func validPDFDeclaredOctetStreamWithPDFExtensionIsUsable() {
        // application/octet-stream resolves to nothing (§D2 rule 2), so the ".pdf"
        // extension is what the lookup actually falls back to.
        #expect(
            AttachmentIntegrity.verdict(of: Self.pdfUsableBytes, named: "x.pdf", contentType: "application/octet-stream") == .usable
        )
    }

    @Test func validPDFDeclaredWithNeitherContentTypeNorNameIsUsable() {
        // No entry for either the type or the extension -> never rejected for want of a
        // signature (§D2 rule 3).
        #expect(
            AttachmentIntegrity.verdict(of: Self.pdfUsableBytes, named: nil, contentType: nil) == .usable
        )
    }

    // MARK: - R-02, R-03 pair: the whole of the design's conservatism

    @Test func arbitraryTextBytesNamedPDFAreSignatureMismatch() {
        #expect(
            AttachmentIntegrity.verdict(of: Data("contenuto".utf8), named: "x.pdf", contentType: nil) == .signatureMismatch
        )
    }

    @Test func sameBytesNamedWithAnUnknownExtensionAreUsable() {
        // ".dwg" has no signature entry in this design, so non-emptiness alone is
        // enough (§D2 rule 3).
        #expect(
            AttachmentIntegrity.verdict(of: Data("contenuto".utf8), named: "x.dwg", contentType: nil) == .usable
        )
    }

    @Test func sameBytesWithNoNameAtAllAreUsable() {
        #expect(
            AttachmentIntegrity.verdict(of: Data("contenuto".utf8), named: nil, contentType: nil) == .usable
        )
    }

    // MARK: - PDF truncation: the window is searched, not suffix-compared

    @Test func pdfHeadWithNoTerminatorAnywhereIsTruncated() {
        #expect(
            AttachmentIntegrity.verdict(of: Self.pdfTruncatedBytes, named: nil, contentType: "application/pdf") == .truncated
        )
    }

    @Test func pdfTerminatorFollowedByTrailingWhitespaceIsStillUsable() {
        #expect(
            AttachmentIntegrity.verdict(of: Self.pdfWithTrailingWhitespaceBytes, named: nil, contentType: "application/pdf") == .usable
        )
    }

    // MARK: - PNG: usable / truncated / signature mismatch

    @Test func validPNGIsUsable() {
        let png = EmailFixtureCorpus.solidColorPNG(width: 8, height: 8)
        #expect(AttachmentIntegrity.verdict(of: png, named: nil, contentType: "image/png") == .usable)
    }

    @Test func pngWithLast20BytesDroppedIsTruncated() {
        let png = EmailFixtureCorpus.solidColorPNG(width: 8, height: 8)
        let truncated = png.dropLast(20)
        #expect(AttachmentIntegrity.verdict(of: truncated, named: nil, contentType: "image/png") == .truncated)
    }

    @Test func pngWithFirstByteFlippedIsSignatureMismatch() {
        var corrupted = EmailFixtureCorpus.solidColorPNG(width: 8, height: 8)
        corrupted[corrupted.startIndex] = corrupted[corrupted.startIndex] ^ 0xFF
        #expect(AttachmentIntegrity.verdict(of: corrupted, named: nil, contentType: "image/png") == .signatureMismatch)
    }

    // MARK: - JPEG: usable / truncated / signature mismatch

    @Test func validJPEGIsUsable() {
        #expect(
            AttachmentIntegrity.verdict(of: Self.jpegUsableBytes, named: nil, contentType: "image/jpeg") == .usable
        )
    }

    @Test func jpegWithNoTerminatorIsTruncated() {
        #expect(
            AttachmentIntegrity.verdict(of: Self.jpegTruncatedBytes, named: nil, contentType: "image/jpeg") == .truncated
        )
    }

    @Test func nonJPEGBytesNamedJPGAreSignatureMismatch() {
        #expect(
            AttachmentIntegrity.verdict(of: Data("not a jpeg at all".utf8), named: "x.jpg", contentType: nil) == .signatureMismatch
        )
    }

    // MARK: - ZIP: usable / truncated / signature mismatch, and a header-only file

    @Test func validZIPIsUsable() {
        #expect(
            AttachmentIntegrity.verdict(of: Self.zipUsableBytes, named: nil, contentType: "application/zip") == .usable
        )
    }

    @Test func zipWithNoEndOfCentralDirectoryIsTruncated() {
        #expect(
            AttachmentIntegrity.verdict(of: Self.zipTruncatedBytes, named: nil, contentType: "application/zip") == .truncated
        )
    }

    @Test func nonZIPBytesNamedZipAreSignatureMismatch() {
        #expect(
            AttachmentIntegrity.verdict(of: Data("not a zip".utf8), named: "x.zip", contentType: nil) == .signatureMismatch
        )
    }

    @Test func fourByteZIPHeaderAloneIsTruncatedNotACrash() {
        // The tail window (66_000 bytes) is far longer than the whole file - must not
        // trap or crash on the range.
        #expect(
            AttachmentIntegrity.verdict(of: Self.zipHeaderOnlyBytes, named: nil, contentType: "application/zip") == .truncated
        )
    }

    // MARK: - Rule 6: a file shorter than its own head signature

    @Test func bytesShorterThanTheDeclaredHeadSignatureAreSignatureMismatch() {
        // "%P" is shorter than the four-byte "%PDF" head this type declares.
        #expect(
            AttachmentIntegrity.verdict(of: Data([0x25, 0x50]), named: nil, contentType: "application/pdf") == .signatureMismatch
        )
    }

    // MARK: - `verdict(ofFileAt:)`

    @Test func nonExistentFileIsEmpty() {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-attachment-integrity-missing-\(UUID().uuidString).pdf", directoryHint: .notDirectory)
        #expect(AttachmentIntegrity.verdict(ofFileAt: missing, named: nil) == .empty)
    }

    @Test func threeMegabyteFileWithValidHeadAndTailIsUsable() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-attachment-integrity-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appending(path: "large.pdf", directoryHint: .notDirectory)
        var bytes = Data("%PDF-1.7\n".utf8)
        bytes.append(Data(repeating: 0x41, count: 3 * 1024 * 1024))
        bytes.append(Data("\n%%EOF".utf8))
        try bytes.write(to: url)

        #expect(AttachmentIntegrity.verdict(ofFileAt: url, named: nil) == .usable)
    }

    /// `verdict(ofFileAt:)` must never call `Data(contentsOf:)` - that would slurp a
    /// 400 MB store reference whole just to draw a chip (§D1, §D8). There is no hook to
    /// count bytes actually read here, so the guarantee is structural: the real
    /// implementation must read only through `URL.resourceValues` and `FileHandle`
    /// windows. Follows `Tests/SharedSourcesPurityTests.swift`'s own file-walking
    /// precedent.
    @Test func fileVerdictImplementationNeverCallsDataContentsOfWhole() throws {
        let repoRoot = try Self.resolvedRepoRoot()
        let fileURL = repoRoot.appendingPathComponent("Sources/Core/Email/AttachmentIntegrity.swift")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(
            !contents.contains("Data(contentsOf:"),
            "AttachmentIntegrity.swift must read a file's size and windows only, never the whole file - ADR-0040 §D1/§D8"
        )
    }

    /// One `deletingLastPathComponent()` off this file's own directory (`Tests/`) gives
    /// the repository root, matching `SharedSourcesPurityTests.resolvedRepoRoot()`.
    private static func resolvedRepoRoot() throws -> URL {
        let thisFileURL = URL(fileURLWithPath: #filePath)
        let candidateRoot = thisFileURL
            .deletingLastPathComponent() // AttachmentIntegrityTests.swift -> Tests/
            .deletingLastPathComponent() // Tests/ -> repository root
        guard FileManager.default.fileExists(atPath: candidateRoot.appendingPathComponent("Sources").path) else {
            struct RepoRootNotFound: Error, CustomStringConvertible {
                let candidate: String
                var description: String { "Could not resolve the repository root from #filePath. Candidate tried: \(candidate)" }
            }
            throw RepoRootNotFound(candidate: candidateRoot.path)
        }
        return candidateRoot
    }
}
