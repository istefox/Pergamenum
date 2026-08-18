import Foundation

/// A closed catalogue's entry, as the completion filter sees it.
///
/// Extracted when the emoji picker arrived and needed the same filter the slash menu had.
/// The alternative was a second copy of the ranking, and a second copy is a copy that
/// drifts: the day someone fixes the tie-break in one of them, the other keeps reshuffling.
protocol RankableEntry {
    /// What the query is matched against first. Named apart from `title` so a type whose
    /// own `title` means something else can still say which string ranks.
    var rankingTitle: String { get }
    /// Extra words the filter matches on, so `/h2` finds "Titolo 2" and `:target` finds
    /// "bersaglio". Without these a catalogue is only usable by someone who already knows
    /// what its entries are called.
    var keywords: [String] { get }
}

extension RankableEntry {
    /// How well `needle` starts this entry, or nil when it starts no word of it.
    ///
    /// Three tiers, and the order is what a person expects: the title itself, then a word
    /// inside the title, then a keyword. `tit` reaches "Titolo 1" before "Pianifica il task
    /// domani" ever reaches it through "tit" - which it does not, and that is the point.
    /// The best subsequence score across the name and the keywords, or nil when the query is
    /// not even a subsequence of any of them.
    ///
    /// `FuzzyMatch` is the same function the wikilink completion ranks note titles with: one
    /// definition of "close enough", not two.
    func fuzzyCloseness(to needle: String) -> Int? {
        var best: Int?
        for candidate in [rankingTitle] + keywords {
            guard let score = FuzzyMatch.score(query: needle, candidate: candidate) else { continue }
            best = max(best ?? score, score)
        }
        return best
    }

    func rank(startingWith needle: String) -> Int? {
        if rankingTitle.lowercased().hasPrefix(needle) { return 3 }
        if EntryRanking.aWord(of: rankingTitle, startsWith: needle) { return 2 }
        if keywords.contains(where: { EntryRanking.aWord(of: $0, startsWith: needle) }) { return 1 }
        return nil
    }
}

/// The filter behind every closed catalogue the completion panel offers.
enum EntryRanking {
    /// The entries matching what has been typed, best first.
    ///
    /// An empty query returns everything, in catalogue order: `/` alone has to show the
    /// menu, not an empty list, and the same holds for `:`.
    ///
    /// **Not `FuzzyMatch`**, which is what the wikilink completion uses and what this used
    /// at first. That function matches a subsequence, so `es` accepts "Giorno succ*es*sivo"
    /// and "Inserisci wikilink" - and since the ranking then reorders on every keystroke,
    /// the list appears to scroll under the caret while showing nothing that was asked for.
    /// A subsequence is the right rule when the person is looking for a note whose title
    /// they half remember; it is the wrong rule for a fixed catalogue, where they are typing
    /// the beginning of a word. So: the query must start a word, and nothing else matches.
    /// `allowingFuzzy` adds a fourth tier **below** the three above: an entry that starts no
    /// word of the query can still be reached as a subsequence, so `stblmnt` finds
    /// «stabilimento». It is off by default, and that default is what keeps the slash menu
    /// exactly as it was - the objection above is to fuzzy *replacing* the word-start rule,
    /// and a tier that only ever sorts last cannot move anything that already matched.
    static func matching<Entry: RankableEntry>(
        _ query: String, in catalogue: [Entry], allowingFuzzy: Bool = false
    ) -> [Entry] {
        guard !query.isEmpty else { return catalogue }
        let needle = query.lowercased()

        // Built in steps rather than as one chained expression: the type checker gives up
        // on the chained form, which is the same note `CompletingTextView` already carries
        // for the wikilink scoring.
        var scored: [Ranked<Entry>] = []
        for (order, entry) in catalogue.enumerated() {
            if let rank = entry.rank(startingWith: needle) {
                scored.append(Ranked(entry: entry, rank: rank, order: order))
            } else if allowingFuzzy, let closeness = entry.fuzzyCloseness(to: needle) {
                // Tier 0, and the fuzzy score decides only the order *within* it: a
                // subsequence match never climbs above a word-start one, however good it is.
                scored.append(Ranked(entry: entry, rank: 0, order: order, closeness: closeness))
            }
        }
        // Catalogue order breaks a tie, never title length: the order is fixed, so the rows
        // that survive a keystroke keep the positions they had relative to each other. That
        // is the difference between a list narrowing and a list reshuffling.
        scored.sort { left, right in
            if left.rank != right.rank { return left.rank > right.rank }
            // Inside the fuzzy tier the score is the only thing that orders: catalogue order
            // there would put «crescita» above a far better match purely for being written
            // first. Everywhere else `closeness` is zero on both sides and this falls through
            // to the catalogue order, which is what keeps a list narrowing and not reshuffling.
            if left.closeness != right.closeness { return left.closeness > right.closeness }
            return left.order < right.order
        }
        return scored.map(\.entry)
    }

    /// One entry with what the sort needs: how well it matched, and where it sat in the
    /// catalogue before the filter ran.
    private struct Ranked<Entry: RankableEntry> {
        let entry: Entry
        let rank: Int
        let order: Int
        /// How good a subsequence match was, and zero for every entry that did not need one.
        var closeness: Int = 0
    }

    /// Words are runs of letters and digits, so "h2" is one word and "da fare" is two.
    /// Anything else separates, which keeps punctuation in a title from hiding the word
    /// after it.
    static func aWord(of text: String, startsWith needle: String) -> Bool {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { $0.hasPrefix(needle) }
    }
}
