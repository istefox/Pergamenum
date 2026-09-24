import SwiftUI

// ADR-0045 §D3 (PG-143 structure refactor): the empty state and the read-only note
// inspector, split out of `PratichePane.swift` for its own struct-body length - moved
// verbatim, `NoteListPane.swift:23-30`'s convention for every member this file widens.
// The sync progress bar this file used to hold moved to `PraticaTopBar.syncStatus`
// (2026-09-24, `docs/specs/pratiche.spec.md:386`).

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

    /// `pratica.md` as it is on disk, read-only here. **The inspector is the one place
    /// that file is edited** (ADR §D13), and this column opens it in the real editor
    /// rather than growing a second text view bound to the same bytes - the shape of
    /// every text-loss defect this repo has documented.
    var inspector: some View {
        // The reader exists only for the links summary's jump (SPEC R-05); the proxy is
        // used inside that action and never while building the content.
        ScrollViewReader { proxy in
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
                    // SPEC R-04: the link counts above the body, so they are seen without
                    // scrolling past it; a click scrolls to the sections below (R-05).
                    if pratiche.selection != nil {
                        praticaLinksSummary {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(Self.praticaLinksAnchor, anchor: .top)
                            }
                        }
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
                    // ADR-0049 Task 5 (R-04): under `pratica.md`'s body, still inside this
                    // same scroll view - `pratiche.selection`, never the timeline's row
                    // selection, is what gates it (R-09). The scroll anchor is set here, at
                    // the call site, so `PratichePane+Links.swift` stays untouched.
                    if pratiche.selection != nil {
                        praticaLinksSection
                            .id(Self.praticaLinksAnchor)
                    }
                }
                .padding(theme.spacing(.m))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.color(.backgroundSecondary))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pratiche-inspector")
        }
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
