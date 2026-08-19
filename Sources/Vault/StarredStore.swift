import Foundation

/// The notes this vault keeps to hand (ADR-0012 D6).
///
/// `.pergamenum/starred.json`, a set of relative paths, and nothing else. **In the vault and
/// not in `UserDefaults`, which is the opposite call from the open tabs (D10), and the two are
/// different questions rather than an inconsistency:** which notes matter is a fact about the
/// vault and should follow it through iCloud Drive (principle 6); which notes happen to be open
/// on this machine is a fact about this machine.
///
/// **Not frontmatter.** SPEC §4.3 closes that schema to `date`, `tags`, `related`, `aliases`,
/// and a note is not a different note because this vault finds it useful. Starring is app state
/// stored beside the notes, so losing the file loses the stars and nothing else - the same
/// guarantee everything else under `.pergamenum/` carries.
///
/// Paths and not hashes, so the file is readable by eye and by anything else; a rename moves
/// the star as part of the rename, in `VaultSession+Files`, because a path that no longer
/// exists is a star hanging off nothing.
struct StarredStore {
    let file: URL

    init(root: URL) {
        file = root
            .appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
            .appending(path: VaultLayout.starredFile, directoryHint: .notDirectory)
    }

    /// What is on disk, or nothing at all.
    ///
    /// A file that will not decode reads as empty rather than as a failure: the stars are a
    /// convenience, and refusing to open a vault over them would be the tail wagging the dog.
    /// The same defensiveness `WriteJournal` keeps for a line it cannot parse.
    func load() -> Set<String> {
        guard let data = try? Data(contentsOf: file),
              let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(paths)
    }

    /// Writes the set, sorted, and returns what went wrong if anything did.
    ///
    /// Sorted because the file is meant to be read by a person and diffed by git if the vault
    /// is in one; a `Set` written in hash order would show a change every time. The problem is
    /// returned rather than thrown for the reason `NoteHistory.record` swallows its own: losing
    /// a star is not a reason to fail the gesture that caused it.
    @discardableResult
    func save(_ paths: Set<String>) -> String? {
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            try encoder.encode(paths.sorted()).write(to: file, options: .atomic)
            return nil
        } catch {
            return "impossibile salvare le note preferite: \(error.localizedDescription)"
        }
    }
}
