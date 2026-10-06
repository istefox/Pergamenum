import Foundation

/// The opens that bring the person to a place: today's note, an event's note, the Tags pane on
/// one tag, the Oggi pane on one day (n1-seams R-09, R-10, R-12, R-13). Pane changes live on
/// `CommandActions` in the shape of `open(link:)`, and not in the views that ask for them.
extension CommandActions {
    /// Today's note, in the Note pane (Cmd+Shift+D, n1-seams R-09), created when missing.
    ///
    /// The pane is read at the keypress and changed only after the note is open, and only if
    /// it is still the one read (ADR-0043 §D7): a person who moved elsewhere during the write
    /// is not pulled back. From Oggi nothing switches, because Oggi already shows the day's note.
    /// A failure keeps the sentence `.dailyNote` always reported and switches nothing.
    func openTodayNote() async {
        let paneAtKeypress = navigation.pane
        do {
            _ = try await vault.openDailyNote(for: .today)
        } catch {
            vault.recordProblem("nota del giorno: \(error)")
            return
        }
        guard paneAtKeypress != .today, navigation.pane == paneAtKeypress else { return }
        navigation.pane = .notes
    }

    /// An event's note, created when missing, in the Note pane (n1-seams R-10). The pane
    /// changes only after the note is open, and only if it is still the one read before the
    /// write, for `openTodayNote`'s reason.
    @discardableResult
    func openEventNote(
        for eventTitle: String,
        on day: CalendarDate,
        start: TaskTime?,
        end: TaskTime?,
        attendees: [String]
    ) async -> String? {
        let paneBefore = navigation.pane
        let path = await vault.openEventNote(
            for: eventTitle, on: day, start: start, end: end, attendees: attendees
        )
        if path != nil, navigation.pane == paneBefore { navigation.pane = .notes }
        return path
    }

    /// The Tags pane narrowed to one tag (a Cmd+clicked `#tag`, n1-seams R-12).
    func open(tag: Tag) {
        navigation.showTag(tag)
    }

    /// The Oggi pane on one day, at the scale it already has (a Cmd+clicked `>date`, n1-seams
    /// R-13): the history's own `.day` destination, so the jump is the one «Indietro» returns to.
    func open(day date: CalendarDate) {
        WindowPlace(navigation: navigation, vault: vault, day: day).apply(.day(date, day.scale))
    }
}
