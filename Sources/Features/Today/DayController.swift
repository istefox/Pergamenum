import Foundation
import Observation

/// The logic of the day view: blocks, events and reminders for one day.
///
/// Separated from the view so it can be exercised against a stub `CalendarStore`.
/// EventKit itself needs a permission dialog only a person can answer, but everything
/// this app does *around* EventKit - deciding what to publish, writing the block back
/// into the note, leaving the note alone when the store refuses - is ordinary logic
/// and has no excuse for being untested.
@MainActor
@Observable
final class DayController {
    private(set) var day: CalendarDate = .today
    private(set) var blocks: [TimeBlock] = []
    /// The days the week and the month draw, empty at the day scale (ADR-0013 §D4).
    private(set) var columns: [DayColumn] = []
    private(set) var events: [CalendarEvent] = []
    private(set) var reminders: [CalendarReminder] = []
    private(set) var problems: [String] = []

    /// Which of the three scales the day view is showing. All three are anchored on
    /// `day`, so switching back to the day lands on the day the week had highlighted.
    var scale: DayScale = .day {
        didSet {
            guard oldValue != scale else { return }
            reload()
        }
    }

    /// Raised by the Calendario menu; the day view shows the matching sheet.
    var isChoosingDate = false
    var isCreatingEvent = false
    var isCreatingReminder = false

    /// The day view's two filters, both off by default.
    ///
    /// `showsDueTasks` lists what falls due next; `showsCompleted` keeps finished tasks
    /// in the day's list instead of dropping them the moment they are ticked.
    var showsDueTasks = false
    /// The week and the month keep their columns rather than recomputing them on every
    /// draw, so this filter has to say when it moved: the day view rereads the index
    /// each time it is laid out, and the two scales do not.
    var showsCompleted = false {
        didSet {
            guard oldValue != showsCompleted, scale != .day else { return }
            reload()
        }
    }

    /// What the last drop did, until it is dismissed. The banner the week and the day
    /// draw from it is the way back: a write nobody was asked to confirm has to say what
    /// it did and offer to undo it (ADR-0013 §D5, the shape ADR-0009 §D5 gave the board).
    var lastDrop: Drop?

    /// What a drag left behind.
    struct Drop: Equatable, Sendable {
        var summary: String
        var journalID: String?
        var isRefusal: Bool
    }

    private let store: any CalendarStore
    /// Not private: the drop of ADR-0013 §D5 lives in `DayController+TaskDrop.swift`,
    /// and a `private` here is file-scoped, which would have kept it in this file for
    /// no reason but the keyword.
    let vault: VaultController
    /// The tail of `write`'s own write Tasks, chained so a new one always waits for the
    /// previous to finish before it applies its own value to `blocks` (ADR-0043
    /// follow-up): overlapping writes used to complete out of order, and whichever
    /// finished last won, silently dropping an earlier-issued write - `publishAllBlocks`
    /// looping over several `publish` calls in a row hit this every time.
    private var pendingWrite: Task<Void, Never>?

    init(store: any CalendarStore, vault: VaultController) {
        self.store = store
        self.vault = vault
    }

    /// Whether the last day change was one scrolled past rather than one gone to
    /// (ADR-0015 §D3).
    ///
    /// Read by the window's history, which sees *that* the day moved and never *how*: five
    /// presses of the week chevron must leave one history entry, and a jump to a date must
    /// leave one too. Only the caller knows which of the two happened, so the caller says.
    ///
    /// **A description of the last change and not a flag held during it.** The observer runs
    /// on the view update after the change, not inside it, so anything set and cleared around
    /// `show` would already be false by the time it was read - the same timing that decided
    /// ADR-0015 §D4. This is simply true until the next `show` that is not a scroll, which is
    /// exactly as long as it means anything.
    private(set) var lastDayMoveWasDrift = false

    func show(_ newDay: CalendarDate) {
        day = newDay
        lastDayMoveWasDrift = false
        reload()
    }

    /// Moves by one unit of the scale being shown: a day, a week, a month.
    ///
    /// What the toolbar's two chevrons and the Calendario menu's `Cmd+←` both call. A
    /// week that paged a day at a time would be a week with a day view's navigator.
    func moveSpan(by steps: Int) {
        show(scale.anchor(day, movedBy: steps))
        lastDayMoveWasDrift = true
    }

    /// Reads everything the day view shows, including the reminder fetch that has no
    /// synchronous form.
    func load() async {
        await store.refreshReminders(on: day)
        reload()
    }

    func reload() {
        events = store.events(on: day)
        reminders = store.reminders(dueOn: day)
        blocks = vault.timeBlocks(on: day)
        columns = scale == .day ? [] : span()
    }

    /// The seven or thirty-five days the week and the month draw, each with its four
    /// sources in the one order (ADR-0013 §D4).
    ///
    /// The events come in one fetch for the whole span rather than one per day, and the
    /// blocks are read only from the days that have a note to read them from: a month
    /// otherwise opens forty-two files to find nothing in most of them.
    private func span() -> [DayColumn] {
        let days = scale == .week
            ? WeekPlan.week(containing: day)
            : WeekPlan.monthWeeks(of: day).flatMap { $0 }
        guard let first = days.first, let last = days.last else { return [] }

        let eventsByDay = store.events(from: first, through: last)
        let tasks = vault.index.allTasks.filter { showsCompleted || $0.state.isOpen }

        return days.map { date in
            // The index is already a dictionary keyed by relative path, so the daily
            // note's presence is one lookup - no Set of every path in the vault.
            let hasNote = vault.index.note(at: vault.dailyNotePath(for: date)) != nil
            return DayColumn(
                day: date,
                entries: WeekPlan.entries(
                    on: date,
                    events: eventsByDay[date] ?? [],
                    blocks: hasNote ? vault.timeBlocks(on: date) : [],
                    tasks: tasks
                ),
                hasNote: hasNote
            )
        }
    }

    /// Opens the daily note for the day shown, creating it from the template when it
    /// does not exist yet.
    func openDailyNote() {
        Task { @MainActor in
            do {
                _ = try await vault.openDailyNote(for: day)
            } catch {
                report("nota del giorno: \(error)")
            }
            reload()
        }
    }

    // MARK: Blocks

    /// Turns a task into a block at the first free slot from `preferredStart`.
    ///
    /// The task's own hour wins when it has one: a task due at 15:00 blocked out at
    /// nine in the morning is a plan for a different day than the one written down.
    /// The duration is the one set in Impostazioni (SPEC §8.3's 30 minutes by default).
    @discardableResult
    func addBlock(from task: TaskItem, preferredStart: Int? = nil) -> TimeBlock? {
        let preferred = preferredStart
            ?? task.scheduledTime?.minutes
            ?? task.dueTime?.minutes
            ?? 9 * 60
        let duration = vault.settings.blockMinutes
        guard let start = TimeBlock.freeStart(from: preferred, in: blocks, duration: duration)
        else { return nil }

        let block = TimeBlock(
            day: day,
            startMinutes: start,
            durationMinutes: duration,
            title: task.text,
            sourceTaskID: task.id,
            isPublished: false
        )
        write { $0 + [block] }
        return block
    }

    /// Moves a block to another hour of the same day (SPEC §8.3).
    ///
    /// **The task the block came from does not move with it.** A block carries
    /// `sourceTaskID`, so rewriting its `>2026-08-20 15:00` to the new hour is one
    /// lookup away - and it would be a second write, in a second file, with no gesture
    /// behind it, which is the thing ADR-0013 §D1 refuses in the same breath as
    /// rollover. The block is the plan for the day; the `>` marker is the schedule.
    /// Dragging the task onto the hour again is how both move.
    @discardableResult
    func move(_ block: TimeBlock, toStart start: Int) -> Bool {
        let others = blocks.filter { $0.id != block.id }
        guard let moved = TimeBlock.moved(block, toStart: start, among: others) else {
            report("blocco tempo: nessuno spazio libero il \(day.compactForm)")
            return false
        }
        guard moved.startMinutes != block.startMinutes else { return false }
        write { $0.filter { $0.id != block.id } + [moved] }
        return true
    }

    /// Changes how long a block lasts, keeping the hour it starts at.
    @discardableResult
    func resize(_ block: TimeBlock, toDuration duration: Int) -> Bool {
        let others = blocks.filter { $0.id != block.id }
        let resized = TimeBlock.resized(block, toDuration: duration, among: others)
        guard resized.durationMinutes != block.durationMinutes else { return false }
        write { $0.filter { $0.id != block.id } + [resized] }
        return true
    }

    func remove(_ block: TimeBlock) {
        write { $0.filter { $0.id != block.id } }
    }

    /// Writes a block to the Apple calendar and marks it published in the note.
    ///
    /// The note is only updated after the event is created: marking a block published
    /// when the write failed would tell the user their day is on their calendar when
    /// it is not.
    @discardableResult
    func publish(_ block: TimeBlock, toCalendarTitled calendarTitle: String? = nil) -> Bool {
        guard !block.isPublished else { return false }
        guard let start = EventKitStore.date(day, hour: block.startMinutes / 60,
                                             minute: block.startMinutes % 60),
              let end = EventKitStore.date(day, hour: block.endMinutes / 60,
                                           minute: block.endMinutes % 60)
        else { return false }

        do {
            _ = try store.createEvent(
                title: block.title, start: start, end: end, calendarTitle: calendarTitle
            )
        } catch {
            report("pubblicazione del blocco: \(error)")
            return false
        }

        var published = block
        published.isPublished = true
        write { $0.filter { $0.id != block.id } + [published] }
        events = store.events(on: day)
        return true
    }

    /// Blocks live in the daily note's `## Timeline` section, so writing them is a write
    /// to that file - and only to that file.
    ///
    /// "Blocca" means put this on the day; where the block is stored is this app's
    /// business, not the user's, and neither is the note it goes into. Writing it used
    /// to go through the editor: the day view opened the daily note to edit its buffer,
    /// which left an editor pane on screen that nobody had asked for and that outlived
    /// the block itself.
    ///
    /// `change` computes the array actually written from `blocks` as it stands right
    /// before *this* write's own turn comes up, not from whatever `blocks` held back
    /// when the caller made the call (ADR-0043 follow-up).
    ///
    /// The refusal branch moves inside the hop rather than being dropped (ADR-0043
    /// §D2): `blocks` must only take the new value once the file actually holds it.
    ///
    /// Chained onto `pendingWrite` rather than fired independently: several calls to
    /// `write` in a row - `publishAllBlocks` looping over `publish` is the case that
    /// surfaced it - used to each start their own detached Task computing its merge
    /// against the same stale `blocks`, so whichever finished last silently reverted
    /// every publish flag the others had just set. Awaiting `previous` first, then
    /// reading `blocks` fresh inside the Task, makes each write see every write ahead
    /// of it in the queue - not just complete after them.
    private func write(_ change: @escaping ([TimeBlock]) -> [TimeBlock]) {
        let previous = pendingWrite
        pendingWrite = Task { @MainActor in
            await previous?.value
            let sorted = change(blocks).sorted { $0.startMinutes < $1.startMinutes }
            guard await vault.setTimeBlocks(sorted, on: day) else {
                report("blocchi tempo del \(day.compactForm): scrittura non riuscita")
                return
            }
            blocks = sorted
        }
    }

    /// Records a failure both here, where a test can see it, and on the vault, which is
    /// the banner the user actually reads.
    private func report(_ message: String) {
        problems.append(message)
        vault.recordProblem(message)
    }

    /// Publishes every block that is not on the calendar yet (SPEC §10, Calendario).
    ///
    /// Reports how many went and how many did not, rather than stopping at the first
    /// failure: a calendar that refused one event has no reason to refuse the rest.
    @discardableResult
    func publishAllBlocks(toCalendarTitled calendarTitle: String? = nil) -> Int {
        var published = 0
        for block in blocks where !block.isPublished {
            // Re-read from `blocks` each time: publishing rewrites the array.
            guard let current = blocks.first(where: { $0.id == block.id }), !current.isPublished
            else { continue }
            if publish(current, toCalendarTitled: calendarTitle) { published += 1 }
        }
        return published
    }

    /// Creates an event on the day being shown (SPEC §10, Calendario › Nuovo evento).
    @discardableResult
    func createEvent(
        title: String,
        startMinutes: Int,
        durationMinutes: Int,
        calendarTitle: String? = nil
    ) -> Bool {
        guard let start = EventKitStore.date(day, hour: startMinutes / 60, minute: startMinutes % 60),
              let end = EventKitStore.date(
                  day,
                  hour: (startMinutes + durationMinutes) / 60,
                  minute: (startMinutes + durationMinutes) % 60
              )
        else { return false }

        do {
            _ = try store.createEvent(title: title, start: start, end: end, calendarTitle: calendarTitle)
            events = store.events(on: day)
            return true
        } catch {
            report("nuovo evento: \(error)")
            return false
        }
    }

    /// Creates a reminder due on the day being shown.
    @discardableResult
    func createReminder(title: String, listTitle: String? = nil) -> Bool {
        do {
            _ = try store.createReminder(title: title, due: day, listTitle: listTitle)
            reminders = store.reminders(dueOn: day)
            return true
        } catch {
            report("nuovo promemoria: \(error)")
            return false
        }
    }

    // MARK: Reminders

    /// Toggles a reminder in the Reminders app (SPEC §8.2, two-way).
    @discardableResult
    func toggle(_ reminder: CalendarReminder) -> Bool {
        do {
            try store.setCompleted(!reminder.isCompleted, reminderID: reminder.id)
            reminders = store.reminders(dueOn: day)
            return true
        } catch {
            report("promemoria: \(error)")
            return false
        }
    }
}
