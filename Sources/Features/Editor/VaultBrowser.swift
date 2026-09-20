import SwiftUI

/// The Note view: folder tree on the left, editor in the middle, inspector on the
/// right. This is the M1 screen the Editor mockup described.
struct VaultBrowser: View {
    @Environment(\.theme) var theme
    @Environment(VaultController.self) var vault
    @Environment(Navigation.self) var navigation
    /// The slash menu runs app commands through this rather than re-implementing them
    /// (M8). Injected at app level, where every collaborator it needs exists.
    @Environment(CommandActions.self) var commandActions
    /// Read for the key combinations the slash menu shows beside each app command.
    @Environment(ShortcutStore.self) var shortcuts
    @Environment(ThemeEngine.self) private var themeEngine

    var body: some View {
        VStack(spacing: 0) {
            // Above everything else in this pane, never inside one column of it - the same
            // reason `BoardTopBar` sits above `WorkspaceView`'s own `HStack` rather than
            // inside `WorkspaceBrowser` (2026-08-28, breadcrumb parity chain).
            VaultTopBar(vault: vault, navigation: navigation)
            HSplitView {
                if !navigation.isNotesFocused && !navigation.isNoteTreeCollapsed {
                    NoteListPane()
                        .frame(minWidth: 190, idealWidth: 230, maxWidth: 320)
                }
                editor
                    .frame(minWidth: 360)
                if navigation.isShowingInspector && !navigation.isNotesFocused {
                    inspector
                        .frame(minWidth: 190, idealWidth: 230, maxWidth: 320)
                }
            }
        }
        .toolbar { toolbar }
        .background(theme.color(.backgroundPrimary))
        .sheet(isPresented: Binding(
            get: { vault.isShowingQuickSwitcher },
            set: { vault.isShowingQuickSwitcher = $0 }
        )) {
            QuickSwitcher { choice in
                vault.isShowingQuickSwitcher = false
                open(choice)
            }
        }
        .sheet(isPresented: Binding(
            get: { vault.isAddingRelatedLink },
            set: { vault.isAddingRelatedLink = $0 }
        )) {
            RelatedLinkSheet()
        }
        .sheet(isPresented: Binding(
            get: { vault.isChoosingTemplate },
            set: { vault.isChoosingTemplate = $0 }
        )) {
            TemplateSheet()
        }
        .modifier(HistorySheetPresentation())
    }

    /// Acts on what the quick switcher was asked for.
    ///
    /// Here and not in the switcher, which is a picker shared with the task view: only this
    /// screen has the editor a heading jump lands in, and only the controller knows whether
    /// Cmd+T asked for a tab of its own (ADR-0012 D5), which is why `openChosenNote` and not
    /// `openNote`.
    private func open(_ choice: QuickSwitcher.Choice) {
        switch choice {
        case .note(let path):
            vault.openChosenNote(at: path)
        case .dailyNote:
            Task { @MainActor in
                do { try await vault.openDailyNote(for: .today) } catch {
                    vault.recordProblem(ConformanceText.creationFailure(error))
                }
            }
        case .createNote(let title):
            Task { @MainActor in
                do { try await vault.createNote(title: title, date: .today) } catch {
                    vault.recordProblem(ConformanceText.creationFailure(error))
                }
            }
        case .heading(let path, let range, let ordinal):
            vault.openChosenNote(at: path)
            // One turn later, so the column has the note before the jump reaches it. Sent in
            // the same pass, the jump arrives at a text view still showing the note you came
            // from and puts the caret on whatever is at that offset.
            Task { @MainActor in navigation.jumpToOutlineEntry(range: range, ordinal: ordinal) }
        }
    }

    /// The commands worth a click, in the place macOS puts them.
    ///
    /// Every one of these is also a menu item with a shortcut: the toolbar is the
    /// discoverable copy, not a second implementation. Nothing lives only here.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { vault.beginNewNote() } label: {
                Label("Nuova nota", systemImage: "square.and.pencil")
                    // Same dot `NoteTabBar` uses for "modifiche non salvate" (PG-029): a
                    // draft parked by stepping out of the composer (PG-028) is otherwise
                    // invisible until the next `Cmd+N`.
                    .overlay(alignment: .topTrailing) {
                        if vault.hasParkedDraft {
                            Circle()
                                .fill(theme.color(.accentPrimary))
                                .frame(width: 6, height: 6)
                                .offset(x: 2, y: -2)
                                .accessibilityLabel("bozza di nota parcheggiata")
                        }
                    }
            }
            .help(vault.hasParkedDraft ? "Nuova nota (bozza parcheggiata)" : "Nuova nota")
            .disabled(vault.root == nil)

            Button { vault.isShowingQuickSwitcher = true } label: {
                Label("Vai alla nota", systemImage: "magnifyingglass")
            }
            .help("Vai alla nota")
            .disabled(vault.root == nil)

            Button { vault.isShowingGlobalSearch = true } label: {
                Label("Ricerca globale", systemImage: "text.magnifyingglass")
            }
            .help("Cerca in tutte le note")
            .disabled(vault.root == nil)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            // The Salva button used to live here, mirroring `NoteTabBar`'s own save state.
            // Removed (2026-09-09): the tab bar already carries the per-tab Salva/Salvato
            // control, so a second one here was a duplicate reading the same
            // `hasUnsavedChanges`, not a second capability. Cmd+S and File > Salva
            // (`VaultCommands.swift`) are untouched — the toolbar was the discoverable
            // copy, never the only implementation (ADR-0023).

            // «Modalità lettura» was here (ADR-0029 §D13): one editor now, always editable
            // and always styled, so there is no mode for a toolbar to toggle.

            // Was a plain Button that never lit up (2026-08-28, toolbar parity chain).
            // «Nuovi elementi» in Workspace is the same kind of control for the other
            // section's own trailing panel, and is a Toggle - this one now matches.
            Toggle(isOn: Bindable(navigation).isShowingInspector) {
                Label("Ispettore", systemImage: "sidebar.right")
            }
            .help("Backlink, conformità, link non risolti")
            .accessibilityIdentifier("notes-inspector-toggle")

            // Same reach pattern as Workspace's «Concentrazione»: hides the note list
            // and the inspector, leaving only the editor.
            Toggle(isOn: Bindable(navigation).isNotesFocused) {
                Label("Concentrazione", systemImage: "rectangle.expand.vertical")
            }
            .help("Nasconde la sidebar, l'elenco note e l'ispettore per lasciare più spazio all'editor")
            .accessibilityIdentifier("notes-focus-toggle")

            // Same negated-binding pattern as Workspace's «Albero» (2026-08-28):
            // `isNoteTreeCollapsed` itself keeps "collapsed = true" for the Vista menu's
            // own checkbox convention; this glyph is lit when the tree is on screen,
            // matching «Ispettore» and «Concentrazione» beside it.
            Toggle(isOn: Binding(
                get: { !navigation.isNoteTreeCollapsed },
                set: { navigation.isNoteTreeCollapsed = !$0 }
            )) {
                Label("Albero", systemImage: "sidebar.left")
            }
            .help("Mostra o nasconde l'elenco delle note e delle cartelle")
            .accessibilityIdentifier("notes-tree-toggle")

            themeToggleToolbarItem(themeEngine)
        }
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if vault.isComposingNote {
            NewNoteComposer(
                draft: vault.noteDraft ?? .init(),
                onCreated: { _ in vault.endNewNote() },
                onCancel: { vault.endNewNote() }
            )
        } else {
            // One column, or two after «Dividi l'editor» (ADR-0012 D4).
            EditorColumns()
        }
    }

    // MARK: Inspector

    @ViewBuilder
    private var inspector: some View {
        // `isOpenNoteVisible` and not just `openNote`: backlinks and the history of a
        // note the composer is covering describe something nobody is looking at (PG-027).
        if let note = vault.openNote, vault.isOpenNoteVisible {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    star(note)
                    categoryLink(note)
                    history(note)
                    backlinks(note)
                    // Under the backlinks, chosen from the mockup: the two answer the same
                    // question a step apart - who points here, and who talks about this
                    // without pointing.
                    UnlinkedMentionsSection(notePath: note.relativePath)
                    LinkedTasksPanel(title: note.title, emptyText: "nessun task linka questa nota")
                    unresolved
                }
                .padding(theme.spacing(.m))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.color(.backgroundSecondary))
        } else {
            Color.clear.background(theme.color(.backgroundSecondary))
        }
    }

    /// The star, at the top of the inspector because it is about the note as a whole rather
    /// than about anything inside it (ADR-0012 D6). The sidebar's context menu does the same
    /// thing for a note nobody has open.
    private func star(_ note: VaultController.OpenNote) -> some View {
        let isStarred = vault.isStarred(note.relativePath)
        return Button { vault.toggleStar(note.relativePath) } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .themedText(.body, color: isStarred ? .accentPrimary : .textTertiary)
                Text(isStarred ? "Preferita" : "Aggiungi alle preferite")
                    .themedText(.caption, color: .textSecondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isStarred ? "Togli dalle preferite" : "Aggiungi alle preferite")
        .accessibilityIdentifier("star-note")
    }

    /// The note's own `pergamenum-category` key, read live from `note.text` rather than
    /// from the index (SPEC "UI flows: Linked note", ADR-0047 §D10) - an unsaved edit
    /// that just added or removed the key shows here before the next write, the same
    /// reason `vault.violations(for:)` reads live text rather than the index's own copy.
    /// Nothing shows when the note carries no such key.
    @ViewBuilder
    private func categoryLink(_ note: VaultController.OpenNote) -> some View {
        if let slug = CategoryFrontmatter.slug(in: NoteDocument.parse(note.text).frontmatter.foreignKeys) {
            let category = vault.categories.entries.first { $0.slug == slug }
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                Text("CATEGORIA").themedText(.caption, color: .textTertiary)
                HStack(spacing: theme.spacing(.xs)) {
                    Circle()
                        .fill(theme.color(category?.colorToken ?? .textTertiary))
                        .frame(width: 8, height: 8)
                    Button(category?.name ?? slug) {
                        // `pendingCategorySelection` set before the pane switch, not
                        // after: `TasksView`'s `.task` reads it once the view is created,
                        // and creation happens as part of the same `pane` change
                        // (`RootView.tasksPane`, ADR-0039 §D3's "bring the destination
                        // pane forward" shape applied to a category instead of a note).
                        navigation.pendingCategorySelection = slug
                        navigation.pane = .tasks
                    }
                    .buttonStyle(.plain)
                    .themedText(.body, color: .accentPrimary)
                    .help("Vai alla categoria")
                    .accessibilityIdentifier("inspector-go-to-category")
                    Spacer()
                    Button {
                        Task { await vault.unlinkCategory(fromNoteAt: note.relativePath) }
                    } label: {
                        Image(systemName: "link.badge.minus").themedText(.caption, color: .textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Scollega la categoria")
                    .accessibilityIdentifier("inspector-unlink-category")
                }
            }
        } else {
            AssignCategoryMenu(notePath: note.relativePath)
        }
    }

    private func backlinks(_ note: VaultController.OpenNote) -> some View {
        let records = vault.index.backlinks(toTitle: note.title)
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("BACKLINK").themedText(.caption, color: .textTertiary)
            if records.isEmpty {
                Text("nessuno").themedText(.caption, color: .textTertiary)
            } else {
                ForEach(records, id: \.relativePath) { record in
                    Button(record.title) { vault.openNote(at: record.relativePath) }
                        .buttonStyle(.plain)
                        .themedText(.body, color: .accentPrimary)
                }
            }
        }
    }

    private var unresolved: some View {
        let links = vault.index.unresolvedLinks().prefix(10)
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("LINK NON RISOLTI").themedText(.caption, color: .textTertiary)
            if links.isEmpty {
                Text("nessuno").themedText(.caption, color: .textTertiary)
            } else {
                ForEach(Array(links), id: \.target) { entry in
                    Text("\(entry.target) · \(entry.sources.count)")
                        .themedText(.caption, color: .textSecondary)
                        .help(entry.sources.map(\.title).joined(separator: "\n"))
                }
            }
        }
    }
}
