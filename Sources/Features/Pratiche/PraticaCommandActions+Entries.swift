import Foundation

// ADR-0076 §D5/§D7 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 6 -
// R-02, R-03, R-11, R-12, R-18.
//
// The manual-entry verbs, and the message-row verbs that create an anchored entry. A pure
// extension split (ADR-0045 §D2's shape): the same command-to-write plumbing the primary file
// hosts, kept here so `PraticaCommandActions`'s body stays inside SwiftLint's limits.
//
// «Collega a un messaggio…» and «Scollega dal messaggio» write through one door,
// `rewriteEntry(_:_:)`: refused while `pratica.md` is dirty in a tab, refused (and the timeline
// reloaded) when the file moved on since the timeline read it, then one whole-file
// `VaultSession.write` `expecting:` the hash just read (ADR-0036 §D5 as amended by ADR-0076
// §D4). No undo is registered: the inverse is the other named verb, as for ADR-0049's links.

extension PraticaCommandActions {
    /// What a rewrite does to the entry's anchor line.
    enum EntryRewrite: Equatable {
        /// Write the line, or replace the one there, naming this Message-ID.
        case anchor(messageID: String)
        /// Remove the line.
        case unanchor
    }

    /// ADR-0076 §D5's dirty sentence. Pratiche's own: `canOperate(on:)`'s names other verbs.
    static let unsavedEntrySentence = "Salva «pratica.md» prima di collegare o scollegare una voce."

    // MARK: - Applicability

    /// The commands a manual-entry row offers (R-12): both surfaces ask this.
    func commands(forEntry entry: PraticaTimelineEntry) -> [PraticaEntryCommand] {
        PraticaEntryCommand.available(hasAnchor: entry.anchor != nil)
    }

    // MARK: - Running

    func run(_ command: PraticaEntryCommand, on entry: PraticaTimelineEntry) {
        switch command {
        case .linkMessage:
            pratiche.anchorRequest = PraticaAnchorRequest(entry: entry)
        case .unlinkMessage:
            Task { @MainActor in await unanchor(entry) }
        }
    }

    /// «Aggiungi nota» / «Aggiungi telefonata» on a message row (R-03): through the composer's
    /// one write path, the object the counts bar's «Nota»/«Telefonata» use. Not `private`:
    /// `run(_:on:detail:)` in the primary file calls it.
    func addAnchoredEntry(_ command: MessageCommand, on entry: PraticaTimelineEntry, detail: PraticaRowDetail?) {
        let kind: PraticaEntry.Kind
        switch command {
        case .addNote: kind = .note
        case .addCall: kind = .call
        default: return
        }
        let composer = PraticaEntryComposer(pratiche: pratiche, vault: vault, navigation: navigation)
        Task { @MainActor in await composer.insertAnchored(kind, on: entry, detail: detail) }
    }

    // MARK: - The two writes (R-11, R-12)

    /// Writes the entry's anchor line, or replaces the one there, naming `messageID` (R-11).
    func anchor(_ entry: PraticaTimelineEntry, to messageID: String) async {
        await rewriteEntry(entry, .anchor(messageID: messageID))
    }

    /// Removes the entry's anchor line and nothing else (R-12).
    func unanchor(_ entry: PraticaTimelineEntry) async {
        await rewriteEntry(entry, .unanchor)
    }

    /// ADR-0076 §D5's one door. Every check below runs on this side of the write's own
    /// suspension, with no `await` between the dirty-tab answer and the write: a precondition
    /// read before an `await` is a filter, not a guard.
    ///
    /// The entry is named by its `fileOrdinal` in the text the timeline read. The origin check
    /// is what makes that name safe: a file that changed since may hold a different entry at
    /// that ordinal, so the command refuses and reloads rather than anchoring the wrong one.
    func rewriteEntry(_ entry: PraticaTimelineEntry, _ rewrite: EntryRewrite) async {
        guard entry.kind != .message,
              let praticaPath = pratiche.selection,
              let session = vault.session
        else { return }
        if case .anchor(let messageID) = rewrite, PraticaEntryAnchor.line(for: messageID) == nil {
            pratiche.report("Questo messaggio non ha un Message-ID che una voce possa nominare: "
                + "non è stato scritto nulla.")
            return
        }
        let notePath = PraticaNaming.praticaNotePath(of: praticaPath)
        // 1. Dirty check: the write below would catch a clean tab up, never a dirty one.
        guard !vault.hasUnsavedTab(showing: notePath) else {
            pratiche.report(Self.unsavedEntrySentence)
            return
        }
        do {
            // 2. Fresh read.
            let (record, text) = try session.read(notePath)
            // 3. Origin check (R-18): the file is still the version this entry was read from.
            // The entry's own `sourceHash`, never the controller's current `timelineOrigin`: a
            // reload while a picker was open advances that to the changed file, and the
            // ordinal would then name another entry. No hash (an entry not read from a
            // file) cannot be proven current.
            guard pratiche.timelineOriginPraticaPath == praticaPath,
                  let origin = entry.sourceHash,
                  record.contentHash == origin
            else {
                pratiche.reloadTimeline(from: vault)
                pratiche.report(PraticaEntryCarry.staleTimelineSentence)
                return
            }
            // 4. Transform. Nil means there is nothing to write: the anchor is already that
            // one, or there is no anchor to remove.
            let updated: String?
            switch rewrite {
            case .anchor(let messageID):
                updated = PraticaEntryEdit.anchoring(entryAt: entry.fileOrdinal, to: messageID, in: text)
            case .unanchor:
                updated = PraticaEntryEdit.unanchoring(entryAt: entry.fileOrdinal, in: text)
            }
            guard let updated else { return }
            // 5. One guarded write; ADR-0067's door catches any clean editor tab up.
            try await session.write(updated, to: notePath, expecting: record.contentHash)
            reload()
        } catch let refusal as VaultSession.WriteRefusal {
            pratiche.report("La voce non è stata aggiornata in «\(notePath)»: \(refusal.description)")
        } catch {
            pratiche.report("La voce non è stata aggiornata in «\(notePath)»: \(error.localizedDescription)")
        }
    }
}
