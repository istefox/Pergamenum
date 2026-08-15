import Foundation

/// Keeping up with changes made outside this process (SPEC §12, watcher FSEvents),
/// and appending text to a note without opening it.
///
/// Both matter more than they used to. ADR-0007 puts a second writer in the vault - a
/// CLI, or an MCP server answering a model - so a file changing underneath is no
/// longer only the user in Obsidian.
extension VaultSession {
    /// A note that changed on disk without this session writing it.
    struct ExternalChange: Equatable, Sendable {
        let path: String
        let text: String
    }

    /// Applies external changes to the index, one path at a time, and reports the ones
    /// a caller may have on screen.
    ///
    /// A path this session wrote itself is recognised by content hash rather than by a
    /// time window, so a real external edit is never mistaken for it, and is not
    /// reported: the caller already knows about its own writes.
    func reconcile(_ paths: [String]) -> [ExternalChange] {
        var changes: [ExternalChange] = []

        for path in paths {
            guard exists(path) else {
                updateIndex(nil, at: path)
                continue
            }
            guard let (record, text) = try? read(path) else { continue }

            if selfWrittenHashes[path] == record.contentHash {
                selfWrittenHashes.removeValue(forKey: path)
                continue
            }

            updateIndex(record, at: path)
            changes.append(ExternalChange(path: path, text: text))
        }
        return changes
    }

    /// Appends text to a note, for the capture route of SPEC §9.
    ///
    /// A blank line, not merely a newline. Appended to a note whose last line is a list
    /// item - which a daily note's Timeline section always ends with - a single newline
    /// makes the text a lazy continuation of that bullet in CommonMark: the capture is
    /// swallowed into the last time block instead of standing on its own, and lands
    /// inside a section this app rewrites.
    @discardableResult
    func append(text: String, to relativePath: String) -> WriteOutcome {
        do {
            var body = try read(relativePath).text
            while body.hasSuffix("\n") { body.removeLast() }
            let separator = body.isEmpty ? "" : "\n\n"
            return .written(try write(body + separator + text + "\n", to: relativePath))
        } catch {
            recordProblem("capture: \(error)")
            return .failed
        }
    }
}
