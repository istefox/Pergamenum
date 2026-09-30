import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D8, plan
// docs/plans/contenitore.md, Task 5 - R-09, R-10, R-12.
//
// Foundation only and named in `sharedSources` (`Project.swift`): search (`VaultSession+Search`,
// shared) reads it, so both connectors find a document by its extracted text (§D9). Only the app
// writes it.

/// The text extracted from each Contenitore document, one JSON file per SHA-256 under
/// `VaultState.extractedText`, beside the vault and never inside it.
///
/// Derived state, like the index and the thumbnails: deleting the directory loses nothing that the
/// next extraction does not put back (principle 3). The key is the hash recorded in the scheda, so
/// a file edited in place after import keeps its old extraction (§D8, named and not fixed).
struct ExtractedTextStore: Sendable {
    let directory: URL

    /// The record for `sha256`, or nil when there is none or it cannot be read.
    func read(sha256: String) -> ExtractedText? {
        guard let url = fileURL(for: sha256), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ExtractedText.self, from: data)
    }

    /// Writes `text` as the record for `sha256`, atomically, creating the directory at first use.
    func write(_ text: ExtractedText, sha256: String) throws {
        guard let url = fileURL(for: sha256) else { throw FileOperationError.failed("hash non valido: \(sha256)") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(text).write(to: url, options: .atomic)
    }

    /// Removes every record: «Svuota cache» (§D8). No vault file is touched.
    func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// `<directory>/<sha256>.json`, or nil unless `sha256` is 64 hex digits, so a hand-edited
    /// scheda key can never name a path outside the directory.
    private func fileURL(for sha256: String) -> URL? {
        let key = sha256.lowercased()
        guard key.count == 64, key.allSatisfy(\.isHexDigit) else { return nil }
        return directory.appending(path: "\(key).json", directoryHint: .notDirectory)
    }
}
