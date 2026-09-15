import Foundation

// ADR-0045 §D3/§D7 (PG-143 structure refactor): the ledger reload/write and the
// isolated-launch messaging, split out of RecordingsController.swift for its own
// file-length warning - moved verbatim except for the widening this seam requires
// (each marked in place, ADR-0045 §D3).

// MARK: - Ledger, vault scoping (R-12) and readable failure (R-13)

// In an extension purely for length: the class body above is already at SwiftLint's
// `type_body_length` limit, and nothing here is part of what the pane calls.
extension RecordingsController {
    static let noVaultMessage = "Nessun vault aperto: apri un vault prima di importare una registrazione."

    /// Rebuilds the store when `vault.session` has changed identity and rereads the ledger
    /// from disk, which is where every other writer of these files leaves its state.
    ///
    /// Not `private`: `RecordingsController.swift`'s `refresh()` calls it from the main
    /// file, `RecordingsController+Interface.swift`'s `ensureStore()` calls it too, and so
    /// does `RecordingsController+Import.swift`'s `importAccepted()`.
    func reloadLedger() {
        guard let session = vault.session else {
            store = nil
            storeIdentity = nil
            ledger = .empty
            entries = [:]
            recordings = []
            stop()
            return
        }

        let identity = session.state.directory.path(percentEncoded: false)
        if identity != storeIdentity {
            // A poll belongs to the vault that started it, and so does everything a row
            // was saying about it (R-12).
            stop()
            storeIdentity = identity
            store = PlaudVaultStore(directory: session.state.directory)
            recordings = []
            rowErrors = [:]
            confirmationFailures = [:]
            pollExpired = []
        }
        ledger = store?.loadLedger() ?? .empty
        entries = ledger.recordings
    }

    /// Writes one entry through, disk first: `pendingConfirmation` that never reached the
    /// file is a debt nothing would retry after a relaunch (ADR §D13). Returns whether the
    /// write actually reached disk, so a caller about to tell the service "imported" can
    /// refuse to when it did not (`importAccepted`).
    ///
    /// Not `private`: `RecordingsController.swift`'s `delete` calls it from the main file,
    /// and `RecordingsController+Import.swift`'s `importAccepted` and `confirm` call it too.
    @discardableResult
    func record(_ entry: PlaudVaultStore.Entry, for recordingID: String) -> Bool {
        ledger.recordings[recordingID] = entry
        entries = ledger.recordings
        do {
            try store?.saveLedger(ledger)
            return true
        } catch {
            rowErrors[recordingID] = "Stato locale non salvato: la conferma non verrà ritentata dopo la chiusura."
            return false
        }
    }

    /// Where a recording's note goes the first time it is imported: `<notes folder>/` at the
    /// vault root, named by `ImportNaming.recordingNoteTitle` (ADR §D5) and made unique the
    /// way every other import already is.
    ///
    /// Not `private`: `RecordingsController+Import.swift`'s `importAccepted` is this file's
    /// only caller.
    func notePath(for proposal: PlaudProposal, in session: VaultSession) -> String {
        let recordedAt = PlaudTimestamp.parse(proposal.recording.recordedAt) ?? Date.now
        let title = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: proposal.recording.name)
        let folder = ledger.notesFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let directory = folder.isEmpty
            ? session.root
            : session.root.appending(path: folder, directoryHint: .isDirectory)
        let fileName = ImportNaming.uniqueFileName(NoteName.fileName(for: title), in: directory)
        return folder.isEmpty ? fileName : "\(folder)/\(fileName)"
    }

    /// The one state an isolated launch ever reports, set on every entry point rather than
    /// once: a method that returned silently would leave a banner from before the flag.
    ///
    /// Not `private`: `RecordingsController.swift` calls it from every isolated guard in the
    /// main file, `RecordingsController+Interface.swift`'s `loadProposal` calls it too, and
    /// so do `RecordingsController+Import.swift`'s `importAccepted` and `retryConfirmation`.
    func isolate() {
        health = .unavailable(message: Self.isolatedMessage)
        bannerMessage = Self.isolatedMessage
    }

    /// R-13: a readable sentence for anything thrown, never `"\(error)"`. `PlaudError` owns
    /// its own wording; anything else is reported through the transport case, which is what
    /// a failure that never reached the mapping table actually was.
    ///
    /// Not `private`: `RecordingsController.swift` calls it from `refresh`, `checkHealth`,
    /// `process` and `askJob` in the main file, `RecordingsController+Interface.swift`'s
    /// `loadProposal` calls it too, and so does `RecordingsController+Import.swift`'s
    /// `confirm`.
    func readableMessage(_ error: any Error) -> String {
        if let plaud = error as? PlaudError { return plaud.message }
        return PlaudError.transportFailure(error.localizedDescription).message
    }
}
