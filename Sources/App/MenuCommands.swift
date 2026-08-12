import AppKit
import SwiftUI

/// The Vista menu of SPEC §10: which pane the window shows, plus the panels and the
/// toggles that belong to it.
struct ViewCommands: Commands {
    let navigation: Navigation
    let vault: VaultController

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            ForEach(Navigation.Pane.allCases) { pane in
                Button(pane.title) { navigation.pane = pane }
                    .keyboardShortcut(
                        pane.shortcut.map { KeyEquivalent($0) } ?? "\0",
                        modifiers: .command
                    )
            }
            Divider()
            Button("Anteprima rapida") { vault.isShowingQuickLook = true }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(vault.root == nil)
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

    var body: some Commands {
        CommandMenu("Calendario") {
            Button("Vai a oggi") {
                navigation.pane = .today
                day.show(.today)
            }
            Button("Giorno precedente") { day.move(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Giorno successivo") { day.move(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Vai a data…") {
                navigation.pane = .today
                day.isChoosingDate = true
            }

            Divider()
            Button("Nuovo evento") {
                navigation.pane = .today
                day.isCreatingEvent = true
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!calendar.eventAccess.isGranted)

            Button("Nuovo promemoria") {
                navigation.pane = .today
                day.isCreatingReminder = true
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!calendar.reminderAccess.isGranted)

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

    var body: some Commands {
        CommandMenu("Inserisci") {
            Button("Wikilink") { navigation.insert("[[]]", cursorBack: 2) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Tag") { navigation.insert("#") }
            Button("Task") { navigation.insert("- [ ] ") }
            Divider()
            Button("Data pianificata") { navigation.insert(">\(CalendarDate.today) ") }
            Button("Scadenza") { navigation.insert("!\(CalendarDate.today) ") }
            Button("Promemoria") { navigation.insert("@remind(\(CalendarDate.today) 09:00) ") }
            Divider()
            Button("Nota correlata…") { vault.isAddingRelatedLink = true }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(vault.openNote == nil)
            Button("Tabella") { navigation.insert(Self.table) }
            Button("Immagine o file…") { insertFile() }
                .disabled(vault.openNote == nil)
            Button("Link email da Mail") { insertMailLink() }
            Divider()
            Button("Apri nel Workspace") { vault.openCurrentNoteInWorkspace() }
                .disabled(vault.openNote == nil)
        }
    }

    private static let table = """
    | Colonna | Colonna |
    |---|---|
    |  |  |

    """

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
        }
    }
}

/// The Modifica-menu entries SPEC §10 adds to the standard ones.
struct EditCommands: Commands {
    let navigation: Navigation

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Incolla come testo puro") {
                // The pasteboard is rewritten to its plain text and pasted through the
                // responder chain, so this works in any field, not only the editor.
                let plain = NSPasteboard.general.string(forType: .string) ?? ""
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(plain, forType: .string)
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift, .option])

            Divider()
            Button("Trova nella nota") { navigation.isFindRequested = true }
                .keyboardShortcut("f", modifiers: .command)
            Button("Sostituisci") { navigation.isReplaceRequested = true }
                .keyboardShortcut("f", modifiers: [.command, .option])
        }
    }
}
