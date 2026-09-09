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

    @FocusState private var isFilterFocused: Bool
    /// `pratica.md` as the inspector shows it, re-read when the chosen pratica changes
    /// rather than on every draw.
    @State private var inspectorBody = ""

    var body: some View {
        VStack(spacing: 0) {
            PraticaTopBar(filterFocus: $isFilterFocused)
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
                    PraticheListColumn()
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
    }

    @ViewBuilder
    private var content: some View {
        if pratiche.selection == nil {
            emptyState
        } else {
            PraticaTimelineView(onOpenNote: openPraticaNote)
        }
    }

    /// Screen 1g: text plus the two buttons, no illustration. Both verbs belong to
    /// Task 8 (the wizard) and Task 7 (the Mail picker); they carry their identifiers
    /// and stay disabled rather than opening a sheet nothing has built.
    private var emptyState: some View {
        VStack(spacing: theme.spacing(.m)) {
            Text("Scegli una pratica o creane una nuova").themedText(.title)
            HStack(spacing: theme.spacing(.s)) {
                Button("Nuova pratica…") {}
                    .disabled(true)
                    .accessibilityIdentifier("pratiche-empty-new")
                Button("Aggiungi da Mail…") {}
                    .disabled(true)
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
