import AppKit

/// `CommandActions`'s "whether it can run" predicates, and the one command
/// (`walkHistory`) whose own condition needs `place` to act (PG-035 — pure code motion
/// off `CommandActions.swift`, which had drifted past both `file_length`'s and
/// `type_body_length`'s warning thresholds). The class's stored properties already carry
/// no `private`, so this needed almost no access-level change - only `place` (used
/// solely by `walkHistory`) moves here with it.
extension CommandActions {
    /// The same value `RootView` derives, built from the same three controllers: this is what
    /// makes the menu entry and the toolbar button the one command they look like.
    private var place: WindowPlace {
        WindowPlace(navigation: navigation, vault: vault, day: day)
    }

    /// What each tab command needs to be worth offering.
    private func canRunTab(_ command: ShortcutCommand) -> Bool {
        switch command {
        case .newTab: vault.root != nil
        case .closeTab: vault.focusedTab != nil
        case .reopenTab: !vault.closedTabPaths.isEmpty
        default: false
        }
    }

    /// The same condition the menu bar puts in `.disabled`, inverted.
    ///
    /// The slash menu needs this as a value rather than as a view modifier: it decides
    /// which commands to *offer*, and offering one that does nothing is how a command
    /// menu teaches people not to trust it.
    func canRun(_ command: ShortcutCommand) -> Bool {
        switch command {
        case .newNote, .newBoard, .dailyNote, .quickTask, .globalCapture, .quickLook, .globalSearch,
             .quickSwitcher, .runConformanceCheck:
            vault.root != nil
        case .save:
            vault.openNote?.hasUnsavedChanges == true
        case .newTab, .closeTab, .reopenTab:
            canRunTab(command)
        case .copyLink, .revealInFinder, .insertRelated, .noteHistory,
             .toggleStar, .applyTemplate:
            canRunOnOpenNote(command)
        case .foldSection, .unfoldAll:
            canRunFolding(command)
        case .goBack, .goForward:
            command == .goBack ? history.canGoBack : history.canGoForward
        // Both act on the task the list has selected, and neither has anything to do
        // without one: «Aggiungi sotto-task» needs a parent to hang the `^parent` off
        // (ADR-0021 D2), not merely a note.
        case .taskToggle, .taskAddSubtask:
            vault.selectedTask != nil
        case .newEvent:
            calendar.eventAccess.isGranted
        case .newReminder:
            calendar.reminderAccess.isGranted
        // Everything else is always available, and the menu bar agrees: pane switching,
        // find, paste, the wikilink insertion and the four rescheduling commands carry no
        // `.disabled` today. See the type's own note about the last four.
        case .openVault, .pastePlain, .findInNote, .replaceInNote, .findNext, .findPrevious,
             .insertWikilink,
             .paneNotes, .paneWorkspace, .paneToday, .paneTasks, .paneConformance,
             .paneDiary, .paneTags, .paneViews, .paneStarred, .toggleInspector,
             .taskToday, .taskTomorrow,
             .taskPlusTwo, .taskNextWeek, .previousDay, .nextDay:
            true
        }
    }

    /// Whether `run(_:on:)` may act on `notePath` - the note-row context menu's own
    /// enablement (ADR-0023 cluster 2, R-03), reachable without the note being open
    /// first. Restricted to the same three commands `run(_:on:)` handles; GREEN reuses
    /// `canRunOnOpenNote`'s condition (`.copyLink`/`.noteHistory` always true given a row,
    /// `.applyTemplate` gated on `vault.templates` being non-empty) rather than a second
    /// spelling of it.
    ///
    /// The path is not read: a row exists because the note does, which is exactly the half
    /// of `canRunOnOpenNote` that asks whether a note is in front of you. What is left is
    /// its other half, written here in the same line it is written there.
    func canRun(_ command: ShortcutCommand, on _: String) -> Bool {
        guard Self.rowCommands.contains(command) else { return false }
        return command == .applyTemplate ? !vault.templates.isEmpty : true
    }

    /// Everything that needs a note in front of it, and the one of them that needs
    /// something else as well.
    ///
    /// A template to write and a note to write it into: «Applica un template…» is offered
    /// greyed rather than hidden when the vault has no `Templates/` folder yet, because
    /// the command is how somebody finds out the folder is a thing.
    /// Folding, split out for the reason `canRunTab` was: this switch sits at the complexity
    /// the linter reports, and this codebase restructures rather than writing its first
    /// `swiftlint:disable`. The two conditions are the ones the Vista menu already had.
    private func canRunFolding(_ command: ShortcutCommand) -> Bool {
        switch command {
        // One condition where there used to be two: the second excluded reading mode, which
        // had no caret and therefore no current section (ADR-0029 §D13 removed it). There is
        // one editor now and it always has a caret, so `currentOutlineEntry` is the whole
        // question again.
        case .foldSection: vault.currentOutlineEntry != nil
        case .unfoldAll: !vault.foldedEntries.isEmpty
        default: false
        }
    }

    /// One step through the window's history, in either direction (ADR-0015).
    ///
    /// Nothing happens when the walk finds nowhere left to reach: every entry it passed named
    /// a note that is gone, and it dropped them on the way.
    func walkHistory(_ command: ShortcutCommand) {
        let walk = command == .goBack ? history.goBack : history.goForward
        if let destination = walk(place.isReachable) { place.apply(destination) }
    }

    private func canRunOnOpenNote(_ command: ShortcutCommand) -> Bool {
        guard vault.openNote != nil else { return false }
        return command == .applyTemplate ? !vault.templates.isEmpty : true
    }
}
