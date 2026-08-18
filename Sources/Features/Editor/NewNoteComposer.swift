import SwiftUI

/// Naming a new note, in the editor pane rather than in a window floating over it.
///
/// The title is the file name (SPEC §4.2), so it has to be settled before the note
/// exists - but settling it in a modal sheet meant the one thing you wanted to do
/// next, write, happened somewhere you could not see. Here the composer occupies the
/// editor column, and on Enter the same column becomes the note with the cursor
/// already in it.
struct NewNoteComposer: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    /// The draft as the controller holds it: the folder arrives from "Nuova nota qui".
    let draft: VaultController.NoteDraft
    /// Called with the path of the note just created, so the editor can take focus.
    let onCreated: (String) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var folder = ""
    @State private var topic = ""
    /// The chosen template's relative path, empty for none (ADR-0011 D6).
    @State private var template = ""
    @State private var error: String?
    /// Bumped to put the caret in the title, including after the folder menu took it.
    @State private var focusRequest = 0

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    private var canCreate: Bool { !trimmedTitle.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            header
            fields
            footer
            Spacer()
        }
        .padding(theme.spacing(.l))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.color(.backgroundPrimary))
        .onAppear {
            title = draft.title
            folder = draft.folder
            topic = draft.topic
            focusRequest += 1
        }
        // Escape gets out of a composer that has taken over the pane, the same as it
        // dismissed the sheet this replaces.
        .onExitCommand(perform: onCancel)
    }

    private var header: some View {
        HStack {
            Text("Nuova nota").themedText(.caption, color: .textTertiary)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.color(.textTertiary))
            }
            .buttonStyle(.plain)
            .help("Annulla")
            .accessibilityLabel("Annulla la nuova nota")
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            // Borderless and in the title face: this is the note's heading being
            // written, not a form field.
            ComposerTextField(
                text: $title,
                placeholder: "Titolo della nota",
                font: theme.nsFont(.title),
                color: NSColor(theme.color(.textPrimary)),
                focusRequest: focusRequest,
                identifier: "new-note-title",
                onSubmit: create
            )
            .frame(height: theme.spacing(.l))

            HStack(spacing: theme.spacing(.s)) {
                folderPicker
                templatePicker
                TextField("topic-… (facoltativo)", text: $topic)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit(create)
            }

            if !templateBody.isEmpty {
                templatePreview
            }
        }
    }

    private var folderPicker: some View {
        Menu {
            Button("(radice)") { folder = "" }
            ForEach(vault.folders, id: \.self) { candidate in
                Button(candidate) { folder = candidate }
            }
        } label: {
            Label(folder.isEmpty ? "(radice)" : folder, systemImage: "folder")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("new-note-folder")
    }

    /// Always rendered, including on a vault with no `Templates/` folder at all - which
    /// is every vault until someone makes one. A control that hides itself is invisible
    /// to the person who has never made a template and therefore does not know they can;
    /// so when there is nothing to list, the menu's one item is the sentence that says
    /// how to make one. Decided by looking at the three candidates side by side in
    /// `TemplateMockup`, approved 2026-08-18.
    private var templatePicker: some View {
        Menu {
            if vault.templates.isEmpty {
                Text("Una nota in \(NoteTemplate.folder)/ diventa un modello")
            } else {
                Button("(nessuno)") { template = "" }
                ForEach(vault.templates, id: \.relativePath) { candidate in
                    Button(candidate.title) { template = candidate.relativePath }
                }
            }
        } label: {
            Label(templateTitle, systemImage: "doc.text")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("new-note-template")
    }

    private var templateTitle: String {
        guard let record = vault.templates.first(where: { $0.relativePath == template })
        else { return "Template" }
        return record.title
    }

    /// What the note will actually start with, substituted exactly as the write will do
    /// it - the same `NoteTemplate.substituting` call, not an approximation of it, so
    /// «Crea» is pressed knowing the result rather than guessing at it.
    private var templateBody: String {
        guard !template.isEmpty, let text = try? vault.session?.read(template).text
        else { return "" }
        return NoteTemplate.substituting(
            title: trimmedTitle.isEmpty ? "{{title}}" : trimmedTitle,
            date: .today,
            in: NoteTemplate.body(of: text)
        )
    }

    private var templatePreview: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("DAL TEMPLATE").themedText(.caption, color: .textTertiary)
            Text(templateBody)
                .themedText(.body, color: .textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(theme.spacing(.s))
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            if let error {
                Text(error).themedText(.caption, color: .taskOverdue)
            } else {
                Text("""
                Il titolo è il nome del file: niente / \\ : * ? " < > | # ^ [ ], \
                massimo \(NoteName.maximumLength) caratteri, nessun suffisso di versione.
                """)
                .themedText(.caption, color: .textTertiary)
            }

            HStack {
                Button("Annulla", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Crea", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
    }

    private func create() {
        guard canCreate else { return }
        let topics = Tag(topic).map { [$0] } ?? []
        if !topic.isEmpty, topics.isEmpty {
            error = "«\(topic)» non è un tag conforme (namespace-valore, minuscolo)"
            return
        }
        do {
            let path = try vault.createNote(
                title: trimmedTitle,
                in: folder.trimmingCharacters(in: .whitespaces),
                date: .today,
                topics: topics,
                body: templateBody
            )
            onCreated(path)
        } catch {
            self.error = ConformanceText.creationFailure(error)
        }
    }
}
