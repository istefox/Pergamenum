import SwiftUI

// ADR-0045 §D3 (PG-143 structure refactor): the empty state, the sync progress bar and
// the read-only note inspector, split out of `PratichePane.swift` for its own
// struct-body length - moved verbatim, `NoteListPane.swift:23-30`'s convention for
// every member this file widens.

extension PratichePane {
    /// Screen 1g: text plus the two buttons, no illustration. Both are a second
    /// rendering of a command declared once - `ShortcutCommand.newPratica` and
    /// `.addToPraticaFromMail`, reached here through the same `Navigation` flags the
    /// menu bar and the two keys set (ADR-0023 §D1).
    ///
    /// Not `private`, on this property and every other member down to
    /// `openPraticaNote` below except `praticaNotePath` (read only by this file's own
    /// `inspector`, `loadInspector` and `openPraticaNote`): `PratichePane.swift`'s
    /// `body` and `content`, in the main file, read or call each of them directly.
    var emptyState: some View {
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
    func syncProgress(_ progress: PraticaSyncEngine.Progress) -> some View {
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
    var inspector: some View {
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
    func loadInspector() {
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
    func openPraticaNote() {
        guard let path = praticaNotePath else { return }
        vault.openChosenNote(at: path)
        navigation.pane = .notes
    }
}
