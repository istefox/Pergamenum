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
    private(set) var events: [CalendarEvent] = []
    private(set) var reminders: [CalendarReminder] = []
    private(set) var problems: [String] = []

    /// Raised by the Calendario menu; the day view shows the matching sheet.
    var isChoosingDate = false
    var isCreatingEvent = false
    var isCreatingReminder = false

    /// The day view's two filters, both off by default.
    ///
    /// `showsDueTasks` lists what falls due next; `showsCompleted` keeps finished tasks
    /// in the day's list instead of dropping them the moment they are ticked.
    var showsDueTasks = false
    var showsCompleted = false

    private let store: any CalendarStore
    private let vault: VaultController

    init(store: any CalendarStore, vault: VaultController) {
        self.store = store
        self.vault = vault
    }

    func show(_ newDay: CalendarDate) {
        day = newDay
        reload()
    }

    func move(by days: Int) {
        show(day.adding(days: days))
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
        blocks = noteText.map { TimeBlockSection.parse(from: $0, day: day) } ?? []
    }

    /// Opens the daily note for the day shown, creating it from the template when it
    /// does not exist yet.
    func openDailyNote() {
        do {
            _ = try vault.openDailyNote(for: day)
        } catch {
            report("nota del giorno: \(error)")
        }
        reload()
    }

    /// The daily note's text, when it is the note currently open.
    private var noteText: String? {
        guard let note = vault.openNote, note.relativePath.contains(day.compactForm) else { return nil }
        return note.text
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
        write(blocks + [block])
        return block
    }

    func remove(_ block: TimeBlock) {
        write(blocks.filter { $0.id != block.id })
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
        write(blocks.filter { $0.id != block.id } + [published])
        events = store.events(on: day)
        return true
    }

    /// Blocks live in the daily note, so writing them is a note edit like any other.
    private func write(_ newBlocks: [TimeBlock]) {
        let sorted = newBlocks.sorted { $0.startMinutes < $1.startMinutes }
        // Opened here when it is not already, and created from the template when it
        // does not exist. "Blocca" means put this on the day; that the block is stored
        // in the daily note is this app's business, not the user's. Before this the
        // button did nothing at all unless the note happened to be open, and said so
        // only in Impostazioni, Avanzate - which is to say, silently.
        if noteText == nil {
            do {
                _ = try vault.openDailyNote(for: day)
            } catch {
                report("nota del giorno: \(error)")
                return
            }
        }
        guard let text = noteText else {
            report("la nota di \(day.compactForm) non è aperta")
            return
        }
        vault.updateOpenNoteText(TimeBlockSection.write(sorted, into: text))
        vault.saveOpenNote()
        blocks = sorted
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
