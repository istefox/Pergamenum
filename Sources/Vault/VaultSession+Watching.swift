import Foundation

/// Keeping up with changes made outside this process (SPEC §12, watcher FSEvents),
/// and appending text to a note without opening it.
///
/// Both matter more than they used to. ADR-0007 puts a second writer in the vault - a
/// CLI, or an MCP server answering a model - so a file changing underneath is no
/// longer only the user in Obsidian.
extension VaultSession {
    /// A note that changed on disk without this session writing it.
    ///
    /// `content` says what the disk holds now: `.text` with the note's new text, or
    /// `.deleted` when nothing is left at the path (ADR-0061 §D1). There is deliberately no
    /// `text` accessor: every reader switches on `content`, so a deletion can never be read
    /// as an empty string by a caller that forgot the second case.
    struct ExternalChange: Equatable, Sendable {
        enum Content: Equatable, Sendable {
            case text(String)
            case deleted
        }

        let path: String
        let content: Content
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
    /// `disk.reconcile` is called with this path's own `selfWrittenHashes` list (§D6):
    /// the actor matches the file's current content hash against every entry still
    /// queued for this path, not only the most recent one, so a write whose bytes were
    /// coalesced away by FSEvents before this session's watcher fired is still
    /// recognised as its own. A match prunes every entry at or below the matched
    /// sequence (Task 7 point 2) - the file has moved at least that far, so nothing
    /// older than that can still be waiting to be observed - and never applies the
    /// mutation: a self-write reconciliation changes nothing the write itself did not
    /// already apply.
    ///
    /// A path with nothing left at it is reported as `.deleted` (ADR-0061 §D2), unless it
    /// matches an absence `moveFile` recorded for the source it vacated (§D6), which is
    /// this session's own and reported no more than a hash is. An **unmatched**
    /// reconciliation drops that path's absence entries stamped below its own sequence: the
    /// disk was read after the vacancy they describe and did not find it, and a marker left
    /// behind would swallow a later real deletion of a note recreated there. A provisional
    /// marker, numbered down from `UInt64.max`, stays out of reach of a read that ran
    /// before its move landed.
    func reconcile(_ paths: [String]) async -> [ExternalChange] {
        var changes: [ExternalChange] = []

        for path in paths {
            let result = await disk.reconcile(path, selfWritten: selfWrittenHashes[path] ?? [])

            if let matched = result.matchedSequence {
                let remaining = (selfWrittenHashes[path] ?? []).filter { $0.sequence > matched }
                if remaining.isEmpty {
                    selfWrittenHashes.removeValue(forKey: path)
                } else {
                    selfWrittenHashes[path] = remaining
                }
                continue
            }

            dropStaleAbsences(at: path, below: result.mutation.sequence)
            apply([result.mutation])
            if let change = result.change {
                changes.append(change)
            }
        }
        return changes
    }

    /// Removes `path`'s absence entries stamped below `sequence` (ADR-0061 §D6, a stale
    /// absence). Hash entries are left alone: they describe particular bytes and are pruned
    /// only by a match, as before.
    private func dropStaleAbsences(at path: String, below sequence: UInt64) {
        guard let entries = selfWrittenHashes[path] else { return }
        let remaining = entries.filter { $0.hash != Self.absenceMarker || $0.sequence >= sequence }
        guard remaining.count != entries.count else { return }
        if remaining.isEmpty {
            selfWrittenHashes.removeValue(forKey: path)
        } else {
            selfWrittenHashes[path] = remaining
        }
    }

    /// Appends text to a note, for the capture route of SPEC §9.
    ///
    /// A blank line, not merely a newline. Appended to a note whose last line is a list
    /// item - which a daily note's Timeline section always ends with - a single newline
    /// makes the text a lazy continuation of that bullet in CommonMark: the capture is
    /// swallowed into the last time block instead of standing on its own, and lands
    /// inside a section this app rewrites.
    ///
    /// `expecting:` the hash of the read the text was built on (ADR-0057 §D8, #496): a
    /// writer landing between the read and the write is refused rather than overwritten,
    /// and the refusal is `.stale`, not `.failed` - the caller says which, and records
    /// nothing here, since the file is intact.
    @discardableResult
    func append(text: String, to relativePath: String) async -> WriteOutcome {
        do {
            let existing = try read(relativePath)
            var body = existing.text
            while body.hasSuffix("\n") { body.removeLast() }
            let separator = body.isEmpty ? "" : "\n\n"
            return .written(try await write(
                body + separator + text + "\n", to: relativePath, expecting: existing.record.contentHash
            ))
        } catch is VaultSession.WriteRefusal {
            return .stale
        } catch {
            recordProblem("capture: \(error)")
            return .failed
        }
    }
}
