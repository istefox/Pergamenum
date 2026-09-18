import Foundation

// ADR-0040 §D2 (2026-09-11): `PraticaSyncEngine` handed `part.decodedData ?? Data()` to the
// hasher and the writer unexamined, so an attachment Mail had not finished downloading landed
// in `allegati/` as a zero-byte file - and two such attachments hash alike, so the second was
// deduplicated onto the first one's name. Bytes are judged here, before anything hashes,
// places or opens them.
//
// ADR-0048 (2026-09-17): "Mail had not finished downloading" is not the only reason these bytes
// come back empty - Exchange sometimes externalizes an attachment permanently to Mail's own
// sibling `Attachments/<rowID>/<part>/` directory and never writes it inline at all. `.empty`
// still means exactly what it says about the *inline* bytes; `PraticaSyncEngine.resolveExternalized`
// is what tries the sibling directory before this verdict turns into a pending retry.

/// Whether an attachment's bytes are the file the sender attached, decided by magic bytes
/// alone. Foundation only - no ImageIO, no `UTType`, no `NSWorkspace`: this file compiles
/// into `perg` and `pergamenum-mcp` as well as into the app (ADR-0001 §D1).
///
/// The check is deliberately one-sided. A part whose declared type and file extension are
/// both unknown here is `.usable` on non-emptiness alone - never rejected for want of a
/// signature, the same «never drop on a guess» rule `InlineImageClassifier` follows. What it
/// cannot answer is a file that begins correctly and stops early inside a valid tail; that
/// needs a format parser and is a named limitation, not an oversight.
enum AttachmentIntegrity {
    /// Why an attachment's bytes are not the file the sender attached. `.usable` is the
    /// only verdict that may be hashed, placed or opened.
    enum Verdict: Equatable, Sendable {
        case usable
        /// Nothing at all: Mail has the part's headers and none of its bytes.
        case empty
        /// A signature is known for this part's declared type or extension and the
        /// leading bytes are not it.
        case signatureMismatch
        /// The head signature matched and the format's own terminator is missing -
        /// the download stopped part way (ADR-0040 §D2).
        case truncated
    }

    /// Decides on bytes already in memory. `contentType` is the part's declared
    /// `Content-Type` base form (`"application/pdf"`), `name` its declared filename -
    /// either may be `nil`, and a part that offers neither is judged on emptiness alone.
    static func verdict(of bytes: Data, named name: String?, contentType: String?) -> Verdict {
        // Rule 1: not a heuristic, and the case that actually fires in production (R-01).
        guard !bytes.isEmpty else { return .empty }
        // Rules 2 and 3: type first, extension second, and nothing known means usable.
        guard let format = format(declaredAs: contentType, named: name) else { return .usable }
        // Rules 4 and 6.
        guard bytes.count >= format.head.count,
              bytes.prefix(format.head.count).elementsEqual(format.head)
        else { return .signatureMismatch }
        // Rule 5, reached only once the head matched, so an unknown format can never be
        // rejected by it.
        return hasTerminator(format, inTailOf: bytes) ? .usable : .truncated
    }

    /// Decides on a file already on disk without reading it whole: the size, the first
    /// bytes of the head signature and the last `terminatorWindow` bytes. A 400 MB store
    /// reference must not be slurped to draw a chip (ADR-0040 §D8, R-07, R-09), so this
    /// reads two windows through a `FileHandle` and never Foundation's whole-file `Data`
    /// loader.
    static func verdict(ofFileAt url: URL, named name: String?) -> Verdict {
        // Absent, unreadable or zero length: all three mean there is nothing to open. A
        // directory reports no size and lands here too.
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            return .empty
        }
        guard let format = format(declaredAs: nil, named: name ?? url.lastPathComponent) else {
            return .usable
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .empty }
        defer { try? handle.close() }
        // An I/O failure is read as «no bytes here», never as a mismatch: the file is not
        // condemned for something the disk did.
        guard let head = try? handle.read(upToCount: format.head.count) else { return .empty }
        guard head.count == format.head.count, head.elementsEqual(format.head) else {
            return .signatureMismatch
        }
        let windowLength = min(format.terminatorWindow, size)
        guard let tail = try? tail(of: handle, from: size - windowLength) else { return .empty }
        return tail.range(of: Data(format.terminator)) != nil ? .usable : .truncated
    }

    // MARK: - The table

    /// One known format: the bytes it must begin with, the bytes it must end with, and how
    /// far back from the end the terminator may sit. The window is searched rather than
    /// compared to the exact last bytes - a PDF routinely carries whitespace or a
    /// linearisation remnant after `%%EOF`, and a JPEG may be padded.
    private struct Format {
        let head: [UInt8]
        let terminator: [UInt8]
        let terminatorWindow: Int
    }

    private static let pdf = Format(
        head: Array("%PDF".utf8), terminator: Array("%%EOF".utf8), terminatorWindow: 2048
    )
    private static let png = Format(
        head: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        terminator: Array("IEND".utf8), terminatorWindow: 16
    )
    private static let jpeg = Format(
        head: [0xFF, 0xD8, 0xFF], terminator: [0xFF, 0xD9], terminatorWindow: 32
    )
    /// Every OOXML and OpenDocument file is a ZIP container. The window is 66_000 because an
    /// end-of-central-directory record may be followed by a comment of up to 65_535 bytes.
    private static let zip = Format(
        head: [0x50, 0x4B, 0x03, 0x04], terminator: [0x50, 0x4B, 0x05, 0x06],
        terminatorWindow: 66_000
    )

    private static let formatsByContentType: [String: Format] = [
        "application/pdf": pdf,
        "image/png": png,
        "image/jpeg": jpeg,
        "application/zip": zip,
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": zip,
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": zip,
        "application/vnd.openxmlformats-officedocument.presentationml.presentation": zip,
    ]

    /// The OpenDocument family is a prefix rather than a list: `text`, `spreadsheet`,
    /// `presentation` and their template forms are all ZIP containers.
    private static let openDocumentTypePrefix = "application/vnd.oasis.opendocument."

    private static let formatsByExtension: [String: Format] = [
        "pdf": pdf,
        "png": png,
        "jpg": jpeg,
        "jpeg": jpeg,
        "zip": zip,
        "docx": zip,
        "xlsx": zip,
        "pptx": zip,
        "odt": zip,
        "ods": zip,
        "odp": zip,
    ]

    // MARK: - Lookup

    private static func format(declaredAs contentType: String?, named name: String?) -> Format? {
        // Rule 2: the declared type answers first. `application/octet-stream` - what a great
        // many senders declare - resolves to nothing, so the extension is consulted next.
        // Keying on the type alone would miss the commonest real shape; keying on the
        // extension alone would misjudge a file a sender renamed.
        if let declared = normalizedContentType(contentType) {
            if let format = formatsByContentType[declared] { return format }
            if declared.hasPrefix(openDocumentTypePrefix) { return zip }
        }
        guard let name else { return nil }
        return formatsByExtension[(name as NSString).pathExtension.lowercased()]
    }

    private static func normalizedContentType(_ contentType: String?) -> String? {
        guard let contentType else { return nil }
        // A declared type may still carry its parameters (`application/pdf; name="x.pdf"`);
        // only the base form is keyed.
        let base = contentType.split(separator: ";", maxSplits: 1).first ?? ""
        let normalized = base.trimmingCharacters(in: .whitespaces).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    // MARK: - Windows

    private static func hasTerminator(_ format: Format, inTailOf bytes: Data) -> Bool {
        let windowLength = min(format.terminatorWindow, bytes.count)
        let start = bytes.index(bytes.endIndex, offsetBy: -windowLength)
        return bytes.range(of: Data(format.terminator), in: start ..< bytes.endIndex) != nil
    }

    private static func tail(of handle: FileHandle, from offset: Int) throws -> Data {
        try handle.seek(toOffset: UInt64(offset))
        return try handle.readToEnd() ?? Data()
    }
}
