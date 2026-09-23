import Foundation
import Testing
@testable import Pergamenum

// PG-139 (issue #239), Task 3: `EntryRanking.matching` now lowercases and word-splits each
// entry once per call instead of once per tier. This is a differential test, not a new
// behaviour spec: it keeps its own copy of the *old*, unoptimised `rank`/`aWord`/
// `fuzzyCloseness` shape (what this file's production code carried before PG-139, each
// re-lowercasing its own argument on every call) and asserts the production
// `EntryRanking.matching` answers exactly what that reference implementation would, over
// every one- and two-character prefix drawn from both real catalogues, with and without
// `allowingFuzzy`.

// MARK: - Reference implementation (the pre-PG-139 shape, kept only for this comparison)

private func referenceAWord(of text: String, startsWith needle: String) -> Bool {
    text.lowercased()
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .contains { $0.hasPrefix(needle) }
}

private func referenceRank<Entry: RankableEntry>(_ entry: Entry, startingWith needle: String) -> Int? {
    if entry.rankingTitle.lowercased().hasPrefix(needle) { return 3 }
    if referenceAWord(of: entry.rankingTitle, startsWith: needle) { return 2 }
    if entry.keywords.contains(where: { referenceAWord(of: $0, startsWith: needle) }) { return 1 }
    return nil
}

private func referenceFuzzyCloseness<Entry: RankableEntry>(_ entry: Entry, to needle: String) -> Int? {
    var best: Int?
    for candidate in [entry.rankingTitle] + entry.keywords {
        guard let score = FuzzyMatch.score(query: needle, candidate: candidate) else { continue }
        best = max(best ?? score, score)
    }
    return best
}

private struct ReferenceRanked<Entry: RankableEntry> {
    let entry: Entry
    let rank: Int
    let order: Int
    var closeness: Int = 0
}

private func referenceMatching<Entry: RankableEntry>(
    _ query: String, in catalogue: [Entry], allowingFuzzy: Bool
) -> [Entry] {
    guard !query.isEmpty else { return catalogue }
    let needle = query.lowercased()

    var scored: [ReferenceRanked<Entry>] = []
    for (order, entry) in catalogue.enumerated() {
        if let rank = referenceRank(entry, startingWith: needle) {
            scored.append(ReferenceRanked(entry: entry, rank: rank, order: order))
        } else if allowingFuzzy, let closeness = referenceFuzzyCloseness(entry, to: needle) {
            scored.append(ReferenceRanked(entry: entry, rank: 0, order: order, closeness: closeness))
        }
    }
    scored.sort { left, right in
        if left.rank != right.rank { return left.rank > right.rank }
        if left.closeness != right.closeness { return left.closeness > right.closeness }
        return left.order < right.order
    }
    return scored.map(\.entry)
}

// MARK: - Every one- and two-character prefix drawn from a catalogue's own text

/// Every one- and two-character lowercase prefix built from the letters/digits actually
/// appearing in `catalogue`'s titles and keywords - the corpus this differential test runs
/// over, rather than a hand-picked handful, since the point is not to miss a case the
/// reference and the optimised path would answer differently.
private func prefixes<Entry: RankableEntry>(in catalogue: [Entry]) -> [String] {
    var letters: Set<Character> = []
    for entry in catalogue {
        letters.formUnion(entry.rankingTitle.lowercased())
        for keyword in entry.keywords { letters.formUnion(keyword.lowercased()) }
    }
    letters = letters.filter { $0.isLetter || $0.isNumber }

    var result: Set<String> = []
    for first in letters {
        result.insert(String(first))
        for second in letters {
            result.insert(String([first, second]))
        }
    }
    return Array(result)
}

/// Runs both implementations over every prefix of `catalogue`, with and without
/// `allowingFuzzy`, and asserts they agree - by `id`, so a coincidental value equality
/// between two different entries cannot mask a real reordering.
private func assertMatchingAgreesWithReference<Entry: RankableEntry & Identifiable>(
    _ catalogue: [Entry], sourceLocation: SourceLocation = #_sourceLocation
) {
    for prefix in prefixes(in: catalogue) {
        for allowingFuzzy in [false, true] {
            let optimised = EntryRanking.matching(prefix, in: catalogue, allowingFuzzy: allowingFuzzy).map(\.id)
            let reference = referenceMatching(prefix, in: catalogue, allowingFuzzy: allowingFuzzy).map(\.id)
            #expect(
                optimised == reference,
                "prefix \"\(prefix)\" allowingFuzzy=\(allowingFuzzy)",
                sourceLocation: sourceLocation
            )
        }
    }
}

@MainActor
@Test func matchingAgreesWithTheReferenceImplementationForTheEditorCommandCatalogue() {
    assertMatchingAgreesWithReference(EditorCommand.all(canRun: { _ in true }))
}

@Test func matchingAgreesWithTheReferenceImplementationForTheEmojiCatalogue() {
    assertMatchingAgreesWithReference(EmojiCatalogue.entries)
}
