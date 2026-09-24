import Foundation

/// The entry composer: the sheet's draft and the verbs that open, commit and close it.
///
/// Moved out of `DiaryController.swift` for SwiftLint headroom when the serial write door
/// and the origin arrived there (ADR-0057). A pure move: the composer only reaches the
/// controller through `add`/`update`, both internal, so every writer of `prose`,
/// `entries`, `origin` and `saveState` stays in the declaring file under `private(set)`.
extension DiaryController {
    /// The sheet's state: a new entry or an existing one, and the fields being edited.
    struct DiaryDraft: Identifiable, Equatable {
        var id: UUID { entry.id }
        var entry: DiaryEntry
        /// False for an entry that is not on the timeline yet, which is what decides
        /// whether the sheet offers "Elimina" and what its title says.
        var isExisting: Bool
    }

    /// Opens the composer on a free-standing new entry.
    ///
    /// The start is where the user clicked, or the next ten-minute mark from now when
    /// the toolbar asked - a diary is usually written about the hour it is.
    func compose(startMinutes: Int? = nil, durationMinutes: Int = 60) {
        let start = startMinutes ?? suggestedStart
        let duration = DiaryGrid.clampDuration(durationMinutes)
        draft = DiaryDraft(
            entry: DiaryEntry(
                startMinutes: DiaryGrid.clampStart(start, duration: duration),
                durationMinutes: duration,
                title: ""
            ),
            isExisting: false
        )
    }

    func edit(_ entry: DiaryEntry) {
        draft = DiaryDraft(entry: entry, isExisting: true)
    }

    /// Commits the sheet: an update when the entry is already on the timeline, an
    /// insertion when it is not.
    func commitDraft() {
        guard let draft else { return }
        if draft.isExisting {
            update(draft.entry)
        } else {
            add(
                title: draft.entry.title,
                note: draft.entry.note,
                startMinutes: draft.entry.startMinutes,
                durationMinutes: draft.entry.durationMinutes,
                colour: draft.entry.colour
            )
        }
        self.draft = nil
    }

    func cancelDraft() { draft = nil }

    /// The current ten-minute mark on the day being shown, or 09:00 on any other day.
    var suggestedStart: Int {
        guard day == .today else { return 9 * 60 }
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let now = (components.hour ?? 9) * 60 + (components.minute ?? 0)
        return DiaryGrid.clampStart(DiaryGrid.snapDown(now), duration: 60)
    }
}
