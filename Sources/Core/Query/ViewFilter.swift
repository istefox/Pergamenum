import Foundation

/// The `where` expression of a view (ADR-0009 §D3).
///
/// A closed set of terms combined with `and`, `or`, `not` and parentheses. There is no
/// escape hatch and this is the point: if a question cannot be asked with these terms,
/// the answer is a new term in a later version with an argument for it, not a general
/// mechanism that makes every future question the user's problem.
///
/// Parsing only, like `SearchQuery`. Deciding whether a note satisfies the expression
/// needs the whole vault and lives in `ViewEvaluator`.
indirect enum ViewFilter: Equatable, Sendable {
    /// No `where` key: every note in the `from` scope.
    case all
    case and(ViewFilter, ViewFilter)
    case or(ViewFilter, ViewFilter)
    case not(ViewFilter)

    /// `path("Clienti")`, `path("01 *")`: a prefix without a wildcard, a glob with one.
    case path(String)
    /// `tag("client-*")`, `tag("status-aperto")`: a glob with a wildcard, exact without.
    case tag(String)
    /// `linksTo("Nota")`: this note carries a wikilink that resolves to that one.
    case linksTo(String)
    /// `linkedFrom("Nota")`: that note carries a wikilink that resolves to this one.
    case linkedFrom(String)
    /// `task(open)`, `task(done)`: the note has at least one task in that state.
    case task(TaskItem.State)
    /// `has(deadline.next)`: the field exists and is not empty.
    case has(ViewField)
    /// `text("frequenza")`: the one term that reads the file (§D3, cost in §D7).
    case text(String)
    /// `date >= 2026-08-01`, `modified < 2026-08-19`, `modified >= week-start`.
    ///
    /// The bound may be relative (ADR-0014), which is why it is a `ViewDateBound` and not a
    /// `CalendarDate`: what day it means is not known until somebody says which day the view
    /// is being read on, and this type is parsed long before that.
    case comparison(ViewField, Comparison, ViewDateBound)

    enum Comparison: String, Equatable, Sendable {
        case greaterThan = ">"
        case atLeast = ">="
        case lessThan = "<"
        case atMost = "<="
        case equalTo = "="

        func admits(_ day: CalendarDate, against bound: CalendarDate) -> Bool {
            switch self {
            case .greaterThan: day > bound
            case .atLeast: day >= bound
            case .lessThan: day < bound
            case .atMost: day <= bound
            case .equalTo: day == bound
            }
        }
    }

    /// Whether the expression reads the files rather than the index. `ViewEvaluator` asks
    /// so it can leave the expensive half for last, and §D7 states the cost this carries.
    var readsText: Bool {
        switch self {
        case .text: true
        case .and(let lhs, let rhs), .or(let lhs, let rhs): lhs.readsText || rhs.readsText
        case .not(let inner): inner.readsText
        default: false
        }
    }
}

// MARK: - Parsing

extension ViewFilter {
    /// Parses a `where` value. The line number is carried in rather than discovered
    /// because §D1 requires an error that names the line, and only the block knows it.
    static func parse(_ source: String, line: Int) throws -> ViewFilter {
        var parser = Parser(tokens: try Lexer.tokens(in: source, line: line), line: line)
        let filter = try parser.expression()
        try parser.expectEnd()
        return filter
    }

    private struct Parser {
        let tokens: [Token]
        let line: Int
        var index = 0

        var current: Token? { index < tokens.count ? tokens[index] : nil }

        /// `or` binds loosest, then `and`, then `not`: the reading a person expects from
        /// `tag("a") and tag("b") or tag("c")` without having been told the rule.
        mutating func expression() throws -> ViewFilter {
            var left = try conjunction()
            while case .keyword("or") = current {
                index += 1
                left = .or(left, try conjunction())
            }
            return left
        }

        private mutating func conjunction() throws -> ViewFilter {
            var left = try unary()
            while case .keyword("and") = current {
                index += 1
                left = .and(left, try unary())
            }
            return left
        }

        private mutating func unary() throws -> ViewFilter {
            if case .keyword("not") = current {
                index += 1
                return .not(try unary())
            }
            if case .open = current {
                index += 1
                let inner = try expression()
                guard case .close = current else {
                    throw ViewBlockError(line: line, reason: "manca una parentesi chiusa")
                }
                index += 1
                return inner
            }
            return try leaf()
        }

        private mutating func leaf() throws -> ViewFilter {
            guard case .word(let name) = current else {
                throw ViewBlockError(line: line, reason: "atteso un termine, trovato \(describeCurrent())")
            }
            index += 1
            if case .comparison(let symbol) = current { return try comparison(field: name, symbol: symbol) }
            guard case .open = current else {
                throw ViewBlockError(
                    line: line,
                    reason: "«\(name)» va usato come termine, per esempio \(name)(…), o come confronto di data"
                )
            }
            index += 1
            guard case .word(let argument) = current else {
                throw ViewBlockError(line: line, reason: "«\(name)» vuole un argomento")
            }
            index += 1
            guard case .close = current else {
                throw ViewBlockError(line: line, reason: "manca la parentesi chiusa di «\(name)»")
            }
            index += 1
            return try term(name: name, argument: argument)
        }

        private func term(name: String, argument: String) throws -> ViewFilter {
            switch name {
            case "path": .path(argument)
            case "tag": .tag(argument)
            case "linksTo": .linksTo(argument)
            case "linkedFrom": .linkedFrom(argument)
            case "text": .text(argument)
            case "task": .task(try state(argument))
            case "has": .has(try field(argument))
            default:
                throw ViewBlockError(
                    line: line,
                    reason: "termine sconosciuto «\(name)». Disponibili: path, tag, linksTo, linkedFrom, "
                        + "task, has, text, e i confronti su date e modified"
                )
            }
        }

        /// The same closed pair `task:` takes in the global search. A rescheduled task
        /// still wants doing, so it answers `task(open)` - `TaskItem.State.isOpen` is
        /// where that is decided, once, for the whole app.
        private func state(_ argument: String) throws -> TaskItem.State {
            switch argument.lowercased() {
            case "open": .open
            case "done": .done
            default: throw ViewBlockError(line: line, reason: "task() accetta open o done, non «\(argument)»")
            }
        }

        private func field(_ argument: String) throws -> ViewField {
            guard let field = ViewField(rawValue: argument) else {
                throw ViewBlockError(line: line, reason: ViewField.absentFieldReason(argument))
            }
            return field
        }

        private mutating func comparison(field name: String, symbol: Comparison) throws -> ViewFilter {
            index += 1
            guard let field = ViewField(rawValue: name), field == .date || field == .modified else {
                throw ViewBlockError(
                    line: line,
                    reason: "solo date e modified si confrontano con \(symbol.rawValue), non «\(name)»"
                )
            }
            guard case .word(let raw) = current, let bound = ViewDateBound.parse(raw) else {
                throw ViewBlockError(
                    line: line,
                    reason: "dopo \(symbol.rawValue) serve una data YYYY-MM-DD, "
                        + "«\(ViewDateBound.todayKeyword)», «\(ViewDateBound.todayKeyword)-N» "
                        + "o «\(ViewDateBound.weekStartKeyword)»"
                )
            }
            index += 1
            return .comparison(field, symbol, bound)
        }

        mutating func expectEnd() throws {
            guard current == nil else {
                throw ViewBlockError(line: line, reason: "avanza \(describeCurrent()) dopo la fine dell'espressione")
            }
        }

        private func describeCurrent() -> String {
            switch current {
            case .none: "la fine della riga"
            case .word(let text): "«\(text)»"
            case .keyword(let text): "«\(text)»"
            case .open: "«(»"
            case .close: "«)»"
            case .comparison(let symbol): "«\(symbol.rawValue)»"
            }
        }
    }

    private enum Token: Equatable {
        case word(String)
        case keyword(String)
        case open
        case close
        case comparison(Comparison)
    }

    private enum Lexer {
        /// Characters a bare word may carry. Quoted strings are the documented form for
        /// an argument; bare words are accepted when they lex as one, which covers
        /// `tag(client-*)` and `has(tasks.open)` and stops at the first space.
        private static let word = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_./*?#àèéìòùÀÈÉÌÒÙ"))

        static func tokens(in source: String, line: Int) throws -> [Token] {
            var tokens: [Token] = []
            var characters = Substring(source)

            while let first = characters.first {
                if first.isWhitespace {
                    characters = characters.dropFirst()
                } else if first == "(" {
                    tokens.append(.open)
                    characters = characters.dropFirst()
                } else if first == ")" {
                    tokens.append(.close)
                    characters = characters.dropFirst()
                } else if first == "\"" {
                    tokens.append(.word(try quoted(&characters, line: line)))
                } else if let symbol = comparison(&characters) {
                    tokens.append(.comparison(symbol))
                } else if first.unicodeScalars.allSatisfy(word.contains) {
                    let text = String(characters.prefix { $0.unicodeScalars.allSatisfy(word.contains) })
                    characters = characters.dropFirst(text.count)
                    let lowered = text.lowercased()
                    tokens.append(["and", "or", "not"].contains(lowered) ? .keyword(lowered) : .word(text))
                } else {
                    throw ViewBlockError(line: line, reason: "carattere inatteso «\(first)»")
                }
            }
            return tokens
        }

        private static func quoted(_ characters: inout Substring, line: Int) throws -> String {
            characters = characters.dropFirst()
            guard let end = characters.firstIndex(of: "\"") else {
                throw ViewBlockError(line: line, reason: "virgolette aperte e mai chiuse")
            }
            let text = String(characters[characters.startIndex..<end])
            characters = characters[characters.index(after: end)...]
            return text
        }

        /// `>=` before `>`, or a bound would read as an equality on the next token.
        private static func comparison(_ characters: inout Substring) -> Comparison? {
            for symbol in ["<=", ">=", "==", "<", ">", "="] where characters.hasPrefix(symbol) {
                characters = characters.dropFirst(symbol.count)
                return Comparison(rawValue: symbol == "==" ? "=" : symbol)
            }
            return nil
        }
    }
}
