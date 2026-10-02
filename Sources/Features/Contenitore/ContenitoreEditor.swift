import Foundation
import Observation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D11 and §D12, plan
// docs/plans/contenitore.md, Task 7 - R-16, R-17; ADR-0073 (a holder of unsaved state reviews
// itself in `QuitCoordinator`), ADR-0067 §D6 and ADR-0068 §D16 (reload on the landed generation).

/// The inspector's edit of one scheda, held by the controller rather than by the view.
///
/// What the person types lives here, not in `@State`: a view that goes away (another row, another
/// pane, Cmd+Q) takes its `@State` with it, and a save started from `.onDisappear` in an unawaited
/// `Task` is a write nothing waits for. Here the draft outlives the view, `settle()` is a save
/// the caller can await, and `ContenitoreController.settleEditing()` is what a selection change
/// and `QuitCoordinator` wait on.
///
/// Three rules, each closing a defect the view-owned shape had:
/// - **Saves are serial.** Each one runs after the previous ended, against the hash that one left,
///   so a second quick edit starts from fresh state instead of the hash the first started with
///   and being refused for a conflict nobody caused.
/// - **The baseline follows the disk.** `refreshFromDisk()` reloads the text and hash the writes
///   guard against when a landed change or an external edit moved them, and keeps every field
///   the person has already edited: «Classifica…» writes through its own model, and the next edit
///   here must be built on its result, not refused for it.
/// - **A refusal still reloads.** A write the guard refuses adopts the file (R-16). A write that
///   merely fails does not: the disk is unchanged, so the draft stays owed and is retried.
@MainActor
@Observable
final class ContenitoreEditor {
    let schedaPath: String
    /// What the fields show and the controls edit. The view binds to it.
    var draft: ContenitoreDraft
    /// The date field's text, committed by `commitDate()`.
    var dateText: String
    /// The last edit's problem sentence, nil after a good one.
    private(set) var problem: String?

    /// The text and hash the last read or write left, what every write is guarded by.
    @ObservationIgnored private var model: ContenitoreInspectorModel
    /// The last queued save; the next one waits for it.
    @ObservationIgnored private var flight: Task<Void, Never>?
    /// Saves queued or running.
    @ObservationIgnored private var saves = 0

    /// Reads the scheda, or nil when it cannot be read.
    init?(session: VaultSession, schedaPath: String) {
        guard let model = ContenitoreInspectorModel(session: session, schedaPath: schedaPath) else { return nil }
        self.schedaPath = schedaPath
        self.model = model
        self.draft = model.draft
        self.dateText = model.draft.date?.description ?? ""
    }

    /// The text the last read or write left, for a test to compare with the disk.
    var baselineText: String { model.text }

    /// True when there is nothing left to write: no save queued or running, no field edited, and
    /// no date text that could be committed and is not the baseline's. A date text that cannot be
    /// committed (invalid, or emptied: a scheda's `date` is the import day and is never cleared,
    /// SPEC §Decisions) is not owed, so it never holds a selection change or the quit. What
    /// they wait for.
    var isSettled: Bool {
        saves == 0 && Self.normalized(draft) == model.draft && !owesDateText
    }

    /// A date text typed that would commit to something other than the baseline's date.
    private var owesDateText: Bool {
        guard dateText != Self.text(of: model.draft.date) else { return false }
        return CalendarDate(iso: dateText.trimmingCharacters(in: .whitespaces)) != nil
    }

    // MARK: - Saving

    /// Queues a save of the draft as it is when the save runs, without waiting for it.
    func requestSave() {
        enqueueSave()
    }

    /// Commits a date typed and not yet committed, then writes everything edited, and returns
    /// when no save is queued or running, including one another caller queued while it waited
    /// (PG-352: the retired editor's own settle and `settleEditing()` overlap). Idempotent: an
    /// editor with nothing to write returns at once.
    func settle() async {
        commitPendingDate()
        // What could not be committed is not owed: the field goes back to the draft's date and the
        // sentence commitDate() recorded stays, so the person sees why.
        if dateText != Self.text(of: draft.date) { dateText = Self.text(of: draft.date) }
        if Self.normalized(draft) != model.draft { enqueueSave() }
        // `flight` is always the last save queued and each one waits for the one before, so this
        // ends; a write that fails still brings `saves` to zero and leaves the draft owed.
        while saves > 0, let flight { await flight.value }
    }

    /// Reads the date field: a valid one becomes the draft's and is saved; an invalid one is
    /// reported and changes nothing.
    func commitDate() {
        let trimmed = dateText.trimmingCharacters(in: .whitespaces)
        guard let date = CalendarDate(iso: trimmed) else {
            problem = "Data non valida: scrivila come AAAA-MM-GG."
            return
        }
        // A committable text is shown as the date it is (a stray space goes), so it never reads as
        // an edit that nothing will write.
        dateText = date.description
        guard date != draft.date else { return }
        draft.date = date
        requestSave()
    }

    /// `commitDate()` only when the text was edited, so settling an untouched field says nothing.
    private func commitPendingDate() {
        guard dateText != Self.text(of: draft.date) else { return }
        commitDate()
    }

    /// The scheda is no longer at its path (deleted or moved outside the app): an owed edit can
    /// never be written, since every write is guarded by the hash of a file that is gone (PG-341).
    var isSchedaGone: Bool { !model.session.exists(schedaPath) }

    /// Drops what is owed: the fields go back to the last text read or written, so nothing is
    /// left to write. The quit's «Non salvare» over a scheda that is gone (PG-341): a save
    /// queued after this finds nothing changed, and one already running is refused by its
    /// guard, as it would have been anyway.
    func discard() {
        adoptModel()
    }

    /// Reports a sentence the view found before there was anything to save (a tag that is not a
    /// tag).
    func report(_ sentence: String) {
        problem = sentence
    }

    @discardableResult
    private func enqueueSave() -> Task<Void, Never> {
        saves += 1
        let previous = flight
        let task = Task { [self] in
            await previous?.value
            await performSave()
        }
        flight = task
        return task
    }

    /// One write, run after every earlier one ended: the draft, the model and its hash are read
    /// now, not when the save was queued.
    private func performSave() async {
        defer { saves -= 1 }
        let wanted = draft
        var local = model
        let outcome = await local.save(
            description: wanted.description, date: wanted.date, colour: wanted.colour, tags: wanted.tags
        )
        model = local
        switch outcome {
        case .saved, .unchanged:
            problem = nil
        case .refused:
            // A scheda that is no longer there (moved or trashed from under the edit) has nothing to
            // show: the draft is kept, still owed, rather than replaced by the last text read.
            guard model.session.exists(schedaPath) else {
                problem = "La scheda non è più al suo posto: la modifica non è stata salvata."
                return
            }
            problem = "La scheda è cambiata nel frattempo: i campi mostrano la versione sul disco."
            adoptModel()
        case .invalid(let refusal):
            problem = refusal.sentence
        case .failed(let reason):
            // The disk did not change and the file is what the model holds, so nothing is
            // adopted: the draft stays owed (`isSettled` false), the next save or settle retries
            // it, and the quit does not go with it lost (ADR-0073 §D7).
            problem = "Modifica non salvata: \(reason)"
        }
    }

    // MARK: - Following the disk

    /// Takes a change another writer landed. Nothing happens when the file is what the model
    /// holds (the usual case: this editor's own write, or an index change elsewhere), or while a
    /// save is queued or running, which finishes against the hash it holds and reloads itself if
    /// refused. Otherwise the model reads the file, and each field the person has not edited
    /// takes the file's value; a field they have edited keeps their value, to be written over
    /// the new baseline.
    func refreshFromDisk() {
        guard saves == 0 else { return }
        var fresh = model
        fresh.reload()
        guard fresh.hash != model.hash else { return }

        let before = model.draft
        let after = fresh.draft
        let current = Self.normalized(draft)
        let dateWasEdited = dateText != Self.text(of: before.date) || current.date != before.date
        draft = ContenitoreDraft(
            description: current.description == before.description ? after.description : draft.description,
            date: current.date == before.date ? after.date : draft.date,
            colour: current.colour == before.colour ? after.colour : draft.colour,
            tags: current.tags == before.tags ? after.tags : draft.tags
        )
        if !dateWasEdited { dateText = Self.text(of: draft.date) }
        model = fresh
    }

    private func adoptModel() {
        draft = model.draft
        dateText = Self.text(of: draft.date)
    }

    // MARK: - Pieces

    /// The draft as a write reads it: the description without the blank lines around it.
    private static func normalized(_ draft: ContenitoreDraft) -> ContenitoreDraft {
        var draft = draft
        draft.description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft
    }

    private static func text(of date: CalendarDate?) -> String {
        date?.description ?? ""
    }
}
