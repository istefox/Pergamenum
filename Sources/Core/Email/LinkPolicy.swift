import Foundation

// PG-124 / #224: one scheme policy for every surface that turns a string into something
// the system opens.

/// Which URL schemes a link in the vault may hand to the system.
///
/// An email body's `href` reaches a note verbatim, and from there three surfaces could
/// open it - a Pratiche row's rendered markdown, a Workspace link card, an exported
/// page - while `NSWorkspace.open` accepts any scheme it finds a handler for: `file:`
/// runs a local document, a custom scheme wakes whatever app registered it. Each surface
/// asks here rather than keeping its own list, so a fifth surface cannot drift from the
/// other four.
///
/// The set is what the app demonstrably produces or receives, not what might be handy:
/// `http`/`https` for the web, `mailto` for an address in an email body, `message` for
/// the links `MailURL` builds into Mail, and the app's own scheme (SPEC §9). A scheme
/// outside it is refused, and each caller degrades to plain text or to doing nothing -
/// never to a link that opens something unannounced.
///
/// Foundation only: `perg` and `pergamenum-mcp` compile everything under `Sources/Core`.
enum LinkPolicy {
    private static let openableSchemes: Set<String> = [
        "http", "https", "mailto", "message", AppInfo.urlScheme,
    ]

    /// `false` for a URL with no scheme at all: a relative reference has nothing to be
    /// opened by, and resolving it against a guessed base is how a path becomes a file.
    static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return openableSchemes.contains(scheme)
    }

    /// The same decision for a raw string, read by scheme prefix rather than through
    /// `URL(string:)`: `NoteExport`'s own escaping pass runs before this is called (PG-124),
    /// and a payload built to break out of an `href` attribute - a stray space, an
    /// unescaped `<` - can fail `URL(string:)` on the whole string even though the scheme
    /// in front of the first `:` is `https` and entirely legitimate. RFC 3986 §3.1 makes
    /// the scheme unambiguous: everything before the first `:`.
    static func isOpenable(_ string: String) -> Bool {
        guard let colon = string.firstIndex(of: ":") else { return false }
        return openableSchemes.contains(string[string.startIndex..<colon].lowercased())
    }
}
