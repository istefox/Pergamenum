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
    /// The vault root, with symlinks resolved once at construction.
    ///
    /// Resolving here rather than at each comparison is what makes the boundary check
    /// sound: `resolvingSymlinksInPath` does nothing for a path that does not exist
    /// yet, so a not-yet-created note under a symlinked vault kept the unresolved
    /// spelling while the root had the resolved one, and every write was refused as
    /// "outside the vault". Building every path from the resolved root removes the
    /// mismatch instead of trying to undo it later.
    let root: URL

    init(root: URL) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
    }

    enum StoreError: Error, CustomStringConvertible {
        case notUTF8(String)
        case outsideVault(String)

        var description: String {
            switch self {
            case .notUTF8(let path): "\(path) is not valid UTF-8"
            case .outsideVault(let path): "\(path) is outside the vault"
            }
        }
    }

    func url(for relativePath: String) -> URL {
        root.appending(path: relativePath, directoryHint: .notDirectory)
    }

    /// Reads a note and derives its record.
    func read(_ relativePath: String) throws -> (record: NoteRecord, text: String) {
        let fileURL = url(for: relativePath)
        try assertInsideVault(fileURL, relativePath)

        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw StoreError.notUTF8(relativePath)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))

        return (
            NoteRecord(
                relativePath: relativePath,
                title: NoteName.title(fromFileName: fileURL.lastPathComponent),
                frontmatter: NoteDocument.parse(text).frontmatter,
                linkTargets: Self.linkTargets(in: text),
                tasks: TaskParser.tasks(in: text, sourcePath: relativePath),
                modifiedAt: attributes[.modificationDate] as? Date ?? .distantPast,
                byteSize: data.count,
                contentHash: Self.hash(data)
            ),
            text
        )
    }

    /// Writes a note atomically and returns the hash of what was written, for the
    /// watcher to recognise as its own.
    @discardableResult
    func write(_ text: String, to relativePath: String) throws -> String {
        let fileURL = url(for: relativePath)
        try assertInsideVault(fileURL, relativePath)

        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let data = Data(text.utf8)
        try data.write(to: fileURL, options: .atomic)
        return Self.hash(data)
    }

    /// Guards against a relative path escaping the vault through `..`.
    ///
    /// Paths reach this layer from wikilinks and from the URL scheme, both of which
    /// are user-supplied text; without the check, `pergamenum://note?file=../../…`
    /// would write outside the vault.
    private func assertInsideVault(_ fileURL: URL, _ relativePath: String) throws {
        // Both sides start from the already-resolved root, so this compares like with
        // like; `standardized` still collapses any `..` the relative path smuggled in,
        // which is what the guard is actually for.
        let resolvedRoot = root.path(percentEncoded: false)
        let resolved = fileURL.standardizedFileURL.path(percentEncoded: false)

        let rootWithSeparator = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        guard resolved.hasPrefix(rootWithSeparator) else {
            throw StoreError.outsideVault(relativePath)
        }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Link targets from the body only. Frontmatter `related` is read separately, so
    /// counting it here would double every structural link in the backlink panel.
    ///
    /// A transcluded note is a link (ADR-0010 §D7): `![[nota]]` names a note, so the note
    /// it names shows the backlink and a transclusion pointing nowhere turns up among the
    /// unresolved links. A file embed is still not one - `![[foto.png]]` stays invisible
    /// here, which is what leaves `embedTargets` free for M11's gallery (ADR-0009 §D2).
    static func linkTargets(in text: String) -> [String] {
        let document = NoteDocument.parse(text)
        var seen = Set<String>()
        var ordered: [String] = []
        for link in WikilinkParser.links(in: document.body)
        where !link.isEmbed || Transclusion.isNoteReference(link.target) {
            if seen.insert(link.target).inserted { ordered.append(link.target) }
        }
        return ordered
    }
}
