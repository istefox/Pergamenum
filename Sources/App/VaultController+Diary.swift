import Foundation

/// The diary as the app asks for it.
///
/// The file work is on `VaultSession` (ADR-0007 §D3); what is here is the editor's
/// side of it, exactly as the time blocks have it.
extension VaultController {
    /// Where the diary of a day lives, whether or not it exists yet.
    func diaryNotePath(for day: CalendarDate) -> String {
        session?.diaryNotePath(for: day) ?? NoteName.dailyFileName(for: day)
    }

    /// A day's diary, or nil when nothing has been written for that day yet.
    func readDiary(on day: CalendarDate) -> (prose: String, entries: [DiaryEntry])? {
        guard let session else { return nil }
        return session.readDiary(on: day, preferring: bufferText(for: diaryNotePath(for: day)))
    }

    /// What a diary note contains before anything has been written into it.
    func emptyDiaryNote(for day: CalendarDate) -> String {
        session?.emptyDiaryNote(for: day) ?? ""
    }

    /// Writes a day's diary, creating the file and its folder when they are missing.
    @discardableResult
    func writeDiary(prose: String, entries: [DiaryEntry], on day: CalendarDate) async -> Bool {
        guard let session else { return false }
        let outcome = await session.writeDiary(prose: prose, entries: entries, on: day)
        if let result = outcome.result { syncOpenNote(with: result) }
        return outcome.succeeded
    }
}
