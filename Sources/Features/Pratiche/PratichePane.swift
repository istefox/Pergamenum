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
    /// Not `private`, on this property and `pratiche`, `vault` and `navigation` below:
    /// `PratichePane+Sheets.swift`'s sheets read `theme` and `pratiche`,
    /// `PratichePane+Inspector.swift`'s members read one or more of all four - both are
    /// extensions of this same struct in separate files.
    @Environment(\.theme) var theme
    @Environment(PraticheController.self) var pratiche
    @Environment(VaultController.self) var vault
    @Environment(Navigation.self) var navigation

    /// The window's own, handed to `PraticaCommandActions` so «Escludi» and «Sposta
    /// in…» register on the stack `NSTextView` already uses (ADR-0026 §D5) rather than
    /// on a second, pane-private one.
    @Environment(\.undoManager) private var undoManager

    @FocusState private var isFilterFocused: Bool
    /// `pratica.md` as the inspector shows it, re-read when the chosen pratica changes
    /// rather than on every draw.
    ///
    /// Not `private`, on this property and `typedName` below: `PratichePane+
    /// Inspector.swift`'s `inspector` and `loadInspector` read/write this one, and
    /// `PratichePane+Sheets.swift`'s `renameSheet` reads/writes `typedName` - both are
    /// extensions of this same struct in separate files.
    @State var inspectorBody = ""
    /// «Rinomina…»'s typed name, held by the pane and not by the row: the row is culled
    /// by its `List` the moment it scrolls out of view, taking a half-typed name with it.
    @State var typedName = ""
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
            //
            // `pratiche-delete-alert` (UX-BLUEPRINT's checklist) lands here, on the
            // message, because an alert is its own window: an identifier on the view
            // that presents it never reaches the alert, and this text is the one
            // element of it that stands for the whole. The destructive button keeps
            // `pratiche-delete-confirm`, which names a button rather than a dialog.
            Text("La cartella, i messaggi e gli allegati vanno nel Cestino.")
                .accessibilityIdentifier("pratiche-delete-alert")
        }
        // A sheet and not an alert: R-34's «Elimina pratica» is the only alert in the
        // whole feature (UX-BLUEPRINT), and a name to type is not a yes/no question.
        .sheet(item: renameRequest) { pratica in
            renameSheet(pratica)
        }
        // §D21.4: the sheet body reads `pratiche.regeneration` live, never the
        // closure's captured item - the preparing→ready transition happens while the
        // sheet is already on screen, and a captured `.preparing` snapshot would never
        // show the diff once it resolves.
        .sheet(item: regenerationBinding) { _ in regenerationSheet() }
    }

    /// The one `PraticaCommandActions` every surface of this pane shares, so the list
    /// column's context menu, the timeline's row menus and the top bar's status pill
    /// all run the same bodies (ADR-0023 §D1).
    ///
    /// Not `private`: `PratichePane+Sheets.swift`'s `renameSheet` and
    /// `regenerationReadySheet` are extensions of this same struct in a separate file,
    /// and read it.
    var actions: PraticaCommandActions {
        PraticaCommandActions(
            pratiche: pratiche, vault: vault, navigation: navigation, undoManager: undoManager
        )
    }

    private var composer: PraticaEntryComposer {
        PraticaEntryComposer(pratiche: pratiche, vault: vault, navigation: navigation)
    }

    /// Not `private`: `PratichePane+Inspector.swift`'s `emptyState` is an extension of
    /// this same struct in a separate file, and calls it.
    func newPratica() {
        navigation.isShowingNuovaPratica = true
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
                    onFollow: { proposal in Task { @MainActor in await actions.follow(proposal) } },
                    onIgnore: { proposal in Task { @MainActor in await actions.ignore(proposal) } }
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
}
