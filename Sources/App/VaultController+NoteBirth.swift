import Foundation

// PG-387 (N4), ADR-0085 §D3-§D5/§D7-§D9 and ADR-0086 §D4, plan docs/plans/pg-387-n4-birth-of-note.md,
// Tasks 5-7 - R-03, R-06, R-08, R-11, R-13, R-14, R-16.

/// Why a door of the note's birth refused before reaching the session, in the person's words.
struct NoteBirthRefusal: Error, CustomStringConvertible, Equatable {
    let description: String
}

/// The subject of the «Estrai in una nota» sheet: where the selection is, what it says, and what
/// the new note will be called.
extension VaultController {
    struct ExtractionDraft: Identifiable, Equatable {
        let id: UUID
        let tabID: NoteTab.ID
        let sourcePath: String
        let range: NSRange
        let text: String
        var title: String
        var folder: String
        let sourceIsDirty: Bool
    }

    // MARK: Creating a note from the composer

    /// The pane host's creation (ADR-0085 §D7/§D9, ADR-0086 §D4): the note is written, opened in
    /// a tab of its own with the caret where the template's `{{cursor}}` stood, the lists are
    /// rescanned, and «Nota creata · Annulla» is offered for it - replacing any earlier offer.
    ///
    /// A refused creation records its sentence and throws, with no tab opened.
    @discardableResult
    func createComposedNote(_ composition: NoteComposition) async throws -> String {
        guard let session else { throw CreationError.alreadyExists("nessuna cartella note aperta") }
        let result: VaultSession.WriteResult
        do {
            result = try await session.createNote(
                title: composition.title, in: composition.folder, date: .today, category: .note,
                topics: composition.tags, body: composition.body
            )
        } catch {
            recordProblem(ConformanceText.creationFailure(error))
            throw error
        }
        let caret = composition.bodyCaret.flatMap {
            NoteTemplate.Resolved(body: composition.body, caretOffset: $0).caret(inWritten: result.text)
        }
        openNoteInNewTab(at: result.path, caret: caret)
        Task { await rescan() }
        creationUndo = CreationUndo.offer(for: result, at: Date())
        return result.path
    }

    /// Quick Open's create row (ADR-0083 §D6, R-11): opens the composer prefilled with the title
    /// instead of writing at the vault root, and closes the switcher. A parked draft wins, as it
    /// does for a dangling link's offer.
    func offerNoteFromQuickOpen(title: String) {
        offerNoteCreation(title: title, besideNoteAt: nil)
        isShowingQuickSwitcher = false
    }

    // MARK: «Classifica…»

    /// Classifies a note, saving the open tab first when `savingFirst` is set (ADR-0085 §D4/§D8).
    ///
    /// Every dirty tab showing the path is saved through `saveTab(_:)`, the one save door; the
    /// tabs are asked again *after* that `await` (ADR-0043 §D7), so an edit typed while the save
    /// was suspended refuses the classification rather than being written over. Without
    /// `savingFirst` a dirty tab refuses at once and nothing is written.
    func classifyNote(
        at path: String, topics: [Tag], toFolder folder: String?, savingFirst: Bool
    ) async throws -> VaultSession.NoteClassifyOutcome {
        let session = try await settledSession(
            for: path, savingFirst: savingFirst, refusal: Self.unsavedClassifyRefusal
        )
        let outcome = try await session.classifyNote(at: path, topics: topics, toFolder: folder)
        // The write already reached the tabs through the landed-change door (ADR-0067); a move
        // announced itself the same way. The rescan only refreshes what the lists derive.
        if folder != nil { Task { await rescan() } }
        return outcome
    }

    static let unsavedClassifyRefusal = "salva la nota prima di classificarla"

    // MARK: «Estrai in una nota»

    /// Builds the extraction draft from the focused tab's selection; false with none.
    ///
    /// The title is derived from the selection's first non-empty line through the capture rule
    /// (ADR-0080 §D3), so it is always one `NoteName.validate` accepts; the folder defaults to
    /// the source note's.
    func beginExtraction() -> Bool {
        guard let tab = focusedTab, let range = tab.selection, range.length > 0 else { return false }
        let text = tab.note.text as NSString
        guard NSMaxRange(range) <= text.length else { return false }
        let selected = text.substring(with: range)
        let firstLine = selected.split(whereSeparator: CaptureTitle.endsTypedLine)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let heading = String(firstLine.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        extraction = ExtractionDraft(
            id: UUID(), tabID: tab.id, sourcePath: tab.note.relativePath, range: range, text: selected,
            title: CaptureTitle.derive(fromTypedLine: heading, now: Date(), calendar: .current).title,
            folder: (tab.note.relativePath as NSString).deletingLastPathComponent,
            sourceIsDirty: tab.note.hasUnsavedChanges
        )
        return true
    }

    /// Extracts the draft's range into the composed note (ADR-0085 §D8).
    ///
    /// Saves a dirty source first when asked, asks the tabs again after the `await`, then hands
    /// the session the draft's text as `expectedText`: the session re-reads the file and refuses
    /// when the text at the range is no longer it, before anything is created. A refused second
    /// write comes back as `.refused` in the outcome, never thrown, with the new note kept.
    func extract(
        _ draft: ExtractionDraft, as composition: NoteComposition, savingFirst: Bool
    ) async throws -> VaultSession.ExtractOutcome {
        let session = try await settledSession(
            for: draft.sourcePath, savingFirst: savingFirst, refusal: Self.unsavedExtractRefusal
        )
        let outcome = try await session.extractToNote(
            from: draft.sourcePath, range: draft.range, expectedText: draft.text,
            title: composition.title, in: composition.folder, topics: composition.tags, date: .today
        )
        Task { await rescan() }
        return outcome
    }

    static let unsavedExtractRefusal = "salva la nota prima di estrarne una parte"

    /// The editor's report of the selection in one column's front tab (nil when collapsed), in
    /// `recordLinkAtCaret(_:inColumn:)`'s shape: written only when it changed.
    func recordSelection(_ range: NSRange?, inColumn columnIndex: Int) {
        let reported = range.flatMap { $0.length > 0 ? $0 : nil }
        guard columns.indices.contains(columnIndex),
              let id = columns[columnIndex].activeID,
              let index = columns[columnIndex].tabs.firstIndex(where: { $0.id == id }),
              columns[columnIndex].tabs[index].selection != reported
        else { return }
        columns[columnIndex].tabs[index].selection = reported
    }

    /// The session to act on `path` through, once every tab showing it is clean.
    ///
    /// With `savingFirst`, each dirty tab is saved through `saveTab(_:)` and a failed save
    /// throws its own sentence. The question is asked again after the saves (ADR-0043 §D7), and
    /// against the same session: a vault switched during the `await` refuses.
    private func settledSession(for path: String, savingFirst: Bool, refusal: String) async throws -> VaultSession {
        guard let session else { throw NoteBirthRefusal(description: "nessuna cartella note aperta") }
        if savingFirst {
            let dirty = columns.flatMap(\.tabs).filter { $0.note.relativePath == path && $0.note.hasUnsavedChanges }
            for tab in dirty {
                if case .failed(let message) = await saveTab(tab.id) { throw NoteBirthRefusal(description: message) }
            }
        }
        guard self.session === session else { throw NoteBirthRefusal(description: "la cartella note è cambiata") }
        guard !hasUnsavedTab(showing: path) else {
            recordProblem(refusal)
            throw NoteBirthRefusal(description: refusal)
        }
        return session
    }

    // MARK: The caret a note is born with

    /// The caret a tab of one column was asked to place, once (ADR-0086 §D4): the front tab's
    /// `pendingCaret`, cleared as it is handed over.
    func takePendingCaret(forColumn columnIndex: Int) -> Int? {
        guard columns.indices.contains(columnIndex),
              let id = columns[columnIndex].activeID,
              let index = columns[columnIndex].tabs.firstIndex(where: { $0.id == id }),
              let caret = columns[columnIndex].tabs[index].pendingCaret
        else { return nil }
        columns[columnIndex].tabs[index].pendingCaret = nil
        return caret
    }

    /// Asks the focused tab to place the caret at `caret` once it is shown; nil asks nothing.
    func requestCaretInFocusedTab(_ caret: Int?) {
        guard let caret, columns.indices.contains(focusedColumnIndex),
              let id = columns[focusedColumnIndex].activeID,
              let index = columns[focusedColumnIndex].tabs.firstIndex(where: { $0.id == id })
        else { return }
        columns[focusedColumnIndex].tabs[index].pendingCaret = caret
    }

    // MARK: «Nota creata · Annulla»

    /// Trashes the note the last pane-host creation made, when the offer is live and the file is
    /// as created (ADR-0085 §D9).
    ///
    /// Everything the decision reads is read here, after nothing was awaited; the trash itself
    /// goes through `trashNote(at:)`, which asks the tabs again and whose landed change closes a
    /// clean tab and forgets the note's id (ADR-0059 §D6). A refusal keeps the offer, so the
    /// strip can say why; a trash or an expiry ends it.
    func undoCreation(now: Date) async -> CreationUndo.Decision {
        guard let offer = creationUndo else { return .expired }
        let currentHash = (try? session?.read(offer.path)).map { NoteStore.hash(Data($0.text.utf8)) }
        let decision = CreationUndo.decide(
            offer, now: now, currentHash: currentHash, tabIsDirty: hasUnsavedTab(showing: offer.path)
        )
        switch decision {
        case .trashed:
            guard await trashNote(at: offer.path) else {
                return .failed(problems.last ?? "La nota non è stata eliminata.")
            }
            if creationUndo == offer { creationUndo = nil }
        case .expired:
            if creationUndo == offer { creationUndo = nil }
        case .unsaved, .changed, .failed:
            break
        }
        return decision
    }
}
