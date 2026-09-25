import Foundation
import Observation

/// The logic of the Diario pane: one day's prose and its entries, and the file both
/// live in.
///
/// Separated from the view so every rule that matters - snapping to ten minutes, not
/// falling off the end of the day, not writing a file for a day nobody wrote anything
/// on - is exercised by tests rather than by clicking.
///
/// It holds the day's file in memory while a person writes, so (ADR-0057) every write goes
/// through **one serial door** (§D4), proves it still replaces the **origin** it was read
/// from (§D2, §D3, §D7), and a refusal is a **conflict** (§D6) that writes nothing and
/// leaves no day until `keepLocalDiary()` or `reloadDiaryFromDisk()` is chosen.
///
/// Nothing here touches EventKit. The diary is the app's own record of a day and
/// answers to nothing outside the vault.
@MainActor
@Observable
final class DiaryController {
    private(set) var day: CalendarDate = .today
    /// The day's text without its `## Diario` section, which is what the editor edits.
    ///
    /// Settable because it is bound straight to the editor; every change goes through
    /// `didSet`, which counts it as an edit and schedules the save.
    var prose: String = "" {
        didSet {
            guard prose != oldValue, isLoaded else { return }
            noteEdited()
            scheduleSave()
        }
    }
    private(set) var entries: [DiaryEntry] = []

    /// The entry being composed or edited, and the sheet that shows it. Nil is closed.
    var draft: DiaryDraft?
    /// Raised by the toolbar's date button.
    var isChoosingDate = false

    private let vault: VaultController
    /// False until the first load, so the initial assignment to `prose` is not read as
    /// an edit and does not schedule a write of a file that may not exist.
    private var isLoaded = false
    private var saveTask: Task<Void, Never>?

    /// A test seam, nil in production: awaited before each write and after its outcome has
    /// been acted on, so `.didWrite` counts writes whose consequences are visible (§D9).
    @ObservationIgnored var testOnlyWriteHook: (@MainActor (DiaryWritePhase) async -> Void)?

    /// Whether the day on screen is safely on disk (ADR-0057 §D6).
    private(set) var saveState: SaveState = .saved

    /// Nothing owed and no write operation queued or running (ADR-0057 §D5): the condition
    /// for `show(_:)`'s synchronous path, and what a test waits on before a round trip.
    var isSettled: Bool { saveState == .saved && runner == nil }

    /// Which file the day was last read from, and what it held (ADR-0057 §D2). Written by
    /// a read, a successful write and the two resolution verbs; never by an edit.
    private(set) var origin: DiaryOrigin = .none

    /// Bumped by every edit; a write marks the day saved only if it has not moved since the
    /// write's snapshot (ADR-0057 §D4). A flag cleared after an `await` describes the snapshot.
    private var editGeneration = 0

    /// The day a navigation asked for while a write was owed or in flight (ADR-0057 §D5).
    /// `move(by:)` counts from it, and the queued switch reads it when it runs.
    private var destination: CalendarDate?

    /// The serial write door (ADR-0057 §D4): one queue drained by one runner task, so at
    /// most one write is ever in flight and each starts once the previous one has settled.
    private enum Operation { case write, switchDay }
    private var operations: [Operation] = []
    private var runner: Task<Void, Never>?

    /// How long typing pauses before the day is written. Long enough not to write on
    /// every keystroke, short enough that no realistic switch away loses a sentence -
    /// and every path that leaves the view flushes it anyway.
    private let saveDelay = Duration.milliseconds(600)

    init(vault: VaultController) {
        self.vault = vault
    }

    // MARK: Loading and saving

    /// Reads the day being shown when that is safe (ADR-0057 §D5, §D7); creates nothing.
    /// Conflicted: nothing, so coming back finds the same conflict. A write owed or in
    /// flight: write it, no re-read - memory is what the file is about to say, and the write
    /// catches a vault or folder change. Settled: re-read, picking up another process's change.
    func load() {
        if case .conflicted = saveState { return }
        guard isSettled else {
            cancelScheduledSave()
            enqueue(.write)
            return
        }
        reload()
    }

    /// Shows another day (ADR-0057 §D5). With nothing owed and nothing in flight the day
    /// changes and is read at once. Otherwise the day being left is flushed and the switch
    /// waits behind that write - and a conflicted day is not left at all (§D6). Asking for
    /// the day on screen meanwhile cancels the switch without re-reading.
    func show(_ newDay: CalendarDate) {
        if case .conflicted = saveState { return }
        guard newDay != day else {
            destination = nil
            return
        }
        guard !isSettled else {
            day = newDay
            reload()
            return
        }
        destination = newDay
        flush()
        enqueue(.switchDay)
    }

    /// Counts from where the pane is going, so two clicks during a flush go two days.
    func move(by days: Int) { show((destination ?? day).adding(days: days)) }

    /// Replaces memory with the day's file and records where it came from. Only called
    /// with nothing owed, or to drop what was owed by choice.
    private func reload() {
        cancelScheduledSave()
        isLoaded = false
        defer { isLoaded = true }
        saveState = .saved
        guard let root = vault.root else {
            prose = ""
            entries = []
            origin = .none
            return
        }
        let file = root.appending(path: vault.diaryNotePath(for: day))
        if let diary = vault.readDiary(on: day) {
            prose = diary.prose
            entries = diary.entries
            origin = .read(file: file, disk: diary.disk)
        } else {
            prose = vault.emptyDiaryNote(for: day)
            entries = []
            origin = .read(file: file, disk: .absent)
        }
    }

    /// An external write reached the day currently open (ADR-0057 §D8, #495). Ignored for
    /// any other day, while conflicted (the conflict already pins the pane, §D6), and when
    /// the text is what `origin` already says the file holds. Otherwise:
    ///
    /// - **nothing owed** → re-read, so a clean pane shows the change at once;
    /// - **owed, nothing in flight** → conflict now, rather than silently dropping the
    ///   edit or silently dropping the change, instead of waiting for the next write to be
    ///   refused into the same conflict;
    /// - **owed, a write queued or in flight** → nothing here. That write carries the
    ///   precondition and refuses into the conflict itself; entering it from here could be
    ///   undone by a write that landed before the change and then marks the day saved.
    func handleExternalChange(path: String, text: String) {
        guard path == vault.diaryNotePath(for: day) else { return }
        if case .conflicted = saveState { return }
        if case .read(_, .present(let hash)) = origin, NoteStore.hash(Data(text.utf8)) == hash { return }
        switch saveState {
        case .saved:
            reload()
        case .pending where runner == nil:
            enterConflict()
        case .pending, .conflicted:
            return
        }
    }

    /// Writes now, if there is anything to write. Called when the pane goes away, when
    /// the app stops being frontmost, and before changing day. Does nothing while
    /// conflicted: a retry per keystroke would refuse per keystroke.
    func flush() {
        cancelScheduledSave()
        save()
    }

    /// Flushes and waits for every pending write to land, for the app-quit path (ADR-0057
    /// §D8, #497): `willTerminateNotification` is the last notification before the process
    /// exits, too late to delay anything, so `applicationShouldTerminate` awaits this instead.
    /// Loops rather than awaiting once: an operation queued after a runner finished starts a new one.
    func settle() async {
        flush()
        while let runner {
            await runner.value
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func cancelScheduledSave() {
        saveTask?.cancel()
        saveTask = nil
    }

    /// Queues a write when one is owed. What it writes is decided when it runs.
    private func save() {
        guard saveState == .pending, isLoaded, vault.root != nil else { return }
        enqueue(.write)
    }

    private func noteEdited() {
        editGeneration += 1
        if saveState == .saved { saveState = .pending }
    }
}

// MARK: The serial write door - a same-file extension, since every member below writes
// `origin`, `saveState`, `prose` or `entries`, whose setters `private(set)` keeps here.
extension DiaryController {
    private func enqueue(_ operation: Operation) {
        operations.append(operation)
        guard runner == nil else { return }
        runner = Task { await drain() }
    }

    private func drain() async {
        while !operations.isEmpty {
            switch operations.removeFirst() {
            case .write: await performWrite()
            case .switchDay: performSwitch()
            }
        }
        runner = nil
    }

    /// One write, run with its predecessor already settled (ADR-0057 §D4). What it writes
    /// is read here, not when it was asked for: `day` cannot change under a pending write,
    /// since `show(_:)` queues its switch behind this, so `prose`/`entries` are the newest
    /// text for this day and `origin` already holds what the previous write left on disk.
    private func performWrite() async {
        if case .conflicted = saveState { return }
        guard let root = vault.root else {
            // No vault, no file: nothing written can ever be owed to it.
            saveState = .saved
            return
        }
        let file = root.appending(path: vault.diaryNotePath(for: day))
        guard origin.file == file else {
            abandonForeignFile(reporting: saveState == .pending)
            return
        }
        guard saveState == .pending else { return }

        let day = day
        let prose = prose
        let entries = entries
        let generation = editGeneration
        let disk = origin.disk
        // A day nobody wrote anything on is not a file. Without this, opening the pane
        // and walking through a week would leave seven empty notes behind.
        guard hasContent || disk != .absent else {
            saveState = .saved
            return
        }

        await testOnlyWriteHook?(.willWrite)
        let outcome = await vault.writeDiary(prose: prose, entries: entries, on: day, over: disk)
        switch outcome {
        case .written(let result):
            origin = .read(file: file, disk: .present(hash: NoteStore.hash(Data(result.text.utf8))))
            settle(after: generation)
        case .unchanged:
            settle(after: generation)
        case .stale:
            enterConflict()
        case .failed:
            // Not a refusal (disk full, permissions): reported, and the day is not pinned
            // to a disk that is failing (ADR-0057 §D5). The next edit tries again.
            vault.recordProblem("diario del \(day.compactForm): scrittura non riuscita")
            settle(after: generation)
        }
        await testOnlyWriteHook?(.didWrite)
    }

    /// Saved when no edit arrived during the write; otherwise still pending, and nothing is
    /// queued here: that edit already owns a write (`entriesChanged` queued it, a keystroke
    /// scheduled it after the typing pause), and a waiting day switch queues its own.
    private func settle(after generation: Int) {
        if editGeneration == generation { saveState = .saved }
    }

    /// The queued half of `show(_:)`.
    private func performSwitch() {
        guard let target = destination else { return }
        if saveState == .pending {
            // An edit arrived while the switch waited: write it before leaving.
            enqueue(.write)
            enqueue(.switchDay)
            return
        }
        destination = nil
        // A refused write pins the day (§D6): the switch is dropped.
        if case .conflicted = saveState { return }
        day = target
        reload()
    }

    /// §D7: the vault or `diaryFolder` changed since the read, so writing would put this
    /// day's text into a file it was never read from. Reports what is dropped, if anything,
    /// and shows the day from the file that is current now.
    private func abandonForeignFile(reporting owed: Bool) {
        if owed {
            vault.recordProblem(
                "modifiche al diario del \(day.compactForm), non salvate: il file non è più quello letto"
            )
        }
        reload()
    }

    /// The one door into `.conflicted` (ADR-0057 §D6), which reports it once.
    private func enterConflict() {
        let reason = VaultWriteRefusal.movedOn(vault.diaryNotePath(for: day)).description
        saveState = .conflicted(reason: reason)
        destination = nil
        vault.recordProblem(reason)
    }

    // MARK: Resolving a conflict

    /// «Tieni la mia versione» (ADR-0057 §D6): adopts what is on disk now as the origin,
    /// without touching the text in memory, and writes that text over it - once. A third
    /// writer landing between this read and the write is refused again and re-enters the
    /// conflict: one attempt per click, never a loop.
    func keepLocalDiary() {
        guard case .conflicted = saveState, let root = vault.root else { return }
        let file = root.appending(path: vault.diaryNotePath(for: day))
        guard origin.file == file else {
            abandonForeignFile(reporting: true)
            return
        }
        cancelScheduledSave()
        origin = .read(file: file, disk: vault.readDiary(on: day)?.disk ?? .absent)
        saveState = .pending
        enqueue(.write)
    }

    /// «Ricarica da disco» (ADR-0057 §D6): drops the text in memory by explicit choice and
    /// reads the day again; a file that is gone reloads as an empty day.
    func reloadDiaryFromDisk() {
        guard case .conflicted = saveState else { return }
        reload()
    }

    /// Whether the day holds anything at all, frontmatter aside.
    private var hasContent: Bool {
        !entries.isEmpty || !NoteDocument.parse(prose).body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Entries

    /// Adds an entry, snapped to the grid and kept inside the day.
    ///
    /// Overlaps are allowed on purpose: the diary records what happened, and what
    /// happened does overlap. The timeline draws them side by side.
    @discardableResult
    func add(
        title: String, note: String = "", startMinutes: Int, durationMinutes: Int, colour: DiaryColour = .blu
    ) -> DiaryEntry {
        let duration = DiaryGrid.clampDuration(durationMinutes)
        let entry = DiaryEntry(
            startMinutes: DiaryGrid.clampStart(startMinutes, duration: duration),
            durationMinutes: duration,
            title: title.trimmingCharacters(in: .whitespaces),
            note: note,
            colour: colour
        )
        entries.append(entry)
        entriesChanged()
        return entry
    }

    /// Replaces an entry with an edited copy of itself, matched by identity so a change
    /// of time and title at once still finds the entry it came from.
    func update(_ entry: DiaryEntry) {
        guard let position = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.durationMinutes = DiaryGrid.clampDuration(entry.durationMinutes)
        updated.startMinutes = DiaryGrid.clampStart(entry.startMinutes, duration: updated.durationMinutes)
        updated.title = entry.title.trimmingCharacters(in: .whitespaces)
        entries[position] = updated
        entriesChanged()
    }

    /// Moves an entry to a new start time, keeping its length.
    func move(_ entry: DiaryEntry, toStart start: Int) {
        guard var moved = entries.first(where: { $0.id == entry.id }) else { return }
        moved.startMinutes = DiaryGrid.clampStart(start, duration: moved.durationMinutes)
        update(moved)
    }

    /// Changes an entry's length, keeping its start.
    func resize(_ entry: DiaryEntry, toDuration duration: Int) {
        guard var resized = entries.first(where: { $0.id == entry.id }) else { return }
        let clamped = DiaryGrid.clampDuration(duration)
        resized.durationMinutes = min(clamped, DiaryGrid.dayMinutes - resized.startMinutes)
        update(resized)
    }

    func remove(_ entry: DiaryEntry) {
        entries.removeAll { $0.id == entry.id }
        entriesChanged()
    }

    /// An entry is a click, not a keystroke: it is written at once rather than after
    /// the typing pause, so nothing on the timeline is ever newer than the file.
    private func entriesChanged() {
        entries.sort { $0.startMinutes < $1.startMinutes }
        noteEdited()
        cancelScheduledSave()
        save()
    }

    // MARK: Timeline geometry

    /// The hours the grid draws: what Impostazioni says, widened to reach every block on
    /// the day (the rest of the geometry is in `DiaryController+Geometry.swift`). A block at
    /// 05:30 under a window starting at eight would otherwise be drawn above the grid,
    /// where nothing is - invisible, and impossible to move back.
    var hours: HourWindow {
        vault.settings.diaryHours.covering(
            startMinutes: entries.map(\.startMinutes),
            endMinutes: entries.map(\.endMinutes)
        )
    }
}
