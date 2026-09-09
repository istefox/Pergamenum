import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
// R-18, R-23, R-27, R-32, R-33; DESIGN.md screens 1a, 1b, 1c, 1g; ADR §D13.
//
// Composed the way `VaultBrowser` is: one top bar for the whole pane, then an
// `HSplitView` of list · timeline · inspector. The bar is never inside a column, for
// the reason `VaultTopBar` is not either - it is chrome of the pane, and a breadcrumb
// living inside the list column would scroll with it.
//
// Column widths from DESIGN.md "Binding decisions": list 260, timeline minimum 360,
// inspector 280, all inside UX-BLUEPRINT's 190-320 ranges.
struct PratichePane: View {
    @Environment(\.theme) private var theme
    @Environment(PraticheController.self) private var pratiche
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation

    /// The window's own, handed to `PraticaCommandActions` so «Escludi» and «Sposta
    /// in…» register on the stack `NSTextView` already uses (ADR-0026 §D5) rather than
    /// on a second, pane-private one.
    @Environment(\.undoManager) private var undoManager

    @FocusState private var isFilterFocused: Bool
    /// `pratica.md` as the inspector shows it, re-read when the chosen pratica changes
    /// rather than on every draw.
    @State private var inspectorBody = ""
    /// «Rinomina…»'s typed name, held by the pane and not by the row: the row is culled
    /// by its `List` the moment it scrolls out of view, taking a half-typed name with it.
    @State private var typedName = ""
    /// R-22's tracer bullet, as it last answered - shown, never acted on.
    @State private var dropReport: MailDropReport?

    var body: some View {
        VStack(spacing: 0) {
            PraticaTopBar(actions: actions, filterFocus: $isFilterFocused)
            // R-18: the banner appears the moment a trigger's own probe comes back
            // `.notGranted`, and goes away on the first trigger that finds the access
            // granted - no restart, no launch check (ADR §D10).
            if pratiche.fullDiskAccessState == .notGranted {
                FullDiskAccessBanner()
            }
            if let progress = pratiche.syncProgress, pratiche.syncingPraticaPath != nil {
                syncProgress(progress)
            }
            if let problem = pratiche.problem {
                Text(problem)
                    .themedText(.caption, color: .taskOverdue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.spacing(.m))
                    .padding(.bottom, theme.spacing(.xs))
                    .accessibilityIdentifier("pratiche-problem")
            }
            HSplitView {
                if !navigation.isNotesFocused {
                    PraticheListColumn(actions: actions, onNewPratica: newPratica)
                        .frame(minWidth: 190, idealWidth: 260, maxWidth: 320)
                }
                content
                    .frame(minWidth: 360)
                if navigation.isShowingPraticaInspector && !navigation.isNotesFocused {
                    inspector
                        .frame(minWidth: 190, idealWidth: 280, maxWidth: 320)
                }
            }
        }
        .background(theme.color(.backgroundPrimary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-pane")
        // On appearing and at no other moment: nothing reads a person's mail store
        // until they have opened this pane at least once in the session (ADR §D10 -
        // the probe is per trigger, never at launch).
        .task {
            pratiche.load(from: vault)
            pratiche.startWatching(vault)
            await pratiche.syncAll(in: vault, kind: .vaultOpen)
        }
        .task(id: pratiche.selection) { loadInspector() }
        .alert(
            "Eliminare «\(pratiche.deletionRequest?.title ?? "")»?",
            isPresented: deletionAlert,
            presenting: pratiche.deletionRequest
        ) { pratica in
            Button("Elimina", role: .destructive) { actions.confirmDeletion(of: pratica) }
                .accessibilityIdentifier("pratiche-delete-confirm")
            Button("Annulla", role: .cancel) { pratiche.deletionRequest = nil }
        } message: { _ in
            // R-34: the folder goes to the Trash, never to `removeItem` - so the
            // sentence promises exactly what the code does.
            Text("La cartella, i messaggi e gli allegati vanno nel Cestino.")
        }
        // A sheet and not an alert: R-34's «Elimina pratica» is the only alert in the
        // whole feature (UX-BLUEPRINT), and a name to type is not a yes/no question.
        .sheet(item: renameRequest) { pratica in
            renameSheet(pratica)
        }
        .sheet(item: regenerationRequest) { request in
            regenerationSheet(request)
        }
    }

    /// The one `PraticaCommandActions` every surface of this pane shares, so the list
    /// column's context menu, the timeline's row menus and the top bar's status pill
    /// all run the same bodies (ADR-0023 §D1).
    private var actions: PraticaCommandActions {
        PraticaCommandActions(
            pratiche: pratiche, vault: vault, navigation: navigation, undoManager: undoManager
        )
    }

    private var composer: PraticaEntryComposer {
        PraticaEntryComposer(pratiche: pratiche, vault: vault, navigation: navigation)
    }

    private func newPratica() {
        navigation.isShowingNuovaPratica = true
    }

    private var deletionAlert: Binding<Bool> {
        Binding(
            get: { pratiche.deletionRequest != nil },
            set: { if !$0 { pratiche.deletionRequest = nil } }
        )
    }

    private var renameRequest: Binding<PraticaListItem?> {
        Binding(
            get: { pratiche.renameRequest },
            set: { pratiche.renameRequest = $0 }
        )
    }

    private var regenerationRequest: Binding<PraticaRegenerationRequest?> {
        Binding(
            get: { pratiche.regenerationRequest },
            set: { pratiche.regenerationRequest = $0 }
        )
    }

    private func renameSheet(_ pratica: PraticaListItem) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Rinomina la pratica").themedText(.title)
            TextField("Nome", text: $typedName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { actions.confirmRename(of: pratica, to: typedName) }
                .accessibilityIdentifier("pratiche-rename-field")
            HStack {
                Spacer()
                Button("Annulla") { pratiche.renameRequest = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Rinomina") { actions.confirmRename(of: pratica, to: typedName) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(typedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("pratiche-rename-confirm")
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 420)
        .onAppear { typedName = pratica.title }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-rename")
    }

    /// «Rigenera…» (§D6's second exception): the current files go to the Trash and the
    /// message is imported again from Mail's own bytes. Asked for first, because a
    /// message file may hold edits made by hand.
    private func regenerationSheet(_ request: PraticaRegenerationRequest) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Rigenerare «\(request.subject)»?").themedText(.title)
            Text("""
            Il file del messaggio va nel Cestino e viene riscritto da Mail. \
            Le modifiche fatte a mano in «\(request.notePath)» vanno perse.
            """)
            .themedText(.caption, color: .textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Annulla") { pratiche.regenerationRequest = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Rigenera") { actions.confirmRegeneration(request) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("pratiche-regenerate-confirm")
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 440)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-regenerate")
    }

    @ViewBuilder
    private var content: some View {
        if pratiche.selection == nil {
            emptyState
        } else {
            VStack(spacing: 0) {
                // Above the timeline and under the banner, which is where DESIGN.md's
                // screen 1a puts it and where the Full Disk Access banner's own
                // "never below the tray" rule expects it.
                PraticaTrayStrip(
                    proposals: pratiche.selectedTray,
                    onFollow: { actions.follow($0) },
                    onIgnore: { actions.ignore($0) }
                )
                if let dropReport {
                    Text("\(dropReport.summary) Per ora usa «Aggiungi a pratica da Mail…» (Cmd+Shift+P).")
                        .themedText(.caption, color: .textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, theme.spacing(.m))
                        .accessibilityIdentifier("pratiche-drop-report")
                }
                PraticaTimelineView(
                    actions: actions,
                    onAddNote: { composer.append(.note) },
                    onAddCall: { composer.append(.call) },
                    onOpenNote: openPraticaNote,
                    onInsertBetween: { first, second, kind in
                        composer.insertBetween(first, and: second, kind: kind)
                    }
                )
                // R-22, the tracer bullet: what a drag from Mail actually offers is
                // recorded and shown, never imported (the probe is the deliverable).
                .mailDropReceiver { dropReport = $0 }
            }
        }
    }

    /// Screen 1g: text plus the two buttons, no illustration. Both are a second
    /// rendering of a command declared once - `ShortcutCommand.newPratica` and
    /// `.addToPraticaFromMail`, reached here through the same `Navigation` flags the
    /// menu bar and the two keys set (ADR-0023 §D1).
    private var emptyState: some View {
        VStack(spacing: theme.spacing(.m)) {
            Text("Scegli una pratica o creane una nuova").themedText(.title)
            HStack(spacing: theme.spacing(.s)) {
                Button("Nuova pratica…", action: newPratica)
                    .disabled(vault.root == nil)
                    .accessibilityIdentifier("pratiche-empty-new")
                Button("Aggiungi da Mail…") { navigation.isShowingAddToPratica = true }
                    .disabled(vault.root == nil)
                    .accessibilityIdentifier("pratiche-empty-add-from-mail")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-empty")
    }

    /// A thin bar with «12 di 80 · Annulla» (DESIGN.md "Binding decisions").
    private func syncProgress(_ progress: PraticaSyncEngine.Progress) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                .progressViewStyle(.linear)
            HStack(spacing: theme.spacing(.s)) {
                Text("\(progress.completed) di \(progress.total)")
                    .themedText(.caption, color: .textSecondary)
                Button("Annulla") { pratiche.cancelSync() }
                    .buttonStyle(.plain)
                    .themedText(.caption, color: .accentPrimary)
                    .disabled(pratiche.requestSyncCancellation == nil)
                    .accessibilityIdentifier("pratiche-sync-cancel")
                Spacer()
            }
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.bottom, theme.spacing(.xs))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-sync-progress")
    }

    /// `pratica.md` as it is on disk, read-only here. **The inspector is the one place
    /// that file is edited** (ADR §D13), and this column opens it in the real editor
    /// rather than growing a second text view bound to the same bytes - the shape of
    /// every text-loss defect this repo has documented.
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                HStack {
                    Text("Nota della pratica").themedText(.heading)
                    Spacer()
                    Button("Apri nell'editor", action: openPraticaNote)
                        .buttonStyle(.plain)
                        .themedText(.caption, color: .accentPrimary)
                        .disabled(pratiche.selection == nil)
                        .accessibilityIdentifier("pratiche-inspector-open")
                }
                if inspectorBody.isEmpty {
                    Text("Nessuna pratica scelta.").themedText(.caption, color: .textTertiary)
                } else {
                    MarkdownBlocksView(
                        blocks: MarkdownBlockParser.blocks(in: inspectorBody),
                        notePath: praticaNotePath ?? "",
                        vaultRoot: vault.root,
                        expandsTransclusions: false
                    )
                }
            }
            .padding(theme.spacing(.m))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.color(.backgroundSecondary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-inspector")
    }

    private var praticaNotePath: String? {
        pratiche.selection.map { "\($0)/\(PraticheController.praticaFileName)" }
    }

    /// One small file, read when the selection changes and never per draw.
    private func loadInspector() {
        guard let path = praticaNotePath, let root = vault.root else {
            inspectorBody = ""
            return
        }
        let url = root.appending(path: path, directoryHint: .notDirectory)
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        inspectorBody = NoteDocument.parse(text).body
    }

    /// The editing path (ADR §D13): the note opens in the Note pane's editor, which is
    /// the only editor this app has for a vault file.
    private func openPraticaNote() {
        guard let path = praticaNotePath else { return }
        vault.openChosenNote(at: path)
        navigation.pane = .notes
    }
}
