import Foundation

/// The pure value type behind `.pergamenum/note-ids.json` (ADR-0059 §D1): a stable id
/// for a note, kept apart from `IndexCache` so deleting the cache, bumping its schema,
/// or opening the vault on another Mac never loses one. The disk half is `NoteIDStore`
/// (`Sources/Vault/NoteIDStore.swift`); this type is Foundation-only, next to
/// `MovedNote`, so it links into `perg` and `pergamenum-mcp` through the `Sources/Core`
/// glob without a `sharedSources` entry of its own (ADR-0059 §D9).
///
/// **Protected-interface proposal** (ADR-0059 "Protected-interface proposal", pending
/// Stefano's approval): this is the shape of every `pergamenum://note?id=` link already
/// pasted into another app. A silent change to its members orphans every id in every
/// vault. The real pin on the on-disk bytes is Acceptance test 8
/// (`Tests/NoteIDRegistryTests.swift`), since `interface-check.sh` sees signatures, not
/// `Codable` keys.
struct NoteIDRegistry: Codable, Equatable, Sendable {
    /// Bumped only if this on-disk shape itself changes. A version `NoteIDStore` does
    /// not recognise reads back as malformed, the same rule `CategoryRegistry` and
    /// `IndexCache` already use for their own format versions.
    static let currentVersion = 1

    var version: Int
    /// Lowercase id -> vault-relative path. Keyed by id because the route looks up in
    /// that direction, and a JSON object's keys make "one id per path" enforceable by
    /// the value type rather than by convention (ADR-0059 §D1).
    var notes: [String: String]

    static let empty = NoteIDRegistry(version: currentVersion, notes: [:])

    /// A fresh, lowercase UUID v4 (ADR-0059 §D1). `VaultSession.mintNoteID(for:)` is the
    /// one production caller: an id is minted when a link needs it, never at indexing
    /// time (§D2).
    static func makeID() -> String {
        UUID().uuidString.lowercased()
    }

    /// The path an id currently names, or nil. Lowercases the id first, so a link pasted
    /// in upper case still resolves (ADR-0059 §D1).
    func path(forID id: String) -> String? {
        notes[id.lowercased()]
    }

    /// The id a path currently has, or nil. A hand-edited file can hold two ids for one
    /// path; the smallest is answered so every call hands out the same one.
    func id(forPath path: String) -> String? {
        let target = Self.trimmed(path)
        guard !target.isEmpty else { return nil }
        return notes.filter { $0.value == target }.keys.min()
    }

    /// Records that `id` now names `path`, dropping whatever id that path held before -
    /// one id per path (ADR-0059 §D1, Acceptance test 3).
    func assigning(_ id: String, to path: String) -> NoteIDRegistry {
        let target = Self.trimmed(path)
        guard !target.isEmpty else { return self }
        var copy = self
        copy.notes = notes.filter { $0.value != target }
        copy.notes[id.lowercased()] = target
        return copy
    }

    /// Carries every entry at or under each move's `old` path onto its `new` path,
    /// folders and notes alike, first dropping any stale entry already sitting at the
    /// destination (ADR-0059 §D4). A folder is carried by its own pair, so an entry with
    /// no file behind it - an evicted note, in no index - moves with it too.
    func relocating(_ moves: [MovedNote]) -> NoteIDRegistry {
        var copy = self
        for move in moves {
            let old = Self.trimmed(move.old)
            let new = Self.trimmed(move.new)
            guard !old.isEmpty, !new.isEmpty, old != new else { continue }
            // An entry at or under the destination is stale: the note that was there left
            // outside the app, and the one arriving brings its own id. One the move itself
            // is about to carry is never counted as stale, whatever the two paths share.
            copy.notes = copy.notes.filter { !Self.covers(new, $0.value) || Self.covers(old, $0.value) }
            copy.notes = copy.notes.mapValues { path in
                guard Self.covers(old, path) else { return path }
                return new + path.dropFirst(old.count)
            }
        }
        return copy
    }

    /// Drops every entry at or under each of `paths` - what a trash forgets
    /// (ADR-0059 §D6). An empty path, the vault root, matches nothing (§D4).
    func removing(_ paths: [String]) -> NoteIDRegistry {
        let targets = paths.map(Self.trimmed).filter { !$0.isEmpty }
        guard !targets.isEmpty else { return self }
        var copy = self
        copy.notes = notes.filter { entry in !targets.contains { Self.covers($0, entry.value) } }
        return copy
    }

    /// Both sides of every comparison are trimmed of `/` (ADR-0059 §D4).
    private static func trimmed(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// `path` is `prefix` itself or lies under it. The `+ "/"` keeps `Progetti` from
    /// matching `Progetti 2/x.md` or `Progetti.md` (ADR-0059 §D4).
    private static func covers(_ prefix: String, _ path: String) -> Bool {
        path == prefix || path.hasPrefix(prefix + "/")
    }
}
