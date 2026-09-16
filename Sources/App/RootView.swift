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
    /// The day pane's controller, because three sidebar rows are three scales of it
    /// (ADR-0013 §D4) rather than three panes.
    @Environment(DayController.self) private var day
    /// The places the window has been (ADR-0015).
    @Environment(NavigationHistory.self) private var history

    /// Optional, which is the shape a macOS sidebar `List` expects: with a
    /// non-optional binding SwiftUI writes the focused row back over the initial
    /// value, so the window opened on an arbitrary pane.
    private var selectedItem: Binding<SidebarItem?> {
        Binding(
            get: { currentItem },
            set: { if let new = $0 { choose(new) } }
        )
    }
    private var pane: Navigation.Pane { navigation.pane }

    /// The row the sidebar lights, derived from where the window actually is rather
    /// than stored beside it: with two copies of "which row is chosen" the toolbar's
    /// scale picker would move the week without moving the row.
    private var currentItem: SidebarItem {
        guard pane == .today else { return .pane(pane) }
        if day.scale != .day { return .scale(day.scale) }
        // Today, at the day scale, with today's note in the column: that *is* what the
        // «Nota di oggi» row goes to, so it is the row that should be lit. Move a day or
        // close the note and the highlight walks back to «Oggi» on its own, because the
        // selection is derived from the state and not stored beside it.
        return isTodaysNoteOpen ? .dailyNote : .pane(.today)
    }

    private var isTodaysNoteOpen: Bool {
        day.day == .today && vault.openNote?.relativePath == vault.dailyNotePath(for: .today)
    }

    /// Where the window is, and how to get back there (ADR-0015). Built per draw from the same
    /// three controllers `currentItem` reads, so the sidebar's highlight and the history can
    /// never disagree about which place is showing.
    private var place: WindowPlace {
        WindowPlace(navigation: navigation, vault: vault, day: day)
    }

    /// Whether the pane on screen is running its own "concentrazione" (2026-08-28,
    /// toolbar parity chain: Note gained its own flag alongside Workspace's).
    private var isFocusedPane: Bool {
        (navigation.isWorkspaceFocused && pane == .workspace)
            || (navigation.isNotesFocused && pane == .notes)
    }

    /// Collapsed only for concentrazione on the pane it belongs to. Derived rather than
    /// stored beside `isWorkspaceFocused`/`isNotesFocused`, the same reasoning as
    /// `currentItem` above: two copies of "is the sidebar open" can disagree, one copy
    /// cannot.
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { isFocusedPane ? .detailOnly : .all },
            set: {
                if $0 == .all {
                    navigation.isWorkspaceFocused = false
                    navigation.isNotesFocused = false
                }
            }
        )
    }

    /// What a row does when it is chosen. Two of them are not destinations, and land on
    /// the Note pane, which is where what they open ends up.
    private func choose(_ item: SidebarItem) {
        switch item {
        case .pane(let chosen):
            navigation.pane = chosen
            if chosen == .today { day.scale = .day }
        case .scale(let scale):
            navigation.pane = .today
            day.scale = scale
        case .dailyNote:
            // The note of the day, shown where a day is shown: the Oggi pane, on today,
            // at the day scale, with the note in its own column. Opening it into the Note
            // pane instead is what made this row feel like a click that bounced.
            navigation.pane = .today
            day.show(.today)
            day.scale = .day
            day.openDailyNote()
        }
    }

    var body: some View {
        content
            // One colour across the whole strip, and opaque. The toolbar is translucent by
            // default, so the backgrounds of the three panes underneath show through it and
            // the seams of the split - the divider between the two editor columns, and the
            // one before the inspector - climb into the title bar as hard vertical edges.
            .toolbarBackground(theme.color(.backgroundSecondary), for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
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
            // `TaskCommand.linkBoard`'s picker (ADR-0039 §D3), hosted here rather than by
            // `TasksView` so it opens from every surface that offers the command — the
            // "Task collegati" panel included, which lives inside the Workspace pane where
            // `TasksView` does not exist.
            .sheet(item: Bindable(navigation).taskPickingBoard) { task in
                WorkspacePicker(task: task) { navigation.taskPickingBoard = nil }
            }
            // `TaskCommand.assignCategory`'s picker (ADR-0047 §D5), hosted here for the
            // same reason as the board picker above: it opens from every surface that
            // offers the command.
            .sheet(item: Bindable(navigation).taskPickingCategory) { task in
                CategoryPicker(task: task) { navigation.taskPickingCategory = nil }
            }
    }

    private var content: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            sidebar
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.color(.backgroundSecondary))
                // On the detail and not on a pane: the two arrows belong to every pane, and
                // declared here they arrive before each pane's own leading group (ADR-0015 §D5).
                .windowHistory(history, place: place)
        }
        .sheet(isPresented: Binding(
            get: { vault.isShowingGlobalSearch },
            set: { vault.isShowingGlobalSearch = $0 }
        )) {
            GlobalSearchView()
        }
        // File → "Importa file…" (SPEC §10): vault-wide, not tied to any one pane,
        // same reasoning as the global search sheet above.
        .sheet(isPresented: Binding(
            get: { !vault.fileImportProposals.isEmpty },
            set: { if !$0 { vault.fileImportProposals = [] } }
        )) {
            FileImportSheet(
                proposals: Binding(
                    get: { vault.fileImportProposals },
                    set: { vault.fileImportProposals = $0 }
                ),
                onCancel: { vault.fileImportProposals = [] },
                onConfirm: { proposals in
                    for proposal in proposals { vault.commitImport(proposal) }
                    vault.fileImportProposals = []
                    Task { await vault.rescan() }
                }
            )
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
        // At window level and not inside `PratichePane`, for the reason the two above
        // are: «Aggiungi a pratica da Mail…» is Cmd+Shift+P from anywhere, and a sheet
        // presented by that pane would do nothing at all from the other five
        // (ADR-0036 R-20/R-21).
        .sheet(isPresented: Bindable(navigation).isShowingNuovaPratica) {
            NuovaPraticaWizard { navigation.isShowingNuovaPratica = false }
        }
        .sheet(isPresented: Bindable(navigation).isShowingAddToPratica) {
            AddToPraticaSheet(
                onClose: { navigation.isShowingAddToPratica = false },
                onNewPratica: {
                    navigation.pane = .pratiche
                    navigation.isShowingNuovaPratica = true
                }
            )
        }
        // Wide enough for the Note pane's own three columns beside this sidebar:
        // below this the outer sidebar gets squeezed into an unreadable strip.
        .frame(minWidth: 1180, minHeight: 700)
    }

    /// Explicit `ForEach` plus `.tag`, rather than the data-driven `List` initialiser:
    /// with `Identifiable` rows the latter binds the selection to the element's `id`,
    /// which silently ignored the initial value.
    ///
    /// Three sections rather than one list (M12): eleven rows in a row read as a list of
    /// commands, and the headings say what kind of thing each row is before they say
    /// which one.
    private var sidebar: some View {
        List(selection: selectedItem) {
            ForEach(SidebarItem.Group.allCases) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        row(item)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color(.backgroundSecondary))
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        // A pane switcher row's own label ("Note", "Workspace") collides with the
        // bare-root segment `VaultTopBar`/`BoardChrome` draw for that same pane when
        // nothing is open in it (2026-08-28, recovery checkpoint) - both read the pane
        // name, both are on screen together whenever that pane is the default at
        // launch, and neither carried an identifier to tell them apart. Scoping the
        // sidebar itself lets a lookup say "the switcher row", not "any text reading
        // the pane's name" - see `WorkspaceIntegrationUITests.openPane`.
        .accessibilityIdentifier("root-sidebar")
    }

    /// `.badge` before `.tag`, and the order is the whole thing: applied after it,
    /// `.badge` drops the tag, the `List` falls back to the `ForEach`'s implicit id -
    /// a `String` - and no row can ever equal a `SidebarItem` selection. The sidebar
    /// then lights nothing and swallows every click, which is how it shipped for the
    /// twenty minutes the starred count sat on the wrong side of the tag.
    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .badge(item == .pane(.starred) ? vault.starredNotes.count : 0)
            .tag(item)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .notes: notesPane
        case .workspace: workspacePane
        case .today: todayPane
        case .diary: diaryPane
        case .tasks: tasksPane
        case .tags: tagsPane
        case .views: viewsPane
        case .starred: starredPane
        case .recordings: recordingsPane
        case .pratiche: pratichePane
        }
    }

    @ViewBuilder
    private var pratichePane: some View {
        if vault.root == nil {
            needsVault("Una pratica è una cartella del vault che si riempie da Mail: senza un vault non c'è dove tenerla.")
        } else {
            PratichePane()
        }
    }

    @ViewBuilder
    private var recordingsPane: some View {
        if vault.root == nil {
            needsVault("Le registrazioni Plaud diventano note di trascrizione: senza un vault non c'è dove scriverle.")
        } else {
            RecordingsPane()
        }
    }

    @ViewBuilder
    private var starredPane: some View {
        if vault.root == nil {
            needsVault("Le preferite sono le note con la stella, tenute in .pergamenum/starred.json.")
        } else {
            StarredPane()
        }
    }

    @ViewBuilder
    private var viewsPane: some View {
        if vault.root == nil {
            needsVault("Una vista è una query salvata dentro una nota, disegnata come tabella, board o calendario.")
        } else {
            ViewsPane()
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
    private var tagsPane: some View {
        if vault.root == nil {
            needsVault("Il pannello Tag raggruppa i tag per namespace e restringe le note a quelli scelti.")
        } else {
            TagBrowserView()
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

}
