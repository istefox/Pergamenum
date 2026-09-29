import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D4 steps 6 and 8,
// plan docs/plans/contenitore.md, Task 3.
//
// App-only on purpose (§D14): not in `sharedSources`, so neither connector can ingest. The
// connectors reach Contenitore only through notes.

extension VaultSession {
    /// Moves a file from outside the vault to `relativePath` inside it: the ingest door.
    ///
    /// Not `restoreFromOutside`, whose refusal of a missing folder is ADR-0068 §D2's deliberate
    /// guard: an import has to create `<root>/YYYY/`. The path resolves through `VaultBoundary`;
    /// an existing destination is refused and nothing is overwritten. The move runs off the main
    /// actor (`FileManager.moveItem` copies and removes across volumes), derives no index record,
    /// is not journalled and announces nothing (ADR-0067 §D8: a binary is out of the editor's
    /// reach). A rehearsal stops after the checks.
    func adoptFromOutside(_ source: URL, to relativePath: String) async throws {
        let destination = try store.url(for: relativePath)
        guard !exists(relativePath) else { throw FileOperationError.alreadyExists(relativePath) }
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw FileOperationError.missing(source.path(percentEncoded: false))
        }
        guard !isDryRun else { return }
        try await Self.moveOutsideTheMainActor(from: source, to: destination)
    }

    /// Moves the file at `relativePath` back out of the vault to `destination`: the ingest
    /// rollback (§D4 step 8), so a half-done import leaves no orphan in the vault. Refuses a
    /// destination that is taken rather than overwrite what the person put there since.
    func returnToOutside(_ relativePath: String, to destination: URL) async throws {
        let source = try store.url(for: relativePath)
        guard exists(relativePath) else { throw FileOperationError.missing(relativePath) }
        guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
            throw FileOperationError.alreadyExists(destination.path(percentEncoded: false))
        }
        guard !isDryRun else { return }
        try await Self.moveOutsideTheMainActor(from: source, to: destination)
    }

    /// One `moveItem`, its destination's folder created first, on a detached task at utility
    /// priority so a cross-volume copy of a large scan never holds the main actor.
    private nonisolated static func moveOutsideTheMainActor(from source: URL, to destination: URL) async throws {
        do {
            try await Task.detached(priority: .utility) {
                let fileManager = FileManager()
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: source, to: destination)
            }.value
        } catch {
            throw FileOperationError.failed("spostamento: \(error.localizedDescription)")
        }
    }
}
