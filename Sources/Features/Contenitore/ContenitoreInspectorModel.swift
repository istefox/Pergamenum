import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D11 and §D12, plan
// docs/plans/contenitore.md, Task 7 - R-16, R-17, R-18.

/// What the inspector edits on a scheda: its body as the description, and three frontmatter
/// fields. Everything else in the file is left as it was read (ADR-0065 §D2).
struct ContenitoreDraft: Equatable, Sendable {
    var description: String
    var date: CalendarDate?
    var colour: ContenitoreColour?
    var tags: [Tag]
}

/// How one guarded edit ended.
enum ContenitoreEditOutcome: Equatable, Sendable {
    case saved
    /// Nothing differed from what was read, so nothing was written.
    case unchanged
    /// The scheda changed on disk since it was read: nothing was written and the model now
    /// holds the new text (R-16).
    case refused
    /// «Classifica» refused the arguments; nothing was written.
    case invalid(ClassificationRefusal)
    case failed(String)
}

/// The inspector's one door onto a scheda (ADR-0071 §D11 «Guarded edits»).
///
/// It remembers the text and hash it read, and every write passes that hash as `expecting:`, so
/// a scheda another writer touched in between is refused rather than overwritten, and the model
/// reloads. A date change never moves the pair: the year folder follows only «Sposta in…»
/// (ADR-0071 §D7).
@MainActor
struct ContenitoreInspectorModel {
    let session: VaultSession
    let schedaPath: String
    private(set) var text: String
    private(set) var hash: String

    /// Reads the scheda, or nil when it cannot be read.
    init?(session: VaultSession, schedaPath: String) {
        guard let read = try? session.read(schedaPath) else { return nil }
        self.session = session
        self.schedaPath = schedaPath
        self.text = read.text
        self.hash = NoteStore.hash(Data(read.text.utf8))
    }

    /// The editable fields as the text read holds them.
    var draft: ContenitoreDraft {
        let document = NoteDocument.parse(text)
        return ContenitoreDraft(
            description: Self.description(fromBody: document.body),
            date: document.frontmatter.date,
            colour: ContenitoreScheda.facts(in: document.frontmatter.foreignKeys)?.colour,
            tags: document.frontmatter.tags
        )
    }

    /// Writes the four fields that differ from what was read, through the guarded door.
    mutating func save(
        description: String, date: CalendarDate?, colour: ContenitoreColour?, tags: [Tag]
    ) async -> ContenitoreEditOutcome {
        let current = draft
        var document = NoteDocument.parse(text)
        if description.trimmingCharacters(in: .whitespacesAndNewlines) != current.description {
            document.body = Self.body(forDescription: description)
        }
        if date != current.date { document.frontmatter.date = date }
        if tags != current.tags { document.frontmatter.tags = tags }
        var updated = document.serialized()
        if colour != current.colour { updated = ContenitoreScheda.settingColour(colour, in: updated) }
        return await write(updated)
    }

    /// «Classifica» (R-18): the tags `ContenitoreClassification` returns, or its refusal with
    /// nothing written.
    mutating func classify(topics: [Tag], type: Tag?) async -> ContenitoreEditOutcome {
        let current = draft
        switch ContenitoreClassification.classify(
            tags: current.tags, topics: topics, type: type, vocabulary: session.vocabulary
        ) {
        case .failure(let refusal):
            return .invalid(refusal)
        case .success(let tags):
            var document = NoteDocument.parse(text)
            document.frontmatter.tags = tags
            return await write(document.serialized())
        }
    }

    /// Reads the scheda again, for a refusal or an external change.
    mutating func reload() {
        guard let read = try? session.read(schedaPath) else { return }
        text = read.text
        hash = NoteStore.hash(Data(read.text.utf8))
    }

    // MARK: - Pieces

    private mutating func write(_ updated: String) async -> ContenitoreEditOutcome {
        guard updated != text else { return .unchanged }
        do {
            try await session.write(updated, to: schedaPath, expecting: hash)
            text = updated
            hash = NoteStore.hash(Data(updated.utf8))
            return .saved
        } catch is VaultSession.WriteRefusal {
            session.recordProblem("la scheda è cambiata nel frattempo, ricaricata: \(schedaPath)")
            reload()
            return .refused
        } catch {
            session.recordProblem("\(schedaPath): \(error)")
            return .failed(String(describing: error))
        }
    }

    /// The description is the body, without the blank lines around it.
    static func description(fromBody body: String) -> String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The body a description is written as: one blank line after the block, one final newline.
    static func body(forDescription description: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : "\n\(trimmed)\n"
    }
}

extension ClassificationRefusal {
    /// The sentence «Classifica» shows for the refusal.
    var sentence: String {
        switch self {
        case .noTopic: "Scegli almeno un argomento."
        case .notATopic(let tag): "\(tag) non è un argomento."
        case .unknownType(let tag): "\(tag) non è un tipo del vocabolario."
        case .secondType(let tags): "Un solo tipo per documento: \(tags.map(\.description).joined(separator: ", "))."
        case .tooManyTags(let count): "\(count) tag, massimo \(TagRules.maximumTagsPerNote)."
        }
    }
}
