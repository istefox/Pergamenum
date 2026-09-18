import Foundation

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 1 - R-01, R-07, R-08, §D1, §D4.

/// A pratica's general links to notes, tasks and boards: the three new
/// `pergamenum-dossier-links-*` keys on `pratica.md` (ADR §D1).
///
/// **Foreign to `Dossier` on purpose.** `Dossier.merging` drops an owned key the
/// moment a `Dossier` value is built without it, and `DossierWriter.update` runs that
/// merge on every membership change a sync makes - folding these keys into `Dossier`
/// would make a person's links one refactor away from being erased by an automatic
/// sync write. `Dossier.ownedKeys` stays seven and `Dossier.render` - a protected
/// interface - is untouched.
struct PraticaLinks: Equatable, Sendable {
    /// One linked task: the note it lives in, and its `^id` inside that note (ADR
    /// §D3) - never the task's own text, which is the most ordinary thing to edit.
    struct TaskReference: Equatable, Sendable {
        var noteTitle: String
        var localID: Int
    }

    /// `pergamenum-dossier-links-notes` - `- "[[Titolo]]"` per linked note.
    var notes: [String] = []
    /// `pergamenum-dossier-links-tasks` - `- "[[Nota]] ^id(3)"` per linked task.
    var tasks: [TaskReference] = []
    /// `pergamenum-dossier-links-boards` - `- "[[Nome.canvas]]"` per linked board.
    var boards: [String] = []

    static let notesKey = "pergamenum-dossier-links-notes"
    static let tasksKey = "pergamenum-dossier-links-tasks"
    static let boardsKey = "pergamenum-dossier-links-boards"

    /// The three key names, in the order `render(_:)` never deviates from and
    /// `merging(_:into:)` never reshuffles other keys around.
    static let ownedKeys = [notesKey, tasksKey, boardsKey]

    static let empty = PraticaLinks()

    /// Parses the three keys out of a note's foreign keys. Always a value, never
    /// `nil` - a pratica with no links yet is not an error, unlike `Dossier.parse`'s
    /// "is this even a pratica" question.
    static func parse(_ foreignKeys: [Frontmatter.ForeignKey]) -> PraticaLinks {
        let lines = foreignKeys.flatMap(\.lines)
        return PraticaLinks(
            notes: DossierYAML.stringList(key: notesKey, lines: lines).compactMap(wikilinkTarget),
            tasks: DossierYAML.stringList(key: tasksKey, lines: lines).compactMap(taskReference),
            boards: DossierYAML.stringList(key: boardsKey, lines: lines).compactMap(wikilinkTarget)
        )
    }

    /// The links of a `pratica.md` at `url`, read from the file - mirrors
    /// `Dossier.parse(praticaFileAt:)` exactly, including its own warning.
    ///
    /// **The index cannot answer this and must not be asked.**
    /// `IndexCache.StoredFrontmatter` persists `date`, `tags`, `aliases` and `related`
    /// and nothing else, so a `NoteRecord` a scan reused from the cache - which is
    /// every unchanged file from the second scan of a vault onward - comes back with
    /// `foreignKeys` empty and no links on it. A unit test never sees that: a
    /// `TemporaryVault` plus one `rescan()` is always the *first* scan. So the index
    /// names the candidates by path and the file decides, here, exactly as it does for
    /// `Dossier` (ADR §D4).
    static func parse(praticaFileAt url: URL) -> PraticaLinks {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .empty }
        return parse(NoteDocument.parse(text).frontmatter.foreignKeys)
    }

    /// Renders the three keys as `Frontmatter.ForeignKey` lines, in `ownedKeys`'
    /// order. A key whose list is empty is omitted, `FrontmatterSerializer`'s own
    /// "no empty list key" rule.
    static func render(_ links: PraticaLinks) -> [Frontmatter.ForeignKey] {
        let rendered: [(String, [String])] = [
            (notesKey, DossierYAML.renderStringList(
                key: notesKey,
                values: links.notes.map { PraticaLinkReference.wikilink($0).rendered },
                quoted: true
            )),
            (tasksKey, DossierYAML.renderStringList(
                key: tasksKey,
                values: links.tasks.map {
                    PraticaLinkReference.task(noteTitle: $0.noteTitle, localID: $0.localID).rendered
                },
                quoted: true
            )),
            (boardsKey, DossierYAML.renderStringList(
                key: boardsKey,
                values: links.boards.map { PraticaLinkReference.wikilink($0).rendered },
                quoted: true
            )),
        ]
        return rendered
            .filter { !$0.1.isEmpty }
            .map { Frontmatter.ForeignKey(name: $0.0, lines: $0.1) }
    }

    /// Replaces this value's own key lines inside `foreignKeys`, **in place** - every
    /// other key, including `Dossier`'s seven, stays at its original position and
    /// byte-for-byte unchanged. `Dossier.merging`'s own C4 rule (ADR-0036 §D12),
    /// applied here so the two codecs preserve each other for free, with no
    /// coordination between them.
    static func merging(_ links: PraticaLinks, into foreignKeys: [Frontmatter.ForeignKey]) -> [Frontmatter.ForeignKey] {
        var pending: [String: Frontmatter.ForeignKey] = [:]
        for key in render(links) { pending[key.name] = key }

        var merged: [Frontmatter.ForeignKey] = []
        let owned = Set(ownedKeys)
        for existing in foreignKeys {
            guard owned.contains(existing.name) else {
                merged.append(existing)
                continue
            }
            if let replacement = pending.removeValue(forKey: existing.name) {
                merged.append(replacement)
            }
        }
        for name in ownedKeys {
            if let addition = pending.removeValue(forKey: name) { merged.append(addition) }
        }
        return merged
    }

    private static func wikilinkTarget(_ raw: String) -> String? {
        guard let reference = PraticaLinkReference(parsing: raw), case let .wikilink(target) = reference
        else { return nil }
        return target
    }

    private static func taskReference(_ raw: String) -> TaskReference? {
        guard let reference = PraticaLinkReference(parsing: raw),
              case let .task(noteTitle, localID) = reference
        else { return nil }
        return TaskReference(noteTitle: noteTitle, localID: localID)
    }
}
