import Foundation

/// What the quit decided, before AppKit's spelling of it: `AppDelegate` maps these to
/// `.terminateNow`, `.terminateLater` and `.terminateCancel` (ADR-0073 §D9).
enum QuitReply: Equatable, Sendable {
    case now, later, cancel
}

/// The one door every termination goes through (ADR-0073 §D1): Cmd+Q, «Esci da Pergamenum»,
/// the red button on the last window and a logout, restart or shutdown all reach
/// `applicationShouldTerminate(_:)`, which asks this.
///
/// Three phases, in order, and exactly one reply:
///
/// 0. **Open field-editor edits end** (`commitEditing`), so a table cell being typed in is in
///    its note's buffer before anything below reads it.
/// 1. **The board settles**, synchronously (ADR-0066 §D5).
/// 2. **The notes.** Every dirty tab of every column is reviewed (`QuitReview`). With none, the
///    quit behaves exactly as it did before this type existed (R-10). Otherwise the person is
///    asked, app-modally, before anything replies (§D3), so no timer runs while the question
///    is open. «Annulla» cancels; «Non salvare» covers the snapshot the question showed;
///    «Salva tutto» saves under `.terminateLater` with a **fail-safe** cap (§D6): elapsed, it
///    cancels the quit rather than completing it, because a note buffer lost to a terminate
///    cannot be retried.
/// 3. **The diary** (ADR-0060 §D2), unchanged, and started only after the notes: its **fail-open**
///    2 s cap races `settle()` in two independent tasks - a task group would wait out a write
///    that ignores cancellation, and the cap would cap nothing.
///
/// Immediately before letting the app go (`.now` or `reply(true)`), the dirty set is read
/// again: a dirty tab the answer did not cover turns the reply into a cancel (§D6, §D7).
///
/// Everything AppKit-shaped comes in as a closure - `commitEditing`, `ask`, `reply`, `reveal`,
/// `sleep` - so the whole decision is under unit tests (`QuitCoordinatorTests`) and the
/// delegate keeps only the mapping (§D9).
@MainActor
final class QuitCoordinator {
    private let vault: @MainActor () -> VaultController?
    private let diary: @MainActor () -> DiaryController?
    private let commitEditing: @MainActor () -> Void
    private let ask: @MainActor (QuitReview) -> QuitReview.Answer
    private let reply: @MainActor (Bool) -> Void
    private let reveal: @MainActor (NoteTab.ID?) -> Void
    private let sleep: @MainActor (Duration) async -> Void
    private let saveAll: (@MainActor (QuitReview) async -> QuitSaveReport)?

    /// How long the diary is waited for before the app goes anyway (ADR-0060 §D2).
    static let diaryCap: Duration = .seconds(2)

    /// True between a `.later` and its one reply. Every path to `reply` goes through
    /// `answer(_:attempt:)`, which pays this debt once; every later caller finds it paid.
    private var owesReply = false
    /// True while «Salva tutto»'s writes and their cap race each other.
    private var notesPending = false
    /// Bumped by every `shouldTerminate()`, so a cap or a settle left over from an earlier,
    /// cancelled quit can never answer a later one.
    private var attempt = 0

    /// - Parameter commitEditing: ends whatever edit is still open in a field editor, so it
    ///   reaches its buffer before anything is read (production: the key window gives up its
    ///   first responder). A GFM table cell reaches the note's text only when its editing ends
    ///   (`TableGridView.controlTextDidEndEditing`); read before that, a clean note would quit
    ///   with `.now` and a dirty one would save without the cell. Required rather than
    ///   defaulted, so a new call site cannot leave it out by omission.
    /// - Parameter saveAll: the bulk save; `nil` means `VaultController.saveForQuit(_:)`. A
    ///   seam for the cap's test, which needs a save that never finishes.
    init(
        vault: @escaping @MainActor () -> VaultController?,
        diary: @escaping @MainActor () -> DiaryController?,
        commitEditing: @escaping @MainActor () -> Void,
        ask: @escaping @MainActor (QuitReview) -> QuitReview.Answer,
        reply: @escaping @MainActor (Bool) -> Void,
        reveal: @escaping @MainActor (NoteTab.ID?) -> Void,
        sleep: @escaping @MainActor (Duration) async -> Void,
        saveAll: (@MainActor (QuitReview) async -> QuitSaveReport)? = nil
    ) {
        self.vault = vault
        self.diary = diary
        self.commitEditing = commitEditing
        self.ask = ask
        self.reply = reply
        self.reveal = reveal
        self.sleep = sleep
        self.saveAll = saveAll
    }

    func shouldTerminate() -> QuitReply {
        attempt += 1
        owesReply = false
        notesPending = false
        let vault = vault()

        // 0. An edit still open in a field editor (a table cell, a card) ends first, so it is
        // in its buffer before the board settles and before the notes are read. Before the
        // settle rather than after: a commit the resign triggers on the board is then flushed
        // by it instead of waiting in an autosave debounce the quit does not wait on.
        commitEditing()

        // 1. The board: its save is not async, so an edit inside its autosave debounce is
        // written before anything here decides whether to wait (#506, ADR-0066).
        vault?.openBoard?.settleForTermination()

        // 2. The notes.
        let review = QuitReview(columns: vault?.columns ?? [])
        guard let vault, !review.isEmpty else { return diaryPhase(covering: review) }

        switch ask(review) {
        case .cancel:
            reveal(nil)
            return .cancel
        case .discard:
            // Re-read after the question: typing that raced the answer is uncovered work.
            if let first = review.uncovered(in: current).first {
                reveal(first.tabID)
                return .cancel
            }
            return diaryPhase(covering: review)
        case .save:
            owesReply = true
            notesPending = true
            saveNotes(review, in: vault, attempt: attempt)
            return .later
        }
    }

    // MARK: The notes phase

    /// Runs the bulk save and its cap as two independent tasks; whichever finishes first ends
    /// the notes phase.
    private func saveNotes(_ review: QuitReview, in vault: VaultController, attempt: Int) {
        Task { [weak self] in
            if let saveAll = self?.saveAll {
                _ = await saveAll(review)
            } else {
                _ = await vault.saveForQuit(review)
            }
            self?.notesSaved(attempt: attempt)
        }
        Task { [weak self] in
            await self?.sleep(QuitReview.noteSaveCap)
            self?.noteCapElapsed(review, in: vault, attempt: attempt)
        }
    }

    /// «Salva tutto» covers nothing it did not save (§D7): the app goes on only when a fresh
    /// review is empty. Anything left - a failed save, a conflict, work typed meanwhile -
    /// cancels, reveals the first such tab and names the notes left unsaved.
    private func notesSaved(attempt: Int) {
        guard attempt == self.attempt, notesPending else { return }
        notesPending = false
        let left = current
        if left.isEmpty {
            _ = diaryPhase(covering: left)
            return
        }
        vault()?.recordProblem("Uscita annullata: note non salvate: \(Self.names(of: left))")
        reveal(left.entries.first?.tabID)
        answer(false, attempt: attempt)
    }

    /// The fail-safe cap (§D6): the save has not finished, so the quit is cancelled - never
    /// completed. A write still in flight may land afterwards; the tab catches up through
    /// ADR-0067's door.
    private func noteCapElapsed(_ review: QuitReview, in vault: VaultController, attempt: Int) {
        guard attempt == self.attempt, notesPending else { return }
        notesPending = false
        let left = current
        let names = left.isEmpty ? Self.names(of: review) : Self.names(of: left)
        vault.recordProblem("Uscita annullata: il salvataggio di \(names) non è terminato")
        reveal(left.entries.first?.tabID ?? review.entries.first?.tabID)
        answer(false, attempt: attempt)
    }

    // MARK: The diary phase

    /// ADR-0060 §D2, started only after the notes. `covered` is what the answer covered, for
    /// the last check before letting go. Returns the synchronous reply; when a reply is
    /// already owed (the save path), the value is ignored and the phase answers through
    /// `reply`.
    private func diaryPhase(covering covered: QuitReview) -> QuitReply {
        let attempt = attempt
        guard let diary = diary(), !diary.isSettled else {
            if owesReply {
                finish(covering: covered, attempt: attempt)
                return .later
            }
            return lastCheck(covering: covered) ? .now : .cancel
        }
        owesReply = true
        Task { [weak self] in
            await diary.settle()
            self?.finish(covering: covered, attempt: attempt)
        }
        Task { [weak self] in
            await self?.sleep(Self.diaryCap)
            self?.finish(covering: covered, attempt: attempt)
        }
        return .later
    }

    private func finish(covering covered: QuitReview, attempt: Int) {
        guard attempt == self.attempt, owesReply else { return }
        answer(lastCheck(covering: covered), attempt: attempt)
    }

    /// The last check before letting go (§D6): true when every dirty tab is covered. An
    /// uncovered one is revealed.
    private func lastCheck(covering covered: QuitReview) -> Bool {
        guard let first = covered.uncovered(in: current).first else { return true }
        reveal(first.tabID)
        return false
    }

    /// The only path to `reply`: pays the debt once.
    private func answer(_ terminate: Bool, attempt: Int) {
        guard attempt == self.attempt, owesReply else { return }
        owesReply = false
        reply(terminate)
    }

    // MARK: Helpers

    /// The dirty set as it is now.
    private var current: QuitReview {
        QuitReview(columns: vault()?.columns ?? [])
    }

    private static func names(of review: QuitReview) -> String {
        let notes = review.notes
        return notes.map { "«\(QuitReview.displayName(of: $0, among: notes))»" }.joined(separator: ", ")
    }
}
