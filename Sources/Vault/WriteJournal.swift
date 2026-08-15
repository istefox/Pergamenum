import Foundation

/// A record of every write a connector made, and the text that was there before it
/// (ADR-0007 §D6).
///
/// Under `.pergamenum/`, with the rest of the disposable state: losing it loses nothing
/// the vault does not still hold. It is a safety net for writes the user did not type
/// themselves, not a version history - the vault's own history is git, or Time Machine,
/// or the fact that these are plain files.
///
/// One entry per file written, newest last, one JSON object per line: appending to a
/// JSONL file cannot corrupt what is already in it, which a re-encoded JSON array can.
struct WriteJournal {
    let directory: URL

    /// What one write replaced.
    struct Entry: Codable, Equatable, Sendable {
        /// Short, sortable and unique enough for a person to type: the timestamp to the
        /// millisecond plus four random characters.
        let id: String
        let timestamp: Date
        let path: String
        /// SHA-256 of the file before, or nil when it did not exist.
        let hashBefore: String?
        let hashAfter: String
        /// The whole previous text, which is what makes `undo` possible. Nil for a file
        /// that was created, where undoing means deleting.
        let textBefore: String?
        /// The command that did it, for reading the log later.
        let command: String
    }

    init(root: URL) {
        directory = root
            .appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
            .appending(path: "ai-journal", directoryHint: .isDirectory)
    }

    private var file: URL { directory.appending(path: "journal.jsonl") }

    /// Appends an entry. Failures are returned rather than thrown: a journal that
    /// cannot be written must not stop a write the user asked for, but they have to be
    /// told the net is not there.
    @discardableResult
    func record(_ entry: Entry) -> String? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var line = try encoder.encode(entry)
            line.append(contentsOf: Data("\n".utf8))

            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: file, options: .atomic)
            }
            return nil
        } catch {
            return "journal: \(error.localizedDescription)"
        }
    }

    /// Every entry, oldest first. A line that will not decode is skipped rather than
    /// failing the read: one bad line must not hide the rest of the net.
    func entries() -> [Entry] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
    }

    func entry(id: String) -> Entry? {
        entries().last { $0.id == id }
    }

    static func makeID(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = .current
        let suffix = String(UUID().uuidString.prefix(4)).lowercased()
        return "\(formatter.string(from: date))-\(suffix)"
    }
}
