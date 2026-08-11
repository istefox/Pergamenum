import SwiftUI

/// The M0 shell: a sidebar over the design system gallery and the mockups of the
/// screens M1 to M5 will implement for real.
///
/// This is scaffolding with an expiry date. Once M1 lands, the sidebar becomes the
/// vault's note tree and the gallery moves behind a developer-only menu item.
struct RootView: View {
    @Environment(\.theme) private var theme
    @Environment(ThemeEngine.self) private var engine
    /// Optional, which is the shape a macOS sidebar `List` expects: with a
    /// non-optional binding SwiftUI writes the focused row back over the initial
    /// value, so the window opened on an arbitrary pane.
    @Environment(VaultController.self) private var vault
    @State private var selectedPane: Pane? = .vault
    private var pane: Pane { selectedPane ?? .vault }

    /// Named `Pane` rather than `Section` so it does not shadow `SwiftUI.Section`
    /// inside this file's view builders.
    enum Pane: String, CaseIterable, Identifiable, Hashable {
        case vault
        case tokens
        case editor
        case workspace
        case today
        case tasks

        var id: String { rawValue }

        /// Panes still showing a mockup rather than the real feature. They stay in the
        /// sidebar as the reference the milestone is built against, and each one leaves
        /// as its milestone lands.
        var isMockup: Bool {
            switch self {
            case .vault, .tokens, .workspace, .tasks, .today: false
            case .editor: true
            }
        }

        var title: String {
            switch self {
            case .vault: "Vault"
            case .tokens: "Design system"
            case .editor: "Editor"
            case .workspace: "Workspace"
            case .today: "Oggi"
            case .tasks: "Attività"
            }
        }

        var symbol: String {
            switch self {
            case .vault: "books.vertical"
            case .tokens: "paintpalette"
            case .editor: "doc.text"
            case .workspace: "square.on.square"
            case .today: "calendar"
            case .tasks: "checklist"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.color(.backgroundSecondary))
        }
        // Wide enough for the vault pane's own three columns beside this sidebar:
        // below this the outer sidebar gets squeezed into an unreadable strip.
        .frame(minWidth: 1180, minHeight: 700)
    }

    /// Explicit `ForEach` plus `.tag`, rather than the data-driven `List` initialiser:
    /// with `Identifiable` rows the latter binds the selection to the element's `id`,
    /// which silently ignored the initial value.
    private var sidebar: some View {
        List(selection: $selectedPane) {
            ForEach(Pane.allCases) { item in
                HStack {
                    Label(item.title, systemImage: item.symbol)
                    if item.isMockup {
                        Spacer()
                        Text("mockup").themedText(.caption, color: .textTertiary)
                    }
                }
                .tag(item)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color(.backgroundSecondary))
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        .safeAreaInset(edge: .bottom) { themePicker }
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .vault: vaultPane
        case .tokens: DesignGalleryView()
        case .editor: EditorMockup()
        case .workspace: workspacePane
        case .today: todayPane
        case .tasks: tasksPane
        }
    }

    @ViewBuilder
    private var todayPane: some View {
        if vault.root == nil {
            needsVault("La vista Oggi mostra la nota giornaliera del vault e la timeline.")
        } else {
            TodayView()
        }
    }

    @ViewBuilder
    private var tasksPane: some View {
        if vault.root == nil {
            needsVault("Le attività sono i task scritti nelle note del vault.")
        } else {
            TasksView()
        }
    }

    @ViewBuilder
    private var workspacePane: some View {
        if vault.root == nil {
            needsVault("Il Workspace è una vista spaziale delle cartelle del vault.")
        } else {
            WorkspaceView()
        }
    }

    private func needsVault(_ explanation: String) -> some View {
        VStack(spacing: theme.spacing(.m)) {
            Image(systemName: "books.vertical")
                .font(.system(size: 40))
                .foregroundStyle(theme.color(.textTertiary))
            Text("Nessun vault aperto").themedText(.title)
            Text(explanation)
                .themedText(.body, color: .textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Apri vault…") { VaultOpenPanel.chooseVault(into: vault) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var vaultPane: some View {
        if vault.root == nil {
            VStack(spacing: theme.spacing(.m)) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.color(.textTertiary))
                Text("Nessun vault aperto").themedText(.title)
                Text("Scegli la cartella del vault. Pergamenum non la modifica finché non salvi una nota.")
                    .themedText(.body, color: .textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button("Apri vault…") { VaultOpenPanel.chooseVault(into: vault) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { VaultOpenPanel.reopenLastVault(into: vault) }
        } else {
            VaultBrowser()
        }
    }

    /// The M0 acceptance criterion is a runtime theme switch, so the control sits in
    /// the window rather than only in Settings, which does not exist yet.
    private var themePicker: some View {
        @Bindable var engine = engine
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("TEMA")
                .themedText(.caption, color: .textTertiary)
            Picker("Tema", selection: $engine.selection) {
                Text("Sistema").tag(ThemeEngine.Selection.followSystem)
                Text("Chiaro").tag(ThemeEngine.Selection.light)
                Text("Scuro").tag(ThemeEngine.Selection.dark)
                ForEach(engine.selectableThemes.filter { !$0.id.hasPrefix("pergamenum-") }) { custom in
                    Text(custom.name).tag(ThemeEngine.Selection.named(custom.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if !engine.problems.isEmpty {
                Label("\(engine.problems.count) problemi nei token", systemImage: "exclamationmark.triangle")
                    .themedText(.caption, color: .taskOverdue)
                    .help(engine.problems.joined(separator: "\n"))
            }
        }
        .padding(theme.spacing(.s))
    }
}
