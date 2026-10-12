import SwiftUI

// PG-387 (N4), ADR-0085 §D7, plan docs/plans/pg-387-n4-birth-of-note.md, Task 6 - R-12. The
// composer's tag field, in a file of its own because the composer was past 225 lines without it.

/// The tags a new note is born with: chips for those chosen, a field that completes from the
/// vault (`client-`, `project-`, topics from what is in use; the closed families from the
/// vocabulary) and refuses, with its sentence, what `TagEntry.check` refuses.
///
/// `type-*` and `status-*` are never chosen here: the note's category assigns them.
struct ComposerTagField: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Binding var tags: [Tag]
    /// What is being typed, parked with the draft as `NoteDraft.topic`.
    @Binding var text: String
    @Binding var problem: String?
    let onSubmit: () -> Void

    /// Every family but the two the category owns.
    static let namespaces: Set<TagNamespace> = Set(TagNamespace.allCases).subtracting([.type, .status])

    private var vocabulary: Vocabulary { vault.session?.vocabulary ?? .empty }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        tags.removeAll { $0 == tag }
                    } label: {
                        Label(tag.description, systemImage: "xmark").themedText(.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, theme.spacing(.xs))
                    .background(theme.color(.accentMuted), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
                }
                TextField("topic-… (facoltativo)", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit {
                        if text.trimmingCharacters(in: .whitespaces).isEmpty { onSubmit() } else { commit() }
                    }
                    .onChange(of: text) { _, _ in problem = nil }
                    .accessibilityIdentifier("new-note-tags")
            }
            if !completions.isEmpty {
                HStack(spacing: theme.spacing(.s)) {
                    ForEach(completions, id: \.self) { tag in
                        Button(tag.description) {
                            text = tag.description
                            commit()
                        }
                        .buttonStyle(.link)
                    }
                }
            }
        }
    }

    private var completions: [Tag] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return TagEntry.completions(
            for: text, allowing: Self.namespaces, usage: vault.index.tagUsage(),
            vocabulary: vocabulary, excluding: tags, limit: 5
        )
    }

    /// Turns what is typed into a chip, or says why not.
    private func commit() {
        switch Self.adding(text, to: tags, vocabulary: vocabulary) {
        case .success(let all):
            tags = all
            text = ""
            problem = nil
        case .failure(let refusal):
            problem = refusal.sentence
        }
    }

    /// `tags` with what is typed added as a chip; `tags` unchanged when nothing is typed. The
    /// composer asks the same thing of text still pending when «Crea» is pressed.
    static func adding(_ typed: String, to tags: [Tag], vocabulary: Vocabulary) -> Result<[Tag], TagEntry.Refusal> {
        guard !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return .success(tags) }
        return TagEntry.check(typed, allowing: namespaces, vocabulary: vocabulary).map { tag in
            tags.contains(tag) ? tags : tags + [tag]
        }
    }
}
