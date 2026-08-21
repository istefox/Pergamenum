import Foundation

/// What a click on a row of the week or the month goes to.
///
/// Four sources, four destinations, and the destination is always the place the thing
/// can be *changed* rather than the place it is mentioned:
///
/// - a **task** or a **deadline** is a line of markdown, so it opens its note with the
///   caret on that line. Opening the file at the top and leaving the reader to find the
///   line is what the app did everywhere until now, and in a grid of one-line rows it
///   reads as a click that did nothing.
/// - a **time block** and an **event** live on the day's timeline, so they take the view
///   to that day at the day scale, which is where a block is moved, published or removed.
///   A block is written in the daily note's `## Timeline`, but that section is this app's
///   business and not a place to drop somebody (`DayController.write`).
///
/// A type of its own rather than a method on each grid: the week and the month ask the
/// same question, and two copies of the answer is one copy that drifts.
@MainActor
struct DayEntryReveal {
    let vault: VaultController
    let navigation: Navigation
    let controller: DayController

    func callAsFunction(_ entry: WeekEntry, on day: CalendarDate) {
        switch entry.kind {
        case .task, .deadline:
            openNote(entry)
        case .block, .event:
            controller.show(day)
            controller.scale = .day
        }
    }

    private func openNote(_ entry: WeekEntry) {
        guard let path = entry.sourcePath else { return }
        vault.openChosenNote(at: path)

        // One turn later, so the column has the note before the jump reaches it. Sent in
        // the same pass, the jump arrives at a text view still showing the note you came
        // from and puts the caret on whatever is at that offset - the lesson
        // `VaultBrowser` paid for with its heading jump.
        Task { @MainActor in
            navigation.pane = .notes
            guard let line = entry.lineIndex,
                  let text = vault.openNote?.text,
                  let range = NoteJump.lineRange(line, in: text)
            else { return }
            // The line number comes from the index, which is a snapshot: a note edited
            // since the last scan can be shorter than it was. `lineRange` answers nil
            // rather than guessing, and the note still opens - it is the caret that is
            // dropped, not the navigation.
            navigation.jumpToLine(
                range: NSRange(range, in: text),
                ordinal: NoteJump.ordinal(of: range.lowerBound, in: text)
            )
        }
    }
}
