import Foundation

/// A record of every write a connector made, and the text that was there before it
/// (ADR-0007 §D6).
///
/// Beside the vault rather than inside it, with the rest of this machine's derived
/// state (ADR-0017): losing it loses nothing the vault does not still hold, so it was
/// never a fact about the vault to begin with, only about what a connector did on this
/// machine. It is a safety net for writes the user did not type themselves, not a
/// version history - the vault's own history is git, or Time Machine, or the fact that
/// these are plain files. An `undo` offered on a second Mac for a write made on the
/// first would pass its own hash guard and still be the wrong offer.
///
/// One entry per file written, newest last, one JSON object per line: appending to a
/// JSONL file cannot corrupt what is already in it, which a re-encoded JSON array can.
struct WriteJournal {
    let directory: URL

    /// What happened to one file (ADR-0016 §D2).
    ///
    /// «The text before» describes a replacement and describes neither a file that moved nor
    /// one that is gone, which is the whole reason the journal could not record a rename. A
    /// rename is **not** a fourth case: it is a move plus a set of replacements sharing one
    /// operation id, because a kind says what happened to a file and an operation says what
    /// the person did.
    enum Kind: String, Codable, Sendable {
        /// The file's text was replaced. What the journal has always recorded.
        case textReplacement
        /// The file went from one path to another and its bytes did not change.
        case move
        /// The file went to the Finder's trash.
        case removal
    }

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

        // MARK: The gesture (ADR-0016)
        //
        // All three are optional, and that is what makes «no migration is written» true rather
        // than aspirational: Swift's synthesised `Codable` does not default a missing key, so a
        // non-optional field here would fail to decode every line already on disk. An entry
        // without them describes a single write that was its own whole gesture, which is exactly
        // what every entry written before ADR-0016 was.

        /// The gesture this write belongs to, when it belongs to one.
        ///
        /// `undo` given this id reverses every entry carrying it, newest first. Nil for a write
        /// that stands alone, where the entry's own id is the unit.
        var operation: String?
        /// What happened to the file. Nil means `.textReplacement`, which is what `kind` reads.
        var storedKind: Kind?
        /// Where a moved file came from. Nil for anything that did not move.
        var pathBefore: String?

        var kind: Kind { storedKind ?? .textReplacement }

        /// `storedKind` is the stored spelling and `kind` is the read one; the key on disk stays
        /// `kind`, so a line written by this version reads as `"kind": "move"` rather than as
        /// something named after an implementation detail.
        enum CodingKeys: String, CodingKey {
            case id, timestamp, path, hashBefore, hashAfter, textBefore, command
            case operation
            case storedKind = "kind"
            case pathBefore
        }

        /// Written out rather than synthesised so the three ADR-0016 fields carry defaults: the
        /// synthesised memberwise initialiser would demand them at every existing call site,
        /// and `= nil` on the properties themselves is what SwiftLint's
        /// `redundant_optional_initialization` refuses.
        init(
            id: String, timestamp: Date, path: String,
            hashBefore: String?, hashAfter: String, textBefore: String?, command: String,
            operation: String? = nil, kind: Kind? = nil, pathBefore: String? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.path = path
            self.hashBefore = hashBefore
            self.hashAfter = hashAfter
            self.textBefore = textBefore
            self.command = command
            self.operation = operation
            self.storedKind = kind
            self.pathBefore = pathBefore
        }
    }

    init(directory: URL) {
        self.directory = directory
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

    /// Every entry of one gesture, oldest first (ADR-0016 §D1).
    ///
    /// Oldest first because that is the order they happened in, and `undo` walks it backwards:
    /// a rename moves the file and then rewrites the links, so reversing it has to put the texts
    /// back before it moves the file back.
    func entries(operation: String) -> [Entry] {
        entries().filter { $0.operation == operation }
    }

    /// Shaped exactly like `NoteHistory.idDateFormatter`, which reads this format back:
    /// configured once at first use and never mutated afterwards, so the instance is
    /// shared safely rather than rebuilt on every journalled write.
    private static let idFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = .current
        return formatter
    }()

    static func makeID(at date: Date) -> String {
        let suffix = String(UUID().uuidString.prefix(4)).lowercased()
        return "\(idFormatter.string(from: date))-\(suffix)"
    }
}
