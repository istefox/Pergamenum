import Foundation

/// A parsed global-search query (SPEC §12).
///
/// Supports `tag:`, `path:`, `task:open` and `"frase esatta"` alongside bare words.
/// Everything is ANDed: a search that widened as you added terms would be useless for
/// narrowing down, which is what search is for.
struct SearchQuery: Equatable, Sendable {
    /// Bare words, matched case- and accent-insensitively anywhere in the note.
    var words: [String]
    /// Quoted phrases, matched as a contiguous run.
    var phrases: [String]
    /// `tag:type-note`, matched against the note's frontmatter and inline tags.
    var tags: [String]
    /// `path:01 Progetti`, matched as a substring of the note's path.
    var paths: [String]
    /// `task:open` or `task:done`.
    var taskState: TaskItem.State?
    /// True when the query asks for nothing, which should list everything rather than
    /// nothing.
    var isEmpty: Bool {
        words.isEmpty && phrases.isEmpty && tags.isEmpty && paths.isEmpty && taskState == nil
    }

    init(_ raw: String) {
        var words: [String] = []
        var phrases: [String] = []
        var tags: [String] = []
        var paths: [String] = []
        var taskState: TaskItem.State?

        for token in SearchQuery.tokenise(raw) {
            switch token {
            case .phrase(let value):
                phrases.append(value.lowercased())
            case .word(let value):
                let lower = value.lowercased()
                if let rest = lower.dropPrefixIfPresent("tag:") {
                    // Accepts `tag:#type-note` too: the hash is how a tag is written
                    // in the body, and typing it should not make the filter miss.
                    tags.append(String(rest.drop(while: { $0 == "#" })))
                } else if let rest = lower.dropPrefixIfPresent("path:") {
                    paths.append(String(rest))
                } else if let rest = lower.dropPrefixIfPresent("task:") {
                    switch rest {
                    case "open": taskState = .open
                    case "done": taskState = .done
                    default: break
                    }
                } else if !lower.isEmpty {
                    words.append(lower)
                }
            }
        }

        self.words = words
        self.phrases = phrases
        self.tags = tags
        self.paths = paths
        self.taskState = taskState
    }

    private enum Token {
        case word(String)
        case phrase(String)
    }

    /// Splits on whitespace, keeping quoted runs together.
    private static func tokenise(_ raw: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var inQuotes = false
        /// True while inside a quote that belongs to an operator (`path:"01 Progetti"`).
        /// Its closing quote must not turn the token into a phrase.
        var quotedOperator = false

        func flush(asPhrase: Bool) {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                tokens.append(asPhrase ? .phrase(trimmed) : .word(trimmed))
            }
            current = ""
        }

        for character in raw {
            if character == "\"" {
                // A quote right after an operator belongs to it: the folders in this
                // vault are called "01 Progetti", so `path:` without quoting would
                // split on the space and search for the wrong thing.
                if current.hasSuffix(":") {
                    inQuotes = true
                    quotedOperator = true
                    continue
                }
                if quotedOperator {
                    inQuotes = false
                    quotedOperator = false
                    continue
                }
                flush(asPhrase: inQuotes)
                inQuotes.toggle()
                continue
            }
            if character == " ", !inQuotes {
                flush(asPhrase: false)
                continue
            }
            current.append(character)
        }
        // An unclosed quote is still a phrase: the user typed a run they want kept
        // together, and dropping it or splitting it would search for something else.
        flush(asPhrase: inQuotes)
        return tokens
    }

    /// Whether a note satisfies every part of the query.
    func matches(record: NoteRecord, text: String) -> Bool {
        guard !isEmpty else { return true }

        let haystack = SearchQuery.fold(text + " " + record.title)
        let pathHaystack = record.relativePath.lowercased()
        let noteTags = Set(record.frontmatter.tags.map { $0.description.lowercased() })
            .union(record.tasks.flatMap { $0.tags.map { $0.description.lowercased() } })

        for word in words where !haystack.contains(SearchQuery.fold(word)) { return false }
        for phrase in phrases where !haystack.contains(SearchQuery.fold(phrase)) { return false }
        for path in paths where !pathHaystack.contains(path) { return false }
        for tag in tags where !noteTags.contains(where: { $0.hasPrefix(tag) }) { return false }

        if let taskState {
            let wanted = record.tasks.contains { task in
                taskState == .open ? task.state.isOpen : task.state == taskState
            }
            guard wanted else { return false }
        }
        return true
    }

    /// Lowercased and accent-folded, so "trasmissibilita" finds "trasmissibilità".
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "it_IT"))
    }
}

private extension String {
    /// The remainder after a prefix, or nil when the prefix is absent.
    func dropPrefixIfPresent(_ prefix: String) -> Substring? {
        hasPrefix(prefix) ? dropFirst(prefix.count) : nil
    }
}
