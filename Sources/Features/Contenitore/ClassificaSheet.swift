import SwiftUI

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D12, plan
// docs/plans/contenitore.md, Task 7 - R-18; mockup 1d.

/// «Classifica»: a document leaves «Da classificare» when it has at least one `topic-*`; the
/// content type is optional and comes from the closed vocabulary. The result is previewed, with
/// `status-inbox` struck through and the count against the seven-tag limit, and «Classifica»
/// stays disabled until `ContenitoreClassification` would accept it.
struct ClassificaSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(VaultController.self) private var vault
    let schedaPath: String
    let actions: ContenitoreCommandActions

    @State private var topics: [Tag] = []
    @State private var type: Tag?
    @State private var topicText = ""
    @State private var problem: String?
    /// The scheda as read when the sheet appeared: the preview is computed from its tags and
    /// «Classifica» writes against its hash, so a scheda changed in between is refused rather
    /// than overwritten, and the refusal's reload becomes the new preview. Never re-read per
    /// keystroke.
    @State private var model: ContenitoreInspectorModel?

    var body: some View {
        let model = self.model
        let result = model.map { model in
            ContenitoreClassification.classify(
                tags: model.draft.tags, topics: topics, type: type, vocabulary: model.session.vocabulary
            )
        }
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Classifica «\(NoteName.title(fromFileName: (schedaPath as NSString).lastPathComponent))»")
                .themedText(.heading)
            Text("Un documento esce da «Da classificare» quando ha almeno un argomento. Il tipo è facoltativo.")
                .themedText(.caption, color: .textSecondary)
            topicSection
            typeSection(model?.session.vocabulary)
            resultSection(result, current: model?.draft.tags ?? [])
            if let problem { Text(problem).themedText(.caption, color: .taskOverdue) }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Classifica") { classify() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!((try? result?.get()) != nil))
                    .accessibilityIdentifier("contenitore-classifica-confirm")
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 520)
        .onAppear {
            guard self.model == nil else { return }
            self.model = vault.session.flatMap { ContenitoreInspectorModel(session: $0, schedaPath: schedaPath) }
        }
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
                    .accessibilityIdentifier("contenitore-classifica-topic")
            }
            ForEach(suggestions, id: \.tag) { suggestion in
                Button("\(suggestion.tag.description)  \(suggestion.count) note") { addTopic(suggestion.tag.description) }
                    .buttonStyle(.link)
            }
            if let created = typedTopic, !suggestions.contains(where: { $0.tag == created }) {
                Button("Crea «\(created.description)»") { addTopic(created.description) }
                    .buttonStyle(.link)
            }
        }
    }

    private func typeSection(_ vocabulary: Vocabulary?) -> some View {
        let types = (vocabulary?.type ?? []).filter { $0 != "note" }.sorted()
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("TIPO · FACOLTATIVO").themedText(.caption, color: .textTertiary)
            Picker("Tipo", selection: $type) {
                Text("nessuno").tag(Tag?.none)
                ForEach(types, id: \.self) { value in
                    Text("type-\(value)").tag(Tag(namespace: .type, value: value) as Tag?)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("contenitore-classifica-type")
        }
    }

    private func resultSection(_ result: Result<[Tag], ClassificationRefusal>?, current: [Tag]) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("RISULTATO").themedText(.caption, color: .textTertiary)
            switch result {
            case .success(let tags):
                HStack(spacing: theme.spacing(.xs)) {
                    ContenitoreTagChips(tags: tags)
                    if current.contains(ContenitoreListModel.inboxTag) {
                        Text(ContenitoreListModel.inboxTag.description)
                            .strikethrough()
                            .themedText(.caption, color: .textTertiary)
                    }
                    Spacer()
                    Text("\(tags.count) di \(TagRules.maximumTagsPerNote) tag").themedText(.caption, color: .textSecondary)
                }
            case .failure(let refusal):
                Text(refusal.sentence).themedText(.caption, color: .textSecondary)
            case nil:
                EmptyView()
            }
        }
    }

    // MARK: - Pieces

    /// Existing `topic-*` tags matching what is typed, most used first.
    private var suggestions: [(tag: Tag, count: Int)] {
        let typed = topicText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !typed.isEmpty, let session = vault.session else { return [] }
        let needle = typed.hasPrefix("topic-") ? String(typed.dropFirst(6)) : typed
        return session.index.tagUsage()
            .filter { $0.tag.namespace == .topic && $0.tag.value.hasPrefix(needle) && !topics.contains($0.tag) }
            .prefix(5)
            .map { $0 }
    }

    /// What is typed, as a topic, when it is a valid one.
    private var typedTopic: Tag? {
        let typed = topicText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !typed.isEmpty else { return nil }
        return Tag(typed.hasPrefix("topic-") ? typed : "topic-\(typed)")
    }

    private func addTopic(_ text: String) {
        let typed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard let tag = Tag(typed.hasPrefix("topic-") ? typed : "topic-\(typed)") else {
            problem = "«\(text)» non è un argomento valido."
            return
        }
        problem = nil
        topicText = ""
        if !topics.contains(tag) { topics.append(tag) }
    }

    private func classify() {
        guard var model else { return }
        Task {
            let outcome = await model.classify(topics: topics, type: type)
            self.model = model
            switch outcome {
            case .saved, .unchanged:
                dismiss()
            case .invalid(let refusal):
                problem = refusal.sentence
            case .refused:
                problem = "La scheda è cambiata nel frattempo: riprova."
            case .failed(let reason):
                problem = "Classificazione non salvata: \(reason)"
            }
        }
    }
}
