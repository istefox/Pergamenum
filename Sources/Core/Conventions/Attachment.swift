import Foundation

/// A file embedded in a note, and where it actually is on disk.
///
/// Two spellings, because a vault is not written by one program: `![[foto.png]]` is
/// what this app and Obsidian write (SPEC §5), `![didascalia](foto.png)` is CommonMark
/// and arrives with notes from everywhere else. Both mean the same thing here.
///
/// Nothing in this file touches the network. A `http` target is recognised precisely so
/// that it is *not* resolved: the app makes no network call in any feature, so a remote
/// image stays a link the browser can open.
enum Attachment {
    struct Embed: Equatable, Sendable {
        /// What the note wrote: a file name, or a path relative to the note.
        var target: String
        /// The label of `![alt](…)`. The wikilink form carries none.
        var alt: String?

        /// What an accessibility element announces for this embed: the CommonMark
        /// caption where there is one, the file name otherwise (ADR-0053 §D2 seam #13,
        /// moved from `CompletingTextView+Accessibility.swift`, unchanged).
        var label: String { alt ?? target }
    }

    /// The embed a line consists of, or nil when the line is anything else.
    ///
    /// Only a line that is *nothing but* the embed. An embed inside a paragraph stays
    /// inline text and reading mode keeps rendering it as a label: a picture dropped in
    /// the middle of a sentence would break the sentence in two.
    static func embed(inLine line: String) -> Embed? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("![") else { return nil }

        if trimmed.hasPrefix("![["), trimmed.hasSuffix("]]") {
            let inner = String(trimmed.dropFirst(3).dropLast(2))
            // `![[foto.png|300]]` sizes the embed in Obsidian; the name is the part
            // before the pipe, and the size is not ours to interpret yet.
            let target = String(inner.split(separator: "|", maxSplits: 1).first ?? "")
                .trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty, !target.contains("]]") else { return nil }
            return Embed(target: target, alt: nil)
        }

        guard let close = trimmed.range(of: "]("), trimmed.hasSuffix(")") else { return nil }
        let alt = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close.lowerBound])
        let target = String(trimmed[close.upperBound...].dropLast())
            .trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !target.contains("]("), !target.contains(")") else { return nil }
        return Embed(target: target, alt: alt.isEmpty ? nil : alt)
    }

    /// True for a target this app must never fetch (principle 2, fully offline).
    static func isRemote(_ target: String) -> Bool {
        let scheme = target.prefix(while: { $0 != ":" }).lowercased()
        return ["http", "https", "ftp"].contains(scheme) && target.contains("://")
    }

    /// The vault-relative path of an embedded file, or nil when the vault has no such
    /// file.
    ///
    /// Beside the note first, because that is where `importFileIntoVault` puts what the
    /// user drops in; then from the vault root, for a note that spells the whole path;
    /// then by name anywhere in the vault, so moving a picture in the Finder does not
    /// blank it out in the note.
    static func resolve(
        _ target: String,
        nearNoteAt notePath: String,
        inVaultAt root: URL
    ) -> String? {
        guard !isRemote(target) else { return nil }
        let decoded = target.removingPercentEncoding ?? target
        for candidate in [decoded, target] where !candidate.isEmpty {
            if let found = search(candidate, nearNoteAt: notePath, inVaultAt: root) { return found }
        }
        return nil
    }

    private static func search(
        _ target: String,
        nearNoteAt notePath: String,
        inVaultAt root: URL
    ) -> String? {
        // An absolute path, or one that climbs out of the vault, is not something a note
        // in this vault is allowed to point at.
        guard !target.hasPrefix("/"), !target.hasPrefix("~"),
              !target.split(separator: "/").contains("..")
        else { return nil }

        let folder = (notePath as NSString).deletingLastPathComponent
        let beside = folder.isEmpty ? target : "\(folder)/\(target)"
        for relative in [beside, target] where exists(relative, in: root) {
            return relative
        }
        return byName((target as NSString).lastPathComponent, in: root)
    }

    private static func exists(_ relativePath: String, in root: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = root.appending(path: relativePath, directoryHint: .notDirectory)
            .path(percentEncoded: false)
        let found = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return found && !isDirectory.boolValue
    }

    /// The first file with this name anywhere in the vault.
    ///
    /// Skips hidden directories, which is what keeps the app's own `.pergamenum` cache -
    /// full of generated thumbnails with names of their own - out of the answer.
    private static func byName(_ fileName: String, in root: URL) -> String? {
        guard !fileName.isEmpty else { return nil }
        // Both sides through the same normalisation, because the enumerator hands back
        // paths the root does not spell the same way: a vault under `/var/…` comes back
        // as `/private/var/…`, and a plain prefix check would match nothing at all. Any
        // vault reached through a symlink has the same problem.
        let base = normalisedFolderPath(root)

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent == fileName,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let full = url.resolvingSymlinksInPath().path(percentEncoded: false)
            guard full.hasPrefix(base) else { continue }
            return String(full.dropFirst(base.count))
        }
        return nil
    }

    /// A folder's path with symlinks resolved and a trailing separator, so one path is
    /// a prefix of another exactly when one folder contains the other.
    private static func normalisedFolderPath(_ url: URL) -> String {
        let path = url.resolvingSymlinksInPath().path(percentEncoded: false)
        return path.hasSuffix("/") ? path : path + "/"
    }
}
