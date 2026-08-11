import Foundation
import Observation

/// The rebuildable index: titles, links, backlinks and tags derived from the files.
///
/// Never the source of truth (SPEC §3, principle 3). Deleting it loses nothing,
/// because everything in it comes from a vault scan.
///
/// Held in memory for now rather than in the SQLite cache ADR-0001 §D2 describes.
/// The contract that ADR states - disposable, rebuilt from a scan, never written as
/// the primary effect of a user action - is satisfied either way, and the choice
/// between them is a question about cold-scan cost on the real Labs vault, which is
/// worth measuring before paying for a dependency. See the ADR's update note.
@MainActor
@Observable
final class NoteIndex {
    private(set) var notes: [String: NoteRecord] = [:]
    /// Files that failed to read during the last scan, surfaced in the UI.
    private(set) var failures: [String] = []
    private(set) var lastScanDuration: Duration = .zero

    /// Lowercased title to the paths that carry it. A vault can legitimately hold two
    /// notes with the same title in different folders; a wikilink to that title is
    /// ambiguous and the UI has to say so rather than silently picking one.
    private var titleIndex: [String: [String]] = [:]
    /// Lowercased link target to the paths of the notes that link to it.
    private var backlinkIndex: [String: [String]] = [:]
    /// Lowercased target to the spelling it was first written with, so the unresolved
    /// links panel shows what the user typed rather than the lookup key.
    private var backlinkDisplayForm: [String: String] = [:]

    // MARK: Population

    func replaceAll(with outcome: VaultScanner.Outcome, duration: Duration) {
        notes = Dictionary(uniqueKeysWithValues: outcome.records.map { ($0.relativePath, $0) })
        failures = outcome.failures.map { "\($0.path): \($0.reason)" }
        lastScanDuration = duration
        rebuildDerivedIndexes()
    }

    /// Applies a single file's change. Passing nil removes the note, which is what a
    /// deletion or a move out of the vault looks like from the watcher.
    func update(_ record: NoteRecord?, at relativePath: String) {
        if let record {
            notes[relativePath] = record
        } else {
            notes.removeValue(forKey: relativePath)
        }
        rebuildDerivedIndexes()
    }

    /// Rebuilds both derived maps from scratch.
    ///
    /// Incremental maintenance would need the note's *previous* link set to know what
    /// to unlink, and getting that wrong leaves phantom backlinks that nothing ever
    /// clears. At vault scale a full rebuild is cheap and cannot drift.
    private func rebuildDerivedIndexes() {
        titleIndex.removeAll(keepingCapacity: true)
        backlinkIndex.removeAll(keepingCapacity: true)
        backlinkDisplayForm.removeAll(keepingCapacity: true)

        func addBacklink(to target: String, from path: String) {
            let key = target.lowercased()
            backlinkIndex[key, default: []].append(path)
            if backlinkDisplayForm[key] == nil { backlinkDisplayForm[key] = target }
        }

        for record in notes.values {
            titleIndex[record.title.lowercased(), default: []].append(record.relativePath)
            for target in record.linkTargets {
                addBacklink(to: target, from: record.relativePath)
            }
            // Structural links live in `related`, not in the body, and must appear in
            // the backlink panel too (W-03 distinguishes the two, the panel shows both).
            for related in record.frontmatter.related {
                for link in WikilinkParser.links(in: related) {
                    addBacklink(to: link.target, from: record.relativePath)
                }
            }
        }
        for key in titleIndex.keys { titleIndex[key]?.sort() }
        for key in backlinkIndex.keys { backlinkIndex[key] = Array(Set(backlinkIndex[key] ?? [])).sorted() }
    }

    // MARK: Queries

    var allNotes: [NoteRecord] {
        notes.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var count: Int { notes.count }

    func note(at relativePath: String) -> NoteRecord? { notes[relativePath] }

    /// Resolves a wikilink target to note paths. More than one result means the link
    /// is ambiguous; none means it is unresolved (W-07).
    func resolve(title: String) -> [String] {
        titleIndex[title.lowercased()] ?? []
    }

    func backlinks(toTitle title: String) -> [NoteRecord] {
        (backlinkIndex[title.lowercased()] ?? []).compactMap { notes[$0] }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Every link target that no note in the vault answers to, with the notes that
    /// point at it. Feeds the "Link non risolti" panel.
    func unresolvedLinks() -> [(target: String, sources: [NoteRecord])] {
        backlinkIndex.compactMap { key, sources in
            guard titleIndex[key] == nil else { return nil }
            let records = sources.compactMap { notes[$0] }
            return records.isEmpty ? nil : (backlinkDisplayForm[key] ?? key, records)
        }
        .sorted { $0.target.localizedStandardCompare($1.target) == .orderedAscending }
    }

    /// Tag usage counts, for autocomplete to offer values already in the vault first
    /// (SPEC §4.4, open families).
    func tagUsage() -> [(tag: Tag, count: Int)] {
        var counts: [Tag: Int] = [:]
        for record in notes.values {
            for tag in record.frontmatter.tags { counts[tag, default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
    }

    /// Titles matching a fuzzy query, best first, for the quick switcher.
    func search(_ query: String, limit: Int = 20) -> [NoteRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(allNotes.prefix(limit)) }

        return notes.values
            .compactMap { record -> (NoteRecord, Int)? in
                // Aliases (F-07) serve search but never the link target, so they are
                // searched here and ignored by `resolve(title:)`.
                let candidates = [record.title] + record.frontmatter.aliases
                let best = candidates.compactMap { FuzzyMatch.score(query: trimmed, candidate: $0) }.max()
                return best.map { (record, $0) }
            }
            .sorted { $0.1 == $1.1 ? $0.0.title.count < $1.0.title.count : $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}

/// Subsequence matching with a bonus for contiguous runs and word starts, which is
/// what makes `trf` find "Trasmissibilità e rapporto di frequenza".
enum FuzzyMatch {
    static func score(query: String, candidate: String) -> Int? {
        let needle = Array(query.lowercased())
        let haystack = Array(candidate.lowercased())
        guard !needle.isEmpty, needle.count <= haystack.count else {
            return needle.isEmpty ? 0 : nil
        }

        var score = 0
        var haystackIndex = 0
        var previousMatchIndex = -2

        for character in needle {
            var found = false
            while haystackIndex < haystack.count {
                defer { haystackIndex += 1 }
                guard haystack[haystackIndex] == character else { continue }

                score += 1
                if haystackIndex == previousMatchIndex + 1 { score += 3 }
                if haystackIndex == 0 || haystack[haystackIndex - 1] == " " { score += 2 }
                previousMatchIndex = haystackIndex
                found = true
                break
            }
            guard found else { return nil }
        }
        // Shorter candidates win ties: an exact short title should outrank a long one
        // that merely contains the same letters.
        return score
    }
}
