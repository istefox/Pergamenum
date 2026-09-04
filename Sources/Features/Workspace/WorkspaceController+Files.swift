import Foundation

/// What a node points at on disk, and its attachment metadata - split out of
/// `WorkspaceController.swift` (`type_body_length` error, > 350 lines) as a size-only move,
/// same convention as `+Crop`/`+Gestures`/`+Nodes`. `emailHeaders` (declared on the base
/// class) lost its `private(set)` for this move: `loadEmailHeaders(for:)` below is its only
/// writer.
extension WorkspaceController {
    /// Absolute URL of the file a node points at, when it points at one.
    func fileURL(for node: CanvasNode) -> URL? {
        guard let store, case .file(let path, _) = node.kind else { return nil }
        return store.root.appending(path: path, directoryHint: .notDirectory)
    }

    /// URLs of the selected file cards, for the Quick Look panel (SPEC §6.6).
    ///
    /// The empty-selection exit is not tidiness: this walks every node in the document
    /// and stats each file it keeps, and the board redraws far more often than anything
    /// is selected. Nothing selected can only ever produce an empty list anyway.
    var selectedFileURLs: [URL] {
        guard !selection.isEmpty else { return [] }
        return document.nodes
            .filter { selection.contains($0.id) }
            .compactMap { node in
                // A folder card previews as a folder, which Quick Look renders as an
                // icon; the file cards are what the panel is useful for.
                subfolder(for: node) == nil ? fileURL(for: node) : nil
            }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// Reads and memoises the headers of an `.eml` card.
    ///
    /// Only the header block is read (SPEC §14 excludes body rendering), so this stays
    /// cheap even for a message with a large attachment: the file is mapped rather than
    /// copied, and only the bytes before the blank line are decoded.
    func loadEmailHeaders(for relativePath: String) {
        guard let store, emailHeaders[relativePath] == nil else { return }
        let fileURL = store.root.appending(path: relativePath, directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return }
        let headerBytes = Self.headerBlock(of: data)

        // Latin-1 as the fallback: an .eml whose headers are not UTF-8 still has
        // readable ASCII field names, and refusing the file would leave the card blank.
        let text = String(data: headerBytes, encoding: .utf8)
            ?? String(data: headerBytes, encoding: .isoLatin1)
            ?? ""
        emailHeaders[relativePath] = EmailHeaderParser.parse(text)
    }

    /// The bytes up to the blank line that ends an `.eml`'s header block.
    ///
    /// `EmailHeaderParser` stops at that line anyway, but only after the whole message
    /// has been decoded into a `String` - which for a base64 attachment is megabytes of
    /// UTF-8 validation done to be thrown away. Cutting at the boundary in bytes keeps
    /// the cost proportional to the headers.
    ///
    /// The search is capped: a file with no blank line in its first 64 KB is not a
    /// message these cards can describe, and the fallback cut lands on the last newline
    /// so a multi-byte character is never split - half a character fails UTF-8 and
    /// silently lands in the Latin-1 fallback as mojibake.
    private static func headerBlock(of data: Data) -> Data {
        let limit = min(data.count, 64 * 1024)
        let window = data[data.startIndex..<data.index(data.startIndex, offsetBy: limit)]

        let separators = [Data([0x0A, 0x0A]), Data([0x0D, 0x0A, 0x0D, 0x0A])]
        if let end = separators.compactMap({ window.range(of: $0)?.lowerBound }).min() {
            return window[window.startIndex..<end]
        }
        // Headers-only file shorter than the cap: nothing was truncated, keep it whole.
        guard limit < data.count, let lastNewline = window.lastIndex(of: 0x0A) else { return window }
        return window[window.startIndex..<lastNewline]
    }

    /// The folder a card points at, when it points at one.
    ///
    /// Checked against the filesystem directly (PG-054), not `subfolderSet`: that set only
    /// ever lists the *direct* children of the currently open board's own folder, so a card
    /// whose target folder was later moved elsewhere in the tree - now a nested path like
    /// `Nord/SudX` rather than a sibling of this board - would never match again no matter
    /// how many times the board reloads. The move itself already repoints the card's stored
    /// path correctly (`FolderFileOperations.repointBoardsPlan`); what was wrong was asking
    /// the wrong question about the result.
    func subfolder(for node: CanvasNode) -> String? {
        guard case .file(let path, _) = node.kind, let store else { return nil }
        var isDirectory: ObjCBool = false
        let url = store.root.appending(path: path, directoryHint: .isDirectory)
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false), isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue ? path : nil
    }
}
