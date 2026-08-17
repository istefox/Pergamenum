import SwiftUI

// MARK: - I blocchi di codice (M8)

/// A code fence as it will look, before the grammar exists.
///
/// The colours are the whole decision of this slice, and they are the part no test can
/// catch: five hues that have to stay legible on `surface.sunken` in both themes without
/// turning a warm paper palette into a terminal. So they are drawn first and approved
/// first, and every piece below is a literal - nothing here calls the highlighter, which
/// is exactly why this can exist before it does.
///
/// The second scene is the one worth looking at longest. It is not a proposal, it is the
/// current behaviour: the editor has never known that a fence exists, so inside one a
/// shell comment is styled as a tag and a date in a SQL query as a scheduling marker.
/// Colouring code is the visible half of this slice; that is the half that is a defect.
struct CodeBlockMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.l)) {
                scene(
                    "Nell'editor: la sorgente resta visibile, i backtick compresi",
                    CodeBlockMock(sample: .swift, style: .editor)
                )
                comparison
                scene(
                    "In lettura: gli stessi colori, senza la sintassi del fence",
                    CodeBlockMock(sample: .swift, style: .reading)
                )
                palette
                scene(
                    "Linguaggio non dichiarato, o che la grammatica non conosce",
                    CodeBlockMock(sample: .unknown, style: .editor)
                )
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.color(.backgroundPrimary))
    }

    private func scene(_ caption: String, _ block: CodeBlockMock) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(caption).themedText(.caption, color: .textTertiary)
            block
        }
    }

    /// What the editor does today beside what it will do. Same three lines of shell.
    private var comparison: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Il difetto che questa fetta chiude, sulle stesse tre righe")
                .themedText(.caption, color: .textTertiary)
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    Text("Adesso").themedText(.caption, color: .textSecondary)
                    CodeBlockMock(sample: .shellAsStyledToday, style: .editor)
                }
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    Text("Con questa fetta").themedText(.caption, color: .textSecondary)
                    CodeBlockMock(sample: .shell, style: .editor)
                }
            }
        }
    }

    /// The seven grammars on one line each, which is the only way to see whether the five
    /// colours hold together across languages that use them in different proportions.
    private var palette: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Le sette grammatiche locali")
                .themedText(.caption, color: .textTertiary)
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                ForEach(CodeSample.tour, id: \.language) { sample in
                    HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.m)) {
                        Text(sample.language ?? "")
                            .themedText(.caption, color: .textTertiary)
                            .frame(width: 56, alignment: .leading)
                        CodeLines(lines: sample.lines)
                    }
                }
            }
            .padding(theme.spacing(.s))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(.surfaceSunken))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        }
    }
}

// MARK: - The block

private struct CodeBlockMock: View {
    @Environment(\.theme) private var theme

    enum Style { case editor, reading }

    let sample: CodeSample
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            // In the editor the fence is text a person typed and can delete, so it stays
            // on screen, quiet. In reading mode it is syntax and disappears, replaced by
            // the language as a label - the same choice SPEC §5 makes everywhere else.
            switch style {
            case .editor:
                CodeLines(lines: [[Piece("```" + (sample.language ?? ""), .fence)]])
            case .reading:
                if let language = sample.language {
                    Text(language).themedText(.caption, color: .textTertiary)
                }
            }

            CodeLines(lines: sample.lines)

            if style == .editor {
                CodeLines(lines: [[Piece("```", .fence)]])
            }
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}

/// One line per row, one `Text` per piece.
///
/// An `HStack` and not a concatenation because a mockup line never wraps and this keeps
/// the pieces readable as data. The real editor colours ranges in an `NSTextStorage`.
private struct CodeLines: View {
    @Environment(\.theme) private var theme

    let lines: [[Piece]]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    ForEach(Array(line.enumerated()), id: \.offset) { _, piece in
                        Text(piece.text)
                            .font(theme.font(.mono))
                            .foregroundStyle(theme.color(piece.role.token))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - The pieces

private struct Piece {
    let text: String
    let role: Role

    init(_ text: String, _ role: Role = .plain) {
        self.text = text
        self.role = role
    }
}

/// The five roles of the grammar, plus the two the fence itself needs.
///
/// `wrong` exists only for the "today" scene: it is the accent colour, which is what a
/// `# commento` in a shell block is painted with right now because the styler reads it as
/// a tag.
private enum Role {
    case plain, fence, keyword, string, comment, number, type, wrong

    var token: ColorToken {
        switch self {
        case .plain: .textPrimary
        case .fence: .textTertiary
        case .keyword: .codeKeyword
        case .string: .codeString
        case .comment: .codeComment
        case .number: .codeNumber
        case .type: .codeType
        case .wrong: .accentPrimary
        }
    }
}

private struct CodeSample {
    let language: String?
    let lines: [[Piece]]

    static let swift = CodeSample(language: "swift", lines: [
        [Piece("// il fornitore conferma la curva", .comment)],
        [Piece("func ", .keyword), Piece("durezza"), Piece("(_ shore: "),
         Piece("Int", .type), Piece(") -> "), Piece("String", .type), Piece(" {")],
        [Piece("    guard ", .keyword), Piece("shore > "), Piece("40", .number),
         Piece(" else { "), Piece("return ", .keyword), Piece("\"morbida\"", .string),
         Piece(" }")],
        [Piece("    return ", .keyword), Piece("\"dura\"", .string)],
        [Piece("}")],
    ])

    static let shell = CodeSample(language: "sh", lines: [
        [Piece("# rigenera l'indice del vault", .comment)],
        [Piece("perg index --rebuild --vault "), Piece("\"$HOME/Labs\"", .string)],
        [Piece("test "), Piece("$?", .plain), Piece(" -eq "), Piece("0", .number),
         Piece(" && echo "), Piece("\"fatto\"", .string)],
    ])

    /// The same three lines with the styling the editor applies to them today.
    static let shellAsStyledToday = CodeSample(language: "sh", lines: [
        [Piece("# rigenera l'indice del vault", .wrong)],
        [Piece("perg index --rebuild --vault \"$HOME/Labs\"")],
        [Piece("test $? -eq 0 && echo \"fatto\"")],
    ])

    static let unknown = CodeSample(language: nil, lines: [
        [Piece("2026-08-17  spedizione 4412  ritardo 2 giorni")],
        [Piece("2026-08-18  spedizione 4413  consegnata")],
    ])

    /// One line each, chosen so every language shows the roles it actually uses: yaml has
    /// no keywords to speak of and json has no comments at all.
    static let tour: [CodeSample] = [
        CodeSample(language: "swift", lines: [[
            Piece("let ", .keyword), Piece("mescola: "), Piece("Mescola", .type),
            Piece(" = .init(shore: "), Piece("70", .number), Piece(")"),
        ]]),
        CodeSample(language: "python", lines: [[
            Piece("def ", .keyword), Piece("carico(t): "), Piece("return ", .keyword),
            Piece("t * "), Piece("9.81", .number), Piece("  # newton", .comment),
        ]]),
        CodeSample(language: "js", lines: [[
            Piece("const ", .keyword), Piece("url = "), Piece("\"https://esempio.it\"", .string),
            Piece("; "), Piece("// non è un commento sopra", .comment),
        ]]),
        CodeSample(language: "json", lines: [[
            Piece("{ "), Piece("\"tags\"", .type), Piece(": ["), Piece("\"project-forno\"", .string),
            Piece("], "), Piece("\"peso\"", .type), Piece(": "), Piece("12.5", .number), Piece(" }"),
        ]]),
        CodeSample(language: "yaml", lines: [[
            Piece("vault", .type), Piece(": "), Piece("~/Labs", .string),
            Piece("    # percorso locale", .comment),
        ]]),
        CodeSample(language: "sh", lines: [[
            Piece("if ", .keyword), Piece("[ -d "), Piece("\"$VAULT\"", .string),
            Piece(" ]; "), Piece("then ", .keyword), Piece("exit ", .keyword),
            Piece("0", .number), Piece("; "), Piece("fi", .keyword),
        ]]),
        CodeSample(language: "sql", lines: [[
            Piece("select ", .keyword), Piece("* from "), Piece("note", .type),
            Piece(" where peso > "), Piece("12.5", .number), Piece(" -- soglia", .comment),
        ]]),
    ]
}
