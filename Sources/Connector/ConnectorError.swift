import Foundation

/// What a vault operation says when it cannot be carried out.
///
/// One error type for both connectors (ADR-0007 §D2). `perg` turns it into an exit code
/// and a line on stderr, the MCP server turns it into a tool result marked `isError` -
/// but the sentence itself is written once, in Italian, for whoever ends up reading it.
struct ConnectorError: Error, CustomStringConvertible {
    let description: String

    /// The caller asked wrong, as opposed to the vault refusing a well-formed request.
    /// Worth keeping apart: the first is a bug in the script or in the model's call,
    /// the second is news for a person.
    let isUsage: Bool

    init(_ description: String, usage: Bool = false) {
        self.description = description
        self.isUsage = usage
    }
}
