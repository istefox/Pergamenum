import Foundation

/// Time blocks written into a daily note that is not the one on screen.
///
/// The day view writes blocks through `DayController`, which acts on the note it is
/// already showing. A task due next Tuesday at 15:00 has to land in next Tuesday's
/// note, and opening that note to write one line would take the editor away from
/// whatever the user was reading - so these go to the file directly.
///
/// The work is on `VaultSession` (ADR-0007 §D3). What this adds is the editor: the
/// buffer is handed down as `preferring:` so an unsaved block is not contradicted by
/// the timeline, and the buffer is put back in step after a write.
extension VaultController {
    /// Where the daily note of a day lives, whether or not it exists yet.
    func dailyNotePath(for day: CalendarDate) -> String {
        session?.dailyNotePath(for: day) ?? NoteName.dailyFileName(for: day)
    }

    /// The editor's copy of a note, when it is showing that one. Nil otherwise, which
    /// is what sends the session to the file.
    func bufferText(for relativePath: String) -> String? {
        guard let note = openNote, note.relativePath == relativePath else { return nil }
        return note.text
    }

    /// A day's blocks, from the file or from the editor buffer when that note happens
    /// to be open.
    func timeBlocks(on day: CalendarDate) -> [TimeBlock] {
        guard let session else { return [] }
        return session.timeBlocks(on: day, preferring: bufferText(for: dailyNotePath(for: day)))
    }

    /// Replaces a day's blocks, creating the daily note when it is missing.
    @discardableResult
    func setTimeBlocks(_ blocks: [TimeBlock], on day: CalendarDate) async -> Bool {
        guard let session else { return false }
        let outcome = await session.setTimeBlocks(
            blocks, on: day, preferring: bufferText(for: dailyNotePath(for: day))
        )
        if let result = outcome.result { syncOpenNote(with: result) }
        return outcome.succeeded
    }

    /// Adds a block to a day's timeline, creating the daily note when it is missing.
    @discardableResult
    func addTimeBlock(
        title: String,
        on day: CalendarDate,
        startMinutes: Int,
        durationMinutes: Int? = nil
    ) async -> TimeBlock? {
        guard let session else { return nil }
        guard let placed = await session.addTimeBlock(
            title: title,
            on: day,
            startMinutes: startMinutes,
            durationMinutes: durationMinutes,
            preferring: bufferText(for: dailyNotePath(for: day))
        ) else { return nil }

        if let result = placed.write.result { syncOpenNote(with: result) }
        return placed.block
    }
}

/// The note an event gets from the timeline (ADR-0013 §D2).
///
/// Here rather than in `DayController` for the reason ADR-0007 §D3 gives: the write belongs to
/// the vault and the day view is one of its callers, not its owner.
extension VaultController {
    /// Where an event's note lives, whether or not it exists yet.
    func eventNotePath(for eventTitle: String, on day: CalendarDate) -> String? {
        session?.eventNotePath(for: eventTitle, on: day)
    }

    /// Whether that note is already there, which is what turns the offer into a link: a second
    /// click on "Nota per questo evento" would otherwise be a second note.
    func hasEventNote(for eventTitle: String, on day: CalendarDate) -> Bool {
        guard let path = eventNotePath(for: eventTitle, on: day) else { return false }
        return index.note(at: path) != nil
    }

    /// Creates the note if it is missing and opens it either way.
    @discardableResult
    func openEventNote(
        for eventTitle: String,
        on day: CalendarDate,
        start: TaskTime? = nil,
        end: TaskTime? = nil,
        attendees: [String] = []
    ) async -> String? {
        guard let session else { return nil }
        guard let created = await session.eventNote(
            for: eventTitle, on: day, start: start, end: end, attendees: attendees
        ) else { return nil }
        // The day's note gained a line, and it may be the one the editor is showing.
        if let write = created.dailyNote { syncOpenNote(with: write) }
        openNote(at: created.path)
        return created.path
    }
}
