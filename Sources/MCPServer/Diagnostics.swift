import Foundation

/// Where this program is allowed to speak.
///
/// stdout is the transport: a JSON-RPC frame with a stray line in the middle of it is a
/// protocol error, and the client's report of it will not mention the line. So nothing
/// ever prints. Everything the server has to say goes to stderr, which is also what the
/// 2026-07-28 spec recommends for a stdio server that wants to be heard.
enum Diagnostics {
    static func log(_ message: String) {
        FileHandle.standardError.write(Data("pergamenum-mcp: \(message)\n".utf8))
    }
}
