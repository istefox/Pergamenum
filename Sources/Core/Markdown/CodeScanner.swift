import Foundation

/// The single left-to-right pass that turns code into spans, driven by a `Language`.
///
/// It works on a `Substring` and hands back indices into the string that substring came
/// from, which is the whole reason it is not written against `String`: the editor needs to
/// colour a fence *inside a note*, and re-deriving those positions afterwards is the arithmetic
/// that already makes `MarkdownStyler.wikilinkSpans` hard to read.
///
/// The order of the four attempts is the grammar's only real rule and it is why a scanner
/// beats a set of regular expressions here: a comment marker inside a string is not a
/// comment, a quote inside a comment does not open a string, and a keyword inside either is
/// just letters. Whichever construct starts first swallows the rest.
struct CodeScanner {
    private let characters: [Character]
    /// One more than `characters.count`: the last entry is the end, so a span that runs to
    /// the end of the code has somewhere to point.
    private let positions: [String.Index]
    private let language: CodeSyntax.Language

    private var spans: [CodeSyntax.Span] = []
    private var cursor = 0
    /// Armed by `select … from`, spent by the next word. SQL's way of naming a table.
    private var nextWordIsAType = false

    init(code: Substring, language: CodeSyntax.Language) {
        characters = Array(code)
        positions = Array(code.indices) + [code.endIndex]
        self.language = language
    }

    mutating func run() -> [CodeSyntax.Span] {
        while cursor < characters.count {
            if let length = comment() {
                emit(length, .comment)
            } else if let (length, token) = string() {
                emit(length, token)
            } else if let length = number() {
                emit(length, .number)
            } else if let length = word() {
                cursor += length
            } else {
                cursor += 1
            }
        }
        return spans
    }

    // MARK: - The four attempts

    private func comment() -> Int? {
        if let block = language.blockComment, matches(block.open) {
            let from = cursor + block.open.count
            guard let close = find(block.close, from: from) else { return characters.count - cursor }
            return close + block.close.count - cursor
        }
        for marker in language.lineComments where matches(marker) {
            return endOfLine() - cursor
        }
        return nil
    }

    /// A string, and the token it turns out to carry: a quoted JSON key is a key, not a
    /// value, and colouring it as a string would leave a JSON block one flat colour.
    private func string() -> (Int, CodeSyntax.Token)? {
        for delimiter in language.blockStrings where matches(delimiter) {
            let from = cursor + delimiter.count
            guard let close = find(delimiter, from: from) else { return (characters.count - cursor, .string) }
            return (close + delimiter.count - cursor, .string)
        }
        guard let quote = language.stringDelimiters.first(where: { $0 == characters[cursor] }) else { return nil }

        var index = cursor + 1
        while index < characters.count {
            // An unterminated string ends with its line and not with the block. Every
            // string is unterminated for as long as it takes to type the closing quote,
            // and swallowing the rest of the note while someone types is the failure that
            // makes an editor feel broken.
            if characters[index] == "\n" { return (index - cursor, .string) }
            if language.escapesWithBackslash, characters[index] == "\\" {
                index += 2
                continue
            }
            if characters[index] == quote { break }
            index += 1
        }
        let length = min(index + 1, characters.count) - cursor
        let isKey = language.typeRule.isKeyBeforeColon && colonFollows(cursor + length)
        return (length, isKey ? .type : .string)
    }

    private func number() -> Int? {
        guard characters[cursor].isNumber else { return nil }
        // `shore40` is one word, not a word and a number.
        guard cursor == 0 || !Self.isIdentifier(characters[cursor - 1]) else { return nil }

        var index = cursor
        if matches("0x") || matches("0X") {
            index += 2
            while index < characters.count, characters[index].isHexDigit || characters[index] == "_" {
                index += 1
            }
            return index - cursor
        }
        while index < characters.count {
            let character = characters[index]
            if character.isNumber || character == "_" {
                index += 1
            } else if character == ".", index + 1 < characters.count, characters[index + 1].isNumber {
                index += 2
            } else {
                break
            }
        }
        return index - cursor
    }

    /// Consumes a word and emits it if it is one of the three kinds worth colouring.
    /// Returns the length either way: a plain identifier still has to be stepped over in
    /// one go, or `Mescola` would be reconsidered from its second letter.
    private mutating func word() -> Int? {
        guard Self.isIdentifierStart(characters[cursor]) else { return nil }
        var index = cursor
        while index < characters.count, Self.isIdentifier(characters[index]) { index += 1 }
        let length = index - cursor
        let text = String(characters[cursor..<index])

        if isKeyword(text) {
            emit(length, .keyword)
            nextWordIsAType = language.typeRule.namesATypeAfter(text.lowercased())
            return 0
        }
        if nextWordIsAType {
            nextWordIsAType = false
            emit(length, .type)
            return 0
        }
        if isType(text, endingAt: index) {
            emit(length, .type)
            // In YAML the key is only half of it: `vault: ~/Labs` has a value that is a
            // string without any quotes to say so, and leaving it plain makes a settings
            // block look like prose.
            if language.unquotedValuesAreStrings { takeUnquotedValue() }
            return 0
        }
        return length
    }

    // MARK: - The two rules that need to look ahead

    private func isKeyword(_ word: String) -> Bool {
        language.caseInsensitiveKeywords
            ? language.keywords.contains(word.lowercased())
            : language.keywords.contains(word)
    }

    private func isType(_ word: String, endingAt index: Int) -> Bool {
        switch language.typeRule {
        case .none, .afterKeyword: false
        case .capitalised: word.first?.isUppercase == true
        case .keyBeforeColon: colonFollows(index)
        }
    }

    /// The value after a YAML key, up to a trailing comment or the end of the line.
    ///
    /// Called with the cursor on the `:`. A quoted value is left alone: the string scanner
    /// reaches it on the next turn of the loop and does it better.
    private mutating func takeUnquotedValue() {
        var index = cursor
        while index < characters.count, characters[index] == " " || characters[index] == ":" { index += 1 }
        guard index < characters.count, characters[index] != "\n" else { return }
        guard !language.stringDelimiters.contains(characters[index]) else { return }

        var end = index
        var lastNonSpace = index
        while end < characters.count, characters[end] != "\n" {
            // ` #` starts a comment even inside a value, so the value stops just before it.
            if characters[end] == "#", end > index, characters[end - 1] == " " { break }
            if characters[end] != " " { lastNonSpace = end }
            end += 1
        }
        cursor = index
        emit(lastNonSpace + 1 - index, .string)
    }

    private func colonFollows(_ index: Int) -> Bool {
        var next = index
        while next < characters.count, characters[next] == " " { next += 1 }
        return next < characters.count && characters[next] == ":"
    }

    // MARK: - Plumbing

    private mutating func emit(_ length: Int, _ token: CodeSyntax.Token) {
        guard length > 0 else {
            cursor += 1
            return
        }
        let end = min(cursor + length, characters.count)
        spans.append(CodeSyntax.Span(range: positions[cursor]..<positions[end], token: token))
        cursor = end
    }

    /// Whether `marker` sits at the cursor. Written without building an array, because it
    /// is asked once per marker per character of every code block on every keystroke.
    private func matches(_ marker: String) -> Bool {
        matches(marker, at: cursor)
    }

    private func matches(_ marker: String, at start: Int) -> Bool {
        var index = start
        for character in marker {
            guard index < characters.count, characters[index] == character else { return false }
            index += 1
        }
        return true
    }

    private func find(_ marker: String, from start: Int) -> Int? {
        guard !marker.isEmpty else { return nil }
        var index = max(start, 0)
        while index < characters.count {
            if matches(marker, at: index) { return index }
            index += 1
        }
        return nil
    }

    private func endOfLine() -> Int {
        var index = cursor
        while index < characters.count, characters[index] != "\n" { index += 1 }
        return index
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private static func isIdentifier(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}

private extension CodeSyntax.TypeRule {
    var isKeyBeforeColon: Bool {
        if case .keyBeforeColon = self { return true }
        return false
    }

    func namesATypeAfter(_ keyword: String) -> Bool {
        if case .afterKeyword(let words) = self { return words.contains(keyword) }
        return false
    }
}
