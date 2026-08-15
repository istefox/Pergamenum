import Foundation

/// Where the CLI writes, and in which of its two voices.
///
/// Every command answers in both: a person reading a terminal, and `--json` for a
/// program. The MCP server of ADR-0007 does not parse this output - it calls
/// `VaultSession` in the same process - but Claude Code drives `perg` through a shell,
/// and a model reading loose prose guesses. JSON is the contract for that.
///
/// stdout carries answers, stderr carries problems, and nothing else is ever mixed into
/// stdout: a caller piping into `jq` must not have a warning land in the middle of it.
enum Output {
    static func line(_ text: String) {
        print(text)
    }

    static func error(_ text: String) {
        FileHandle.standardError.write(Data("perg: \(text)\n".utf8))
    }

    /// Prints a value as JSON, sorted and indented so a diff of two runs is readable.
    static func json(_ value: some Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(value)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch let encodingFailure {
            // Reported rather than swallowed: a caller waiting on JSON that never
            // arrives has nothing to go on.
            Self.error("l'output JSON non è stato generato: \(encodingFailure)")
        }
    }
}

/// What the process exits with.
///
/// Three values rather than the usual two, because a shell script driving this has to
/// tell "you asked wrong" from "the vault said no": the first is worth fixing in the
/// script, the second is worth showing to a person.
enum ExitCode: Int32 {
    case success = 0
    /// The command line itself was wrong: unknown command, missing argument.
    case usage = 1
    /// The command was understood and could not be carried out.
    case failure = 2
}

struct CommandError: Error, CustomStringConvertible {
    let description: String
    let code: ExitCode

    init(_ description: String, code: ExitCode = .failure) {
        self.description = description
        self.code = code
    }
}
