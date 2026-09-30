import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D12, plan
// docs/plans/contenitore.md, Task 7 - R-23, R-27.
//
// Its own file because `CommandActions.swift` sits at the edge of `file_length`.

/// While the Contenitore pane is on screen, File's «Copia link Pergamenum» and «Rivela nel
/// Finder», and Modifica's «Sposta nel Cestino», act on the selected document: the menu bar
/// carries one of each, not a second copy for the pane (§D12). Away from the pane nothing here
/// answers, and the Note pane's behaviour is exactly what it was.
extension CommandActions {
    /// The two File commands the pane redirects.
    private static let contenitoreFileCommands: Set<ShortcutCommand> = [.copyLink, .revealInFinder]

    /// The pane's command runner, when the pane is shown and a controller is wired.
    var contenitoreActions: ContenitoreCommandActions? {
        guard navigation.pane == .contenitore, let contenitore else { return nil }
        return ContenitoreCommandActions(vault: vault, navigation: navigation, contenitore: contenitore)
    }

    /// Whether `command` is the pane's to answer now, and if so whether it can run: nil leaves
    /// the question to the open note.
    func canRunOnContenitoreSelection(_ command: ShortcutCommand) -> Bool? {
        guard Self.contenitoreFileCommands.contains(command), let actions = contenitoreActions else { return nil }
        guard let selection = actions.contenitore.selection else { return false }
        return actions.canRun(Self.contenitoreCommand(for: command), on: selection)
    }

    /// Runs `command` on the pane's selection and returns true, or returns false and does nothing
    /// when the pane is not the one shown.
    func runOnContenitoreSelection(_ command: ShortcutCommand) -> Bool {
        guard Self.contenitoreFileCommands.contains(command), let actions = contenitoreActions else { return false }
        if let selection = actions.contenitore.selection {
            actions.run(Self.contenitoreCommand(for: command), on: selection)
        }
        return true
    }

    /// Modifica › «Sposta nel Cestino»: enabled only with the pane shown and a document selected.
    var canTrashContenitoreSelection: Bool {
        guard let actions = contenitoreActions, let selection = actions.contenitore.selection else { return false }
        return actions.canRun(.trash, on: selection)
    }

    /// Asks the pane's confirmation for the selected document (the dialog performs the trash).
    func trashContenitoreSelection() {
        guard let actions = contenitoreActions, let selection = actions.contenitore.selection else { return }
        actions.run(.trash, on: selection)
    }

    private static func contenitoreCommand(for command: ShortcutCommand) -> ContenitoreCommand {
        command == .copyLink ? .copyLink : .revealInFinder
    }
}
