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
        guard let text = String(data: data, encoding: .utf8) else {
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
    @discardableResult
    func write(_ text: String, to relativePath: String) throws -> String {
        let fileURL = try boundary.url(for: relativePath)

        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let data = Data(text.utf8)
        try data.write(to: fileURL, options: .atomic)
        return Self.hash(data)
    }

    static func hash(_ data: Data) -> String {
        hexString(SHA256.hash(data: data))
    }

    /// Lowercase hex, two digits per byte, no separator - byte-identical to
    /// `bytes.map { String(format: "%02x", $0) }.joined()`, which spends a `String(format:)`
    /// and a temporary String on each of a digest's thirty-two bytes. The hash it builds is
    /// persisted in the index cache, so the spelling is not free to change.
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
