import Foundation

/// The vault's category registry on disk: `.pergamenum/categories.json` (ADR-0047
/// §D2). Copies `StarredStore`'s shape - atomic pretty-printed write, a problem
/// returned rather than thrown - with one deliberate divergence: a file that exists
/// and does not decode is reported and treated as empty for the session, **never**
/// silently replaced by a save. Losing a star is nothing; replacing a hand-edited
/// registry with an empty one would lose the only copy of data that exists nowhere
/// else.
struct CategoryRegistryStore {
    let file: URL

    /// What `load()` found, so `VaultSession+Categories.swift` can refuse every
    /// mutation while the file on disk could not be understood, rather than overwrite
    /// it with whatever the session holds in memory.
    enum LoadedState: Equatable {
        case absent
        case loaded
        case malformed
    }

    init(root: URL) {
        file = root
            .appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
            .appending(path: VaultLayout.categoriesFile, directoryHint: .notDirectory)
    }

    /// Reads the registry and the state it was found in. A missing file is an empty
    /// registry, `.absent`. A file whose bytes will not decode, or whose `version`
    /// this app does not recognise, reads back as empty too, but tagged `.malformed`.
    func load() -> (registry: CategoryRegistry, state: LoadedState) {
        guard let data = try? Data(contentsOf: file) else {
            return (.empty, .absent)
        }
        guard let registry = try? JSONDecoder().decode(CategoryRegistry.self, from: data),
              registry.version == CategoryRegistry.currentVersion
        else {
            return (.empty, .malformed)
        }
        return (registry, .loaded)
    }

    /// Writes the registry atomically, pretty-printed with sorted keys so a hand-kept
    /// vault diffs cleanly in git. The problem is returned rather than thrown for the
    /// reason `StarredStore.save` gives: losing a registry edit to a write failure is
    /// not a reason to fail the gesture that caused it, only to report it.
    @discardableResult
    func save(_ registry: CategoryRegistry) -> String? {
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(registry).write(to: file, options: .atomic)
            return nil
        } catch {
            return "impossibile salvare il registro delle categorie: \(error.localizedDescription)"
        }
    }
}
