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
struct EditorCommand: Identifiable, Sendable, Equatable, RankableEntry {
    let id: String
    let title: String
    /// Extra words the fuzzy filter matches on, so `/h2` finds "Titolo 2" and `/todo`
    /// finds "Task". Without these the menu is only usable by someone who already knows
    /// what the entries are called.
    let keywords: [String]
    let symbol: String
    let action: Action
    /// The key combination this command also answers to, as the settings pane has it -
    /// the user's, never the default, or the menu would teach a shortcut that does
    /// nothing. Nil for the entries that only exist here.
    var shortcutCaption: String?

    /// What the filter matches first (`RankableEntry`).
    var rankingTitle: String { title }

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
    ] + viewEntries

    /// The five saved views (ADR-0009), one entry each.
    ///
    /// Five and not one because `render:` is the only key of the grammar with no default:
    /// the choice has to be made anyway, and making it from the menu is the difference
    /// between choosing and remembering how the word is spelled. The fuzzy filter does the
    /// rest - `/vista` offers all five, `/board` offers the one.
    ///
    /// Added by M11 to a catalogue M8 declared closed, which is what its own note says
    /// happens: the list is the feature, and a view nobody can write from here is a
    /// feature you have to have read the ADR to use.
    static let viewEntries: [EditorCommand] = ViewBlock.Renderer.allCases.map { render in
        EditorCommand(
            id: "view.\(render.rawValue)",
            title: "Vista \(ViewCatalogue.rendererName(render))",
            keywords: ["view", "query", "vista", render.rawValue],
            symbol: viewSymbol(render),
            action: viewAction(render)
        )
    }

    /// The task syntax of SPEC §7.1, written for you.
    ///
    /// Built per call rather than as a `static let`, and that is the whole reason this is
    /// a function: the date is today's, and a catalogue computed once at launch would
    /// start writing yesterday's date some time after midnight - on the machine of
    /// somebody who leaves the app open, which is everybody.
    ///
    /// The date is written out rather than left as a bare `>`: the marker alone still
    /// needs the format looked up, and a wrong one parses as text and silently fails to
    /// schedule anything. Today's is the one guess that is always meaningful, and moving
    /// it is a matter of typing over four characters.
    static func taskSyntaxEntries(today: CalendarDate) -> [EditorCommand] {
        [
            EditorCommand(
                id: "task.scheduled", title: "Pianifica per un giorno",
                keywords: ["data", "quando", "pianifica", ">"],
                symbol: "calendar", action: .insert(">\(today.description)", cursorBack: 0)
            ),
            EditorCommand(
                id: "task.due", title: "Scadenza",
                keywords: ["deadline", "entro", "!"],
                symbol: "exclamationmark.circle", action: .insert("!\(today.description)", cursorBack: 0)
            ),
            EditorCommand(
                id: "task.reminder", title: "Promemoria",
                keywords: ["remind", "notifica", "avviso", "@"],
                symbol: "bell",
                // The caret lands on the hour, which is the part that is never today's
                // default and always has to be typed.
                action: .insert("@remind(\(today.description) 09:00)", cursorBack: 6)
            ),
            EditorCommand(
                id: "task.repeat", title: "Ripeti",
                keywords: ["repeat", "ricorrenza", "ogni"],
                symbol: "repeat", action: .insert("@repeat(0/3)", cursorBack: 2)
            ),
        ]
    }

    /// The skeleton a view starts from, with the caret between the quotes of the tag.
    ///
    /// A `where:` is written in rather than left out: an empty filter is legal and means
    /// the whole vault, which on a real vault draws a table of every note and reads like
    /// the feature is broken. A board carries its `group:` because without one the block
    /// does not parse, and a menu that writes an invalid block is worse than no menu.
    private static func viewAction(_ render: ViewBlock.Renderer) -> Action {
        let head = "```\(ViewBlock.language)\nwhere: tag(\""
        let grouping = render == .board ? "group: tag(\"status-*\")\n" : "sort: title\n"
        let tail = "\")\n\(grouping)render: \(render.rawValue)\n```\n"
        // Counted from the text rather than written as a number: a skeleton edited later
        // would leave a literal offset pointing at the wrong character.
        return .insert(head + tail, cursorBack: tail.count)
    }

    private static func viewSymbol(_ render: ViewBlock.Renderer) -> String {
        switch render {
        case .table: "tablecells"
        case .list: "list.bullet.rectangle"
        case .gallery: "square.grid.2x2"
        case .calendar: "calendar"
        case .board: "rectangle.split.3x1"
        }
    }

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
    static func all(
        canRun: (ShortcutCommand) -> Bool,
        caption: (ShortcutCommand) -> String? = { _ in nil },
        today: CalendarDate = .today
    ) -> [EditorCommand] {
        editorEntries + taskSyntaxEntries(today: today) + appEntries.compactMap { entry in
            guard case .app(let command) = entry.action else { return entry }
            guard canRun(command) else { return nil }
            var entry = entry
            entry.shortcutCaption = caption(command)
            return entry
        }
    }

    /// The entries matching what has been typed after the `/`, best first.
    ///
    /// The ranking itself lives in `EntryRanking`, shared with the emoji catalogue: two
    /// copies of a tie-break rule is one copy too many.
    static func matching(_ query: String, in catalogue: [EditorCommand]) -> [EditorCommand] {
        EntryRanking.matching(query, in: catalogue)
    }
}
