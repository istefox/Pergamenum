import Foundation

/// Everything the slash menu can do, as data.
///
/// A closed catalogue, like `ShortcutCommand` and `KeyBinding.namedKeys` are closed: the
/// list is the feature, and a command that is not here simply is not offered. Adding one
/// is a line, which is the property M8 needs, because every milestone after it adds
/// entries to this menu.
///
/// Two kinds and no third. `insert` writes markdown at the caret and is the whole of what
/// the editor itself can do; `app` runs a command the app already has, through
/// `CommandActions`, so the slash menu never re-implements an action the menu bar owns.
struct EditorCommand: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    /// Extra words the fuzzy filter matches on, so `/h2` finds "Titolo 2" and `/todo`
    /// finds "Task". Without these the menu is only usable by someone who already knows
    /// what the entries are called.
    let keywords: [String]
    let symbol: String
    let action: Action

    enum Action: Sendable, Equatable {
        /// Markdown written at the caret; `cursorBack` puts the caret back inside what
        /// was written, which is what makes `![[]]` and a code fence usable.
        case insert(String, cursorBack: Int)
        case app(ShortcutCommand)
    }

    // MARK: The catalogue

    /// The entries that write markdown.
    ///
    /// Deliberately absent: callouts. `> [!nota]` is markdown Obsidian renders and this
    /// app does not yet - the reading view has no callout at all, it is listed in M8's
    /// later slices - and a menu entry that produces something the reading view shows as
    /// a plain quote would be the menu making a promise the app does not keep.
    static let editorEntries: [EditorCommand] = [
        EditorCommand(
            id: "heading1", title: "Titolo 1", keywords: ["h1", "titolo", "heading"],
            symbol: "textformat.size.larger", action: .insert("# ", cursorBack: 0)
        ),
        EditorCommand(
            id: "heading2", title: "Titolo 2", keywords: ["h2", "titolo", "heading", "sezione"],
            symbol: "textformat.size", action: .insert("## ", cursorBack: 0)
        ),
        EditorCommand(
            id: "heading3", title: "Titolo 3", keywords: ["h3", "titolo", "heading"],
            symbol: "textformat.size.smaller", action: .insert("### ", cursorBack: 0)
        ),
        EditorCommand(
            id: "bulletList", title: "Elenco puntato", keywords: ["lista", "bullet", "punti"],
            symbol: "list.bullet", action: .insert("- ", cursorBack: 0)
        ),
        EditorCommand(
            id: "numberedList", title: "Elenco numerato", keywords: ["lista", "numeri", "ordinato"],
            symbol: "list.number", action: .insert("1. ", cursorBack: 0)
        ),
        EditorCommand(
            id: "task", title: "Task", keywords: ["todo", "attività", "checkbox", "da fare"],
            symbol: "checklist", action: .insert("- [ ] ", cursorBack: 0)
        ),
        EditorCommand(
            id: "quote", title: "Citazione", keywords: ["quote", "blockquote"],
            symbol: "text.quote", action: .insert("> ", cursorBack: 0)
        ),
        EditorCommand(
            id: "codeBlock", title: "Blocco di codice", keywords: ["code", "fence", "snippet"],
            symbol: "curlybraces", action: .insert("```\n\n```\n", cursorBack: 5)
        ),
        EditorCommand(
            id: "table", title: "Tabella", keywords: ["table", "griglia"],
            symbol: "tablecells", action: .insert(Self.table, cursorBack: 0)
        ),
        EditorCommand(
            id: "separator", title: "Separatore", keywords: ["linea", "hr", "divisore"],
            symbol: "minus", action: .insert("\n---\n\n", cursorBack: 0)
        ),
        EditorCommand(
            id: "embed", title: "Incorpora nota o file", keywords: ["embed", "transclusione", "immagine"],
            symbol: "doc.richtext", action: .insert("![[]]", cursorBack: 2)
        ),
        EditorCommand(
            id: "tag", title: "Tag", keywords: ["etichetta", "hashtag"],
            symbol: "number", action: .insert("#", cursorBack: 0)
        ),
    ]

    /// The same table the Inserisci menu writes. One copy, so the two cannot drift into
    /// producing different markdown for the same command.
    static let table = """
    | Colonna | Colonna |
    |---|---|
    |  |  |

    """

    /// The entries that run a command the app already has.
    ///
    /// Every `ShortcutCommand` except two. `globalCapture` is the hot key for capturing
    /// from *another* application, and offering it from inside the editor would open a
    /// panel to write a note while the person is already writing one. `pastePlain` needs
    /// the pasteboard and the caret at once, and the slash menu has just consumed both by
    /// replacing the text that was typed.
    static let appEntries: [EditorCommand] = ShortcutCommand.allCases
        .filter { $0 != .globalCapture && $0 != .pastePlain }
        .map { command in
            EditorCommand(
                id: "app.\(command.rawValue)",
                title: command.title,
                keywords: [command.section.title],
                symbol: "command",
                action: .app(command)
            )
        }

    // MARK: Filtering

    /// The catalogue in menu order: what the editor writes first, then what the app does.
    ///
    /// Writing beats navigating on a tie because the menu opens from the caret, in the
    /// middle of a sentence, and that is where the writing entries belong.
    static func all(canRun: (ShortcutCommand) -> Bool) -> [EditorCommand] {
        editorEntries + appEntries.filter { entry in
            guard case .app(let command) = entry.action else { return true }
            return canRun(command)
        }
    }

    /// The entries matching what has been typed after the `/`, best first.
    ///
    /// An empty query returns everything, in catalogue order: `/` alone has to show the
    /// menu, not an empty list.
    static func matching(_ query: String, in catalogue: [EditorCommand]) -> [EditorCommand] {
        guard !query.isEmpty else { return catalogue }

        // Built in steps rather than as one chained expression: the type checker gives up
        // on the chained form, which is the same note `CompletingTextView` already
        // carries for the wikilink scoring.
        var scored: [(command: EditorCommand, score: Int)] = []
        for entry in catalogue {
            let candidates = [entry.title] + entry.keywords
            var best: Int?
            for candidate in candidates {
                guard let score = FuzzyMatch.score(query: query, candidate: candidate) else { continue }
                if best == nil || score > best! { best = score }
            }
            guard let best else { continue }
            scored.append((entry, best))
        }
        scored.sort { left, right in
            left.score == right.score ? left.command.title.count < right.command.title.count : left.score > right.score
        }
        return scored.map(\.command)
    }
}
