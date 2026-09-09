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
        guard let data = try? Data(contentsOf: url) else { throw ReadError.fileNotFound }
        return try parse(data)
    }

    /// Parses already-loaded `.emlx` bytes: strips the leading byte-count line,
    /// returns the RFC 822 bytes it names and the trailing plist, and reports whether
    /// the RFC 822 part has a body or only headers (R-04).
    static func parse(_ data: Data) throws -> EMLXDocument {
        guard let newline = data.firstIndex(of: 0x0A) else {
            throw ReadError.malformed(reason: "nessuna riga di conteggio byte")
        }
        let countText = String(decoding: data[data.startIndex..<newline], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        guard let count = Int(countText), count >= 0 else {
            throw ReadError.malformed(reason: "riga di conteggio byte non numerica: «\(countText)»")
        }
        let start = data.index(after: newline)
        guard let end = data.index(start, offsetBy: count, limitedBy: data.endIndex) else {
            throw ReadError.malformed(
                reason: "il file promette \(count) byte RFC 822 e ne contiene \(data.distance(from: start, to: data.endIndex))"
            )
        }
        let rfc822 = Data(data[start..<end])
        return EMLXDocument(
            rfc822: rfc822,
            plistData: Data(data[end..<data.endIndex]),
            bodyState: bodyState(ofRFC822: rfc822)
        )
    }

    /// «Body not downloaded» is decided on the RFC 822 bytes alone: Exchange writes the
    /// headers and stops, so the blank line that ends them is either absent or followed
    /// by nothing (SPEC "The `.emlx` container and «body not downloaded»").
    ///
    /// Deliberately not read from the trailing plist: its keys are undocumented, and a
    /// flag this app guessed wrong would silently mark a real message as pending and
    /// keep rewriting it on every sync (ADR §D6 allows exactly that one rewrite).
    private static func bodyState(ofRFC822 rfc822: Data) -> EMLXDocument.BodyState {
        guard let body = headerBodySeparator(in: rfc822) else { return .pending }
        let text = String(decoding: rfc822[body...], as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .pending : .complete
    }

    /// The index of the first body byte, i.e. just past the `CRLF CRLF` (or `LF LF`)
    /// that ends the header block. `nil` when the bytes never reach one.
    static func headerBodySeparator(in rfc822: Data) -> Data.Index? {
        let bytes = Array(rfc822)
        var offset = 0
        while offset < bytes.count {
            if offset + 3 < bytes.count,
               bytes[offset] == 0x0D, bytes[offset + 1] == 0x0A,
               bytes[offset + 2] == 0x0D, bytes[offset + 3] == 0x0A {
                return rfc822.index(rfc822.startIndex, offsetBy: offset + 4)
            }
            if offset + 1 < bytes.count, bytes[offset] == 0x0A, bytes[offset + 1] == 0x0A {
                return rfc822.index(rfc822.startIndex, offsetBy: offset + 2)
            }
            offset += 1
        }
        return nil
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
        // `.../Data/<fan>/Messages/<ROWID>.emlx` → `.../Data/<fan>/Attachments/<ROWID>/<part>`.
        // Two levels up rather than a string substitution of "Messages": a mailbox
        // named `Messages.mbox` appears in the same path and would be rewritten too.
        emlxURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Attachments", directoryHint: .isDirectory)
            .appending(path: "\(rowID)", directoryHint: .isDirectory)
            .appending(path: part, directoryHint: .notDirectory)
    }
}
