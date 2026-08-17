import Foundation
import Testing
@testable import Pergamenum

/// The seven local grammars (M8).
///
/// The point of these is not that a keyword turns purple. It is the order of the four
/// attempts in `CodeScanner.run`: a comment marker inside a string is not a comment, a
/// quote inside a comment does not open a string, and a construct nobody closed must end
/// with its line rather than swallow the rest of the note. Every one of those is a state
/// a person passes through while typing, so the scanner meets all of them constantly.

@MainActor
private func tokens(_ code: String, _ language: String?) -> [(text: String, token: CodeSyntax.Token)] {
    CodeSyntax.spans(in: code[...], language: language).map { (String(code[$0.range]), $0.token) }
}

@MainActor
private func text(of token: CodeSyntax.Token, in code: String, _ language: String?) -> [String] {
    tokens(code, language).filter { $0.token == token }.map(\.text)
}

// MARK: - One line per grammar

@MainActor
@Test func swiftGetsItsKeywordsTypesStringsAndNumbers() {
    let code = "let mescola: Mescola = .init(shore: 70)  // dura"
    // `init` too: the scanner has no idea it is a call here rather than a declaration,
    // and that is the honest limit of a keyword set without a parser behind it.
    #expect(text(of: .keyword, in: code, "swift") == ["let", "init"])
    #expect(text(of: .type, in: code, "swift") == ["Mescola"])
    #expect(text(of: .number, in: code, "swift") == ["70"])
    #expect(text(of: .comment, in: code, "swift") == ["// dura"])
}

@MainActor
@Test func pythonReadsHashAsAComment() {
    let code = "def carico(t): return t * 9.81  # newton"
    #expect(text(of: .keyword, in: code, "python").sorted() == ["def", "return"])
    #expect(text(of: .number, in: code, "python") == ["9.81"])
    #expect(text(of: .comment, in: code, "python") == ["# newton"])
}

@MainActor
@Test func javascriptTakesTheStringBeforeTheSlashesInsideIt() {
    // The case the whole ordering exists for: `//` inside a URL is not a comment, because
    // the string started first and runs to its closing quote.
    let code = "const url = \"https://esempio.it\"; // vero commento"
    #expect(text(of: .string, in: code, "js") == ["\"https://esempio.it\""])
    #expect(text(of: .comment, in: code, "js") == ["// vero commento"])
}

@MainActor
@Test func jsonColoursItsKeysApartFromItsValues() {
    // Both are quoted strings; only one is followed by a colon. Without that distinction
    // a JSON block is one flat colour and unreadable.
    let code = "{ \"tags\": [\"project-forno\"], \"peso\": 12.5 }"
    #expect(text(of: .type, in: code, "json") == ["\"tags\"", "\"peso\""])
    #expect(text(of: .string, in: code, "json") == ["\"project-forno\""])
    #expect(text(of: .number, in: code, "json") == ["12.5"])
}

@MainActor
@Test func jsonHasNoCommentsAtAll() {
    // The one thing everybody knows about JSON. A `//` here is bad JSON, and colouring it
    // grey would tell the reader it is fine.
    #expect(text(of: .comment, in: "{ \"a\": 1 } // niente", "json").isEmpty)
}

@MainActor
@Test func yamlTakesTheKeyAndTheUnquotedValueAndStopsAtTheComment() {
    let code = "vault: ~/Labs    # percorso locale"
    #expect(text(of: .type, in: code, "yaml") == ["vault"])
    #expect(text(of: .string, in: code, "yaml") == ["~/Labs"])
    #expect(text(of: .comment, in: code, "yaml") == ["# percorso locale"])
}

@MainActor
@Test func shellKeywordsAndQuotedPaths() {
    let code = "if [ -d \"$VAULT\" ]; then exit 0; fi"
    #expect(text(of: .string, in: code, "bash") == ["\"$VAULT\""])
    #expect(text(of: .keyword, in: code, "bash").contains("then"))
    #expect(text(of: .number, in: code, "bash") == ["0"])
}

@MainActor
@Test func sqlIsCaseInsensitiveAndNamesTheTableAfterFrom() {
    let code = "SELECT * FROM note WHERE peso > 12.5 -- soglia"
    #expect(text(of: .keyword, in: code, "sql").contains("SELECT"))
    #expect(text(of: .type, in: code, "sql") == ["note"])
    #expect(text(of: .comment, in: code, "sql") == ["-- soglia"])
}

// MARK: - The hostile half

@MainActor
@Test func anUnterminatedStringEndsWithItsLineAndNotWithTheBlock() {
    // Every string is unterminated for as long as it takes to type the closing quote. A
    // scanner that ran to the end of the block would repaint the whole fence on every
    // keystroke inside a string.
    let code = "let a = \"aperta\nlet b = 2"
    #expect(text(of: .string, in: code, "swift") == ["\"aperta"])
    #expect(text(of: .number, in: code, "swift") == ["2"])
}

@MainActor
@Test func aCommentMarkerInsideAStringIsNotAComment() {
    #expect(text(of: .comment, in: "cerca = \"# non un commento\"", "python").isEmpty)
    #expect(text(of: .comment, in: "select 'a -- b' from t", "sql").isEmpty)
}

@MainActor
@Test func aKeywordInsideACommentIsJustLetters() {
    let code = "// let var func"
    #expect(text(of: .keyword, in: code, "swift").isEmpty)
    #expect(text(of: .comment, in: code, "swift") == ["// let var func"])
}

@MainActor
@Test func anUnclosedBlockCommentEndsWithTheCode() {
    let code = "/* apre e non chiude\nlet a = 1"
    #expect(text(of: .comment, in: code, "swift") == [code])
}

@MainActor
@Test func aNumberGluedToAWordIsPartOfTheWord() {
    // `shore40` is an identifier. Colouring its tail would look like a rendering fault.
    #expect(text(of: .number, in: "let shore40 = 2", "swift") == ["2"])
    #expect(text(of: .number, in: "let hex = 0x1F", "swift") == ["0x1F"])
}

@MainActor
@Test func aShebangIsAComment() {
    #expect(text(of: .comment, in: "#!/bin/sh\necho ciao", "sh") == ["#!/bin/sh"])
}

@MainActor
@Test func nothingIsSaidAboutALanguageNobodyWroteAGrammarFor() {
    // The fallback, and it has to be silence rather than a guess: a half-coloured block
    // reads as a bug, a plain one reads as a block of data.
    #expect(tokens("let a = 1", "brainfuck").isEmpty)
    #expect(tokens("let a = 1", nil).isEmpty)
    #expect(tokens("let a = 1", "").isEmpty)
    #expect(tokens("", "swift").isEmpty)
}

@MainActor
@Test func theInfoStringMayCarryMoreThanTheLanguage() {
    // ```swift title="Mescola.swift" is a fence Obsidian accepts, so the first word is
    // the language and the rest is somebody else's metadata.
    #expect(CodeSyntax.language(named: "swift title=\"Mescola.swift\"")?.names.first == "swift")
    #expect(CodeSyntax.language(named: "SWIFT")?.names.first == "swift")
}

@MainActor
@Test func everyAliasReachesExactlyOneGrammar() {
    // The lookup takes the first match, so a name in two records would resolve by
    // declaration order - which is the sort of thing nobody notices until a `ts` block
    // is highlighted as SQL.
    var seen: Set<String> = []
    for grammar in CodeSyntax.grammars {
        for name in grammar.names {
            #expect(seen.insert(name).inserted, "«\(name)» compare in due grammatiche")
        }
    }
}

@MainActor
@Test func theSpansAreInOrderAndNeverOverlap() {
    // A left-to-right pass has no reason to produce anything else, and the editor applies
    // them in order onto a text storage: two spans over the same characters would mean
    // the later one silently wins.
    let code = """
    // intestazione
    let nome: Mescola = "dura"   // 70 shore
    let numeri = [1, 2.5, 0x1F]
    """
    var previous: String.Index?
    for span in CodeSyntax.spans(in: code[...], language: "swift") {
        if let previous { #expect(span.range.lowerBound >= previous) }
        previous = span.range.upperBound
    }
}
