import SwiftUI

struct NewCanvasItemSheet: View {
    enum Kind { case folder, link, note }

    @Environment(\.theme) private var theme
    let kind: Kind
    /// Closes the sheet: «Annulla», and «Fine» on a document's confirmation.
    let onCancel: () -> Void
    /// Makes the item and answers what the sheet shows next. Awaited, so the sheet stays open,
    /// with what was typed, until the write is done (n1-seams R-18); the caller closes it when
    /// it answers `.editing` for a made folder or link.
    let onConfirm: (String) async -> Confirmation
    /// «Apri» on a document's confirmation, with the note's path (note-workflow R-05).
    let onOpen: (String) -> Void

    /// Where the sheet stands once the person has pressed «Crea» (note-workflow R-05): typing, the
    /// write running, the document made (the sheet stays open to offer «Apri»), or a sentence.
    enum Confirmation: Equatable {
        case editing
        case working
        case created(path: String, title: String)
        case failed(String)
    }

    /// What the sheet shows after `creation`: the document's confirmation, or its sentence.
    static func confirmation(
        after creation: WorkspaceController.DocumentCreation, title: String
    ) -> Confirmation {
        switch creation {
        case .created(let path): .created(path: path, title: title)
        case .failed(let sentence): .failed(sentence)
        }
    }

    @State private var value = ""
    @State private var phase: Confirmation = .editing

    private var isCreating: Bool { phase == .working }

    private var title: String {
        switch kind {
        case .folder: "Nuova cartella"
        case .link: "Nuovo link"
        case .note: "Nuovo documento"
        }
    }

    private var prompt: String {
        switch kind {
        case .folder: "Nome della cartella"
        case .link: "URL o URI (https://, obsidian://, message://)"
        case .note: "Titolo della nota"
        }
    }

    var body: some View {
        Group {
            if case .created(let path, let created) = phase {
                confirmation(path: path, title: created)
            } else {
                form
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 460)
        .background(theme.color(.surfaceCard))
    }

    /// The document is made and on the board: «Apri» shows it in the Note pane, «Fine» (Return
    /// or Esc) closes the sheet (note-workflow R-05).
    private func confirmation(path: String, title created: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(title).themedText(.title)
            Text("Documento «\(created)» creato e posizionato sulla board.")
                .themedText(.body, color: .textSecondary)
            HStack {
                Spacer()
                Button("Apri") { onOpen(path) }
                Button("Fine", action: onCancel)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onExitCommand(perform: onCancel)
    }

    private var failure: String? {
        if case .failed(let sentence) = phase { sentence } else { nil }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(title).themedText(.title)
            TextField(prompt, text: $value)
                .textFieldStyle(.roundedBorder)
                // The sentence is about the value that failed: a new one is a new attempt.
                .onChange(of: value) { _, _ in
                    if failure != nil { phase = .editing }
                }
            // In place, the way the Cmd+N composer reports a refused title.
            if let failure {
                Text(failure).themedText(.caption, color: .taskOverdue)
            }
            HStack {
                Spacer()
                // Not while the write runs: dismissing mid-write would still make the item,
                // and a failure after that would have no sheet left to show its sentence.
                Button("Annulla", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCreating)
                Button("Crea", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
    }

    private func confirm() {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        phase = .working
        Task { @MainActor in
            phase = await onConfirm(trimmed)
        }
    }
}

/// Renders a file's thumbnail, falling back to its type icon while the render runs
/// or when the file has no preview at all.
struct ImportSheet: View {
    @Environment(\.theme) private var theme
    @Binding var proposals: [WorkspaceController.ImportProposal]
    let onCancel: () -> Void
    let onConfirm: ([WorkspaceController.ImportProposal]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(proposals.count == 1 ? "Importa file" : "Importa \(proposals.count) file")
                .themedText(.title)
            Text("Il nome proposto segue le convenzioni harness. Puoi modificarlo.")
                .themedText(.caption, color: .textSecondary)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                    ForEach($proposals) { $proposal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proposal.originalName)
                                .themedText(.caption, color: .textTertiary)
                            TextField("Nome file", text: $proposal.proposedName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)

            HStack {
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Importa") { onConfirm(proposals) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 560)
        .background(theme.color(.surfaceCard))
    }
}
