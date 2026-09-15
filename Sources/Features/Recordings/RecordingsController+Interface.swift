import Foundation

// ADR-0045 §D3/§D7 (PG-143 structure refactor): the four reads and two writes the
// interface asks for, split out of RecordingsController.swift for its own file-length
// warning - moved verbatim; `ensureStore` keeps its `private` because every one of its
// callers moved into this same file with it (§D3 rule 3).

// MARK: - What the interface asks for (Task 7's sheet, Task 8's Impostazioni field)

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Tasks 7-8 -
// R-04, R-10, R-11; ADR §D9, §D12.
//
// Four reads and two writes the pane cannot perform for itself, because they need the
// service, the session or the store - all three private to this file. Kept here rather than
// spread into the views for the reason the whole controller exists: a view that fetched its
// own proposal, or resolved its own state directory, would be a second place the isolation
// flag (`isIsolated`) and the vault scoping (R-12) have to be remembered.
extension RecordingsController {
    /// `GET /proposals/{id}` for the review sheet (R-04). `nil` on any failure, with the
    /// readable reason left on the row (R-13) rather than thrown at a view that has no way
    /// to say it.
    func loadProposal(recordingID: String) async -> PlaudProposal? {
        guard !isIsolated else {
            isolate()
            return nil
        }
        do {
            let proposal = try await service.proposal(recordingID: recordingID)
            rowErrors[recordingID] = nil
            return proposal
        } catch {
            rowErrors[recordingID] = readableMessage(error)
            return nil
        }
    }

    /// ADR §D9's suppression set for one recording: the union of the ledger's fingerprints
    /// and the ones the note itself already carries. Read from the file every time rather
    /// than cached - the note is the source of truth and the person may have edited it since.
    func suppressedFingerprints(recordingID: String) -> Set<String> {
        ensureStore()
        guard let entry = ledger.recordings[recordingID] else { return [] }
        var existingText: String?
        if let path = entry.notePath, let session = vault.session {
            existingText = try? session.read(path).text
        }
        return TranscriptNote.suppressionSet(
            existingNoteText: existingText, ledgerFingerprints: entry.quoteFingerprints
        )
    }

    /// The pending review for a recording, or `nil` when there is none or when the one on
    /// disk was taken against a different `generated_at` (R-10's boundary, ADR §D12).
    func draft(recordingID: String, generatedAt: String) -> PlaudVaultStore.Draft? {
        ensureStore()
        return store?.draft(for: recordingID, currentGeneratedAt: generatedAt)
    }

    /// R-10: called on every checkbox and every rename field as it changes, so a sheet
    /// dismissed by accident - or an app quit mid-review - comes back to the same decisions.
    func saveDraft(_ draft: PlaudVaultStore.Draft, for recordingID: String) {
        ensureStore()
        guard let store else { return }
        var drafts = store.loadDrafts()
        drafts[recordingID] = draft
        do {
            try store.saveDrafts(drafts)
        } catch {
            rowErrors[recordingID] = "Bozza di revisione non salvata: le scelte non verranno "
                + "ripristinate dopo la chiusura."
        }
    }

    /// Dropped once its decisions have been acted on: keeping it would restore them over a
    /// later, different proposal for the same recording.
    func clearDraft(for recordingID: String) {
        ensureStore()
        guard let store else { return }
        var drafts = store.loadDrafts()
        guard drafts.removeValue(forKey: recordingID) != nil else { return }
        try? store.saveDrafts(drafts)
    }

    /// R-11's «Giorni registrazioni Plaud», read straight off the ledger.
    ///
    /// A vault-scoped operational setting living in `plaud.json` and **not** in
    /// `VaultSettings` (ADR §D12): Impostazioni writes it through `updateDays(_:)` below, so
    /// looking for a `VaultSettings` key for it is looking for something that does not exist.
    var days: Int { ledger.days }

    /// Clamped to what the service accepts, on the way in: outside 1…3650 it answers 400
    /// `invalid_days`, and a setting that can only fail is not a setting.
    func updateDays(_ requested: Int) {
        ensureStore()
        guard store != nil else { return }
        ledger.days = min(max(requested, PlaudVaultStore.minimumDays), PlaudVaultStore.maximumDays)
        do {
            try store?.saveLedger(ledger)
        } catch {
            bannerMessage = "Intervallo di giorni non salvato: la cartella di stato del vault non è scrivibile."
        }
    }

    /// Reads the ledger once for a caller that arrives before the pane has (Impostazioni is
    /// its own scene and may be opened first). Not on every call: `saveDraft` runs on every
    /// keystroke of a rename field, and a disk read per keystroke is a cost with no answer.
    private func ensureStore() {
        guard store == nil else { return }
        reloadLedger()
    }
}
