import Foundation

/// How a connector renders a payload.
///
/// One encoder, so `perg note read --json` and the MCP server's `read_note` produce the
/// same bytes for the same note. Sorted keys and pretty printing because the reader is
/// as often a person diffing two runs as it is a program.
enum ConnectorJSON {
    static func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)

        // JSONEncoder emits UTF-8 and nothing else, so this cannot fail - but it is said
        // out loud rather than replaced by a lossy decode that would quietly hand back
        // replacement characters if it ever did.
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw ConnectorError("la risposta non è UTF-8")
        }
        return text
    }
}
