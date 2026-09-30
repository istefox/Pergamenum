import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D2, plan
// docs/plans/contenitore.md, Task 2. `import Foundation` only: named in `sharedSources` by
// hand, since `Sources/Index/**` is not a glob.

extension IndexSnapshot {
    /// Every scheda under `root` (a vault-relative folder), in path order.
    ///
    /// "Under the root" is evaluated here, at read time, and never stored on the record: the
    /// root is a setting, and changing it must need no rescan (§D2). A note is a scheda when it
    /// carries `pergamenum-contenitore: 1` (`NoteRecord.contenitore`) and sits below the root.
    func schede(underRoot root: String) -> [NoteRecord] {
        let prefix = Self.contenitorePrefix(root)
        guard !prefix.isEmpty else { return [] }
        return notes.values
            .filter { $0.contenitore != nil && $0.relativePath.hasPrefix(prefix) }
            .sorted { $0.relativePath < $1.relativePath }
    }

    /// The scheda under `root` whose recorded file hash is `sha256`, the duplicate check of
    /// ADR-0071 §D4 step 4. The first in path order when, unusually, more than one matches.
    func scheda(withSHA256 sha256: String, underRoot root: String) -> NoteRecord? {
        let wanted = sha256.lowercased()
        return schede(underRoot: root).first { $0.contenitore?.sha256 == wanted }
    }

    /// `root/`, slashes trimmed, or empty for a root that names no folder.
    private static func contenitorePrefix(_ root: String) -> String {
        let trimmed = root.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespaces))
        return trimmed.isEmpty ? "" : trimmed + "/"
    }
}
