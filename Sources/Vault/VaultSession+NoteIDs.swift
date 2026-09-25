import Foundation

/// The stable note-id registry's lifecycle (ADR-0059 §D2/§D3/§D5): mint one on demand,
/// and keep every entry in step with a rename, a move or a trash.
///
/// **No copy in memory** (§D3). `VaultSession` holds no registry - `noteIDStore` below
/// is a computed property, built fresh over `root` on every call, so `VaultSession.swift`
/// itself is not touched by this chain at all. Every door here does the same four
/// things: `load()`, apply one pure change, compare the result with what was loaded, and
/// `save` only if they differ. A change that leaves the registry as it was writes
/// nothing, so a vault where nobody ever copied a link never gains the file.
///
/// **A registry that is `malformed` or `evicted` is never written** (§D3): a changing
/// door refuses and records one problem naming `VaultLayout.noteIDsFile`, and the read
/// door answers `.unreadable`.
extension VaultSession {
    /// The three things a lookup by id can answer (ADR-0059 §D7): a resolvable path, an
    /// id nobody has minted, or a registry that could not be read at all. Each gets its
    /// own sentence at the route.
    enum NoteIDLookup: Equatable, Sendable {
        case found(String)
        case unknown
        case unreadable
    }

    /// Where the registry is read from and written back to. Rebuilt on every access
    /// rather than held: three processes (the app, `perg`, `pergamenum-mcp`) can each
    /// rename a note, and a session saving back an old copy over another's change would
    /// be exactly the lost update ADR-0052 describes (ADR-0059 §D3).
    var noteIDStore: NoteIDStore {
        NoteIDStore(root: root)
    }

    /// Answers a `pergamenum://note?id=` route (ADR-0059 §D7). The path is not checked
    /// here: the route checks it through `VaultBoundary`, since the file is hand-editable
    /// and its paths are untrusted input.
    func lookUpNote(id: String) -> NoteIDLookup {
        let (registry, state) = noteIDStore.load()
        switch state {
        case .malformed, .evicted:
            return .unreadable
        case .absent, .loaded:
            return registry.path(forID: id).map(NoteIDLookup.found) ?? .unknown
        }
    }

    /// Returns `relativePath`'s existing id, or mints and saves a new one - never both
    /// (ADR-0059 §D2). Returns nil when the path is not `.md`, is outside the vault, has
    /// no file behind it, the registry cannot be read, or the session is a dry run with
    /// no id to return yet.
    ///
    /// A new id is returned only once it is on disk: an id handed out but never stored
    /// would be a link that can never resolve. An id is never regenerated for a path that
    /// has one, so every copy of a note's link hands out the same id.
    func mintNoteID(for relativePath: String) -> String? {
        guard (relativePath as NSString).pathExtension.lowercased() == "md",
              let url = try? store.url(for: relativePath),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return nil }

        let (registry, state) = noteIDStore.load()
        guard state == .absent || state == .loaded else {
            recordProblem(Self.unreadableRegistryProblem(state, paths: [relativePath]))
            return nil
        }
        if let existing = registry.id(forPath: relativePath) { return existing }
        guard !isDryRun else { return nil }

        let id = NoteIDRegistry.makeID()
        if let problem = noteIDStore.save(registry.assigning(id, to: relativePath)) {
            recordProblem(problem)
            return nil
        }
        return id
    }

    /// Carries every id at or under each move's `old` path onto its `new` path
    /// (ADR-0059 §D4/§D5) - the door `moveFile` and the folder verbs call after their own
    /// disk operation has succeeded. Nothing under `isDryRun`: a rehearsal never touches
    /// the registry.
    func relocateNoteIDs(_ moves: [MovedNote]) {
        guard !moves.isEmpty else { return }
        changeNoteIDs(paths: moves.map(\.old)) { $0.relocating(moves) }
    }

    /// Forgets every id at or under each of `paths` (ADR-0059 §D6) - what `trashFile`
    /// and the folder trash door call so a later note created at the same path never
    /// inherits an old link. Nothing under `isDryRun`.
    func forgetNoteIDs(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        changeNoteIDs(paths: paths) { $0.removing(paths) }
    }

    /// The id `relativePath` has now, without ever minting one; nil when it has none or the
    /// registry cannot be read. What `trashFile` records before it forgets.
    func existingNoteID(for relativePath: String) -> String? {
        let (registry, state) = noteIDStore.load()
        guard state == .absent || state == .loaded else { return nil }
        return registry.id(forPath: relativePath)
    }

    /// Puts back the id a trash forgot, once an undo has written the note back at the same
    /// path (ADR-0059 §D6), so a link copied before the trash resolves again.
    func restoreNoteID(_ id: String, to relativePath: String) {
        changeNoteIDs(paths: [relativePath]) { $0.assigning(id, to: relativePath) }
    }

    /// The four steps every changing door shares (§D3): read the file now rather than
    /// trust a copy, apply one pure change, and save only when it changed something.
    /// `paths` only names what the refusal sentence is about.
    private func changeNoteIDs(paths: [String], _ change: (NoteIDRegistry) -> NoteIDRegistry) {
        guard !isDryRun else { return }
        let (registry, state) = noteIDStore.load()
        guard state == .absent || state == .loaded else {
            recordProblem(Self.unreadableRegistryProblem(state, paths: paths))
            return
        }
        let changed = change(registry)
        guard changed != registry else { return }
        if let problem = noteIDStore.save(changed) {
            recordProblem(problem)
        }
    }

    /// One sentence for a registry the doors refuse to touch, naming the file and what
    /// the refusal is about (ADR-0059 §D3).
    private static func unreadableRegistryProblem(_ state: NoteIDStore.LoadedState, paths: [String]) -> String {
        let reason = state == .evicted ? "non è ancora scaricato da iCloud" : "non è leggibile"
        let subject = paths.map { "«\($0)»" }.joined(separator: ", ")
        return "il registro degli id delle note (\(VaultLayout.noteIDsFile)) \(reason): "
            + "nessun id è stato scritto per \(subject)"
    }
}
