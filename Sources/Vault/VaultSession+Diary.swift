import Foundation

/// The diary's file, read and written whole.
///
/// A diary note is an ordinary note in an ordinary folder: `Diario/20260814.md`, with
/// the day's prose above and the `## Diario` section below. The diary never goes
/// through the editor's open-note buffer, so writing an entry cannot take the Note pane
/// somewhere the user did not ask to go - the same rule the time blocks learned.
///
/// Because it holds the file in memory for as long as a person is writing, the read says
/// what it found on disk and the write proves it is still replacing that (ADR-0057 §D1,
/// §D3): another writer's change in between - another process, or in the
/// `diaryFolder == dailyFolder` setup this app's own capture panel, time blocks or event
/// notes - is refused as `.stale`, never overwritten.
extension VaultSession {
    /// What the diary's file held on disk when it was read (ADR-0057 §D1) - the claim
    /// `writeDiary`'s `over:` parameter checks the write against.
    enum DiaryDiskState: Equatable, Sendable {
        case absent
        case present(hash: String)
    }

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
    ///
    /// `disk` comes from the same read as the text (ADR-0057 §D1): `.present(hash:)`
    /// when the file was read, `.absent` when it was not - read even when `preferring:`
    /// supplies the text, since `disk` is a claim about the bytes on disk, not about the
    /// buffer. A file that exists but cannot be read (not UTF-8) also reports `.absent`;
    /// the write door's `expectingAbsent:` tests existence, so a write over it is refused
    /// rather than overwriting what could not be read.
    func readDiary(
        on day: CalendarDate, preferring text: String? = nil
    ) -> (prose: String, entries: [DiaryEntry], disk: DiaryDiskState)? {
        let onDisk = try? read(diaryNotePath(for: day))
        let disk: DiaryDiskState = onDisk.map { .present(hash: $0.record.contentHash) } ?? .absent
        guard let source = text ?? onDisk?.text else { return nil }
        let split = DiarySection.split(source)
        return (prose: split.prose, entries: split.entries, disk: disk)
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

    /// Writes a day's diary, creating the file and its folder when they are missing - but
    /// only over the disk state it was derived from.
    ///
    /// `over:` is mandatory (ADR-0057 §D3): the disk state `readDiary` returned for the same
    /// day, or what the caller's last write left there. `.present(h)` writes with
    /// `expecting: h`; `.absent` writes with `expectingAbsent: true`, so a file another
    /// writer created meanwhile is refused rather than erased. A refusal answers `.stale`
    /// and records **no** problem - the caller enters its own conflict and records it once
    /// there. Any other failure records one and answers `.failed`.
    @discardableResult
    func writeDiary(
        prose: String, entries: [DiaryEntry], on day: CalendarDate, over disk: DiaryDiskState
    ) async -> WriteOutcome {
        let relativePath = diaryNotePath(for: day)
        let text = DiarySection.write(entries, into: prose)
        do {
            switch disk {
            case .present(let hash):
                return .written(try await write(text, to: relativePath, expecting: hash))
            case .absent:
                return .written(try await write(text, to: relativePath, expectingAbsent: true))
            }
        } catch is VaultWriteRefusal {
            return .stale
        } catch {
            recordProblem("diario del \(day.compactForm): \(error)")
            return .failed
        }
    }
}
