import AppKit
import SwiftUI

/// What every command in `ShortcutCommand` actually does, in one callable place.
///
/// Until now each action was a closure inside a `Button` in the menu bar, which is fine
/// while the menu bar is the only way to reach it. M8's slash menu is a second way, and a
/// second way that re-implemented the actions would be two copies drifting - the same
/// failure ADR-0007 §D2 keeps out of the connectors, arriving here by a different door.
///
/// So the menus and the slash menu both call this, and neither owns the behaviour.
///
/// **`canRun` reproduces exactly what the menu bar disables today, including where that
/// looks like an oversight.** The four rescheduling commands have no `.disabled` in the
/// Task menu even though they act on the selected task, so they answer `true` here as
/// well. Making them stricter would be a behaviour change smuggled inside an extraction,
/// and `CommandActionTests` exists to catch exactly that; if the menu should be stricter,
/// that is a separate change with its own reason.
/// A class and `@Observable` for one reason only: this is how everything else in the app
/// reaches the views, through `.environment(_:)`, and `VaultBrowser()` takes no arguments
/// on purpose. Nothing here is state and nothing here changes, so nothing observes it.
@MainActor
@Observable
final class CommandActions {
    let navigation: Navigation
    let vault: VaultController
    let day: DayController
    let calendar: EventKitStore
    let capturePanel: CapturePanel
    /// The places the window has been (ADR-0015), so «Indietro» is the same command from the
    /// menu, the key and the toolbar rather than three of them.
    let history: NavigationHistory
    /// Internal rather than private so a test can name it - the same reason
    /// `RecentVaults.key` is internal. Defaults to the real system pasteboard; a test
    /// passes `.volatile()` so running the suite does not touch the user's own clipboard.
    let pasteboard: NSPasteboard
    /// The Registrazioni pane's controller (ADR-0032), so «Aggiorna registrazioni» is one
    /// command reached from the menu, from Cmd+R and from the pane's own toolbar button
    /// rather than three copies of a refresh.
    ///
    /// Optional with a `nil` default, unlike the six above: this type is built with those
    /// six in `Tests/CommandActionTests.swift` and `Tests/RowCommandTests.swift`, and a
    /// required seventh parameter would turn a wiring change into an edit of two test files.
    /// `canRun(.refreshRecordings)` never consults it - which pane is showing is the whole
    /// condition (blueprint) - so a `nil` here only means the refresh does nothing.
    let recordings: RecordingsController?

    init(
        navigation: Navigation,
        vault: VaultController,
        day: DayController,
        calendar: EventKitStore,
        capturePanel: CapturePanel,
        history: NavigationHistory,
        pasteboard: NSPasteboard = .general,
        recordings: RecordingsController? = nil
    ) {
        self.navigation = navigation
        self.vault = vault
        self.day = day
        self.calendar = calendar
        self.capturePanel = capturePanel
        self.history = history
        self.pasteboard = pasteboard
        self.recordings = recordings
    }

    // MARK: Running

    /// Dispatches by the section the command lives in, which is the same grouping the
    /// menu bar uses.
    ///
    /// The first version was one exhaustive switch over all thirty-three commands, so a
    /// command added and forgotten was a *compile* error. That is the stronger guarantee
    /// and it was given up for a reason worth writing down: SwiftLint scores a
    /// thirty-three-way switch at complexity 31, which its default configuration reports
    /// as an **error**, and this codebase contains no `swiftlint:disable` anywhere -
    /// introducing the first one, for a rule that is right in general, is the worse trade.
    ///
    /// What replaces it is nearly as good and is not nothing. `ShortcutCommand.section`
    /// is itself an exhaustive switch, so a new command still cannot compile without being
    /// given a section; it then reaches that section's method, and the `default` there is
    /// an `assertionFailure`, so the omission is loud on the first Debug run rather than a
    /// menu entry that quietly does nothing.
    func run(_ command: ShortcutCommand) {
        // The commands whose whole action is raising a flag the window is watching,
        // handled as the table they are rather than as five identical switch arms.
        if let flag = Self.flags[command] {
            vault[keyPath: flag] = true
            return
        }
        switch command.section {
        case .file: runFile(command)
        case .tab: runTab(command)
        case .edit: runEdit(command)
        case .insert: runInsert(command)
        case .view: runView(command)
        case .task: runTask(command)
        case .calendar: runCalendar(command)
        }
    }

    /// The note-row context menu's three commands (ADR-0023 cluster 2, R-03/R-04):
    /// «Copia link Pergamenum», «Cronologia…», «Applica un template…», invoked from a row
    /// that may not be the open note. "Apri la nota, poi esegui l'azione" - the note at
    /// `notePath` opens first (`vault.openNote(at:)`, whose own short-circuit is what
    /// makes invoking this on the already-open note a no-op re-open), then `run(command)`
    /// runs exactly as it does from the menu bar. Anything outside the three commands does
    /// nothing at all - it does not open the note either.
    ///
    /// **The one exception to that pattern, and the reason is a test rather than a
    /// preference.** A command outside `rowCommands` returns silently instead of tripping
    /// `assertionFailure`: `RowCommandTests.runOnANonNoteCommandDoesNotOpenTheNote` invokes
    /// this with `.newBoard` as its negative control, and the unit suite is built Debug, so
    /// an assertion there would trap the whole run rather than record a no-op. The set below
    /// is the guard, and it is the only place the three commands are named.
    func run(_ command: ShortcutCommand, on notePath: String) {
        guard Self.rowCommands.contains(command) else { return }
        vault.openNote(at: notePath)
        // `openNote(at:)` returns having changed nothing when the file cannot be read, and
        // the command would then act on whichever note was open before - copying the wrong
        // link, or opening the wrong note's history. Asking what is actually open is the
        // only honest way to tell the two apart, since the open itself reports neither.
        guard vault.openNote?.relativePath == notePath else { return }
        run(command)
    }

    /// The three commands a note row may run (ADR-0023 cluster 2). Named once and read by
    /// both `run(_:on:)` and `canRun(_:on:)`, so the menu cannot offer an entry the action
    /// refuses, nor grey one it would have performed.
    static let rowCommands: Set<ShortcutCommand> = [.copyLink, .noteHistory, .applyTemplate]

    /// The tabs of the Note pane (ADR-0012 D5). Their own method rather than three more
    /// arms of `runFile`: they are one family, and the File menu already separates them
    /// with a divider.
    private func runTab(_ command: ShortcutCommand) {
        switch command {
        case .newTab:
            // The Note pane first, for the same reason «Nuova nota» does it: a tab opened
            // from the Attività pane would open out of sight.
            navigation.pane = .notes
            vault.beginNewTab()
        case .closeTab:
            vault.closeFocusedTab()
        case .reopenTab:
            navigation.pane = .notes
            vault.reopenClosedTab()
        default:
            break
        }
    }

    private func runFile(_ command: ShortcutCommand) {
        switch command {
        case .newNote:
            // The Note pane first: the composer is part of the editor, so from any other
            // pane the command would compose out of sight.
            navigation.pane = .notes
            vault.beginNewNote()
        case .newBoard:
            // The Workspace pane first, for the same reason: the folder-naming sheet
            // opens on the Workspace, so any other pane would compose it out of sight.
            navigation.pane = .workspace
            vault.beginNewBoard()
        case .dailyNote:
            // Reported rather than swallowed: the command doing nothing at all, with no
            // reason given, is the worst outcome when the daily note cannot be created.
            do {
                _ = try vault.openDailyNote(for: .today)
            } catch {
                vault.recordProblem("nota del giorno: \(error)")
            }
        case .quickTask:
            vault.beginTaskCapture()
        case .globalCapture:
            capturePanel.toggle()
        case .save:
            vault.saveOpenNote()
        case .openVault:
            VaultOpenPanel.chooseVault(into: vault)
        case .copyLink, .revealInFinder, .toggleStar:
            runOnOpenNote(command)
        default:
            assertionFailure("«\(command.title)» è nella sezione File e non è gestito")
        }
    }

    /// The three that act on the note in front of you.
    ///
    /// One arm of `runFile` between them rather than three: they share a precondition and
    /// a subject, and three arms was what took that switch past the complexity the linter
    /// reports.
    private func runOnOpenNote(_ command: ShortcutCommand) {
        switch command {
        case .copyLink:
            copyLinkToOpenNote()
        case .revealInFinder:
            revealOpenNote()
        case .toggleStar:
            // The open note, which is the one the star could not reach: the note list's
            // context menu has always been able to star any *other* note.
            if let path = vault.openNote?.relativePath { vault.toggleStar(path) }
        default:
            assertionFailure("«\(command.title)» non agisce sulla nota aperta")
        }
    }

    private func runEdit(_ command: ShortcutCommand) {
        switch command {
        case .pastePlain:
            pastePlain()
        case .findInNote:
            navigation.isFindRequested = true
        case .replaceInNote:
            navigation.isReplaceRequested = true
        case .findNext:
            navigation.findStep = (navigation.findStep ?? 0) + 1
        case .findPrevious:
            navigation.findStep = (navigation.findStep ?? 0) - 1
        default:
            assertionFailure("«\(command.title)» è nella sezione Modifica e non è gestito")
        }
    }

    private func runInsert(_ command: ShortcutCommand) {
        switch command {
        case .insertWikilink:
            navigation.insert("[[]]", cursorBack: 2)
        default:
            assertionFailure("«\(command.title)» è nella sezione Inserisci e non è gestito")
        }
    }

    private func runView(_ command: ShortcutCommand) {
        switch command {
        case .paneNotes, .paneWorkspace, .paneToday, .paneTasks, .paneConformance, .paneDiary,
             .paneTags, .paneViews, .paneStarred, .paneRecordings, .refreshRecordings,
             .panePratiche:
            runNavigation(command)
        case .toggleInspector:
            navigation.isShowingInspector.toggle()
        case .runConformanceCheck:
            // Brings the pane forward as well as asking for the check: the view that runs
            // the linter only exists while that pane is shown, so from anywhere else the
            // command would do nothing at all.
            navigation.pane = .conformance
            vault.isCheckingConformance = true
        case .foldSection:
            // The section the caret is in, which the editor reports as it moves. Without a
            // caret there is no "this section", and the command is disabled rather than
            // guessing at the first one. `currentOutlineEntry` is an ordinal, `toggleFold`
            // now wants the heading's own offset - translated here, fresh against the open
            // note's own text, rather than handing the ordinal through and letting it be
            // misread as an offset at the other end.
            if let entry = vault.currentOutlineEntry, let text = vault.openNote?.text {
                let entries = NoteOutline.entries(in: text)
                if entries.indices.contains(entry) {
                    let offset = text.utf16.distance(from: text.startIndex, to: entries[entry].range.lowerBound)
                    vault.toggleFold(offset)
                }
            }
        case .unfoldAll:
            vault.foldedEntries = []
        case .goBack, .goForward:
            walkHistory(command)
        default:
            assertionFailure("«\(command.title)» è nella sezione Vista e non è gestito")
        }
    }

    /// The ten "go to this pane" commands, and «Aggiorna registrazioni» beside them.
    ///
    /// Split off `runView` and sharing one arm with the panes for the reason `run(_:)`'s own
    /// header records: an eleventh arm scored that switch past the complexity SwiftLint
    /// reports, and this codebase restructures rather than writing its first
    /// `swiftlint:disable`. The refresh is not a navigation and does not pretend to be one -
    /// it never changes `navigation.pane`.
    private func runNavigation(_ command: ShortcutCommand) {
        guard command != .refreshRecordings else {
            // Only ever reached while the pane is showing (`canRun`), so unlike «Verifica
            // conformità» it does not bring its pane forward first: Cmd+R from anywhere else
            // is disabled rather than being a navigation in disguise.
            Task { await recordings?.refreshAndCheckHealth() }
            return
        }
        if let pane = Navigation.Pane.allCases.first(where: { $0.shortcut == command }) {
            navigation.pane = pane
        }
    }

    private func runTask(_ command: ShortcutCommand) {
        switch command {
        case .taskToggle:
            if let task = vault.selectedTask { vault.toggle(task) }
        case .taskToday:
            vault.rescheduleSelectedTask(daysFromToday: 0)
        case .taskTomorrow:
            vault.rescheduleSelectedTask(daysFromToday: 1)
        case .taskPlusTwo:
            vault.rescheduleSelectedTask(daysFromToday: 2)
        case .taskNextWeek:
            vault.rescheduleSelectedTask(daysFromToday: 7)
        case .taskAddSubtask:
            addSubtaskToSelectedTask()
        default:
            assertionFailure("«\(command.title)» è nella sezione Task e non è gestito")
        }
    }

    private func runCalendar(_ command: ShortcutCommand) {
        switch command {
        // One unit of the scale being shown, like the two chevrons beside them: in the
        // week these move a week, or the shortcut and the toolbar would be two
        // different navigations wearing one name.
        case .previousDay:
            day.moveSpan(by: -1)
        case .nextDay:
            day.moveSpan(by: 1)
        case .newEvent:
            navigation.pane = .today
            day.isCreatingEvent = true
        case .newReminder:
            navigation.pane = .today
            day.isCreatingReminder = true
        default:
            assertionFailure("«\(command.title)» è nella sezione Calendario e non è gestito")
        }
    }

    /// Opens the composer already pointed at the selected task as its parent (ADR-0021
    /// D9, A9), which is the whole of «Aggiungi sotto-task».
    ///
    /// The draft itself is `TaskDraft.subtask(of:)`, which is where the reason for its
    /// destination is written: the task row's context menu assigns that same value
    /// (ADR-0023 §D6), so the two entry points cannot compose different sub-tasks.
    private func addSubtaskToSelectedTask() {
        guard let parent = vault.selectedTask else { return }
        vault.taskDraft = .subtask(of: parent)
    }

    /// Four commands do exactly one thing: set a `Bool` on the controller that some view
    /// is watching. Written as a table because that is what they are, and because five
    /// identical switch arms are what pushed this file's dispatch over the complexity the
    /// linter reports as an error.
    private static let flags: [ShortcutCommand: ReferenceWritableKeyPath<VaultController, Bool>] = [
        .quickLook: \.isShowingQuickLook,
        .globalSearch: \.isShowingGlobalSearch,
        .quickSwitcher: \.isShowingQuickSwitcher,
        .insertRelated: \.isAddingRelatedLink,
        .noteHistory: \.isShowingHistory,
        .applyTemplate: \.isChoosingTemplate,
    ]

    // MARK: The three that need more than a line

    /// Puts a `pergamenum://` link to the open note on the pasteboard, for pasting into
    /// Obsidian, DEVONthink, Mail or Calendar (SPEC §9).
    private func copyLinkToOpenNote() {
        guard let note = vault.openNote, let url = PergamenumLink.note(path: note.relativePath) else { return }
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    private func revealOpenNote() {
        guard let note = vault.openNote, let root = vault.root else { return }
        NSWorkspace.shared.activateFileViewerSelecting([
            root.appending(path: note.relativePath, directoryHint: .notDirectory),
        ])
    }

    /// The pasteboard is rewritten to its plain text and pasted through the responder
    /// chain, so this works in any field, not only the editor. Always the real system
    /// pasteboard, never `self.pasteboard` - the paste responder chain reads from
    /// `.general` by construction, so rewriting any other pasteboard would be a silent
    /// no-op.
    private func pastePlain() {
        let plain = NSPasteboard.general.string(forType: .string) ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plain, forType: .string)
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    }
}
