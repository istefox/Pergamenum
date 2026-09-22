import Foundation

/// The one apply-plan loop meant to replace six hand-copied ones (ADR-0041 §D4/§D5):
/// `NoteFileOperations.rename`'s own loop, `FolderFileOperations.renameFolder`'s two loops,
/// `BoardFileOperations.renameBoard`'s two loops and `moveBoard`'s one, and the loops in
/// `VaultSession+Files`'s `renameNote`/`moveNote`. Every one of those writes an ordinary note
/// through `writing: { try store.write($0.after, to: $0.path) }` or, since ADR-0054 §D6, a
/// `.canvas` document through the one guarded repoint door, `writing: canvas.writeRepoint` -
/// `apply` itself must stay ignorant of which, so a caller supplies the writer.
enum VaultPlanApplication {
    struct Outcome: Equatable, Sendable {
        var rewrittenPaths: [String] = []
        var failures: [String] = []
        /// Paths whose bytes moved on since the change's `before` was read, so nothing was
        /// written - a `VaultWriteRefusal` caught and classified apart from `failures`
        /// (ADR-0046 §D4). Declared after `failures` so every existing memberwise call stays
        /// valid. Of the eight synchronous-overload callers, the three still writing a plain
        /// `store.write` note (`FolderFileOperations.renameFolder`, `BoardFileOperations
        /// .renameBoard`, `NoteFileOperations.rename`'s own note half) can never populate
        /// this; the five now writing a `.canvas` through `canvas.writeRepoint` (ADR-0054
        /// §D6) can.
        var refusals: [String] = []
    }

    /// Each change in order: on success its path joins `rewrittenPaths`, a caught
    /// `VaultWriteRefusal` joins `refusals` with the bare path, and every other throw joins
    /// `failures` with the interpolation `"\(change.path): \(error)"` - the format all six
    /// copies this replaces already wrote, so no caller's assertion changes when it switches
    /// over.
    ///
    /// A throw never stops the loop, in either branch (ADR-0046 §D3). The changes are
    /// independent files and a rename that gave up halfway would leave the vault
    /// half-rewritten with nothing said about the rest; every one of the six originals
    /// continued too, and R-06 (Task 7) leans on it.
    static func apply(
        _ changes: [VaultFileChange],
        writing: (VaultFileChange) throws -> Void
    ) -> Outcome {
        var outcome = Outcome()
        for change in changes {
            do {
                try writing(change)
                outcome.rewrittenPaths.append(change.path)
            } catch is VaultWriteRefusal {
                outcome.refusals.append(change.path)
            } catch {
                outcome.failures.append("\(change.path): \(error)")
            }
        }
        return outcome
    }

    /// The same loop for a writer that has to be awaited (ADR-0043 §D2): `VaultSession`'s
    /// writers go through the one `async` write door, and a caller cannot hand an `await`
    /// to the synchronous overload above.
    ///
    /// A second declaration rather than a rewrite of the first, resolved by whether the
    /// call site says `await` - the mechanism ADR-0041 §D9 already used for `write`. Unlike
    /// that case this is **not** a second door in §D1's sense: `apply` owns no state, stamps
    /// no clock and touches no index. It is a `for` loop that collects failures, and the
    /// synchronous overload keeps the eight `store.write`/raw-`Data.write` call sites in the
    /// three file-operations types, which are not vault-session writers.
    ///
    /// `isolation: isolated (any Actor)? = #isolation` is what makes it compile under strict
    /// concurrency: without it the writer closure - which captures a `@MainActor VaultSession`
    /// - would be *sent* from the caller's actor into a non-isolated function, which Swift 6
    /// refuses by name («sending value of non-Sendable type ... risks causing data races»).
    /// Inheriting the caller's isolation means the loop runs where the caller already is, so
    /// nothing crosses a boundary and the writes keep their existing order.
    static func apply(
        _ changes: [VaultFileChange],
        isolation: isolated (any Actor)? = #isolation,
        writing: (VaultFileChange) async throws -> Void
    ) async -> Outcome {
        var outcome = Outcome()
        for change in changes {
            do {
                try await writing(change)
                outcome.rewrittenPaths.append(change.path)
            } catch is VaultWriteRefusal {
                outcome.refusals.append(change.path)
            } catch {
                outcome.failures.append("\(change.path): \(error)")
            }
        }
        return outcome
    }
}
