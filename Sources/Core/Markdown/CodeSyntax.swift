import Foundation

/// A very small syntax highlighter for the seven languages a note in this vault actually
/// contains code in.
///
/// One scanner, parameterised by a `Language` record, and not seven parsers: the seven
/// differ by almost nothing - what starts a comment, what quotes a string, which words are
/// keywords - and a single scanner has a single place to be wrong in. It runs on every
/// keystroke through `MarkdownStyler`, so it is a left-to-right pass over the characters
/// with no backtracking and no regular expressions.
///
/// It returns ranges and never colours: this is `Core`, it must not import SwiftUI
/// (ADR-0001 §D1), and both the editor and the reading view have to reach it. What a
/// keyword looks like is a theme token, decided by the view.
///
/// It is deliberately not a parser. It cannot tell a class from a function name, it will
/// call `Mescola` a type wherever the word appears, and inside a language it does not know
/// it says nothing at all. A highlighter that is wrong quietly is worse than one that is
/// modest, so the five roles are the ones a scanner can honestly fill.
enum CodeSyntax {
    enum Token: Equatable, Sendable {
        case keyword, string, comment, number, type
    }

    struct Span: Equatable, Sendable {
        var range: Range<String.Index>
        var token: Token
    }

    /// The tokens of one code block. Empty when the language is unknown or absent, which
    /// leaves the block monospaced and uncoloured - the honest answer, and the same one a
    /// block of tabular data or a log excerpt deserves.
    ///
    /// A `Substring` and not a `String`: the returned ranges index the string the slice was
    /// taken from, so the editor can hand it a fence out of a whole note and get positions
    /// it can colour without converting anything.
    static func spans(in code: Substring, language name: String?) -> [Span] {
        guard let language = language(named: name) else { return [] }
        var scanner = CodeScanner(code: code, language: language)
        return scanner.run()
    }

    /// The language a fence's info string names, aliases included, or nil.
    static func language(named name: String?) -> Language? {
        guard let name, !name.isEmpty else { return nil }
        // Only the first word: ```swift title="Mescola.swift" is a fence Obsidian accepts.
        let key = name.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        return grammars.first { $0.names.contains(key) }
    }

    // MARK: - The record

    struct Language: Sendable {
        /// Every spelling that reaches this grammar, lowercased. The first is the canonical
        /// one only for readability; nothing depends on the order.
        let names: [String]
        let lineComments: [String]
        let blockComment: (open: String, close: String)?
        /// Checked before `stringDelimiters`, so `"""` is one string and not three.
        let blockStrings: [String]
        let stringDelimiters: [Character]
        /// Whether `\"` keeps a string open. False for the two data formats, where it
        /// costs nothing, and for SQL, where the escape is a doubled quote.
        let escapesWithBackslash: Bool
        let keywords: Set<String>
        let caseInsensitiveKeywords: Bool
        let typeRule: TypeRule
        /// YAML only: `vault: ~/Labs` has a value that is a string without saying so.
        let unquotedValuesAreStrings: Bool

        init(
            names: [String],
            lineComments: [String] = [],
            blockComment: (open: String, close: String)? = nil,
            blockStrings: [String] = [],
            stringDelimiters: [Character] = ["\""],
            escapesWithBackslash: Bool = true,
            keywords: Set<String> = [],
            caseInsensitiveKeywords: Bool = false,
            typeRule: TypeRule = .none,
            unquotedValuesAreStrings: Bool = false
        ) {
            self.names = names
            self.lineComments = lineComments
            self.blockComment = blockComment
            self.blockStrings = blockStrings
            self.stringDelimiters = stringDelimiters
            self.escapesWithBackslash = escapesWithBackslash
            self.keywords = keywords
            self.caseInsensitiveKeywords = caseInsensitiveKeywords
            self.typeRule = typeRule
            self.unquotedValuesAreStrings = unquotedValuesAreStrings
        }
    }

    /// The four shapes a name-worth-colouring has across these seven languages. Data, not
    /// code: adding a language must not mean adding a branch to the scanner.
    enum TypeRule: Sendable {
        case none
        /// A word starting with a capital, which is the convention in all three of the
        /// languages that use it here.
        case capitalised
        /// A word or a quoted string followed by `:` - a key in JSON and in YAML.
        case keyBeforeColon
        /// The word after one of these, which is how SQL names a table.
        case afterKeyword(Set<String>)
    }
}
