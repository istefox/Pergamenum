import Foundation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 5 - R-08;
// ADR §D9.
//
// Dedup across a re-run is a quote fingerprint, never a task id: the contract guarantees a
// task's id is stable only within one proposal read, not across separate `process` runs.
//
// The five steps, in order:
//
//   1. `precomposedStringWithCanonicalMapping` (NFC)
//   2. `folding(.diacriticInsensitive, .caseInsensitive, .widthInsensitive)`, en_US_POSIX
//   3. every character that is not a letter or a digit becomes a space
//   4. split on whitespace, join with a single space
//   5. an empty result is never a fingerprint: it matches nothing, including another empty
//      one - the guard against a punctuation-only quote suppressing every other such quote.
enum PlaudQuote {
    static func fingerprint(_ raw: String) -> String {
        let folded = raw
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        // Step 3 is also what makes `TranscriptNote.sanitizedQuote` invisible here (ADR §D10):
        // the five characters it replaces with a space were going to become one anyway.
        let alphanumericOnly = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        let words = String(alphanumericOnly).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return uniqueFingerprint() }
        return words.joined(separator: " ")
    }

    /// Step 5, spelled as a value rather than as a rule the callers have to remember: a
    /// quote of pure punctuation gets a fingerprint no other call can ever produce, so it
    /// matches nothing - not even the next punctuation-only quote, and not even itself on a
    /// second call. "Empty" means unique, never equal.
    ///
    /// The prefix is unrepresentable in step 4's output (which is letters, digits and single
    /// spaces), so this can never collide with a real fingerprint either.
    private static func uniqueFingerprint() -> String {
        "\u{1}unica-\(UUID().uuidString)"
    }
}
