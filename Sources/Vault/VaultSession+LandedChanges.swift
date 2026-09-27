import Foundation

/// ADR-0067: one door onto the editor after a landed change.
///
/// A write this app makes itself is self-hashed, so `VaultSession.reconcile` drops it when
/// FSEvents reports it back (ADR-0043 §D3.3), and the caller's catch-up used to be a tab's
/// only chance to hear of it - performed by hand at eighteen call sites (ADR-0058), which is
/// exactly the shape `CLAUDE.md`'s working agreement warns about: a step a caller can forget.
/// This file is the replacement: the session announces every change it lands, to the one
/// subscriber `VaultController` installs on the session it currently holds (§D4).
///
/// The doors that call `announce(_:)`, each only once its change is real (index applied,
/// self-write bookkeeping reconciled): `write` (`VaultSession.swift`), `moveFile` and
/// `trashFile` (`VaultSession+Journal.swift`), and the three app-only folder doors -
/// `renameFolder`, `trashFolder` (`VaultSession+Folders.swift`) and `moveItems`' folder case
/// (`VaultSession+Move.swift`), plus `restoreFromOutside` below (ADR-0068 §D3). A rehearsal,
/// a refusal or a failed disk operation returns or
/// throws before reaching it. The `.canvas` door, `writeFile`, never announces (§D1).
extension VaultSession {
    /// What the session just made real on disk or in the vault's shape, handed to
    /// `landedChangeSubscriber` (§D1).
    ///
    /// `Equatable, Sendable` for free: `WriteResult` already is (`VaultSession.swift`), and a
    /// `String`/`UUID?` pair costs nothing extra.
    enum LandedChange: Equatable, Sendable {
        /// A text write landed, through `write(_:to:expecting:expectingAbsent:
        /// requiringExistingFolder:origin:)`. `origin` is the writer tab's id, or `nil` for
        /// every writer that is not a tab's own save (§D2).
        case written(WriteResult, origin: UUID?)
        /// A file moved, through `moveFile(from:to:)` or one of the three app-only folder
        /// doors that carry a note along with its folder.
        case moved(from: String, to: String)
        /// A file was trashed, through `trashFile(at:)` or one of the three app-only folder
        /// doors that trash a note along with its folder.
        case trashed(String)

        /// The paths the change touches: the written path, both ends of a move, the trashed
        /// path - the ones `announce(_:)` advances a generation for (§D6).
        var paths: [String] {
            switch self {
            case .written(let result, _): [result.path]
            case .moved(let from, let to): [from, to]
            case .trashed(let path): [path]
            }
        }
    }

    /// Tells `landedChangeSubscriber`, when one is installed, that `change` just landed.
    ///
    /// Bumps `landedGenerations` for every path `change` touches first (§D6), then calls the
    /// subscriber synchronously, before the door that called this returns to its own caller
    /// (§D1): no keystroke can land between the change and the editor's catch-up. In `perg`
    /// and `pergamenum-mcp` no subscriber is ever installed, so only the generation moves.
    func announce(_ change: LandedChange) {
        advanceLandedGenerations(change.paths)
        landedChangeSubscriber?(change)
    }

    /// ADR-0067 §D6: how many times a landed change has touched `path`, for the one reader
    /// that needs it - the Pratiche inspector, keying its reload on the selected
    /// `pratica.md`'s own generation. Not an ordering authority: `VaultDisk`'s per-path
    /// sequence (ADR-0043 §D1) stays that. 0 for a path never touched.
    func landedGeneration(at path: String) -> UInt64 {
        landedGenerations[path] ?? 0
    }

    /// Restores a file from outside the vault to `relativePath` (ADR-0068 §D3) - the
    /// «Escludi» undo's counterpart to `trashFile(forgettingNoteID: false)`.
    ///
    /// Refuses a destination the boundary rejects, one that is taken, and one whose folder is
    /// missing - no directory is created (PG-168). A rehearsal stops there. The source's bytes
    /// are hashed on the main actor before the hop and recorded as a provisional self-write
    /// (ADR-0041 §D10), so a watcher racing the restore finds this session's own record of it;
    /// `VaultDisk.restoreFile` then moves, reads once and stamps the mutation.
    ///
    /// Not journalled, like the Pratiche trash it undoes, and the note-id registry is left
    /// alone: that trash never forgot the id (§D3, ADR-0059 §D6).
    func restoreFromOutside(_ source: URL, to relativePath: String) async throws {
        let destination = try store.url(for: relativePath)
        guard !exists(relativePath) else { throw FileOperationError.alreadyExists(relativePath) }
        var isDirectory: ObjCBool = false
        let parentExists = FileManager.default.fileExists(
            atPath: destination.deletingLastPathComponent().path(percentEncoded: false), isDirectory: &isDirectory
        )
        guard parentExists, isDirectory.boolValue else {
            throw WriteRefusal.folderVanished((relativePath as NSString).deletingLastPathComponent)
        }
        guard !isDryRun else { return }

        let data: Data
        do {
            data = try Data(contentsOf: source)
        } catch {
            throw FileOperationError.failed("ripristino: \(error.localizedDescription)")
        }
        let provisional = reserveProvisionalSequence()
        selfWrittenHashes[relativePath, default: []].append((sequence: provisional, hash: NoteStore.hash(data)))

        let mutation: VaultDisk.IndexMutation
        do {
            mutation = try await disk.restoreFile(from: source, to: relativePath)
        } catch {
            removeSelfWrittenEntry(at: relativePath, sequence: provisional)
            if error is FileOperationError || error is WriteRefusal { throw error }
            throw FileOperationError.failed("ripristino: \(error.localizedDescription)")
        }
        reconcileProvisionalSequence(at: relativePath, provisional: provisional, actual: mutation.sequence)
        apply([mutation])
        // ADR-0067 §D1: last, once the restore is real. A file that is not UTF-8 is no note a
        // tab could show, so there is no text to announce for it.
        if let text = NoteStore.decodedText(data) {
            announce(.written(WriteResult(path: relativePath, text: text), origin: nil))
        }
    }
}
