import Foundation

/// The seven grammars, as data.
///
/// Seven and not eight: the roadmap lists `md` too, and it is left out on purpose. The
/// grammar of markdown in this app is `MarkdownStyler` itself, and running it inside a
/// fence would put back exactly the confusion the fence exists to remove - an example
/// heading in a code block would become a heading again.
///
/// The keyword lists are short on purpose. They cover what appears in a note, not what a
/// compiler accepts; a word this app fails to colour reads as ordinary code, while a word
/// it colours wrongly reads as a bug.
extension CodeSyntax {
    static let grammars: [Language] = [swift, python, javascript, json, yaml, shell, sql]

    static let swift = Language(
        names: ["swift"],
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        blockStrings: ["\"\"\""],
        keywords: [
            "let", "var", "func", "class", "struct", "enum", "protocol", "extension",
            "if", "else", "guard", "return", "for", "while", "in", "switch", "case",
            "default", "break", "continue", "import", "init", "self", "nil", "true",
            "false", "throws", "throw", "try", "await", "async", "static", "private",
            "public", "internal", "where", "do", "catch", "defer", "some", "any",
        ],
        typeRule: .capitalised
    )

    static let python = Language(
        names: ["python", "py"],
        lineComments: ["#"],
        blockStrings: ["\"\"\"", "'''"],
        stringDelimiters: ["\"", "'"],
        keywords: [
            "def", "class", "return", "if", "elif", "else", "for", "while", "in",
            "import", "from", "as", "with", "try", "except", "finally", "lambda",
            "None", "True", "False", "self", "not", "and", "or", "is", "pass",
            "raise", "yield", "global", "assert", "del", "break", "continue",
        ],
        typeRule: .capitalised
    )

    static let javascript = Language(
        names: ["js", "javascript", "ts", "typescript", "jsx", "tsx"],
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'", "`"],
        keywords: [
            "const", "let", "var", "function", "return", "if", "else", "for", "while",
            "class", "new", "import", "export", "default", "async", "await", "try",
            "catch", "finally", "typeof", "instanceof", "null", "undefined", "true",
            "false", "this", "switch", "case", "break", "continue", "of", "in",
            "interface", "type",
        ],
        typeRule: .capitalised
    )

    static let json = Language(
        names: ["json"],
        // No comment of any kind, which is the one thing everybody knows about JSON and
        // the reason a `//` in a JSON block has to stay plain rather than turn grey.
        escapesWithBackslash: true,
        keywords: ["true", "false", "null"],
        typeRule: .keyBeforeColon
    )

    static let yaml = Language(
        names: ["yaml", "yml"],
        lineComments: ["#"],
        stringDelimiters: ["\"", "'"],
        keywords: ["true", "false", "null", "yes", "no", "on", "off"],
        typeRule: .keyBeforeColon,
        unquotedValuesAreStrings: true
    )

    static let shell = Language(
        names: ["sh", "bash", "zsh", "shell", "console"],
        lineComments: ["#"],
        stringDelimiters: ["\"", "'"],
        keywords: [
            "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
            "case", "esac", "function", "return", "export", "local", "exit", "in",
            "source", "set", "unset", "readonly",
        ]
    )

    static let sql = Language(
        names: ["sql"],
        lineComments: ["--"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["'", "\""],
        // A quote is escaped by doubling it, not with a backslash. `''` therefore closes
        // and immediately reopens, which lands in the right place by accident and is
        // worth knowing before someone "fixes" it.
        escapesWithBackslash: false,
        keywords: [
            "select", "from", "where", "insert", "into", "update", "set", "delete",
            "join", "left", "right", "inner", "outer", "on", "group", "by", "order",
            "having", "limit", "as", "and", "or", "not", "null", "distinct", "values",
            "create", "table", "drop", "alter", "index", "asc", "desc", "count",
        ],
        caseInsensitiveKeywords: true,
        typeRule: .afterKeyword(["from", "join", "into", "update", "table"])
    )
}
