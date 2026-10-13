import Foundation

// PG-387 (N4), ADR-0085 §D7, plan docs/plans/pg-387-n4-birth-of-note.md, Task 4 - R-11, R-12.

/// What the composer hands to whoever creates the note: the title, the folder, the tags the
/// topic field resolved, the body (a template already resolved) and the absolute UTF-16 caret the
/// template's `{{cursor}}` gave, when it had one.
struct NoteComposition: Equatable, Sendable {
    var title: String
    var folder: String
    var tags: [Tag] = []
    var body: String = ""
    var bodyCaret: Int?

    /// The reasons «Crea» is disabled, in the person's words; empty when the composition may be
    /// created. A closed-family value outside the vocabulary, or a `type-*`/`status-*` tag, blocks;
    /// so does a tag set that, with the tags the note is born with, passes the seven-tag limit.
    ///
    /// Each tag is asked through `TagEntry.check`, the field's own rule, so the composer cannot
    /// accept what the field would have refused.
    func blockingProblems(vocabulary: Vocabulary) -> [String] {
        let chosen: Set<TagNamespace> = Set(TagNamespace.allCases).subtracting([.type, .status])
        var problems = tags.compactMap { tag -> String? in
            if case .failure(let refusal) = TagEntry.check(tag.description, allowing: chosen, vocabulary: vocabulary) {
                return refusal.sentence
            }
            return nil
        }
        let born = TagRules.initialTags(for: .note, topics: tags).count
        if born > TagRules.maximumTagsPerNote {
            problems.append("\(born) tag, massimo \(TagRules.maximumTagsPerNote).")
        }
        return problems
    }
}
