import Foundation

// PG-436 (audit 2026-10-31 R-02: SEC-01, SEC-02, S05-10), recorded as the 2026-10-31
// amendment to ADR-0048. An attachment's name comes out of the email verbatim
// (`MIMEDecoder`, RFC 2231 percent-decoding included, so `%2F` is already `/`), and a
// `storePath` comes back out of a note's frontmatter, which any writer of the vault can
// edit. Neither is a path this app may hand to the filesystem as it is.

/// The one way to turn an untrusted name or path into a file URL under a directory the
/// code already treats as legitimate. Foundation only: it compiles into `perg` and
/// `pergamenum-mcp` as well as into the app (ADR-0001 §D1), like the rest of
/// `Sources/Core/Email`.
///
/// Exposed as resolvers that answer a URL or `nil`, never as a check beside an
/// `appending(path:)`: a check a caller can skip is one the next caller skips
/// (ADR-0041, `.claude/rules/vault-writes.md`).
enum MailAttachmentPath {
    /// APFS's own name limit, `getconf NAME_MAX` (255), counted in UTF-8 bytes. A longer
    /// name cannot exist on the volume, so it is refused rather than shortened: a
    /// shortened name would point at a different file.
    static let maximumNameBytes = 255

    /// `name` reduced to one path component, or `nil` when it cannot be one: a NUL
    /// anywhere, nothing left after `lastPathComponent`, `.`, `..`, a `/` that survives
    /// the reduction (`"/"` itself), or more than `maximumNameBytes` UTF-8 bytes.
    ///
    /// The NUL check runs on the raw name, before the reduction: `lastPathComponent`
    /// would otherwise drop the part of the name that carried it.
    static func component(of name: String) -> String? {
        guard !name.unicodeScalars.contains("\u{0}") else { return nil }
        let bare = (name as NSString).lastPathComponent
        guard !bare.isEmpty, bare != ".", bare != "..", !bare.contains("/"),
              bare.utf8.count <= maximumNameBytes
        else { return nil }
        return bare
    }

    /// The file `name` names directly inside `directory`, or `nil` when `name` is not
    /// one safe path component or the result does not lie inside `directory`. The
    /// component check touches no filesystem; the containment check resolves symbolic
    /// links, which reads the directory chain on disk but never opens the file, so a
    /// refused name is never read or copied.
    static func file(named name: String, in directory: URL) -> URL? {
        guard let component = component(of: name) else { return nil }
        return contained(directory.appending(path: component, directoryHint: .notDirectory), in: directory)
    }

    /// `url` standardized and with its symbolic links resolved, when that lies strictly
    /// below `root` resolved the same way; `nil` otherwise. Compared by path components,
    /// never by string prefix, so `/root` never contains `/rootevil`. Both sides go
    /// through the same resolution: `FileManager.temporaryDirectory` is itself under a
    /// symbolic link (`/var` to `/private/var`), and resolving one side alone would
    /// refuse every path beneath it.
    ///
    /// The answer is the resolved URL, never `url` as given: the path checked is the
    /// path the caller opens. Standardizing drops a `..` lexically when what precedes it
    /// does not resolve on disk (`a/link/../x` becomes `a/x` while the kernel would walk
    /// `link` first and land beside its target), so handing back `url` would let the
    /// kernel open a different file than the one checked here.
    static func contained(_ url: URL, in root: URL) -> URL? {
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let components = candidate.pathComponents
        guard components.count > base.count, Array(components.prefix(base.count)) == base else { return nil }
        return candidate
    }
}
