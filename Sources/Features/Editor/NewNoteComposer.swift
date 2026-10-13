import SwiftUI

/// Naming a new note, in the editor pane rather than in a window floating over it.
///
/// The title is the file name (SPEC §4.2), so it has to be settled before the note
/// exists - but settling it in a modal sheet meant the one thing you wanted to do
/// next, write, happened somewhere you could not see. Here the composer occupies the
/// editor column, and on Enter the same column becomes the note with the cursor
/// already in it.
///
/// Since ADR-0085 §D7 it is the one naming surface in three hosts: the Note pane, a sheet with
/// the folder fixed (Workspace «Documento»), and the «Estrai in una nota» sheet. It composes a
/// `NoteComposition` and hands it to `perform`, or to `vault.createComposedNote` in the pane.
struct NewNoteComposer: View {
    @Environment(\.theme) var theme
    @Environment(VaultController.self) private var vault

    /// The draft as the controller holds it: the folder arrives from "Nuova nota qui",
    /// and everything else from a draft parked by stepping out of a previous composer.
    let draft: VaultController.NoteDraft
    /// Where the composer is hosted (ADR-0085 §D7, R-11): the Note pane, a sheet with the folder
    /// fixed (Workspace «Documento»), or the extract sheet.
    enum Host: Equatable {
        case pane
        case sheet(folder: String)
        case extract(VaultController.ExtractionDraft)
    }

    let host: Host
    /// What «Crea» does with the composition; nil is the pane host's `vault.createComposedNote`.
    let perform: (@MainActor (NoteComposition) async throws -> String)?
    /// Called with the path of the note just created, so the editor can take focus.
    let onCreated: (String) -> Void
    let onCancel: () -> Void

    init(
        draft: VaultController.NoteDraft,
        host: Host = .pane,
        perform: (@MainActor (NoteComposition) async throws -> String)? = nil,
        onCreated: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.host = host
        self.perform = perform
        self.onCreated = onCreated
        self.onCancel = onCancel
    }

    /// The sheets' width (ADR-0003 §D1).
    static let sheetWidth: CGFloat = 520

    @State private var title = ""
    @State private var folder = ""
    /// The tag being typed, not yet a chip; parked as `NoteDraft.topic`.
    @State private var topic = ""
    @State private var tags: [Tag] = []
    /// The chosen template's relative path, empty for none (ADR-0011 D6).
    @State private var template = ""
    @State private var error: String?
    @State private var isCreating = false
    /// Bumped to put the caret in the title, including after the folder menu took it.
    @State private var focusRequest = 0

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    private var vocabulary: Vocabulary { vault.session?.vocabulary ?? .empty }
    private var problems: [String] {
        NoteComposition(title: trimmedTitle, folder: folder, tags: tags).blockingProblems(vocabulary: vocabulary)
    }
    private var canCreate: Bool { !trimmedTitle.isEmpty && problems.isEmpty && !isCreating }

    private var isSheet: Bool { host != .pane }
    private var extraction: VaultController.ExtractionDraft? {
        if case .extract(let draft) = host { return draft }
        return nil
    }

    /// What has been typed so far, in the shape the controller parks (PG-028).
    private var typed: VaultController.NoteDraft {
        .init(folder: folder, title: trimmedTitle, topic: topic, template: template, tags: tags)
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            header
            fields
            footer
            if !isSheet { Spacer() }
        }
        .padding(theme.spacing(.l))
        .background(theme.color(.backgroundPrimary))
        .onAppear(perform: load)
        // Whatever took the composer off the screen without dismissing it - a note
        // clicked in the list, the quick switcher, a backlink - was a step out and not a
        // change of mind, so what was typed is kept for the next Cmd+N (PG-028). The
        // controller ignores this when the draft is already gone, which is what
        // «Annulla» and «Crea» leave behind. A sheet host parks nothing (ADR-0085 §D7).
        .onDisappear { if host == .pane { vault.parkNewNote(typed) } }
        // Escape gets out of a composer that has taken over the pane, the same as it
        // dismissed the sheet this replaces.
        .onExitCommand(perform: onCancel)
        if isSheet {
            content.frame(width: Self.sheetWidth, alignment: .topLeading)
        } else {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func load() {
        switch host {
        case .pane:
            (title, folder, template) = (draft.title, draft.folder, draft.template)
        case .sheet(let fixed):
            (title, folder, template) = (draft.title, fixed, draft.template)
        case .extract(let extraction):
            // The selection is the body: a template would put a second text around it.
            (title, folder, template) = (extraction.title, extraction.folder, "")
        }
        topic = draft.topic
        tags = draft.tags
        focusRequest += 1
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
                folderControl
                if extraction == nil { templatePicker }
            }
            ComposerTagField(tags: $tags, text: $topic, problem: $error, onSubmit: create)

            if let extraction {
                preview(heading: "SELEZIONE", text: extraction.text)
            } else if let resolved = resolvedTemplate(at: Date()), !resolved.body.isEmpty {
                preview(heading: "DAL TEMPLATE", text: resolved.body)
            }
        }
    }

    /// The folder menu in the pane and the extract sheet; a fixed label in the board's sheet,
    /// whose note goes beside the board (n1-seams R-10).
    @ViewBuilder
    private var folderControl: some View {
        if case .sheet = host {
            Label(folder.isEmpty ? "(radice)" : folder, systemImage: "folder")
                .themedText(.body, color: .textSecondary)
                .lineLimit(1)
                .accessibilityIdentifier("new-note-folder")
        } else {
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
    }

    /// Always rendered, including on a vault with no `Templates/` folder at all - which
    /// is every vault until someone makes one. A control that hides itself is invisible
    /// to the person who has never made a template and therefore does not know they can;
    /// so when there is nothing to list, the menu's one item is the sentence that says
    /// how to make one. Decided by looking at the three candidates side by side in
    /// `TemplateMockup`, approved 2026-08-18. Absent from the extract sheet only.
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

    /// What the note will actually start with, resolved exactly as the write will have it - the
    /// same `NoteTemplate.resolve` call, so «Crea» is pressed knowing the result (ADR-0086 §D5).
    private func resolvedTemplate(at now: Date) -> NoteTemplate.Resolved? {
        guard !template.isEmpty, let text = try? vault.session?.read(template).text else { return nil }
        let clock = Calendar.current.dateComponents([.hour, .minute], from: now)
        return NoteTemplate.resolve(
            NoteTemplate.body(of: text),
            title: trimmedTitle.isEmpty ? "{{title}}" : trimmedTitle,
            date: .today,
            time: TaskTime(hour: clock.hour ?? 0, minute: clock.minute ?? 0)
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            if let error {
                Text(error).themedText(.caption, color: .taskOverdue)
            } else if let problem = problems.first {
                Text(problem).themedText(.caption, color: .taskOverdue)
            } else if extraction?.sourceIsDirty == true {
                Text("La nota di origine ha modifiche non salvate: viene salvata prima di estrarre.")
                    .themedText(.caption, color: .textSecondary)
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
                Button(confirmTitle, action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
                    .accessibilityIdentifier("new-note-create")
            }
        }
    }

    private var confirmTitle: String {
        guard let extraction else { return "Crea" }
        return extraction.sourceIsDirty ? "Salva ed estrai" : "Estrai"
    }

    private func create() {
        guard canCreate else { return }
        // A tag still being typed is part of what «Crea» means; a refused one stops it here.
        let chosen: [Tag]
        switch ComposerTagField.adding(topic, to: tags, vocabulary: vocabulary) {
        case .success(let all): chosen = all
        case .failure(let refusal):
            error = refusal.sentence
            return
        }
        let resolved = resolvedTemplate(at: Date())
        let composition = NoteComposition(
            title: trimmedTitle,
            folder: folder.trimmingCharacters(in: .whitespaces),
            tags: chosen,
            body: extraction?.text ?? resolved?.body ?? "",
            bodyCaret: extraction == nil ? resolved?.caretOffset : nil
        )
        isCreating = true
        Task { @MainActor in
            defer { isCreating = false }
            do {
                let path: String
                if let perform {
                    path = try await perform(composition)
                } else {
                    path = try await vault.createComposedNote(composition)
                }
                onCreated(path)
            } catch {
                self.error = ConformanceText.creationFailure(error)
            }
        }
    }
}
