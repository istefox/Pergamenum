import Foundation

/// `IndexSnapshot`'s tag usage, tag filtering and fuzzy search, plus the `ViewCorpus`
/// conformance built on them (PG-035 — pure code motion off `IndexSnapshot.swift`, which
/// had drifted past `file_length`'s warning threshold). Touches only `notes`, `allNotes`
/// and `resolve(title:)`, all already internal — no access-level changes needed.
extension IndexSnapshot {
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

    /// The notes carrying **every** one of these tags, title-sorted (ADR-0012, slice 3).
    ///
    /// Here rather than in the tag browser, which is where it was first written: a filter over
    /// the index belongs beside the index, and a view is not a place a test can reach. An empty
    /// set answers nothing at all rather than everything - the browser with no tag chosen is
    /// asking a question, not selecting the vault.
    func notes(carryingAll tags: Set<Tag>) -> [NoteRecord] {
        guard !tags.isEmpty else { return [] }
        return notes.values
            .filter { tags.isSubset(of: Set($0.frontmatter.tags)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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

/// The corpus a view is evaluated over (ADR-0009 §D4).
///
/// Two members and no more: the query grammar is closed, so what it can ask about the
/// vault as a whole is closed with it. Keeping the protocol in `Core/Query` and the
/// conformance here is what lets the engine be tested against ten notes in memory
/// without an index, a cache file or a vault on disk.
extension IndexSnapshot: ViewCorpus {
    var records: [NoteRecord] { allNotes }

    func paths(forTitle title: String) -> [String] { resolve(title: title) }
}
