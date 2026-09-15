import Foundation

// ADR-0045 §D3/§D7 (PG-143 structure refactor): the two-phase import (ADR §D13), split
// out of RecordingsController.swift because moving the other two extensions alone still
// left it over SwiftLint's `file_length` limit. Moved verbatim - `confirm` and
// `fingerprints(ofAccepted:in:added:)` keep their `private`, since both of their callers
// moved into this same file with them (§D3 rule 3).
extension RecordingsController {
    // MARK: - Two-phase import (ADR §D13)

    /// Phase 1: renders the note through `TranscriptNote.render` and writes it via
    /// `vault.session?.write(_:to:)`, recording the new fingerprints and
    /// `pendingConfirmation` in the ledger. Phase 2: `POST /proposals/{id}/imported` with
    /// exactly `acceptedTaskIDs` (R-06 - the rejected ids are never sent). If phase 2
    /// throws, the note stays written, `confirmationFailures[recordingID]` is set to the
    /// readable message (R-13), and `pendingConfirmation` stays owed for `retryConfirmation`
    /// to retry - the note is never re-written and no fingerprint is ever added twice.
    func importAccepted(
        recordingID: String,
        proposal: PlaudProposal,
        acceptedTaskIDs: Set<String>,
        speakerRenames: [String: String]
    ) async {
        guard !isIsolated else { return isolate() }
        reloadLedger()
        guard let session = vault.session, store != nil else {
            rowErrors[recordingID] = Self.noVaultMessage
            return
        }
        // An unparseable `recorded_at` used to fall through silently to today's date, both
        // in the note's frontmatter and in its file name (`notePath`/`TranscriptNote.render`
        // each default to "now" when parsing fails) - filing a malformed recording under the
        // wrong date instead of surfacing it (RTF review finding, 2026-09-06). Rejected here,
        // before either fallback is ever reached.
        guard PlaudTimestamp.parse(proposal.recording.recordedAt) != nil else {
            rowErrors[recordingID] = "Data di registrazione non valida: \"\(proposal.recording.recordedAt)\""
            return
        }

        var entry = ledger.recordings[recordingID] ?? PlaudVaultStore.Entry(status: "new")
        // The note is the source of truth (principle 1): what it already holds suppresses a
        // task just as the ledger does, and it is read here rather than remembered.
        let existing = entry.notePath.flatMap { try? session.read($0) }
        let existingText = existing?.text
        let text = TranscriptNote.render(
            proposal: proposal,
            acceptedTaskIDs: acceptedTaskIDs,
            speakerRenames: speakerRenames,
            ledgerFingerprints: entry.quoteFingerprints,
            existingNoteText: existingText
        )
        let path = entry.notePath ?? notePath(for: proposal, in: session)

        // Phase 1: the file first. A failure here means nothing was imported at all, so
        // nothing is recorded and no confirmation is owed.
        //
        // `expecting:` (ADR-0043 §D8, Task 9) - nil for a brand-new note (nothing to
        // expect), the record's own hash for a re-import: `text` is a merge of the
        // proposal with `existingText` (ADR-0032 §D9's dedup suppression set), so a note
        // that moved on between the read above and this write would make the merge
        // stale and re-import quotes it already suppressed. The two-phase shape below
        // makes the refusal clean: phase 2's `POST` only runs after phase 1 succeeds, so
        // a refusal here aborts before anything leaves the machine.
        do {
            try await session.write(text, to: path, expecting: existing?.record.contentHash)
        } catch let refusal as VaultSession.WriteRefusal {
            rowErrors[recordingID] = "Scrittura della nota non riuscita: \(refusal.description)"
            return
        } catch {
            rowErrors[recordingID] = "Scrittura della nota non riuscita: \(path)"
            return
        }

        entry.status = "imported"
        entry.notePath = path
        entry.quoteFingerprints = fingerprints(
            ofAccepted: acceptedTaskIDs, in: proposal, added: entry.quoteFingerprints
        )
        entry.pendingConfirmation = acceptedTaskIDs.sorted()
        entry.lastImportedAt = Date.now.ISO8601Format()
        guard record(entry, for: recordingID) else {
            // The ledger write failed: the pending-confirmation debt never reached disk, so
            // telling the service "imported" now would leave nothing to retry it from
            // (ADR §D13). `rowErrors[recordingID]` is already set by `record`.
            return
        }

        // Phase 2, and only now: a confirmation the vault cannot honour would mark the
        // recording imported service-side with nothing to show for it (ADR §D13).
        await confirm(recordingID: recordingID, taskIDs: entry.pendingConfirmation)
    }

    /// Re-issues only phase 2 of `importAccepted` for the ids already recorded as
    /// `pendingConfirmation` - no note write, no proposal re-fetch, one `confirmImported`
    /// call.
    func retryConfirmation(recordingID: String) async {
        guard !isIsolated else { return isolate() }
        guard let entry = entries[recordingID], !entry.pendingConfirmation.isEmpty else { return }
        await confirm(recordingID: recordingID, taskIDs: entry.pendingConfirmation)
    }

    /// `POST /proposals/{id}/imported` with exactly the accepted ids and nothing else
    /// (R-06). On success the debt is cleared; on failure the note stays written and the
    /// debt stays owed, which is the whole point of recording it before asking (ADR §D13).
    private func confirm(recordingID: String, taskIDs: [String]) async {
        do {
            try await service.confirmImported(recordingID: recordingID, taskIDs: taskIDs)
            confirmationFailures[recordingID] = nil
            guard var entry = ledger.recordings[recordingID] else { return }
            entry.pendingConfirmation = []
            record(entry, for: recordingID)
        } catch {
            confirmationFailures[recordingID] = readableMessage(error)
        }
    }

    /// Every accepted task's quote fingerprint, added to the ones already recorded. The
    /// ledger only ever grows (ADR §D9): that is what makes a task the person deleted from
    /// the note stay deleted instead of returning on the next forced re-run.
    private func fingerprints(
        ofAccepted acceptedTaskIDs: Set<String>, in proposal: PlaudProposal, added existing: [String]
    ) -> [String] {
        var known = existing
        for theme in proposal.themes {
            for task in theme.tasks where acceptedTaskIDs.contains(task.id) {
                let fingerprint = PlaudQuote.fingerprint(task.quote)
                guard !known.contains(fingerprint) else { continue }
                known.append(fingerprint)
            }
        }
        return known
    }
}
