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
    func setTimeBlocks(_ blocks: [TimeBlock], on day: CalendarDate) -> Bool {
        guard let session else { return false }
        let outcome = session.setTimeBlocks(
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
    ) -> TimeBlock? {
        guard let session else { return nil }
        guard let placed = session.addTimeBlock(
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
