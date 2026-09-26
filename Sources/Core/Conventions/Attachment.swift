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
    ///
    /// Builds one `VaultBoundary` per call, which resolves the root's symlinks once. For
    /// the callers off the keystroke path; the editor's `EmbedTable` keeps its own
    /// boundary and calls `resolve(_:nearNoteAt:within:)` (ADR-0063 §D7).
    static func resolve(
        _ target: String,
        nearNoteAt notePath: String,
        inVaultAt root: URL
    ) -> String? {
        resolve(target, nearNoteAt: notePath, within: VaultBoundary(root: root))
    }

    /// The same resolution against a boundary the caller already built (ADR-0063 §D7).
    ///
    /// Every probe goes through `boundary.url(for:)`. A note whose folder resolves
    /// outside the vault answers nil **before any probe at all** - not beside it, not
    /// from the root, not by name - so a file of the same name inside the vault cannot
    /// make an escaping note look like it resolved.
    static func resolve(
        _ target: String,
        nearNoteAt notePath: String,
        within boundary: VaultBoundary
    ) -> String? {
        guard !isRemote(target) else { return nil }
        let folder = (notePath as NSString).deletingLastPathComponent
        // An empty folder is the vault root, which the resolver refuses by design.
        if !folder.isEmpty, (try? boundary.url(for: folder)) == nil { return nil }
        let decoded = target.removingPercentEncoding ?? target
        for candidate in [decoded, target] where !candidate.isEmpty {
            if let found = search(candidate, inFolder: folder, within: boundary) { return found }
        }
        return nil
    }

    private static func search(
        _ target: String,
        inFolder folder: String,
        within boundary: VaultBoundary
    ) -> String? {
        // An absolute path, or one that climbs out of the vault, is not something a note
        // in this vault is allowed to point at.
        guard !target.hasPrefix("/"), !target.hasPrefix("~"),
              !target.split(separator: "/").contains("..")
        else { return nil }

        let beside = folder.isEmpty ? target : "\(folder)/\(target)"
        for relative in [beside, target] where exists(relative, within: boundary) {
            return relative
        }
        return byName((target as NSString).lastPathComponent, within: boundary)
    }

    private static func exists(_ relativePath: String, within boundary: VaultBoundary) -> Bool {
        guard let url = try? boundary.url(for: relativePath) else { return false }
        var isDirectory: ObjCBool = false
        let found = FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        return found && !isDirectory.boolValue
    }

    /// The first file with this name anywhere in the vault.
    ///
    /// Skips hidden directories, which is what keeps the app's own `.pergamenum` cache -
    /// full of generated thumbnails with names of their own - out of the answer.
    private static func byName(_ fileName: String, within boundary: VaultBoundary) -> String? {
        guard !fileName.isEmpty else { return nil }
        // Walked from the boundary's root, whose symlinks were resolved once when the
        // boundary was built, so the enumerator hands back paths spelled the same way (a
        // vault under `/var/…` is already `/private/var/…` there) and the root needs no
        // second resolution here. A match is still resolved on its own, so a symlinked
        // file pointing outside the vault fails the prefix test.
        let rootPath = boundary.root.path(percentEncoded: false)
        let base = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        let enumerator = FileManager.default.enumerator(
            at: boundary.root,
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
}
