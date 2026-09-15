import SwiftUI

// ADR-0045 §D2 (PG-143 structure refactor): the toolbar/menu rendering half of
// `PraticaCommandActions`, moved out unchanged - a pure file move, every type here
// was already top-level.

/// The pratica row's context menu and the same catalogue drawn as a toolbar row.
///
/// Built by iterating `PraticaCommandActions.commands(for:)` rather than by listing
/// entries: the titles, the symbols and the applicability rules come from the
/// catalogue, so a surface cannot list a pratica's commands differently (ADR-0023 §D8).
@MainActor
enum PraticaMenuItems {
    @ViewBuilder
    static func menu(for pratica: PraticaListItem, actions: PraticaCommandActions) -> some View {
        ForEach(actions.commands(for: pratica), id: \.self) { command in
            if command == .delete { Divider() }
            Button(command.title) { actions.run(command, on: pratica) }
                .accessibilityIdentifier(command.identifier)
        }
    }
}

/// The message row's footer and its context menu (ADR-0023 §D1) - one catalogue, two
/// renderings, the argument-carrying pair drawn as a submenu of destinations on both.
@MainActor
enum MessageMenuItems {
    @ViewBuilder
    static func menu(
        for entry: PraticaTimelineEntry, detail: PraticaRowDetail?, actions: PraticaCommandActions
    ) -> some View {
        ForEach(actions.commands(for: detail), id: \.self) { command in
            item(command, entry: entry, detail: detail, actions: actions)
        }
    }

    @ViewBuilder
    static func item(
        _ command: MessageCommand,
        entry: PraticaTimelineEntry,
        detail: PraticaRowDetail?,
        actions: PraticaCommandActions
    ) -> some View {
        if command.carriesArgument {
            Menu(command.title) {
                destinations(command, entry: entry, detail: detail, actions: actions)
            }
            .accessibilityIdentifier(command.identifier)
        } else {
            Button(command.title) { actions.run(command, on: entry, detail: detail) }
                .accessibilityIdentifier(command.identifier)
        }
    }

    /// The submenu both surfaces build from the same list, so «Sposta in ▸» and
    /// «Aggiungi anche a ▸» cannot offer different pratiche in the menu and in the
    /// footer.
    @ViewBuilder
    private static func destinations(
        _ command: MessageCommand,
        entry: PraticaTimelineEntry,
        detail: PraticaRowDetail?,
        actions: PraticaCommandActions
    ) -> some View {
        let others = actions.destinations(besides: actions.praticaPathForMenu(of: detail))
        if others.isEmpty {
            Text("Nessun'altra pratica")
        } else {
            ForEach(others) { destination in
                Button("\(destination.client) › \(destination.title)") {
                    Task { @MainActor in
                        switch command {
                        case .moveTo: await actions.move(entry, detail: detail, to: destination)
                        case .alsoAddTo: await actions.alsoAdd(entry, detail: detail, to: destination)
                        default: break
                        }
                    }
                }
            }
        }
    }
}

extension PraticaCommandActions {
    /// The folder a row's file sits in, for the destinations submenu - the same
    /// arithmetic `praticaPath(detail:)` does, reachable from the menu builder.
    func praticaPathForMenu(of detail: PraticaRowDetail?) -> String {
        guard let notePath = detail?.notePath,
              let range = notePath.range(of: "/\(PraticheController.messagesDirectoryName)/")
        else { return pratiche.selection ?? "" }
        return String(notePath[..<range.lowerBound])
    }
}
