import SwiftUI

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D11 and §D12, plan
// docs/plans/contenitore.md, Task 7 - R-19, R-20, R-27.

/// Menu entries for a list of `ContenitoreCommand`s on one document: the row's context menu and
/// the «Documento» menu both draw through this, so neither holds its own list (ADR-0023 §D1).
///
/// «Sposta in…» is a submenu of the containers, the root first (mockup 1e). It lives inside the
/// row's own menu, not in a view nested in the row, so ADR-0069's AppKit host is not needed.
struct ContenitoreMenuItems: View {
    let commands: [ContenitoreCommand]
    let schedaPath: String
    let actions: ContenitoreCommandActions

    var body: some View {
        ForEach(commands, id: \.self) { command in
            if command == .trash { Divider() }
            if command == .moveTo {
                ContenitoreMoveMenu(schedaPath: schedaPath, actions: actions)
                    .disabled(!actions.canRun(command, on: schedaPath))
            } else {
                Button(command.title) { actions.run(command, on: schedaPath) }
                    .disabled(!actions.canRun(command, on: schedaPath))
                    .accessibilityIdentifier(command.identifier)
            }
        }
    }
}

/// «Sposta in…» ▸ the root, then every sub-container, indented by depth.
struct ContenitoreMoveMenu: View {
    let schedaPath: String
    let actions: ContenitoreCommandActions

    var body: some View {
        let root = actions.contenitore.root
        Menu(ContenitoreCommand.moveTo.title) {
            Button("\(root) (radice)") { move(to: root) }
            ForEach(ContenitoreListModel.allPaths(actions.contenitore.containers())) { node in
                Button(String(repeating: "    ", count: node.depth + 1) + node.name) { move(to: node.path) }
            }
        }
        .accessibilityIdentifier(ContenitoreCommand.moveTo.identifier)
    }

    private func move(to container: String) {
        Task { await actions.move(schedaPath, toContainer: container) }
    }
}

/// The «Documento» menu (ADR-0071 §D11, gate G2): between Inserisci and Task, active only while
/// the Contenitore pane is shown. It carries the catalogue's `.documento` entries and «Nuovo
/// sottocontenitore…»; File and Modifica carry the other three (§D12).
///
/// Keys: Cmd+Opt+K «Classifica…» and Cmd+Opt+O «Apri scheda», both free in the remappable
/// catalogue (`ShortcutCommand.defaultBinding`). «Apri» has no menu key: Return as a key
/// equivalent would fire from every text field in the window, the inspector's description
/// included, so the list opens on Return and double-click itself (`primaryAction`).
struct DocumentoCommands: Commands {
    let navigation: Navigation
    let vault: VaultController
    let contenitore: ContenitoreController

    private var actions: ContenitoreCommandActions {
        ContenitoreCommandActions(vault: vault, navigation: navigation, contenitore: contenitore)
    }

    private var isActive: Bool { navigation.pane == .contenitore && vault.root != nil }

    var body: some Commands {
        CommandMenu("Documento") {
            let selection = isActive ? contenitore.selection : nil
            ForEach(ContenitoreCommand.menuBar(.documento), id: \.self) { command in
                if command == .moveTo {
                    if let selection {
                        ContenitoreMoveMenu(schedaPath: selection, actions: actions)
                    } else {
                        Menu(command.title) {}.disabled(true)
                    }
                } else {
                    Button(command.title) { if let selection { actions.run(command, on: selection) } }
                        .keyboardShortcut(Self.key(for: command))
                        .disabled(selection.map { !actions.canRun(command, on: $0) } ?? true)
                }
            }
            Divider()
            Button("Nuovo sottocontenitore…") { contenitore.creatingContainerIn = Self.parent(of: contenitore) }
                .disabled(!isActive)
        }
    }

    /// The container a new one goes into: the one in scope, the root otherwise.
    static func parent(of contenitore: ContenitoreController) -> String {
        if case .container(let path) = contenitore.scope { return path }
        return contenitore.root
    }

    private static func key(for command: ContenitoreCommand) -> KeyboardShortcut? {
        switch command {
        case .classify: KeyboardShortcut("k", modifiers: [.command, .option])
        case .openScheda: KeyboardShortcut("o", modifiers: [.command, .option])
        default: nil
        }
    }
}
