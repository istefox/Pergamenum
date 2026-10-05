import SwiftUI

struct NewCanvasItemSheet: View {
    enum Kind { case folder, link, note }

    @Environment(\.theme) private var theme
    let kind: Kind
    let onCancel: () -> Void
    /// Makes the item and answers the sentence to show when it could not, nil when it was
    /// made. Awaited, so the sheet stays open, with what was typed, until the write is done
    /// (n1-seams R-18); the caller closes it on success.
    let onConfirm: (String) async -> String?

    @State private var value = ""
    @State private var failure: String?
    @State private var isCreating = false

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
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(title).themedText(.title)
            TextField(prompt, text: $value)
                .textFieldStyle(.roundedBorder)
                // The sentence is about the value that failed: a new one is a new attempt.
                .onChange(of: value) { _, _ in failure = nil }
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
        .padding(theme.spacing(.l))
        .frame(width: 460)
        .background(theme.color(.surfaceCard))
    }

    private func confirm() {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        isCreating = true
        Task { @MainActor in
            failure = await onConfirm(trimmed)
            isCreating = false
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
