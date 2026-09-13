import Foundation

/// The one way to turn a caller-supplied relative path into a `URL` inside the vault.
///
/// This used to be `NoteStore.assertInsideVault`, a private step beside the value it
/// guarded: a caller obtained the `URL` first and called the check afterwards, or forgot
/// to. Nine of eleven call sites forgot (ADR-0041 §D1). A resolver cannot be forgotten,
/// because the `URL` a caller needs only exists on the other side of it.
struct VaultBoundary: Sendable {
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

    /// Resolves a relative path against the root, or refuses it.
    ///
    /// Paths reach this layer from wikilinks and from the URL scheme, both of which are
    /// user-supplied text; without the check, `pergamenum://note?file=../../…` would
    /// write outside the vault.
    ///
    /// The decided policy, edge case by edge case:
    ///
    /// - `a/../b.md` resolves to `<root>/b.md` and is legal. Collapsing `..` inside the
    ///   vault is fine; escaping with it is not. That pair is the whole of the guard.
    /// - An **absolute** path is refused, and refused before anything else.
    ///   `URL.appending(path:)` silently drops a leading separator, so `/etc/passwd`
    ///   would otherwise resolve to `<root>/etc/passwd` — inside the vault, and a
    ///   different file from the one the caller named. Answering a different file is
    ///   worse than refusing.
    /// - `""`, `"."` and `"./"` resolve to the vault root itself and are refused: this
    ///   returns a file inside the vault, and the vault directory is not one.
    /// - `"./x.md"` is accepted as `x.md`. A trailing slash, a unicode name and a literal
    ///   `%2e%2e` component are all kept verbatim — none of them escapes.
    ///
    /// The thrown `Violation` carries the path **as the caller spelled it**, never the
    /// resolved one: the message is read by a person looking at a problem list.
    func url(for relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/") else { throw Violation.outsideVault(relativePath) }

        let resolved = root
            .appending(path: relativePath, directoryHint: .notDirectory)
            .standardizedFileURL
        guard isInside(resolved) else { throw Violation.outsideVault(relativePath) }
        return resolved
    }

    /// The same comparison, for a `URL` the caller already holds — a directory found by a
    /// vault walk, say, or a file a `FileManager` enumeration handed back. The vault root
    /// itself is not contained: `contains` and `url(for:)` answer alike everywhere.
    func contains(_ url: URL) -> Bool {
        isInside(url.standardizedFileURL)
    }

    /// Both sides start from the already-resolved root, so this compares like with like;
    /// the caller has already standardised, which collapses any `..` the path smuggled in
    /// and is what the guard is actually for.
    private func isInside(_ standardized: URL) -> Bool {
        let resolvedRoot = root.path(percentEncoded: false)
        let resolved = standardized.path(percentEncoded: false)

        let rootWithSeparator = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        return resolved.hasPrefix(rootWithSeparator) && resolved != rootWithSeparator
    }
}

extension VaultBoundary {
    enum Violation: Error, CustomStringConvertible, Equatable {
        case outsideVault(String)

        var description: String {
            switch self {
            case .outsideVault(let path): "\(path) is outside the vault"
            }
        }
    }
}
