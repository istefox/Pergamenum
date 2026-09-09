import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - R-04.

/// One `.emlx`/`.partial.emlx` container, read: the leading byte-count line stripped,
/// the RFC 822 bytes it names, and the trailing plist Mail appends after them.
struct EMLXDocument: Equatable, Sendable {
    /// Whether the RFC 822 part actually carries a body, or only headers - an
    /// Exchange message whose body has not been downloaded yet (SPEC "The `.emlx`
    /// container and «body not downloaded»").
    enum BodyState: Equatable, Sendable {
        case complete
        case pending
    }

    /// The RFC 822 message: headers, blank line, body - when `bodyState == .complete`.
    /// When `.pending`, this still carries whatever headers Mail has (subject, from,
    /// date, `Message-ID`), just no body after them.
    var rfc822: Data
    /// The plist Mail appends after the RFC 822 bytes, undecoded: a caller that needs
    /// one specific key (e.g. `flags`) parses it itself with `PropertyListSerialization`
    /// rather than this type committing to a schema Mail does not document.
    var plistData: Data
    var bodyState: BodyState
}

enum EMLXReader {
    enum ReadError: Error, Equatable, Sendable {
        /// Neither `<ROWID>.emlx` nor `<ROWID>.partial.emlx` exists at the given URL.
        case fileNotFound
        /// The byte-count line could not be read as an integer, or the file is
        /// shorter than that count promises - a torn or non-`.emlx` file.
        case malformed(reason: String)
    }

    /// Reads one `.emlx`/`.partial.emlx` file from disk.
    ///
    /// Never reads `~/Library/Mail` in a test: every unit test calls `parse(_:)`
    /// directly on synthetic bytes built by `Tests/EmailFixtureCorpus.swift`, the same
    /// rule `Tests/MailStoreFixture.swift` follows for the index (ADR §D7).
    static func read(contentsOf url: URL) throws -> EMLXDocument {
        // Coder-owned: `Data(contentsOf:)` then `parse(_:)`. Stubbed to throw, never to
        // fabricate a document, so a caller cannot mistake "not implemented yet" for
        // "the file said so".
        throw ReadError.fileNotFound
    }

    /// Parses already-loaded `.emlx` bytes: strips the leading byte-count line,
    /// returns the RFC 822 bytes it names and the trailing plist, and reports whether
    /// the RFC 822 part has a body or only headers (R-04).
    static func parse(_ data: Data) throws -> EMLXDocument {
        // Coder-owned (ADR §D4 follow-up: the container is `"<N>\n" + N bytes of RFC
        // 822 + trailing plist`). Stubbed to throw so every positive assertion in
        // `Tests/EMLXReaderTests.swift` starts red.
        throw ReadError.malformed(reason: "EMLXReader.parse is not implemented yet")
    }

    /// The sibling `Attachments/<ROWID>/<part>/` directory Mail writes extracted
    /// attachment parts into, one level above the `Messages/` folder holding the
    /// `.emlx` itself (SPEC "Components": "Locates extracted attachments in the
    /// sibling `Attachments/` directory").
    ///
    /// `emlxURL` is shaped
    /// `.../Data/<fan>/Messages/<ROWID>.emlx` (`MailStoreReader.emlxPath(forRow:)`'s own
    /// output, ADR §D4); the sibling directory replaces `Messages` with `Attachments`
    /// at the same `Data/<fan>/` level and appends the ROWID and the part number.
    static func attachmentsDirectory(forMessageAt emlxURL: URL, rowID: Int, part: String) -> URL {
        // Deliberately wrong (returns the input unchanged) so the location test is red
        // until the coder implements the sibling-directory computation.
        emlxURL
    }
}
