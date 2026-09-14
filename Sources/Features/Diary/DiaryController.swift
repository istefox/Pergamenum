import Foundation
import Observation

/// The logic of the Diario pane: one day's prose and its entries, and the file both
/// live in.
///
/// Separated from the view so every rule that matters - snapping to ten minutes, not
/// falling off the end of the day, not writing a file for a day nobody wrote anything
/// on - is exercised by tests rather than by clicking.
///
/// Nothing here touches EventKit. The diary is the app's own record of a day and
/// answers to nothing outside the vault.
@MainActor
@Observable
final class DiaryController {
    private(set) var day: CalendarDate = .today
    /// The day's text without its `## Diario` section, which is what the editor edits.
    ///
    /// Settable because it is bound straight to the editor; every write goes through
    /// `noteProseEdited` so the save can be scheduled.
    var prose: String = "" {
        didSet {
            guard prose != oldValue, isLoaded else { return }
            isDirty = true
            scheduleSave()
        }
    }
    private(set) var entries: [DiaryEntry] = []
    private(set) var problems: [String] = []

    /// The entry being composed or edited, and the sheet that shows it. Nil is closed.
    var draft: DiaryDraft?
    /// Raised by the toolbar's date button.
    var isChoosingDate = false

    private let vault: VaultController
    /// False until the first load, so the initial assignment to `prose` is not read as
    /// an edit and does not schedule a write of a file that may not exist.
    private var isLoaded = false
    private var isDirty = false
    private var saveTask: Task<Void, Never>?

    /// How long typing pauses before the day is written. Long enough not to write on
    /// every keystroke, short enough that no realistic switch away loses a sentence -
    /// and every path that leaves the view flushes it anyway.
    private let saveDelay = Duration.milliseconds(600)

    init(vault: VaultController) {
        self.vault = vault
    }

    // MARK: Loading and saving

    /// Reads the day being shown. Creates nothing: a day only becomes a file once
    /// something is written on it.
    func load() {
        // Anything still owed to the day being left is written before it is replaced.
        // Cancelling the pending save instead - which is what this did - threw away the
        // last sentence typed whenever the pane was reopened quickly enough.
        //
        // `wasDirty` is read before `flush()` starts that write asynchronously
        // (ADR-0043 follow-up): `load()` re-reading `day`'s own file right after
        // flushing it races that write, and very likely wins the race, reading back
        // whatever was on disk *before* it landed and discarding the very sentence the
        // flush is about to persist. When the day being reloaded is the one just
        // flushed, `prose`/`entries` already hold what the write will make the file
        // say, so `reload` leaves them alone instead of overwriting them with a stale
        // read.
        let wasDirty = isDirty
        flush()
        reload(skipDiskReadBecauseJustFlushed: wasDirty)
    }

    func show(_ newDay: CalendarDate) {
        guard newDay != day else { return }
        flush()
        day = newDay
        // Not `load()`: its own `flush()` would re-fire here, and since the async write
        // `flush()` just started above has not completed yet, `isDirty` is often still
        // true - re-entering `save()` would snapshot the *old* day's leftover prose
        // against `self.day`, which is already `newDay`, and write it to the wrong
        // file. The flush above already owns whatever was pending for the day being
        // left; the day being shown was never dirty to begin with.
        reload(skipDiskReadBecauseJustFlushed: false)
    }

    /// The read half of `load()`: never called before a matching `flush()` for the day
    /// it is about to (maybe) read, and never on a day it might race.
    private func reload(skipDiskReadBecauseJustFlushed wasDirty: Bool) {
        isLoaded = false
        defer { isLoaded = true }

        guard vault.root != nil else {
            prose = ""
            entries = []
            return
        }
        guard !wasDirty else {
            isDirty = false
            return
        }
        if let diary = vault.readDiary(on: day) {
            prose = diary.prose
            entries = diary.entries
        } else {
            prose = vault.emptyDiaryNote(for: day)
            entries = []
        }
        isDirty = false
    }

    func move(by days: Int) { show(day.adding(days: days)) }

    /// Writes now, if there is anything to write. Called when the pane goes away, when
    /// the app stops being frontmost, and before changing day.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        guard isDirty, isLoaded, vault.root != nil else { return }
        // A day nobody wrote anything on is not a file. Without this, opening the pane
        // and walking through a week would leave seven empty notes behind.
        guard hasContent || vault.readDiary(on: day) != nil else {
            isDirty = false
            return
        }
        // The failure branch and the flag both move inside the hop (ADR-0043 §D2): a diary
        // marked clean before its file holds the text is a diary the next save skips.
        //
        // Snapshotted before the Task starts, not read from `self` inside it: `show(_:)`
        // calls `flush()` (which lands here) and then overwrites `day`/`prose`/`entries`
        // with the new day's values *synchronously*, before this Task's body ever runs -
        // so reading `self.…` inside the closure would write the wrong day's content.
        let day = day
        let prose = prose
        let entries = entries
        Task { @MainActor in
            guard await vault.writeDiary(prose: prose, entries: entries, on: day) else {
                problems.append("diario del \(day.compactForm): scrittura non riuscita")
                return
            }
            isDirty = false
        }
    }

    /// Whether the day holds anything at all, frontmatter aside.
    private var hasContent: Bool {
        !entries.isEmpty || !NoteDocument.parse(prose).body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Entries

    /// Adds an entry, snapped to the grid and kept inside the day.
    ///
    /// Overlaps are allowed on purpose: the diary records what happened, and what
    /// happened does overlap. The timeline draws them side by side.
    @discardableResult
    func add(
        title: String,
        note: String = "",
        startMinutes: Int,
        durationMinutes: Int,
        colour: DiaryColour = .blu
    ) -> DiaryEntry {
        let duration = DiaryGrid.clampDuration(durationMinutes)
        let entry = DiaryEntry(
            startMinutes: DiaryGrid.clampStart(startMinutes, duration: duration),
            durationMinutes: duration,
            title: title.trimmingCharacters(in: .whitespaces),
            note: note,
            colour: colour
        )
        entries.append(entry)
        entriesChanged()
        return entry
    }

    /// Replaces an entry with an edited copy of itself, matched by identity so a change
    /// of time and title at once still finds the entry it came from.
    func update(_ entry: DiaryEntry) {
        guard let position = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.durationMinutes = DiaryGrid.clampDuration(entry.durationMinutes)
        updated.startMinutes = DiaryGrid.clampStart(entry.startMinutes, duration: updated.durationMinutes)
        updated.title = entry.title.trimmingCharacters(in: .whitespaces)
        entries[position] = updated
        entriesChanged()
    }

    /// Moves an entry to a new start time, keeping its length.
    func move(_ entry: DiaryEntry, toStart start: Int) {
        guard var moved = entries.first(where: { $0.id == entry.id }) else { return }
        moved.startMinutes = DiaryGrid.clampStart(start, duration: moved.durationMinutes)
        update(moved)
    }

    /// Changes an entry's length, keeping its start.
    func resize(_ entry: DiaryEntry, toDuration duration: Int) {
        guard var resized = entries.first(where: { $0.id == entry.id }) else { return }
        let clamped = DiaryGrid.clampDuration(duration)
        resized.durationMinutes = min(clamped, DiaryGrid.dayMinutes - resized.startMinutes)
        update(resized)
    }

    func remove(_ entry: DiaryEntry) {
        entries.removeAll { $0.id == entry.id }
        entriesChanged()
    }

    /// An entry is a click, not a keystroke: it is written at once rather than after
    /// the typing pause, so nothing on the timeline is ever newer than the file.
    private func entriesChanged() {
        entries.sort { $0.startMinutes < $1.startMinutes }
        isDirty = true
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    // MARK: Composing

    /// The sheet's state: a new entry or an existing one, and the fields being edited.
    struct DiaryDraft: Identifiable, Equatable {
        var id: UUID { entry.id }
        var entry: DiaryEntry
        /// False for an entry that is not on the timeline yet, which is what decides
        /// whether the sheet offers "Elimina" and what its title says.
        var isExisting: Bool
    }

    /// Opens the composer on a free-standing new entry.
    ///
    /// The start is where the user clicked, or the next ten-minute mark from now when
    /// the toolbar asked - a diary is usually written about the hour it is.
    func compose(startMinutes: Int? = nil, durationMinutes: Int = 60) {
        let start = startMinutes ?? suggestedStart
        let duration = DiaryGrid.clampDuration(durationMinutes)
        draft = DiaryDraft(
            entry: DiaryEntry(
                startMinutes: DiaryGrid.clampStart(start, duration: duration),
                durationMinutes: duration,
                title: ""
            ),
            isExisting: false
        )
    }

    func edit(_ entry: DiaryEntry) {
        draft = DiaryDraft(entry: entry, isExisting: true)
    }

    /// Commits the sheet: an update when the entry is already on the timeline, an
    /// insertion when it is not.
    func commitDraft() {
        guard let draft else { return }
        if draft.isExisting {
            update(draft.entry)
        } else {
            add(
                title: draft.entry.title,
                note: draft.entry.note,
                startMinutes: draft.entry.startMinutes,
                durationMinutes: draft.entry.durationMinutes,
                colour: draft.entry.colour
            )
        }
        self.draft = nil
    }

    func cancelDraft() { draft = nil }

    /// The current ten-minute mark on the day being shown, or 09:00 on any other day.
    var suggestedStart: Int {
        guard day == .today else { return 9 * 60 }
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let now = (components.hour ?? 9) * 60 + (components.minute ?? 0)
        return DiaryGrid.clampStart(DiaryGrid.snapDown(now), duration: 60)
    }

    // MARK: Timeline geometry

    /// The hours the grid draws: what Impostazioni says, widened to reach every block
    /// on the day.
    ///
    /// The setting says which hours are always there; it does not decide which hours
    /// exist. A block at 05:30 under a window starting at eight would be drawn above
    /// the grid, where nothing is - invisible, and impossible to move back.
    var hours: HourWindow {
        vault.settings.diaryHours.covering(
            startMinutes: entries.map(\.startMinutes),
            endMinutes: entries.map(\.endMinutes)
        )
    }

    var firstHour: Int { hours.first }
    var lastHour: Int { hours.last }

    var placements: [DiaryLayout.Placement] { DiaryLayout.place(entries) }

    /// How much of the day is accounted for, which is the one number a diary is asked
    /// for at the end of an evening.
    var totalMinutes: Int { entries.reduce(0) { $0 + $1.durationMinutes } }
}
