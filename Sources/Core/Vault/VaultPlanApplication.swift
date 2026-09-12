import Foundation

/// The one apply-plan loop meant to replace six hand-copied ones (ADR-0041 §D4/§D5):
/// `NoteFileOperations.rename`'s own loop, `FolderFileOperations.renameFolder`'s two loops,
/// `BoardFileOperations.renameBoard`'s two loops and `moveBoard`'s one, and the loops in
/// `VaultSession+Files`'s `renameNote`/`moveNote`. Every one of those writes an ordinary note
/// through `writing: { try store.write($0.after, to: $0.path) }` or a `.canvas` document through
/// `writing: { try Data($0.after.utf8).write(to: try store.url(for: $0.path), options: .atomic) }`
/// - `apply` itself must stay ignorant of which, so a caller supplies the writer.
enum VaultPlanApplication {
    struct Outcome: Equatable, Sendable {
        var rewrittenPaths: [String] = []
        var failures: [String] = []
    }

    /// Each change in order: on success its path joins `rewrittenPaths`, on a throw the
    /// interpolation `"\(change.path): \(error)"` joins `failures` - the format all six copies
    /// this replaces already wrote, so no caller's assertion changes when it switches over.
    ///
    /// A throw never stops the loop. The changes are independent files and a rename that gave up
    /// halfway would leave the vault half-rewritten with nothing said about the rest; every one of
    /// the six originals continued too, and R-06 (Task 7) leans on it.
    static func apply(
        _ changes: [VaultFileChange],
        writing: (VaultFileChange) throws -> Void
    ) -> Outcome {
        var outcome = Outcome()
        for change in changes {
            do {
                try writing(change)
                outcome.rewrittenPaths.append(change.path)
            } catch {
                outcome.failures.append("\(change.path): \(error)")
            }
        }
        return outcome
    }
}
