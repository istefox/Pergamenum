import AppKit
import SwiftUI

/// The Vista menu of SPEC §10: which pane the window shows, plus the panels and the
/// toggles that belong to it.
struct ViewCommands: Commands {
    let navigation: Navigation
    let vault: VaultController
    let shortcuts: ShortcutStore
    let actions: CommandActions

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            // Above the panes rather than below them: this is how you leave where the panes
            // took you, and Safari and Finder both put it first (ADR-0015 §D5).
            Button("Indietro") { actions.run(.goBack) }
                .keyboardShortcut(shortcuts.shortcut(for: .goBack))
                .disabled(!actions.canRun(.goBack))
            Button("Avanti") { actions.run(.goForward) }
                .keyboardShortcut(shortcuts.shortcut(for: .goForward))
                .disabled(!actions.canRun(.goForward))
            Divider()

            ForEach(Navigation.Pane.allCases) { pane in
                Button(pane.title) { actions.run(pane.shortcut) }
                    .keyboardShortcut(shortcuts.shortcut(for: pane.shortcut))
            }
            Divider()
            // Not Cmd+Shift+E, which SPEC §10 assigns to the source/style toggle:
            // the Calendario menu already binds that key to "Nuovo promemoria", and a
            // second command on the same key simply never fires. The collision with
            // the spec predates this menu entry and is left as it is.
            // Left as a `Toggle` rather than routed through `actions.run`: the checkmark
            // beside it is the state, and a button would lose it. The binding is the
            // action here, so there is no second copy to drift.
            // No shortcut and no entry in the remappable catalogue (ADR-0012 D4): not every
            // command has one - «Cattura rapida» has none either - and a pair of rows in the
            // settings pane for splitting an editor buys nothing.
            Button("Dividi l'editor") { vault.splitEditor() }
                .disabled(vault.root == nil || vault.columns.count > 1)
            Button("Chiudi la colonna") { vault.closeColumn(vault.focusedColumnIndex) }
                .disabled(vault.columns.count < 2)
            Divider()
            // «Modalità lettura» was here (ADR-0029 §D13). There is one editor now, always
            // editable and always styled, so there is no mode to pick between.
            // The inspector had a toolbar button and nothing else, so backlinks, linked
            // tasks and the unlinked mentions were three answers with no key between them.
            Button("Ispettore") { actions.run(.toggleInspector) }
                .keyboardShortcut(shortcuts.shortcut(for: .toggleInspector))
            // The Workspace's own trailing column (ADR-0021 D7): nuovi elementi, task
            // collegati, task assegnati, note referenziate. A `Toggle` and not a `Button`
            // because the checkmark beside it is the state.
            // No shortcut and no `ShortcutCommand` case: the UX blueprint asks for none,
            // and "Dividi l'editor" above is the precedent for a keyless Vista entry.
            Toggle("Pannello Workspace", isOn: Bindable(navigation).isShowingTray)
                .disabled(navigation.pane != .workspace)
            // Hides the app sidebar, the board list and the tray at once, for more
            // room on the board itself. Same keyless precedent as the toggle above.
            // Qualified with the section name (2026-08-28, toolbar parity chain): with
            // Note carrying its own «Concentrazione Note» below, the bare name stopped
            // saying which section it acted on.
            Toggle("Concentrazione Workspace", isOn: Bindable(navigation).isWorkspaceFocused)
                .disabled(navigation.pane != .workspace)
            // Narrower than «Concentrazione»: only the board-list tree, tray untouched.
            // Named for what checking it does, not for a shown/hidden state - "Albero
            // Workspace" would read backwards next to "Pannello Workspace" above, where
            // checked means shown rather than hidden.
            Toggle("Nascondi albero Workspace", isOn: Bindable(navigation).isWorkspaceTreeCollapsed)
                .disabled(navigation.pane != .workspace)
            // Note's own equivalents (2026-08-28, toolbar parity chain): same two
            // flags, same menu convention (checked = hidden), mirroring the toolbar's
            // own «Concentrazione»/«Albero» glyphs which invert that presentation.
            Toggle("Concentrazione Note", isOn: Bindable(navigation).isNotesFocused)
                .disabled(navigation.pane != .notes)
            Toggle("Nascondi albero Note", isOn: Bindable(navigation).isNoteTreeCollapsed)
                .disabled(navigation.pane != .notes)
            Divider()
            // Brings the pane forward as well as asking for the check: the view that
            // runs the linter only exists while that pane is shown, so from anywhere
            // else the command would do nothing at all.
            Divider()

            Button("Ripiega la sezione") { actions.run(.foldSection) }
                .keyboardShortcut(shortcuts.shortcut(for: .foldSection))
                .disabled(!actions.canRun(.foldSection))

            Button("Espandi tutto") { actions.run(.unfoldAll) }
                .keyboardShortcut(shortcuts.shortcut(for: .unfoldAll))
                .disabled(!actions.canRun(.unfoldAll))

            Divider()

            // ADR-0032: the menu entry and the pane's own `arrow.clockwise` button are the
            // same command, and it is live only while the Registrazioni pane is showing
            // (blueprint). The pane rows themselves stay row-scoped and out of the menu bar.
            Button("Aggiorna registrazioni") { actions.run(.refreshRecordings) }
                .keyboardShortcut(shortcuts.shortcut(for: .refreshRecordings))
                .disabled(!actions.canRun(.refreshRecordings))
            Divider()
            Button("Preferita") { actions.run(.toggleStar) }
                .keyboardShortcut(shortcuts.shortcut(for: .toggleStar))
                .disabled(!actions.canRun(.toggleStar))
            Button("Applica un template…") { actions.run(.applyTemplate) }
                .keyboardShortcut(shortcuts.shortcut(for: .applyTemplate))
                .disabled(!actions.canRun(.applyTemplate))
            Divider()
            Button("Anteprima rapida") { actions.run(.quickLook) }
                .keyboardShortcut(shortcuts.shortcut(for: .quickLook))
                .disabled(!actions.canRun(.quickLook))
            Button("Rigenera indice") { Task { await vault.rescan() } }
                .disabled(vault.root == nil)
        }
    }
}

/// The Calendario menu of SPEC §10.
///
/// Every entry acts on the day the Oggi pane is showing, which is why the controller
/// is created once at app level rather than inside the view: a menu that could only
/// work while a particular view held focus would not be a menu.
struct CalendarCommands: Commands {
    let day: DayController
    let calendar: EventKitStore
    let navigation: Navigation
    let shortcuts: ShortcutStore
    let actions: CommandActions

    var body: some Commands {
        CommandMenu("Calendario") {
            // Not a `ShortcutCommand`: it has no shortcut, so it stays a closure here.
            Button("Vai a oggi") {
                navigation.pane = .today
                day.show(.today)
            }
            Button("Giorno precedente") { actions.run(.previousDay) }
                .keyboardShortcut(shortcuts.shortcut(for: .previousDay))
            Button("Giorno successivo") { actions.run(.nextDay) }
                .keyboardShortcut(shortcuts.shortcut(for: .nextDay))
            Button("Vai a data…") {
                navigation.pane = .today
                day.isChoosingDate = true
            }

            Divider()
            Button("Nuovo evento") { actions.run(.newEvent) }
                .keyboardShortcut(shortcuts.shortcut(for: .newEvent))
                .disabled(!actions.canRun(.newEvent))

            Button("Nuovo promemoria") { actions.run(.newReminder) }
                .keyboardShortcut(shortcuts.shortcut(for: .newReminder))
                .disabled(!actions.canRun(.newReminder))

            Divider()
            Button("Pubblica i time block sul Calendario") {
                day.publishAllBlocks(toCalendarTitled: calendar.writeCalendarTitle)
            }
            .disabled(!calendar.eventAccess.isGranted || day.blocks.allSatisfy(\.isPublished))

            Button("Aggiorna da EventKit") { Task { await day.load() } }
        }
    }
}

/// The Inserisci menu of SPEC §10.
///
/// Each entry asks the editor to put text at the cursor. The menu holds no reference
/// to the text view: it would go stale the moment the editor is rebuilt.
struct InsertCommands: Commands {
    let navigation: Navigation
    let vault: VaultController
    let shortcuts: ShortcutStore
    let actions: CommandActions

    var body: some Commands {
        CommandMenu("Inserisci") {
            Button("Wikilink") { actions.run(.insertWikilink) }
                .keyboardShortcut(shortcuts.shortcut(for: .insertWikilink))
            Button("Tag") { navigation.insert("#") }
            Button("Task") { navigation.insert("- [ ] ") }
            Divider()
            Button("Data pianificata") { navigation.insert(">\(CalendarDate.today) ") }
            Button("Scadenza") { navigation.insert("!\(CalendarDate.today) ") }
            Button("Promemoria") { navigation.insert("@remind(\(CalendarDate.today) 09:00) ") }
            Divider()
            Button("Nota correlata…") { actions.run(.insertRelated) }
                .keyboardShortcut(shortcuts.shortcut(for: .insertRelated))
                .disabled(!actions.canRun(.insertRelated))
            Button("Tabella") { navigation.insert(EditorCommand.table) }
            Button("Vista…") { insertView() }
            Button("Immagine o file…") { insertFile() }
                .disabled(vault.openNote == nil)
            Button("Link email da Mail") { insertMailLink() }
            // Beside the entry that puts a `message://` link in a note, because both
            // start from the same thing - the message selected in Mail - and differ
            // only in where it lands (R-21).
            Button("Aggiungi a pratica da Mail…") { actions.run(.addToPraticaFromMail) }
                .keyboardShortcut(shortcuts.shortcut(for: .addToPraticaFromMail))
                .disabled(!actions.canRun(.addToPraticaFromMail))
            Divider()
            Button("Apri nel Workspace") { vault.openCurrentNoteInWorkspace() }
                .disabled(vault.openNote == nil)
        }
    }

    /// Copies the chosen file into the vault beside the note and embeds it (SPEC §5).
    private func insertFile() {
        guard let note = vault.openNote,
              let urls = VaultOpenPanel.chooseFiles(
                  title: "Inserisci un file",
                  message: "Il file viene copiato nella cartella della nota."
              )
        else { return }

        let names = urls.compactMap { vault.importFileIntoVault($0, near: note.relativePath) }
        guard !names.isEmpty else { return }
        navigation.insert(names.map(EditorEdits.embed(forFileNamed:)).joined(separator: "\n") + "\n")
    }

    /// Writes a closed, parseable `pergamenum-view` stub at the cursor and opens the query
    /// builder on it in the same gesture (R-04, ADR-0034 §D10) - the sheet always edits a
    /// fence that already exists, rather than sometimes writing one.
    private func insertView() {
        let stub = ViewQueryText.stub(atLineStart: true)
        navigation.insert(stub.text, cursorBack: stub.cursorBack, opensQueryBuilder: true)
    }

    /// Reads the message selected in Mail and inserts its `message://` link (SPEC §10).
    private func insertMailLink() {
        switch MailLink.selectedMessage() {
        case .success(let link):
            navigation.insert("[\(link.subject)](\(link.url))")
        case .failure(let problem):
            vault.recordProblem(problem.description)
        }
    }
}

/// The Aiuto menu entries of SPEC §10.
struct HelpCommands: Commands {
    let navigation: Navigation

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Guida sintassi task") { navigation.isShowingTaskSyntaxHelp = true }
            Button("Convenzioni harness") { navigation.isShowingConventionsHelp = true }
            Button("Come funziona il Diario") { navigation.isShowingDiaryHelp = true }
        }
    }
}

/// «Cerca Aggiornamenti…» in the Pergamenum menu (ADR-0031, R-02).
///
/// `after: .appInfo` is Sparkle's own documented placement and the standard macOS one:
/// straight under «Informazioni su Pergamenum».
///
/// **No `import Sparkle` here.** This file speaks to `SparkleUpdateController` and nothing
/// else (ADR-0031 §D2): Sparkle enters the app through that one file under `Sources/App/`,
/// and the menu layer has no business knowing which framework answers the button.
///
/// No `ShortcutCommand` case and no `.keyboardShortcut`: ADR-0023 §D5 - the catalogue is the
/// set of *rebindable* shortcuts, not of all commands, and this one never had a key.
struct UpdateCommands: Commands {
    let updater: SparkleUpdateController

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Cerca Aggiornamenti…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

/// The Modifica-menu entries SPEC §10 adds to the standard ones.
struct EditCommands: Commands {
    let navigation: Navigation
    let shortcuts: ShortcutStore
    let actions: CommandActions

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Incolla come testo puro") { actions.run(.pastePlain) }
                .keyboardShortcut(shortcuts.shortcut(for: .pastePlain))
        }
        // **Replacing and not adding.** SwiftUI's standard group is the system Find submenu,
        // which drives `NSTextFinder` and already binds Cmd+F, Cmd+Alt+F, Cmd+G and
        // Cmd+Shift+G. Beside it, our own «Trova nella nota» was a second Cmd+F that never
        // fired: AppKit's item won, so Cmd+F opened AppKit's bar and ours never appeared.
        // Seen on screen on 2026-08-18, and the reason the find slice has its own Cmd+G -
        // taking this submenu away takes those two keys with it.
        CommandGroup(replacing: .textEditing) {
            Button("Trova nella nota") { actions.run(.findInNote) }
                .keyboardShortcut(shortcuts.shortcut(for: .findInNote))
            Button("Sostituisci") { actions.run(.replaceInNote) }
                .keyboardShortcut(shortcuts.shortcut(for: .replaceInNote))
            Button("Trova successivo") { actions.run(.findNext) }
                .keyboardShortcut(shortcuts.shortcut(for: .findNext))
            Button("Trova precedente") { actions.run(.findPrevious) }
                .keyboardShortcut(shortcuts.shortcut(for: .findPrevious))
        }
    }
}

/// The Vista > Tema section of the menu bar (SPEC §10). Lives here rather than in
/// the gallery because the menu belongs to the app, not to a feature.
struct ThemeCommands: Commands {
    @Bindable var engine: ThemeEngine

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Menu("Tema") {
                Picker("Tema", selection: $engine.selection) {
                    Text("Sistema").tag(ThemeEngine.Selection.followSystem)
                    Text("Chiaro").tag(ThemeEngine.Selection.light)
                    Text("Scuro").tag(ThemeEngine.Selection.dark)
                    ForEach(engine.selectableThemes.filter { !$0.id.hasPrefix("pergamenum-") }) { theme in
                        Text(theme.name).tag(ThemeEngine.Selection.named(theme.id))
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}
