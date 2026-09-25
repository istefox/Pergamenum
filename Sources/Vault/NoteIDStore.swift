import Foundation

/// The vault's note-id registry on disk: `.pergamenum/note-ids.json` (ADR-0059 §D1).
/// In the shape of `CategoryRegistryStore`, with one further state that store does not
/// need: `.evicted`, for the iCloud placeholder `VaultScanner.evictedNoteName` already
/// recognises for notes. A registry that is `malformed` or `evicted` is never written
/// over (ADR-0059 §D3) - losing a hand-edited or not-yet-downloaded registry would lose
/// every id in the vault, which nothing else remembers.
struct NoteIDStore {
    let file: URL

    /// What `load()` found, so `VaultSession+NoteIDs.swift` can refuse every mutation
    /// while the file on disk could not be understood or is not here yet, rather than
    /// overwrite it with whatever a door computed in memory.
    enum LoadedState: Equatable {
        case absent
        case loaded
        case malformed
        case evicted
    }

    init(root: URL) {
        file = root
            .appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
            .appending(path: VaultLayout.noteIDsFile, directoryHint: .notDirectory)
    }

    /// The iCloud placeholder that stands in for the registry while its bytes are not
    /// downloaded: `.note-ids.json.icloud`, beside where the file would be. Built here
    /// rather than through `VaultScanner.evictedNoteName`, which answers `.md` names only.
    var placeholder: URL {
        file.deletingLastPathComponent()
            .appending(path: ".\(VaultLayout.noteIDsFile).icloud", directoryHint: .notDirectory)
    }

    /// Reads the registry and the state it was found in (ADR-0059 §D3).
    /// `CategoryRegistryStore.load()`'s shape, widened by `.evicted`:
    ///
    /// - no file and no placeholder is an empty registry, `.absent`, which a door may
    ///   create;
    /// - no file but a placeholder is `.evicted`;
    /// - a file that cannot be read, does not decode, or carries a version this app does
    ///   not recognise is `.malformed`. A file that exists and cannot be read is never
    ///   taken for an absent one, or the next save would replace it.
    func load() -> (registry: NoteIDRegistry, state: LoadedState) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: file.path(percentEncoded: false)) else {
            let evicted = fileManager.fileExists(atPath: placeholder.path(percentEncoded: false))
            return (.empty, evicted ? .evicted : .absent)
        }
        guard let data = try? Data(contentsOf: file),
              let registry = try? JSONDecoder().decode(NoteIDRegistry.self, from: data),
              registry.version == NoteIDRegistry.currentVersion
        else {
            return (.empty, .malformed)
        }
        return (registry, .loaded)
    }

    /// Writes the registry atomically, pretty-printed with sorted keys, the same encoder
    /// settings as `CategoryRegistryStore.save` (ADR-0059 §D1: "a vault kept in git then
    /// diffs cleanly"). The problem is returned rather than thrown, as that store does;
    /// `VaultSession.mintNoteID(for:)` is what refuses to hand out an id whose save
    /// failed (§D2).
    @discardableResult
    func save(_ registry: NoteIDRegistry) -> String? {
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(registry).write(to: file, options: .atomic)
            return nil
        } catch {
            return "impossibile salvare il registro degli id delle note (\(VaultLayout.noteIDsFile)): "
                + error.localizedDescription
        }
    }
}
