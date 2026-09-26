import CryptoKit
import Foundation

/// One note on disk, as the index and the UI see it.
struct NoteRecord: Identifiable, Equatable, Sendable {
    /// Path relative to the vault root, e.g. `01 Progetti/Trasmissibilità.md`.
    /// Stable identity for everything except a rename, which is what W-08 makes an
    /// in-app operation.
    var relativePath: String
    /// The file stem, which is the note title (naming.md 4.6).
    var title: String
    var frontmatter: Frontmatter
    /// Wikilink targets found in the body, in source order, duplicates removed.
    var linkTargets: [String]
    /// Files the body embeds on a line of their own, in source order, duplicates removed
    /// (ADR-0009 §D2). The half `linkTargets` leaves out, and what the gallery renderer
    /// of M11 draws.
    ///
    /// Defaulted so that the many places building a record for a test need not say
    /// "no embeds" to mean it; the one place that reads a note from disk always fills it.
    var embedTargets: [String] = []
    /// The `pergamenum-category` scalar of this note's frontmatter (ADR-0047 §D5),
    /// when it carries one - the slug this note is the linked home of (SPEC "Note ↔
    /// category"). Defaulted for the same reason `embedTargets` is: the many places
    /// building a record for a test need not say "no category" to mean it.
    var categorySlug: String?
    /// Tasks found in the body, with their line numbers (SPEC §7.1).
    var tasks: [TaskItem]
    var modifiedAt: Date
    var byteSize: Int
    /// SHA-256 of the file's contents as last read or written by the app.
    ///
    /// This is what lets the watcher tell the app's own write apart from an external
    /// edit without suppression windows, which are timing-dependent and lose real
    /// edits that land inside them (ADR-0001 §D3).
    var contentHash: String

    var id: String { relativePath }

    /// The folder containing the note, or "" at the vault root.
    var folder: String {
        let components = relativePath.split(separator: "/")
        return components.count <= 1 ? "" : components.dropLast().joined(separator: "/")
    }
}

/// Reads and writes note files.
///
/// Every write is atomic: a crash between truncate and write would otherwise leave a
/// half-written note, and "file over app" is worthless if the file can be corrupted
/// by the app that promises to protect it.
struct NoteStore: Sendable {
    /// The vault root, with symlinks resolved once at construction - see
    /// `VaultBoundary.root` for why that resolution happens here and not per comparison.
    let root: URL

    /// The only way this type turns a caller's relative path into a `URL` on disk
    /// (ADR-0041 §D1).
    private let boundary: VaultBoundary

    init(root: URL) {
        let boundary = VaultBoundary(root: root)
        self.boundary = boundary
        self.root = boundary.root
    }

    enum StoreError: Error, CustomStringConvertible {
        case notUTF8(String)

        var description: String {
            switch self {
            case .notUTF8(let path): "\(path) is not valid UTF-8"
            }
        }
    }

    /// The door thirty-one call sites use to get a `URL` on disk, and therefore the one
    /// that has to carry the guard (ADR-0041 §D2).
    ///
    /// It is `throws` for the reason the ADR gives: making the accessor throwing is what
    /// converts «nine call sites forgot the check» into «nine call sites will not compile
    /// until they handle it». `read` and `write` below resolve through `boundary`
    /// directly rather than through this accessor, because they already did.
    func url(for relativePath: String) throws -> URL {
        try boundary.url(for: relativePath)
    }

    /// Reads a note and derives its record.
    ///
    /// Parses `NoteDocument.parse(text)` exactly once (ADR-0041 §D7) and hands the parsed
    /// document to `makeRecord`, which both this and `record(from:attributes:at:)`
    /// (`NoteStore+ReadSurface.swift`) go through - the field-building logic is shared, the
    /// parse is not, because each of those two entry points starts from a different thing
    /// it already has (a `URL` here, raw `Data` there) and would otherwise have to parse
    /// again to call the other.
    func read(_ relativePath: String) throws -> (record: NoteRecord, text: String) {
        let fileURL = try boundary.url(for: relativePath)

        let data = try Data(contentsOf: fileURL)
        guard let text = Self.decodedText(data) else {
            throw StoreError.notUTF8(relativePath)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
        let document = NoteDocument.parse(text)

        return (
            Self.makeRecord(from: data, text: text, document: document, attributes: attributes, at: relativePath),
            text
        )
    }

    /// The fields a read derives, given a document already parsed once by the caller.
    /// Shared by `read` above and `record(from:attributes:at:)`
    /// (`NoteStore+ReadSurface.swift`, ADR-0041 §D7) so the two do not drift onto two
    /// copies of the same field list.
    static func makeRecord(
        from data: Data,
        text: String,
        document: NoteDocument,
        attributes: [FileAttributeKey: Any],
        at relativePath: String
    ) -> NoteRecord {
        NoteRecord(
            relativePath: relativePath,
            title: NoteName.title(fromFileName: (relativePath as NSString).lastPathComponent),
            frontmatter: document.frontmatter,
            linkTargets: linkTargets(in: document),
            embedTargets: Transclusion.embeddedFiles(in: text),
            categorySlug: CategoryFrontmatter.slug(in: document.frontmatter.foreignKeys),
            tasks: TaskParser.tasks(in: text, sourcePath: relativePath),
            modifiedAt: attributes[.modificationDate] as? Date ?? .distantPast,
            byteSize: data.count,
            contentHash: hash(data)
        )
    }

    /// Writes a note atomically and returns the hash of what was written, for the
    /// watcher to recognise as its own.
    ///
    /// `requiringExistingFolder` (PG-168) is the container half of the same opt-in family as
    /// `VaultSession.write`'s `expecting:`, defaulted to today's behaviour so all six callers
    /// keep creating (a rename or a move legitimately writes into a folder it has just made).
    /// When set, the parent is **not** created and `Data.write` is left to fail with its own
    /// ENOENT. That failure is the point: a caller that opts in is one for which bringing back
    /// a directory somebody just vacated is worse than not writing, and an unconditional
    /// `createDirectory` here is what turned a mid-sync folder move into a stray
    /// `<vacated>/email/` holding a message and no `pratica.md`. The *named* refusal is raised
    /// one layer up, in `VaultDisk`, where the check and the write share an isolation; this
    /// flag is what makes losing that check's race loud instead of quiet.
    @discardableResult
    func write(_ text: String, to relativePath: String, requiringExistingFolder: Bool = false) throws -> String {
        let fileURL = try boundary.url(for: relativePath)

        if !requiringExistingFolder {
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        // ADR-0064 §D4.3: the BOM belongs to the file. A file that starts with one keeps it when
        // the new bytes do not bring their own; a new file, or one without, never gains one.
        var data = Data(text.utf8)
        if !data.starts(with: Self.byteOrderMark), Self.startsWithByteOrderMark(fileURL) {
            data = Self.byteOrderMark + data
        }
        try data.write(to: fileURL, options: .atomic)
        return Self.hash(data)
    }

    /// The UTF-8 byte-order mark, `EF BB BF`.
    static let byteOrderMark = Data([0xEF, 0xBB, 0xBF])

    /// The one decode door for a note's bytes (ADR-0064 §D4.1): one leading BOM is removed, then
    /// the rest is decoded as UTF-8. The text the app works on never starts with a BOM read from a
    /// vault note, whatever the platform's own decode does with it.
    static func decodedText(_ data: Data) -> String? {
        String(data: withoutByteOrderMark(data), encoding: .utf8)
    }

    private static func withoutByteOrderMark(_ data: Data) -> Data {
        data.starts(with: byteOrderMark) ? data.dropFirst(byteOrderMark.count) : data
    }

    /// Reads three bytes, not the file: one extra small read per note write.
    private static func startsWithByteOrderMark(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: byteOrderMark.count)) == byteOrderMark
    }

    /// The one guarded write for a planned note rewrite (ADR-0055 §D1), beside
    /// `CanvasStore.writeRepoint` - the `.canvas` twin of this same door.
    ///
    /// Compares `change.expectedHash` (`VaultFileChange+ExpectedHash.swift:11`) against the
    /// file's current bytes and throws `VaultWriteRefusal.movedOn(change.path)` on a mismatch,
    /// with nothing written - a missing file included, since `nil` never equals a non-nil
    /// expectation (ADR-0046 §D8: a vanished note is refused, not re-created). A match delegates
    /// to `write(_:to:requiringExistingFolder:)` above with `requiringExistingFolder: true`: the
    /// comparison has already proven the file, and therefore its parent, is there, so a redundant
    /// `createDirectory` has nothing left to do (PG-168's decision, applied where it belongs).
    ///
    /// Not `VaultSession.writeGuarded` (`VaultSession.swift:626`), which does the same thing
    /// through the async journalled door - two types, one verb, resolved by the receiver: a
    /// caller inside `Sources/Vault`'s file-operations types uses this one, a caller inside a
    /// `VaultSession` transaction uses that one. `VaultWriteRefusal` is referred to unqualified,
    /// not `Pergamenum.VaultWriteRefusal`, which would not compile in `perg`/`pergamenum-mcp`
    /// (ADR-0046 §D4).
    func writeGuarded(_ change: VaultFileChange) throws {
        let fileURL = try boundary.url(for: change.path)
        let current = try? Data(contentsOf: fileURL)
        guard current.map(Self.hash) == change.expectedHash else {
            throw VaultWriteRefusal.movedOn(change.path)
        }
        try write(change.after, to: change.path, requiringExistingFolder: true)
    }

    /// A note's content hash: SHA-256 over the bytes after one leading BOM, if there is one
    /// (ADR-0064 §D4.2, G1.2). For every file without a BOM this is the plain SHA-256 of the file,
    /// so every hash already persisted for such a file stays valid. For a BOM file the raw-bytes
    /// hash and the decoded text's hash become the same value, which every `expecting:`
    /// comparison and the watcher's self-write check already assumed they were.
    static func hash(_ data: Data) -> String {
        hexString(SHA256.hash(data: withoutByteOrderMark(data)))
    }

    /// Lowercase hex, two digits per byte, no separator - byte-identical to
    /// `bytes.map { String(format: "%02x", $0) }.joined()`, which spends a `String(format:)`
    /// and a temporary String on each of a digest's thirty-two bytes. The hash it builds is
    /// persisted in the index cache, so the spelling is not free to change. What is hashed was
    /// redefined once, deliberately and with a bound, by ADR-0064 §D4.2: a leading BOM is
    /// skipped, and only a BOM file's value moved.
    static func hexString(_ bytes: some Sequence<UInt8>) -> String {
        let digits: [UInt8] = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.underestimatedCount * 2)
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Link targets from the body only. Frontmatter `related` is read separately, so
    /// counting it here would double every structural link in the backlink panel.
    ///
    /// A transcluded note is a link (ADR-0010 §D7): `![[nota]]` names a note, so the note
    /// it names shows the backlink and a transclusion pointing nowhere turns up among the
    /// unresolved links. A file embed is still not one - `![[foto.png]]` stays invisible
    /// here, which is what leaves `embedTargets` free for M11's gallery (ADR-0009 §D2).
    ///
    /// A thin wrapper over `linkTargets(in document:)` (`NoteStore+ReadSurface.swift`) for
    /// the two callers (`Tests/TransclusionTests.swift:182`, `:221`) that only have text,
    /// not an already-parsed document (ADR-0041 §D7).
    static func linkTargets(in text: String) -> [String] {
        linkTargets(in: NoteDocument.parse(text))
    }
}
