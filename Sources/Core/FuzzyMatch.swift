import Foundation

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
