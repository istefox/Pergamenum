import SwiftUI

/// Creates a structural link, asking for the reason in both directions.
///
/// The reason is required by W-04 and the return link by W-05, so both are in the
/// form rather than optional extras: a link without a reason is a citation, and one
/// written in a single direction is the discrepancy the conformance view reports.
///
/// ADR-0084 §D4: the reverse reason mirrors the forward one until the person edits it
/// (`ReverseReasonMirror`), a candidate whose title another candidate shares shows its folder
/// label, and «Rendi strutturale» arrives with its row's path already chosen.
struct RelatedLinkSheet: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    /// The target is a path, never a title: two notes can share one (ADR-0084 §D4).
    @State private var selectedPath: String?
    @State private var reason = ""
    @State private var mirror = ReverseReasonMirror()
    @State private var error: String?

    private var reverseReason: String { mirror.reverse }

    private var sourceTitle: String { vault.openNote?.title ?? "" }
    private var selectedTitle: String? {
        selectedPath.flatMap { vault.index.note(at: $0)?.title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Nota correlata").themedText(.title)
            Text("Un legame strutturale si scrive su entrambe le note, ciascuna con il suo motivo.")
                .themedText(.caption, color: .textSecondary)

            TextField("Cerca la nota da collegare…", text: $query)
                .textFieldStyle(.roundedBorder)

            let listed = candidates
            let shared = LinkChoice.sharedTitles(listed.map(\.title))
            List(listed, id: \.relativePath, selection: $selectedPath) { note in
                HStack {
                    Text(note.title).themedText(.body)
                    Spacer()
                    // R-22: two «Riunione» rows are told apart by their folder, the root included.
                    Text(
                        shared.contains(note.title.lowercased())
                            ? LinkChoice.folderLabel(of: note.relativePath) : note.folder
                    )
                        .themedText(.caption, color: .textTertiary)
                }
                .contentShape(Rectangle())
                .tag(note.relativePath)
            }
            .frame(height: 150)
            .scrollContentBackground(.hidden)

            if let selectedTitle {
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    Text("Perché «\(sourceTitle)» rimanda a «\(selectedTitle)»")
                        .themedText(.caption, color: .textTertiary)
                    TextField("motivo", text: $reason)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: reason) { _, forward in mirror.forwardChanged(to: forward) }

                    Text("Perché «\(selectedTitle)» rimanda a «\(sourceTitle)»")
                        .themedText(.caption, color: .textTertiary)
                    // Follows the forward reason, in the field's normal text (the approved
                    // proposal), until the person edits it; never overwritten after that.
                    TextField("motivo del ritorno", text: Binding(
                        get: { mirror.reverse },
                        set: { mirror.reverseEdited(to: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            if let error {
                Text(error).themedText(.caption, color: .taskOverdue)
            }

            HStack {
                Spacer()
                Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Collega", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isComplete)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 560)
        .background(theme.color(.surfaceCard))
        .onAppear(perform: takePreselection)
    }

    private var candidates: [NoteRecord] {
        let openPath = vault.openNote?.relativePath
        return vault.index.search(query, limit: 20).filter { $0.relativePath != openPath }
    }

    /// «Rendi strutturale» chose a row before the sheet opened: its title goes in the search
    /// field, so the row is in the list, and its path is selected.
    private func takePreselection() {
        guard let path = vault.takeStructuralLinkPreselection(),
              let record = vault.index.note(at: path)
        else { return }
        query = record.title
        selectedPath = path
    }

    private var isComplete: Bool {
        selectedPath != nil
            && !reason.trimmingCharacters(in: .whitespaces).isEmpty
            && !reverseReason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func create() {
        guard let selectedPath, let source = vault.openNote else { return }
        Task { @MainActor in
            let created = await vault.addStructuralLink(
                from: source.relativePath,
                toNoteAt: selectedPath,
                reason: reason,
                reverseReason: reverseReason
            )
            if created {
                dismiss()
            } else {
                error = vault.problems.last ?? "il legame non è stato creato"
            }
        }
    }
}
