import Foundation

/// The one apply-plan loop meant to replace six hand-copied ones (ADR-0041 §D4/§D5):
/// `NoteFileOperations.rename`'s own loop, `FolderFileOperations.renameFolder`'s two loops,
/// `BoardFileOperations.renameBoard`'s two loops and `moveBoard`'s one, and the loops in
/// `VaultSession+Files`'s `renameNote`/`moveNote`. Every one of those writes an ordinary note
/// through `writing: { try store.write($0.after, to: $0.path) }` or a `.canvas` document through
/// `writing: { try Data($0.after.utf8).write(to: try store.url(for: $0.path), options: .atomic) }`
/// - `apply` itself must stay ignorant of which, so a caller supplies the writer.
///
/// STUB (ADR-0155 §D1, tester-owns-interface): the body below is a placeholder that ignores
/// `changes` entirely, deliberately left wrong so `VaultPlanApplicationTests`'s positive
/// assertions (three changes rewritten, a thrown middle change still letting the third be
/// attempted, the failure string format) stay red until the coder implements the real loop.
enum VaultPlanApplication {
    struct Outcome: Equatable, Sendable {
        var rewrittenPaths: [String] = []
        var failures: [String] = []
    }

    /// Coder: for each change in order, call `writing(change)`; on success append `change.path`
    /// to `rewrittenPaths`; on throw append `"\(change.path): \(error)"` to `failures` (matching
    /// all six existing copies exactly) and continue to the next change regardless - a thrown
    /// change must never stop the ones after it from being attempted (R-06, Task 7).
    static func apply(
        _ changes: [VaultFileChange],
        writing: (VaultFileChange) throws -> Void
    ) -> Outcome {
        Outcome()
    }
}
