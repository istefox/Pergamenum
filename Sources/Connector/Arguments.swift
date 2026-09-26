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
    ///
    /// One list for both connectors, so `--dry-run` means the same thing wherever it is
    /// typed. `allow-write` belongs to the MCP server alone and is harmless here: `perg`
    /// writes when told to and has no such switch to shadow.
    static let flagNames: Set<String> = [
        "json", "help", "dry-run", "apply", "version", "all", "completed", "allow-write",
    ]

    enum ParseError: Error, CustomStringConvertible, Equatable {
        case missingValue(String)
        case unknownFlagSyntax(String)
        /// `--dry-run=true`: a flag spelled with a value (ADR-0063 §D3). Refused rather
        /// than filed among the options, where `has("dry-run")` would miss it and the
        /// write would be real.
        case flagTakesNoValue(String)

        var description: String {
            switch self {
            case .missingValue(let name): "l'opzione --\(name) vuole un valore"
            case .unknownFlagSyntax(let token): "argomento non riconosciuto: \(token)"
            case .flagTakesNoValue(let name): "l'opzione --\(name) non vuole un valore"
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

            // ADR-0063 §D3, in this order: a bare `--`, `name=value`, a flag, and last an
            // option whose value is the next token.
            guard token != "--" else { throw ParseError.unknownFlagSyntax(token) }
            let body = String(token.dropFirst(2))
            if let equals = body.firstIndex(of: "=") {
                let name = String(body[body.startIndex..<equals])
                if Self.flagNames.contains(name) { throw ParseError.flagTakesNoValue(name) }
                // Taken verbatim: `--title=--strange` is how a value starting with `--`
                // gets through.
                options[name] = String(body[body.index(after: equals)...])
                continue
            }
            if Self.flagNames.contains(body) {
                flags.insert(body)
                continue
            }
            // A value that begins with `--` is the next option, not this one's value:
            // taking it would let `--folder --dry-run` eat the flag and write for real.
            // A single dash (`-1`) is still a value.
            guard index < raw.endIndex, !raw[index].hasPrefix("--") else {
                throw ParseError.missingValue(body)
            }
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
