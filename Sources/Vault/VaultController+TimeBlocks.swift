import Foundation

/// Time blocks written into a daily note that is not the one on screen.
///
/// The day view writes blocks through `DayController`, which acts on the note it is
/// already showing. A task due next Tuesday at 15:00 has to land in next Tuesday's
/// note, and opening that note to write one line would take the editor away from
/// whatever the user was reading - so these go to the file directly.
extension VaultController {
    /// Where the daily note of a day lives, whether or not it exists yet.
    func dailyNotePath(for day: CalendarDate) -> String {
        let fileName = NoteName.dailyFileName(for: day)
        return settings.dailyFolder.isEmpty ? fileName : "\(settings.dailyFolder)/\(fileName)"
    }

    /// A day's blocks, read from its note.
    ///
    /// From the file, or from the editor buffer when that note happens to be open, so a
    /// block typed by hand and not yet saved is not contradicted by the timeline beside
    /// it.
    func timeBlocks(on day: CalendarDate) -> [TimeBlock] {
        guard let text = dailyNoteText(for: day) else { return [] }
        return TimeBlockSection.parse(from: text, day: day)
    }

    /// Replaces a day's blocks, creating the daily note when it is missing.
    ///
    /// Writes the file, never the editor. Blocking out a day is not a reason to take the
    /// editor somewhere the user did not ask to go: the day view used to open the daily
    /// note to write a block into it and leave that pane on screen afterwards, which is
    /// how a deleted block kept leaving an empty box behind. An editor already showing
    /// that note is kept in step, as the task writes do.
    @discardableResult
    func setTimeBlocks(_ blocks: [TimeBlock], on day: CalendarDate) -> Bool {
        guard let store else { return false }
        let relativePath = dailyNotePath(for: day)
        // Nothing to write and nothing to write it into: a day with no blocks and no
        // note is a day this app has no business creating a file for.
        if blocks.isEmpty, dailyNoteText(for: day) == nil { return true }

        do {
            let body = try dailyNoteBody(for: day)
            let updated = TimeBlockSection.write(
                blocks.sorted { $0.startMinutes < $1.startMinutes }, into: body
            )
            let hash = try store.write(updated, to: relativePath)
            selfWrittenHashes[relativePath] = hash
            index.update(try store.read(relativePath).record, at: relativePath)

            if var note = openNote, note.relativePath == relativePath, !note.hasUnsavedChanges {
                note.text = updated
                note.savedText = updated
                replaceOpenNote(note)
            }
            return true
        } catch {
            recordProblem("blocchi tempo: \(error)")
            return false
        }
    }

    /// Adds a block to a day's timeline, creating the daily note when it is missing.
    ///
    /// Returns the block as it was placed: the requested start is honoured unless
    /// something is already there, in which case it moves on rather than overlapping.
    @discardableResult
    func addTimeBlock(
        title: String,
        on day: CalendarDate,
        startMinutes: Int,
        durationMinutes: Int? = nil
    ) -> TimeBlock? {
        let duration = durationMinutes ?? settings.blockMinutes
        let existing = timeBlocks(on: day)
        guard let start = TimeBlock.freeStart(from: startMinutes, in: existing, duration: duration)
        else {
            recordProblem("blocco tempo: nessuno spazio libero il \(day.compactForm)")
            return nil
        }

        let block = TimeBlock(
            day: day,
            startMinutes: start,
            durationMinutes: duration,
            title: title,
            sourceTaskID: nil,
            isPublished: false
        )
        return setTimeBlocks(existing + [block], on: day) ? block : nil
    }

    /// The daily note's text when there is one, without creating anything.
    private func dailyNoteText(for day: CalendarDate) -> String? {
        let relativePath = dailyNotePath(for: day)
        if let note = openNote, note.relativePath == relativePath { return note.text }
        return try? store?.read(relativePath).text
    }

    /// The daily note's text, written from the template first when the file is not
    /// there. Same frontmatter `createNote` would give it (SPEC §4.3), so a note born
    /// this way is indistinguishable from one opened with Cmd+T.
    private func dailyNoteBody(for day: CalendarDate) throws -> String {
        guard let store else { throw CreationError.alreadyExists("nessun vault aperto") }
        let relativePath = dailyNotePath(for: day)
        if let existing = try? store.read(relativePath) { return existing.text }

        var frontmatter = Frontmatter.empty
        frontmatter.date = day
        frontmatter.tags = TagRules.ordered([Tag(namespace: .type, value: "note")])
        let text = FrontmatterSerializer.render(frontmatter) + "\n"
        let hash = try store.write(text, to: relativePath)
        selfWrittenHashes[relativePath] = hash
        index.update(try store.read(relativePath).record, at: relativePath)
        return text
    }
}
