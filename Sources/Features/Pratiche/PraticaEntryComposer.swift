import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 -
// R-28, R-29; ADR §D5, §D13.
//
// «Nota», «Telefonata» and «Inserisci qui»: the two writes §D5 allows the timeline to
// make, and nothing else.
//
//   1. one heading appended to `pratica.md`, through one `VaultSession.write` - free, or
//      anchored to a message with its anchor line in the same write (ADR-0076 §D4, §D7:
//      «Aggiungi nota»/«Aggiungi telefonata» on a message row)
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
    ///
    /// `insert(_:at:)` is `async` (ADR-0041 Task 8); this stays synchronous and wraps it
    /// in `Task { }`, so `PratichePane`'s plain `() -> Void` callbacks need no change.
    func append(_ kind: PraticaEntry.Kind) {
        Task { await insert(kind, at: Date()) }
    }

    /// «Inserisci qui» (R-28): the midpoint between the two rows the gap sits between,
    /// so the entry reads back in the place a person put it. `PraticaTimelineModel.insertionDate`
    /// owns the rule (the neighbours' placement times, ADR-0076 §D3, R-07); this only says
    /// which two rows are the neighbours.
    func insertBetween(_ first: PraticaTimelineEntry, and second: PraticaTimelineEntry, kind: PraticaEntry.Kind) {
        Task { await insert(kind, at: PraticaTimelineModel.insertionDate(between: first, and: second)) }
    }

    /// The one write path both of the above go through.
    ///
    /// `async` since ADR-0041 Task 8: both writes below go through `VaultSession.write`'s
    /// actor-hop overload, and the order (insertion, then the diary mirror, then the
    /// reload and hand-off) is preserved exactly as it was.
    ///
    /// `expecting:` (ADR-0043 §D8, Task 9) - this is the fourth race the ADR names by
    /// this line: `source` predates any writer reaching the actor first, and a stale
    /// `insertion.text` composed from it would silently discard whatever landed in
    /// between. A refusal here is reported exactly like any other write failure - the
    /// heading was never written, so nothing is inconsistent.
    func insert(_ kind: PraticaEntry.Kind, at timestamp: Date) async {
        guard let praticaPath = pratiche.selection,
              let pratica = pratiche.selectedPratica
        else { return }
        let counterpart = counterpart(of: praticaPath, fallback: pratica.client)
        await commit(kind, at: timestamp, counterpart: counterpart, anchor: nil, in: pratica)
    }

    /// «Aggiungi nota» / «Aggiungi telefonata» on a message row (ADR-0076 §D7, R-03): a heading
    /// at the time of writing, followed by the anchor line naming the message, in the pratica the
    /// row belongs to - never the selection alone, the same rule `PraticaCommandActions`
    /// follows for a row command.
    ///
    /// The heading names the message's own counterpart (plan interpretation 3), read fresh from
    /// the message file, and falls back to the dossier's first counterpart when the message
    /// names nobody or cannot be read. An id `PraticaEntryAnchor.line(for:)` cannot spell is
    /// reported and nothing is written: a free entry in its place would read as done.
    func insertAnchored(_ kind: PraticaEntry.Kind, on message: PraticaTimelineEntry, detail: PraticaRowDetail?) async {
        // The folder the message's file sits in, falling back to the selection for a row whose
        // detail is not loaded yet.
        guard let praticaPath = detail?.praticaFolder ?? pratiche.selection,
              let pratica = pratiche.pratiche.first(where: { $0.id == praticaPath })
        else { return }
        guard let messageID = message.messageID, PraticaEntryAnchor.line(for: messageID) != nil else {
            pratiche.report("«\(message.subject)» non ha un Message-ID che una voce possa nominare: "
                + "la voce non è stata scritta.")
            return
        }
        let counterpart = messageCounterpart(at: detail?.notePath)
            ?? counterpart(of: praticaPath, fallback: pratica.client)
        await commit(kind, at: Date(), counterpart: counterpart, anchor: messageID, in: pratica)
    }

    /// The one write path both inserts go through: the dirty-tab refusal, a fresh read, one
    /// guarded write, the diary mirror, the reload and the hand-off, in that order.
    /// `pratica.id` is the pratica's folder path (`PraticheController.selectedPratica`'s lookup).
    private func commit(
        _ kind: PraticaEntry.Kind, at timestamp: Date, counterpart: String, anchor: String?,
        in pratica: PraticaListItem
    ) async {
        guard let session = vault.session else { return }
        let praticaPath = pratica.id
        let notePath = PraticaNaming.praticaNotePath(of: praticaPath)
        // The same refusal every file operation makes (`VaultController+Files`): a
        // tab holding unsaved edits to this note is asked to save first, never
        // merged with and never discarded - the write below catches that tab up (ADR-0067).
        guard vault.canOperate(on: notePath) else { return }
        do {
            let (record, source) = try session.read(notePath)
            let insertion = PraticaEntry.insert(
                kind: kind, at: timestamp, counterpart: counterpart, anchor: anchor, in: source
            )
            try await session.write(insertion.text, to: notePath, expecting: record.contentHash)
            await mirror(kind, of: pratica, counterpart: counterpart, on: timestamp, session: session)
            pratiche.reloadTimeline(from: vault)
            handOff(insertion, notePath: notePath)
        } catch let refusal as VaultSession.WriteRefusal {
            pratiche.report("La voce non è stata scritta in «\(notePath)»: \(refusal.description)")
        } catch {
            pratiche.report("La voce non è stata scritta in «\(notePath)»: \(error.localizedDescription)")
        }
    }

    /// The message's own counterpart (ADR-0076 §D1): the sender of a received message, else the
    /// first recipient that is not one of the person's own addresses, else the first Cc. Read
    /// from the file now, not from the row, which carries only the sender.
    private func messageCounterpart(at notePath: String?) -> String? {
        guard let notePath, let session = vault.session,
              let (_, text) = try? session.read(notePath),
              let document = MessageDocument.parse(text),
              let name = PraticaEntry.counterpart(
                  ofMessage: document.frontmatter,
                  ownAddresses: Set(vault.settings.pratiche.ownAddresses)
              ),
              !name.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return name
    }

    /// R-29: exactly one line in that day's daily note, and none at all when «Scrivi
    /// nel diario» is off - `DailyNoteMirror.appending` answers `nil` for the second
    /// case, which is what keeps this from writing a file back unchanged.
    ///
    /// The day is the entry's own timestamp and not today: an «Inserisci qui» entry
    /// belongs to the day it is dated, or the diary would say a call happened on the
    /// afternoon somebody typed it up.
    ///
    /// `expecting:` (ADR-0043 §D8, Task 9): same shape as `insert`'s own race, and the
    /// daily note is the file most likely to have a second writer - time blocks,
    /// capture, the diary itself - between this read and this write.
    private func mirror(
        _ kind: PraticaEntry.Kind, of pratica: PraticaListItem, counterpart: String,
        on timestamp: Date, session: VaultSession
    ) async {
        guard vault.settings.pratiche.mirrorsToDailyNote else { return }
        let entry = DailyNoteMirror.Entry(
            praticaTitle: pratica.title, kind: kind, counterpart: counterpart
        )
        do {
            let path = try await session.dailyNote(for: CalendarDate(timestamp))
            let (record, existing) = try session.read(path)
            guard let updated = DailyNoteMirror.appending(
                entry, to: existing, isEnabled: vault.settings.pratiche.mirrorsToDailyNote
            ) else { return }
            try await session.write(updated, to: path, expecting: record.contentHash)
        } catch let refusal as VaultSession.WriteRefusal {
            pratiche.report("La riga nel diario non è stata scritta: \(refusal.description)")
        } catch {
            // The heading is already on disk and that is the entry: a diary line that
            // could not be written is reported, never rolled back into a lost entry.
            pratiche.report("La riga nel diario non è stata scritta: \(error.localizedDescription)")
        }
    }

    /// §D13's editing path: the note opens in the real editor with the caret on the new
    /// body line. `jumpToLine` sets `pane = .notes` itself, so nothing here has to.
    ///
    /// **Not `private` (ADR-0043 §D7, Task 8):** `Tests/VaultWriteOrderingBatch3Tests.swift`
    /// calls this directly to force the write/hand-off boundary without a sleep.
    ///
    /// `openNote(at:)` focuses a tab that already holds the note rather than re-reading
    /// it - and after the first entry it always does, since this very hand-off opened
    /// it. That buffer was caught up by the write in `insert` itself, before this runs
    /// (ADR-0067 §D1, §D5): to the write's own result, never a fresh read - the file, after
    /// `await`, may already have moved on again (`insert`'s own race, closed by
    /// `expecting:` above, is exactly why an un-preconditioned re-read would be wrong) - and
    /// asking rather than silently replacing a buffer the user was editing when the write
    /// landed (ADR-0001 §D3.4). So this only opens the note and places the caret.
    func handOff(_ insertion: PraticaEntry.Insertion, notePath: String) {
        vault.openChosenNote(at: notePath)
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
    /// is a heading `PraticaManualEntries.parse` still reads, but a person
    /// cannot.
    func counterpart(of praticaPath: String, fallback: String) -> String {
        guard let root = vault.root,
              let dossier = PraticheController.dossier(at: praticaPath, vaultRoot: root),
              let first = dossier.counterparts.first(where: { !$0.isEmpty })
        else { return fallback }
        return first
    }
}
