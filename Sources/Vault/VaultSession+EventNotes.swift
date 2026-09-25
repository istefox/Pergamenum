import Foundation

/// The note an event gets from the timeline (ADR-0013 §D2, §D3).
///
/// Two writes, in this order: the note itself, then the link in the daily note. The link is
/// second on purpose - a daily note pointing at a file that was never created is a broken
/// wikilink the linter reports, while a note nothing links to is an ordinary note.
extension VaultSession {
    /// Where an event's note lives, whether or not it exists yet.
    func eventNotePath(for eventTitle: String, on day: CalendarDate) -> String {
        let name = NoteName.fileName(for: EventNote.title(for: eventTitle, on: day))
        return settings.dailyFolder.isEmpty ? name : "\(settings.dailyFolder)/\(name)"
    }

    /// An event note, and the write that put a line about it in the day's note.
    struct CreatedEventNote: Sendable {
        let path: String
        /// Nil when the day's note already carried the link, or could not be written. The
        /// caller uses it to put the editor back in step when that note is the one on screen.
        let dailyNote: WriteResult?
    }

    /// The note for an event, created if it is not there, and its path either way.
    ///
    /// Born in the capture shape, `type-note` + `status-inbox` (§D3): a note made by one click
    /// is a stub, and `status-inbox` is what tells the linter to stop asking it for a `topic-*`
    /// until somebody has decided what it is about. The alternative - a sheet asking for the
    /// topic first - makes the note conformant at birth and the feature unused.
    ///
    /// It follows that the stub shows up in the Inbox view, which is the exemption working
    /// rather than a leak: an event note nobody has tagged is exactly something waiting to be
    /// dealt with.
    @discardableResult
    func eventNote(
        for eventTitle: String,
        on day: CalendarDate,
        start: TaskTime? = nil,
        end: TaskTime? = nil,
        attendees: [String] = []
    ) async -> CreatedEventNote? {
        let relativePath = eventNotePath(for: eventTitle, on: day)
        guard !exists(relativePath) else {
            return CreatedEventNote(path: relativePath, dailyNote: nil)
        }

        let title = EventNote.title(for: eventTitle, on: day)
        do {
            try await createNote(
                title: title,
                in: settings.dailyFolder,
                date: day,
                category: .capture,
                body: EventNote.body(
                    eventTitle: eventTitle, start: start, end: end,
                    attendees: attendees, day: day
                )
            )
        } catch {
            recordProblem("nota dell'evento: \(error)")
            return nil
        }

        return CreatedEventNote(
            path: relativePath, dailyNote: await linkFromDailyNote(to: title, on: day)
        )
    }

    /// Adds the wikilink to the day's note, creating that note when it is missing.
    ///
    /// A failure here is reported and swallowed rather than thrown back: the note the user
    /// asked for exists, and refusing the whole gesture because the day's index line could not
    /// be written would destroy the thing that succeeded to report the thing that did not.
    ///
    /// `expecting:` the hash of the read the link was added to (ADR-0057 §D8, #496): a
    /// writer landing in between is refused rather than overwritten, and named as such.
    private func linkFromDailyNote(to title: String, on day: CalendarDate) async -> WriteResult? {
        do {
            let relativePath = try await dailyNote(for: day)
            let existing = try read(relativePath)
            let updated = EventNoteSection.adding(title, to: existing.text)
            guard updated != existing.text else { return nil }
            return try await write(updated, to: relativePath, expecting: existing.record.contentHash)
        } catch let refusal as VaultSession.WriteRefusal {
            recordProblem("collegamento dalla nota del giorno non scritto: \(refusal)")
            return nil
        } catch {
            recordProblem("collegamento dalla nota del giorno: \(error)")
            return nil
        }
    }
}
