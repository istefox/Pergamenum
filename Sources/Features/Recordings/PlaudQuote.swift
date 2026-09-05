import Foundation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 5 - R-08;
// ADR §D9.
//
// Dedup across a re-run is a quote fingerprint, never a task id: the contract guarantees a
// task's id is stable only within one proposal read, not across separate `process` runs.
//
// Tester-declared signature only (this dispatch's brief, task 5: "implement... no, DECLARE
// PlaudQuote.fingerprint(_:) -> String... stub body, tester owns declaration only"). The
// body below is an obviously-wrong-but-compiling placeholder - it returns the raw string
// completely unchanged, doing none of the five steps the ADR names - so
// `Tests/PlaudQuoteTests.swift` can reference the real symbol and run red until the coder
// implements the real algorithm:
//
//   1. `precomposedStringWithCanonicalMapping` (NFC)
//   2. `folding(.diacriticInsensitive, .caseInsensitive, .widthInsensitive)`, en_US_POSIX
//   3. every character that is not a letter or a digit becomes a space
//   4. split on whitespace, join with a single space
//   5. an empty result is never a fingerprint: it matches nothing, including another empty
//      one - the guard against a punctuation-only quote suppressing every other such quote.
enum PlaudQuote {
    static func fingerprint(_ raw: String) -> String {
        raw
    }
}
