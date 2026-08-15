import Foundation

/// The vault as an answer: what a connector hands back, whatever asked.
///
/// These types are the contract of ADR-0007. `perg --json` encodes them and the MCP
/// server encodes them, so a model that reads a note through a shell and a model that
/// reads it through a tool call get the same field names and the same shapes. Two
/// hand-built dictionaries would have drifted the first time a field was added to one.
///
/// Encodable and nothing else on purpose: they are written, never parsed back. Whoever
/// consumes them is on the other side of a pipe and is not this program.
enum VaultAPI {}

extension VaultAPI {
    /// A note as it appears in a list: enough to decide whether to read it.
    struct NoteSummary: Encodable {
        let path: String
        let title: String
        let tags: [String]
        let date: String?
        let tasks: Int
        let links: [String]

        init(_ record: NoteRecord) {
            path = record.relativePath
            title = record.title
            tags = record.frontmatter.tags.map(\.description)
            date = record.frontmatter.date?.description
            tasks = record.tasks.count
            links = record.linkTargets
        }
    }

    /// A note and its text. The text is the file verbatim, frontmatter included: a
    /// connector that stripped it would be answering about a note that does not exist.
    struct NoteText: Encodable {
        let note: NoteSummary
        let text: String
    }

    /// Just enough to point at a note.
    struct NoteReference: Encodable {
        let path: String
        let title: String

        init(_ record: NoteRecord) {
            path = record.relativePath
            title = record.title
        }
    }

    /// The wikilinks a note carries, with the two kinds kept apart: a link that answers
    /// to nothing is the interesting half, and a flat list hides it.
    struct LinkSummary: Encodable {
        let resolved: [String]
        let unresolved: [String]
    }

    /// A link target nothing in the vault answers to, and who writes it.
    struct UnresolvedLink: Encodable {
        let target: String
        let sources: [String]
    }

    struct SearchHit: Encodable {
        let path: String
        let title: String
        let excerpt: String

        init(_ result: VaultSession.SearchResult) {
            path = result.path
            title = result.title
            excerpt = result.excerpt
        }
    }

    /// A task line of SPEC §7, addressable: `path` and `line` together name it exactly,
    /// which is what a second call needs in order to act on the same one.
    struct TaskSummary: Encodable {
        let id: String
        let text: String
        let state: String
        let path: String
        /// One-based, as an editor counts and as `path:line` is written everywhere else.
        let line: Int
        let scheduled: String?
        let due: String?
        let project: String?
        let links: [String]

        init(_ task: TaskItem) {
            id = task.id
            text = task.text
            state = String(task.state.marker)
            path = task.sourcePath
            line = task.lineIndex + 1
            scheduled = task.scheduled?.description
            due = task.due?.description
            project = task.project?.description
            links = task.links
        }
    }

    struct BlockSummary: Encodable {
        let start: String
        let end: String
        let title: String
        let published: Bool

        init(_ block: TimeBlock) {
            start = block.startText
            end = block.endText
            title = block.title
            published = block.isPublished
        }
    }

    /// A day as the vault has it: no EventKit anywhere in this layer (ADR-0007 §D4), so
    /// this is the day as written down rather than the day as the Mac knows it.
    struct DaySummary: Encodable {
        let date: String
        let notePath: String
        let noteExists: Bool
        let blocks: [BlockSummary]
        let scheduled: [TaskSummary]
        let due: [TaskSummary]
    }

    struct LintFinding: Encodable {
        let path: String
        let name: [String]
        let frontmatter: [String]
        let tags: [String]
        let relatedMissingInSection: [String]
        let relatedMissingInFrontmatter: [String]
        let count: Int

        init(path: String, _ violations: NoteViolations) {
            self.path = path
            name = violations.name.map { "\($0)" }
            frontmatter = violations.frontmatter.map { "\($0)" }
            tags = violations.tags.map { "\($0)" }
            relatedMissingInSection = violations.relatedMissingInSection
            relatedMissingInFrontmatter = violations.relatedMissingInFrontmatter
            count = violations.count
        }
    }

    struct LintReport: Encodable {
        let checked: Int
        let conformant: Int
        let findings: [LintFinding]
        /// Set when `.pergamenum/vocabolari.json` is missing, because then the tag rules
        /// had nothing to judge against and a clean report means less than it looks.
        let warning: String?
    }

    struct VaultStats: Encodable {
        let vault: String
        let notes: Int
        let tasks: Int
        let openTasks: Int
        let unresolvedLinks: Int
        let reusedFromCache: Int
        let failures: [String]
        let scanMilliseconds: Int
    }

    /// The result of a write, or of the rehearsal of one.
    ///
    /// `applied` false with a `diff` is a dry run; `applied` true with no diff is a write
    /// that happened. `note` carries anything the vault decided differently from what was
    /// asked - a block that moved off an occupied hour, for one - because finding that
    /// out later, on the timeline, is worse than being told.
    struct WriteSummary: Encodable {
        let path: String
        let applied: Bool
        let diff: String?
        let note: String?
    }

    struct JournalRow: Encodable {
        let id: String
        let timestamp: Date
        let command: String
        let path: String
        let created: Bool

        init(_ entry: WriteJournal.Entry) {
            id = entry.id
            timestamp = entry.timestamp
            command = entry.command
            path = entry.path
            created = entry.textBefore == nil
        }
    }
}
