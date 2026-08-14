import Foundation

/// The diary's file, read and written whole.
///
/// A diary note is an ordinary note in an ordinary folder: `Diario/20260814.md`, with
/// the day's prose above and the `## Diario` section below. The diary never goes
/// through the editor's open-note buffer, so writing an entry cannot take the Note pane
/// somewhere the user did not ask to go - the same rule the time blocks learned.
extension VaultController {
    /// Where the diary of a day lives, whether or not it exists yet.
    func diaryNotePath(for day: CalendarDate) -> String {
        let fileName = NoteName.dailyFileName(for: day)
        return settings.diaryFolder.isEmpty ? fileName : "\(settings.diaryFolder)/\(fileName)"
    }

    /// A day's diary, or nil when nothing has been written for that day yet.
    ///
    /// From the editor buffer when that note happens to be open, so a line typed by
    /// hand and not yet saved is not contradicted by the timeline beside it.
    func readDiary(on day: CalendarDate) -> (prose: String, entries: [DiaryEntry])? {
        let relativePath = diaryNotePath(for: day)
        if let note = openNote, note.relativePath == relativePath {
            return DiarySection.split(note.text)
        }
        guard let text = try? store?.read(relativePath).text else { return nil }
        return DiarySection.split(text)
    }

    /// What a diary note contains before anything has been written into it: the same
    /// frontmatter `createNote` would give it (SPEC §4.3), so a note born this way is
    /// indistinguishable from one made with Cmd+N.
    func emptyDiaryNote(for day: CalendarDate) -> String {
        var frontmatter = Frontmatter.empty
        frontmatter.date = day
        frontmatter.tags = TagRules.ordered([Tag(namespace: .type, value: "note")])
        return FrontmatterSerializer.render(frontmatter) + "\n"
    }

    /// Writes a day's diary, creating the file and its folder when they are missing.
    @discardableResult
    func writeDiary(prose: String, entries: [DiaryEntry], on day: CalendarDate) -> Bool {
        guard let store else { return false }
        let relativePath = diaryNotePath(for: day)
        let text = DiarySection.write(entries, into: prose)

        do {
            let hash = try store.write(text, to: relativePath)
            selfWrittenHashes[relativePath] = hash
            index.update(try store.read(relativePath).record, at: relativePath)

            // An editor already showing this note is kept in step, as the task writes
            // do. With unsaved changes of its own it is left alone: the buffer is the
            // user's work and ADR-0001 §D3.4 says to ask rather than to merge.
            if var note = openNote, note.relativePath == relativePath, !note.hasUnsavedChanges {
                note.text = text
                note.savedText = text
                replaceOpenNote(note)
            }
            return true
        } catch {
            recordProblem("diario del \(day.compactForm): \(error)")
            return false
        }
    }
}
