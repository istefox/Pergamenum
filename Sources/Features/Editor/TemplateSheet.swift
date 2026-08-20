import SwiftUI

/// Writes a template into the note that is already open (ADR-0011 D5).
///
/// A template could only ever start a *new* note, which left the common case out: the
/// note exists, it is open, and what is missing is the shape - a meeting's headings, a
/// client's checklist.
///
/// **It inserts at the caret and replaces nothing.** Not "apply", which in every other
/// app means overwrite: a template dropped over a note somebody had already written into
/// would be the one destructive gesture in an app whose whole argument is that the files
/// are yours. Where it lands is where you left the cursor, and `Cmd+Z` takes it back
/// because it is an ordinary edit in the text view.
///
/// The template's own frontmatter is dropped on the way in, by the same `NoteTemplate.body`
/// the composer uses: it carries the template's date and the template's tags, which
/// belong to the template.
struct TemplateSheet: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Applica un template").themedText(.title)
                Text("Il testo viene inserito al cursore. Niente viene sostituito.")
                    .themedText(.caption, color: .textSecondary)
            }

            if vault.templates.isEmpty {
                Text("Nessun template in \(NoteTemplate.folder)/.")
                    .themedText(.body, color: .textSecondary)
            } else {
                List(vault.templates, id: \.relativePath) { template in
                    Button { apply(template) } label: {
                        HStack(spacing: theme.spacing(.xs)) {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(theme.color(.accentPrimary))
                            Text(template.title).themedText(.body)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("template-choice")
                }
                .frame(height: 220)
                .scrollContentBackground(.hidden)
            }

            HStack {
                Spacer()
                Button("Annulla") { vault.isChoosingTemplate = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 460)
        .background(theme.color(.surfaceCard))
    }

    private func apply(_ template: NoteRecord) {
        defer { vault.isChoosingTemplate = false }
        guard let note = vault.openNote,
              let text = try? vault.session?.read(template.relativePath).text
        else { return }

        let body = NoteTemplate.substituting(
            title: note.title,
            date: .today,
            in: NoteTemplate.body(of: text)
        )
        // Through `Navigation`, which is how every other insertion reaches the editor:
        // the sheet has no reference to the text view, and giving it one would break the
        // moment the editor is rebuilt.
        navigation.insert(body)
    }
}
