import Foundation

/// The diary's file, read and written whole.
///
/// A diary note is an ordinary note in an ordinary folder: `Diario/20260814.md`, with
/// the day's prose above and the `## Diario` section below. The diary never goes
/// through the editor's open-note buffer, so writing an entry cannot take the Note pane
/// somewhere the user did not ask to go - the same rule the time blocks learned.
extension VaultSession {
    /// Where the diary of a day lives, whether or not it exists yet.
    func diaryNotePath(for day: CalendarDate) -> String {
        let fileName = NoteName.dailyFileName(for: day)
        return settings.diaryFolder.isEmpty ? fileName : "\(settings.diaryFolder)/\(fileName)"
    }

    /// A day's diary, or nil when nothing has been written for that day yet.
    ///
    /// `preferring:` is the editor's copy when it happens to be showing that note, so a
    /// line typed by hand and not yet saved is not contradicted by the timeline beside
    /// it. See the note on `VaultSession+TimeBlocks` for why it arrives as an argument.
    func readDiary(
        on day: CalendarDate, preferring text: String? = nil
    ) -> (prose: String, entries: [DiaryEntry])? {
        guard let source = text ?? (try? read(diaryNotePath(for: day)).text) else { return nil }
        return DiarySection.split(source)
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
    func writeDiary(prose: String, entries: [DiaryEntry], on day: CalendarDate) async -> WriteOutcome {
        let relativePath = diaryNotePath(for: day)
        do {
            return .written(try await write(DiarySection.write(entries, into: prose), to: relativePath))
        } catch {
            recordProblem("diario del \(day.compactForm): \(error)")
            return .failed
        }
    }
}
