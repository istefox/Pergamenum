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
    ///
    /// The door `VaultController.reconcile` actually calls (ADR-0043 §D3): the per-path
    /// read moves off the main actor and into `VaultDisk`, which reads, advances that
    /// path's clock and hands back the mutation - applied through `apply(_:)` (§D1) - plus
    /// the `ExternalChange` to report, when there is one.
    ///
    /// `disk.reconcile` is called with `selfWritten: []` (§D6, a later task in this chain,
    /// widens `selfWrittenHashes` to a pruned per-path list the actor can match against
    /// directly); the session still recognises its own write by content hash here, and
    /// skips applying the mutation at all when it does - a self-write reconciliation
    /// changes nothing the write itself did not already apply.
    func reconcile(_ paths: [String]) async -> [ExternalChange] {
        var changes: [ExternalChange] = []

        for path in paths {
            let result = await disk.reconcile(path, selfWritten: [])

            if let selfHash = selfWrittenHashes[path], selfHash == result.mutation.record?.contentHash {
                selfWrittenHashes.removeValue(forKey: path)
                continue
            }

            apply([result.mutation])
            if let change = result.change {
                changes.append(change)
            }
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
    func append(text: String, to relativePath: String) async -> WriteOutcome {
        do {
            var body = try read(relativePath).text
            while body.hasSuffix("\n") { body.removeLast() }
            let separator = body.isEmpty ? "" : "\n\n"
            return .written(try await write(body + separator + text + "\n", to: relativePath))
        } catch {
            recordProblem("capture: \(error)")
            return .failed
        }
    }
}
