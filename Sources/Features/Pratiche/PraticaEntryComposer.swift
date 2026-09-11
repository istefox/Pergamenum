import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 -
// R-28, R-29; ADR §D5, §D13.
//
// «Nota», «Telefonata» and «Inserisci qui»: the two writes §D5 allows the timeline to
// make, and nothing else.
//
//   1. one heading appended to `pratica.md`, through one `VaultSession.write`
//   2. one line appended to that day's daily note, unless «Scrivi nel diario» is off
//
// Then the caret goes to the new body line through `Navigation.jumpToLine(range:
// ordinal:)` (§D13): **the timeline never writes a text range and never hosts a text
// view over `pratica.md`** - the note opens in the one editor this app has, which is
// the whole of why the blueprint's inline row editor was rejected.
@MainActor
struct PraticaEntryComposer {
    let pratiche: PraticheController
    let vault: VaultController
    let navigation: Navigation

    /// «Nota» / «Telefonata» at the bottom of the timeline: now, which is what the two
    /// buttons in the counts bar mean.
    func append(_ kind: PraticaEntry.Kind) {
        insert(kind, at: Date())
    }

    /// «Inserisci qui» (R-28): the midpoint between the two rows the gap sits between,
    /// so the entry reads back in the place a person put it. `PraticaEntry.midpoint`
    /// owns the arithmetic; this only says which two rows are the neighbours.
    func insertBetween(_ first: PraticaTimelineEntry, and second: PraticaTimelineEntry, kind: PraticaEntry.Kind) {
        insert(kind, at: PraticaEntry.midpoint(between: first.date, and: second.date))
    }

    /// The one write path both of the above go through.
    func insert(_ kind: PraticaEntry.Kind, at timestamp: Date) {
        guard let praticaPath = pratiche.selection,
              let pratica = pratiche.selectedPratica,
              let session = vault.session
        else { return }

        let notePath = PraticaCommandActions.praticaNotePath(of: praticaPath)
        // The same refusal every file operation makes (`VaultController+Files`): a
        // tab holding unsaved edits to this note is asked to save first, never
        // merged with and never discarded - the hand-off below reloads that tab.
        guard vault.canOperate(on: notePath) else { return }
        let counterpart = counterpart(of: praticaPath, fallback: pratica.client)
        do {
            let source = try session.read(notePath).text
            let insertion = PraticaEntry.insert(
                kind: kind, at: timestamp, counterpart: counterpart, in: source
            )
            try session.write(insertion.text, to: notePath)
            mirror(kind, of: pratica, counterpart: counterpart, on: timestamp, session: session)
            pratiche.reloadTimeline(from: vault)
            handOff(insertion, notePath: notePath)
        } catch {
            pratiche.report("La voce non è stata scritta in «\(notePath)»: \(error.localizedDescription)")
        }
    }

    /// R-29: exactly one line in that day's daily note, and none at all when «Scrivi
    /// nel diario» is off - `DailyNoteMirror.appending` answers `nil` for the second
    /// case, which is what keeps this from writing a file back unchanged.
    ///
    /// The day is the entry's own timestamp and not today: an «Inserisci qui» entry
    /// belongs to the day it is dated, or the diary would say a call happened on the
    /// afternoon somebody typed it up.
    private func mirror(
        _ kind: PraticaEntry.Kind, of pratica: PraticaListItem, counterpart: String,
        on timestamp: Date, session: VaultSession
    ) {
        guard vault.settings.pratiche.mirrorsToDailyNote else { return }
        let entry = DailyNoteMirror.Entry(
            praticaTitle: pratica.title, kind: kind, counterpart: counterpart
        )
        do {
            let path = try session.dailyNote(for: CalendarDate(timestamp))
            let existing = try session.read(path).text
            guard let updated = DailyNoteMirror.appending(
                entry, to: existing, isEnabled: vault.settings.pratiche.mirrorsToDailyNote
            ) else { return }
            try session.write(updated, to: path)
        } catch {
            // The heading is already on disk and that is the entry: a diary line that
            // could not be written is reported, never rolled back into a lost entry.
            pratiche.report("La riga nel diario non è stata scritta: \(error.localizedDescription)")
        }
    }

    /// §D13's editing path: the note opens in the real editor with the caret on the new
    /// body line. `jumpToLine` sets `pane = .notes` itself, so nothing here has to.
    private func handOff(_ insertion: PraticaEntry.Insertion, notePath: String) {
        vault.openChosenNote(at: notePath)
        // `openNote(at:)` focuses a tab that already holds the note rather than
        // re-reading it - and after the first entry it always does, since this very
        // hand-off opened it. That buffer predates the write above, and its next
        // save would put the file back without the heading: catch it up first. Safe
        // to replace outright, since `canOperate(on:)` above refused a dirty tab.
        if vault.openNote?.relativePath == notePath {
            vault.reloadFocusedNote()
        }
        navigation.jumpToLine(
            range: insertion.cursorRange,
            ordinal: Self.ordinal(ofOffset: insertion.cursorRange.location, in: insertion.text)
        )
    }

    /// Which heading of the note the caret's offset falls under, counted the way
    /// `NoteOutline.entries(in:)` counts - the bridge `Navigation.OutlineJump.ordinal`
    /// documents between the editor (characters) and the reading surfaces (blocks).
    static func ordinal(ofOffset offset: Int, in text: String) -> Int {
        let entries = NoteOutline.entries(in: text)
        var ordinal = 0
        for (index, entry) in entries.enumerated() {
            let start = text.utf16.distance(from: text.startIndex, to: entry.range.lowerBound)
            if start <= offset { ordinal = index }
        }
        return ordinal
    }

    /// Who the entry is with: the dossier's first counterpart, and the client folder's
    /// name when the dossier names none. Never blank - «Nota ·» with nothing after it
    /// is a heading `PraticheController.parseEntryHeading` still reads, but a person
    /// cannot.
    func counterpart(of praticaPath: String, fallback: String) -> String {
        guard let root = vault.root,
              let dossier = PraticheController.dossier(at: praticaPath, vaultRoot: root),
              let first = dossier.counterparts.first(where: { !$0.isEmpty })
        else { return fallback }
        return first
    }
}
