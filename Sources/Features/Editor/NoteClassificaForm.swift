import SwiftUI

// PG-387 (N4), ADR-0085 §D3/§D5, plan docs/plans/pg-387-n4-birth-of-note.md, Task 5 - R-02, R-03,
// R-04. The `.note` face of `ClassificaSheet`, in a file of its own because the scheda face
// already fills that one.

/// «Classifica…» on a note: topics through `TagEntry` with vocabulary completion, an optional
/// folder, and the frontmatter preview (`status-inbox` struck, the added topics marked, «N di 7
/// tag»). On a note with unsaved edits the confirm reads «Salva e classifica» and the controller
/// door saves first (G2).
struct NoteClassificaForm: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(VaultController.self) private var vault
    let path: String

    @State private var topics: [Tag] = []
    @State private var topicText = ""
    /// The folder to move the note to, nil to leave it where it is.
    @State private var folder: String?
    @State private var problem: String?
    /// The move failed after the classification landed: shown before the sheet closes.
    @State private var moveProblem: String?
    @State private var isWorking = false

    private var vocabulary: Vocabulary { vault.session?.vocabulary ?? .empty }
    private var currentTags: [Tag] { vault.index.notes[path]?.frontmatter.tags ?? [] }
    private var currentFolder: String { (path as NSString).deletingLastPathComponent }
    private var isDirty: Bool { vault.hasUnsavedTab(showing: path) }

    var body: some View {
        let result = NoteClassification.classify(tags: currentTags, topics: topics, vocabulary: vocabulary)
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Classifica «\(NoteName.title(fromFileName: (path as NSString).lastPathComponent))»")
                .themedText(.heading)
            Text("Una nota esce da «Da classificare» quando ha almeno un argomento.")
                .themedText(.caption, color: .textSecondary)
            topicSection
            folderSection
            preview(result)
            if let problem { Text(problem).themedText(.caption, color: .taskOverdue) }
            if let moveProblem { Text(moveProblem).themedText(.caption, color: .taskOverdue) }
            buttons(canConfirm: (try? result.get()) != nil)
        }
        .padding(theme.spacing(.l))
        .frame(width: 520)
    }

    // MARK: - Sections

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("ARGOMENTI · OBBLIGATORIO").themedText(.caption, color: .textTertiary)
            HStack(spacing: theme.spacing(.xs)) {
                ForEach(topics, id: \.self) { topic in
                    Button {
                        topics.removeAll { $0 == topic }
                    } label: {
                        Label(topic.description, systemImage: "xmark").themedText(.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, theme.spacing(.xs))
                    .background(theme.color(.accentMuted), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
                }
                TextField("topic-…", text: $topicText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTopic(topicText) }
                    .accessibilityIdentifier("note-classifica-topic")
            }
            ForEach(completions, id: \.self) { tag in
                Button(tag.description) { addTopic(tag.description) }
                    .buttonStyle(.link)
            }
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("CARTELLA · FACOLTATIVA").themedText(.caption, color: .textTertiary)
            Picker("Cartella", selection: $folder) {
                Text("Resta in «\(currentFolder.isEmpty ? "(radice)" : currentFolder)»").tag(String?.none)
                ForEach(vault.folders.filter { $0 != currentFolder }, id: \.self) { name in
                    Text(name).tag(Optional(name))
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("note-classifica-folder")
        }
    }

    private func preview(_ result: Result<[Tag], ClassificationRefusal>) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("RISULTATO").themedText(.caption, color: .textTertiary)
            switch result {
            case .success(let tags):
                HStack(spacing: theme.spacing(.xs)) {
                    ForEach(ClassificaPreview.lines(current: currentTags, result: tags), id: \.tag) { line in
                        Text(line.tag.description)
                            .strikethrough(line.struck)
                            .themedText(.caption, color: line.struck ? .textTertiary : (line.added ? .accentPrimary : .textSecondary))
                    }
                    Spacer()
                    Text(ClassificaPreview.countLabel(tags.count)).themedText(.caption, color: .textSecondary)
                }
            case .failure(let refusal):
                Text(refusal.sentence).themedText(.caption, color: .textSecondary)
            }
        }
    }

    @ViewBuilder
    private func buttons(canConfirm: Bool) -> some View {
        HStack {
            Spacer()
            if moveProblem != nil {
                Button("Chiudi") { dismiss() }.keyboardShortcut(.defaultAction)
            } else {
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isDirty ? "Salva e classifica" : "Classifica") { classify() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm || isWorking)
                    .accessibilityIdentifier("note-classifica-confirm")
            }
        }
    }

    // MARK: - Pieces

    private var completions: [Tag] {
        guard !topicText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return TagEntry.completions(
            for: topicText, allowing: [.topic], usage: vault.index.tagUsage(),
            vocabulary: vocabulary, excluding: topics, limit: 5
        )
    }

    private func addTopic(_ text: String) {
        switch TagEntry.check(text, allowing: [.topic], vocabulary: vocabulary) {
        case .success(let tag):
            problem = nil
            topicText = ""
            if !topics.contains(tag) { topics.append(tag) }
        case .failure(let refusal):
            problem = refusal.sentence
        }
    }

    private func classify() {
        // Captured before the `Task`: the sheet's own state may move while the write is awaited.
        let (path, topics, folder, savingFirst) = (path, topics, folder, isDirty)
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let outcome = try await vault.classifyNote(
                    at: path, topics: topics, toFolder: folder, savingFirst: savingFirst
                )
                if let left = outcome.moveProblem { moveProblem = left } else { dismiss() }
            } catch let refusal as ClassificationRefusal {
                problem = refusal.sentence
            } catch {
                problem = "Classificazione non salvata: \(error)"
            }
        }
    }
}
