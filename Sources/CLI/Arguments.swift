import Foundation

/// The command line, taken apart.
///
/// Hand-written rather than swift-argument-parser: this repository had no package
/// dependency at all before ADR-0007, the one it is about to take is the MCP SDK, and
/// what is needed here is a hundred lines that a reader can hold in their head.
///
/// The grammar is `perg <words...> [--option value] [--flag]`. Boolean flags are named
/// in `Arguments.flagNames` rather than guessed: without a list, `--dry-run note new`
/// is ambiguous - `note` could be the flag's value or the first word - and guessing
/// wrong on a command that writes files is not a mistake worth risking.
struct Arguments {
    /// Positional words, in order: usually a group and a subcommand, then the rest.
    private(set) var words: [String] = []
    private(set) var options: [String: String] = [:]
    private(set) var flags: Set<String> = []

    /// Every `--name` that takes no value.
    static let flagNames: Set<String> = [
        "json", "help", "dry-run", "apply", "version", "all", "completed",
    ]

    enum ParseError: Error, CustomStringConvertible {
        case missingValue(String)
        case unknownFlagSyntax(String)

        var description: String {
            switch self {
            case .missingValue(let name): "l'opzione --\(name) vuole un valore"
            case .unknownFlagSyntax(let token): "argomento non riconosciuto: \(token)"
            }
        }
    }

    init(_ raw: [String]) throws {
        var index = raw.startIndex
        while index < raw.endIndex {
            let token = raw[index]
            index += 1

            guard token.hasPrefix("--") else {
                // A lone "-" or "-x" is not part of this grammar; saying so beats
                // silently treating it as a word and acting on the wrong thing.
                if token.hasPrefix("-"), token.count > 1 {
                    throw ParseError.unknownFlagSyntax(token)
                }
                words.append(token)
                continue
            }

            let body = String(token.dropFirst(2))
            if let equals = body.firstIndex(of: "=") {
                options[String(body[body.startIndex..<equals])] = String(body[body.index(after: equals)...])
                continue
            }
            if Self.flagNames.contains(body) {
                flags.insert(body)
                continue
            }
            guard index < raw.endIndex else { throw ParseError.missingValue(body) }
            options[body] = raw[index]
            index += 1
        }
    }

    subscript(_ name: String) -> String? { options[name] }

    func has(_ flag: String) -> Bool { flags.contains(flag) }

    /// The positional word at a position, or nil when the user stopped short.
    func word(_ position: Int) -> String? {
        position < words.count ? words[position] : nil
    }

    /// Everything from a position on, joined - for a command whose last argument is
    /// free text that the shell has already split on spaces.
    func rest(from position: Int) -> String {
        position < words.count ? words[position...].joined(separator: " ") : ""
    }
}
