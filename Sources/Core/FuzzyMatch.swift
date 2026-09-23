import Foundation

/// Subsequence matching with a bonus for contiguous runs and word starts, which is
/// what makes `trf` find "Trasmissibilità e rapporto di frequenza".
enum FuzzyMatch {
    static func score(query: String, candidate: String) -> Int? {
        score(needle: Array(query.lowercased()), haystack: Array(candidate.lowercased()))
    }

    /// `score(query:candidate:)`'s own body, taking each side already lowercased and split
    /// into `[Character]` - the shape a caller ranking one query against many candidates
    /// needs so the query is lowercased once rather than once per candidate (PG-139/#239:
    /// `EntryRanking.matching`'s fuzzy tier is exactly this shape, over up to 96 entries per
    /// keystroke). Semantics identical to the wrapper above by construction.
    static func score(needle: [Character], haystack: [Character]) -> Int? {
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
