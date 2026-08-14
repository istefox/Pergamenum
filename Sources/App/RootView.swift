import SwiftUI

/// The window's panes.
///
/// The sidebar lists the app's actual work and nothing else. The design system left
/// it for Settings, where the look of the app belongs, and the editor mockup left it
/// for the Note pane, which has had the real editor since M1 - a mockup beside the
/// thing it was a mockup of is a place for a user to go and find nothing.
struct RootView: View {
    @Environment(\.theme) private var theme
    @Environment(ThemeEngine.self) private var engine
    /// Optional, which is the shape a macOS sidebar `List` expects: with a
    /// non-optional binding SwiftUI writes the focused row back over the initial
    /// value, so the window opened on an arbitrary pane.
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation
    @Environment(ShortcutStore.self) private var shortcuts

    /// Optional, which is the shape a macOS sidebar `List` expects: with a
    /// non-optional binding SwiftUI writes the focused row back over the initial
    /// value, so the window opened on an arbitrary pane.
    private var selectedPane: Binding<Navigation.Pane?> {
        Binding(
            get: { navigation.pane },
            set: { if let new = $0 { navigation.pane = new } }
        )
    }
    private var pane: Navigation.Pane { navigation.pane }

    var body: some View {
        content
            // A `pergamenum://canvas` link has to bring the Workspace forward before
            // anything can act on it: the view that consumes the route only exists
            // while that pane is shown, so from any other pane the link did nothing at
            // all. Switching the pane here, where Navigation lives, is the whole fix -
            // the consuming happens in WorkspaceView, once it is on screen.
            .onChange(of: vault.routeState.pendingCanvas?.path) { _, pending in
                if pending != nil { navigation.pane = .workspace }
            }
            .task {
                if vault.routeState.pendingCanvas != nil { navigation.pane = .workspace }
                if let root = vault.root { engine.attach(vaultRoot: root) }
            }
            // The vault's own themes (SPEC §11.3). Without this the engine never
            // looked at `.pergamenum/themes/` outside the test suite, so a theme file
            // in a vault did nothing at all and the picker in Settings could only
            // ever offer the two bundled themes.
            .onChange(of: vault.root) { _, newRoot in
                if let newRoot {
                    engine.attach(vaultRoot: newRoot)
                } else {
                    engine.detachVault()
                }
            }
            .sheet(isPresented: Bindable(navigation).isShowingTaskSyntaxHelp) {
                HelpSheet(topic: .taskSyntax) { navigation.isShowingTaskSyntaxHelp = false }
            }
            .sheet(isPresented: Bindable(navigation).isShowingConventionsHelp) {
                HelpSheet(topic: .conventions) { navigation.isShowingConventionsHelp = false }
            }
            .sheet(isPresented: Bindable(navigation).isShowingDiaryHelp) {
                HelpSheet(topic: .diary) { navigation.isShowingDiaryHelp = false }
            }
    }

    private var content: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.color(.backgroundSecondary))
        }
        .sheet(isPresented: Binding(
            get: { vault.isShowingGlobalSearch },
            set: { vault.isShowingGlobalSearch = $0 }
        )) {
            GlobalSearchView()
        }
        // At window level rather than inside the Attività pane: quick capture is meant
        // to work from wherever you are, and presented by that pane the command did
        // nothing at all from the other four.
        .sheet(isPresented: Binding(
            get: { vault.taskDraft != nil },
            set: { if !$0 { vault.taskDraft = nil } }
        )) {
            TaskComposer { vault.taskDraft = nil }
        }
        // Wide enough for the Note pane's own three columns beside this sidebar:
        // below this the outer sidebar gets squeezed into an unreadable strip.
        .frame(minWidth: 1180, minHeight: 700)
    }

    /// Explicit `ForEach` plus `.tag`, rather than the data-driven `List` initialiser:
    /// with `Identifiable` rows the latter binds the selection to the element's `id`,
    /// which silently ignored the initial value.
    private var sidebar: some View {
        List(selection: selectedPane) {
            ForEach(Navigation.Pane.allCases) { item in
                Label(item.title, systemImage: item.symbol)
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
        case .notes: notesPane
        case .workspace: workspacePane
        case .today: todayPane
        case .diary: diaryPane
        case .tasks: tasksPane
        case .conformance: conformancePane
        }
    }

    @ViewBuilder
    private var diaryPane: some View {
        if vault.root == nil {
            needsVault("Il diario tiene la giornata: il testo libero e le ore che sono state usate.")
        } else {
            DiaryView()
        }
    }

    @ViewBuilder
    private var conformancePane: some View {
        if vault.root == nil {
            needsVault("Il linter verifica le note contro le convenzioni harness.")
        } else {
            ConformanceView()
        }
    }

    @ViewBuilder
    private var todayPane: some View {
        if vault.root == nil {
            needsVault("La vista Oggi mostra la nota giornaliera e la timeline.")
        } else {
            TodayView()
        }
    }

    @ViewBuilder
    private var tasksPane: some View {
        if vault.root == nil {
            needsVault("Le attività sono i task scritti nelle note.")
        } else {
            TasksView()
        }
    }

    @ViewBuilder
    private var workspacePane: some View {
        if vault.root == nil {
            needsVault("Il Workspace è una vista spaziale delle cartelle delle note.")
        } else {
            WorkspaceView()
        }
    }

    private func needsVault(_ explanation: String) -> some View {
        VStack(spacing: theme.spacing(.m)) {
            Image(systemName: "folder")
                .font(.system(size: 40))
                .foregroundStyle(theme.color(.textTertiary))
            Text("Nessuna cartella note aperta").themedText(.title)
            Text(explanation)
                .themedText(.body, color: .textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Apri cartella note…") { VaultOpenPanel.chooseVault(into: vault) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var notesPane: some View {
        if vault.root == nil {
            VStack(spacing: theme.spacing(.m)) {
                Image(systemName: "folder")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.color(.textTertiary))
                Text("Nessuna cartella note aperta").themedText(.title)
                Text("Scegli la cartella che contiene le note. Pergamenum non la modifica finché non salvi una nota.")
                    .themedText(.body, color: .textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button("Apri cartella note…") { VaultOpenPanel.chooseVault(into: vault) }
                    .keyboardShortcut(shortcuts.shortcut(for: .openVault))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
