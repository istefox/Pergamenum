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
        guard let store else { return nil }
        let relativePath = dailyNotePath(for: day)
        let duration = durationMinutes ?? settings.blockMinutes

        do {
            let body = try dailyNoteBody(for: day)
            let existing = TimeBlockSection.parse(from: body, day: day)
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
            let updated = TimeBlockSection.write(
                (existing + [block]).sorted { $0.startMinutes < $1.startMinutes }, into: body
            )
            let hash = try store.write(updated, to: relativePath)
            selfWrittenHashes[relativePath] = hash
            index.update(try store.read(relativePath).record, at: relativePath)

            // Keep an editor showing that note in step, as the task writes do.
            if var note = openNote, note.relativePath == relativePath, !note.hasUnsavedChanges {
                note.text = updated
                note.savedText = updated
                replaceOpenNote(note)
            }
            return block
        } catch {
            recordProblem("blocco tempo: \(error)")
            return nil
        }
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
