import Foundation

/// Time blocks, which live as lines under a `## Timeline` heading in the daily note
/// and nowhere else (SPEC §8.3).
///
/// Every read takes an optional `preferring:` text. The app has an editor that may
/// hold a version of the daily note newer than the file - a block typed by hand and
/// not yet saved - and the timeline beside it must not contradict it. Passing that
/// text in, rather than letting this type reach for it, keeps the buffer where it
/// belongs: a caller with no editor passes nothing and reads the file.
extension VaultSession {
    /// The daily note's text when there is one, without creating anything.
    func dailyNoteText(for day: CalendarDate) -> String? {
        try? read(dailyNotePath(for: day)).text
    }

    /// A day's blocks, read from its note.
    func timeBlocks(on day: CalendarDate, preferring text: String? = nil) -> [TimeBlock] {
        guard let source = text ?? dailyNoteText(for: day) else { return [] }
        return TimeBlockSection.parse(from: source, day: day)
    }

    /// Replaces a day's blocks, creating the daily note when it is missing.
    ///
    /// Writes the file, never the editor. Blocking out a day is not a reason to take the
    /// editor somewhere the user did not ask to go: the day view used to open the daily
    /// note to write a block into it and leave that pane on screen afterwards, which is
    /// how a deleted block kept leaving an empty box behind.
    @discardableResult
    func setTimeBlocks(
        _ blocks: [TimeBlock], on day: CalendarDate, preferring text: String? = nil
    ) async -> WriteOutcome {
        let relativePath = dailyNotePath(for: day)
        // Nothing to write and nothing to write it into: a day with no blocks and no
        // note is a day this app has no business creating a file for.
        if blocks.isEmpty, text ?? dailyNoteText(for: day) == nil { return .unchanged }

        do {
            let (body, expecting) = try await dailyNoteBody(for: day)
            let updated = TimeBlockSection.write(
                blocks.sorted { $0.startMinutes < $1.startMinutes }, into: body
            )
            // `expecting:` (ADR-0043 §D8, Task 9): `body` was read (or just created) by
            // `dailyNoteBody` before this write, straddling the `await` above.
            return .written(try await write(updated, to: relativePath, expecting: expecting))
        } catch is VaultSession.WriteRefusal {
            recordProblem("il giorno non è più dove risultava: \(relativePath)")
            return .stale
        } catch {
            recordProblem("blocchi tempo: \(error)")
            return .failed
        }
    }

    /// A block placed on a day, and the write that put it there.
    struct PlacedBlock: Sendable {
        let block: TimeBlock
        let write: WriteOutcome
    }

    /// Adds a block to a day's timeline, creating the daily note when it is missing.
    ///
    /// Returns the block as it was placed: the requested start is honoured unless
    /// something is already there, in which case it moves on rather than overlapping.
    func addTimeBlock(
        title: String,
        on day: CalendarDate,
        startMinutes: Int,
        durationMinutes: Int? = nil,
        preferring text: String? = nil
    ) async -> PlacedBlock? {
        let duration = durationMinutes ?? settings.blockMinutes
        let existing = timeBlocks(on: day, preferring: text)
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
        let outcome = await setTimeBlocks(existing + [block], on: day, preferring: text)
        return outcome.succeeded ? PlacedBlock(block: block, write: outcome) : nil
    }

    /// The daily note's text, written from the template first when the file is not
    /// there. Same frontmatter `createNote` would give it (SPEC §4.3), so a note born
    /// this way is indistinguishable from one opened with Cmd+T.
    ///
    /// Returns the hash `setTimeBlocks` above should `expecting:` on its own write
    /// (ADR-0043 §D8, Task 9): the existing note's own hash when there was one, or the
    /// hash of the template this call just wrote when there was not - never nil in the
    /// creation case, since by the time this returns the file is no longer new.
    private func dailyNoteBody(for day: CalendarDate) async throws -> (text: String, expecting: String?) {
        let relativePath = dailyNotePath(for: day)
        if let existing = try? read(relativePath) { return (existing.text, existing.record.contentHash) }

        var frontmatter = Frontmatter.empty
        frontmatter.date = day
        frontmatter.tags = TagRules.ordered([Tag(namespace: .type, value: "note")])
        let text = FrontmatterSerializer.render(frontmatter) + "\n"
        try await write(text, to: relativePath)
        return (text, NoteStore.hash(Data(text.utf8)))
    }
}
