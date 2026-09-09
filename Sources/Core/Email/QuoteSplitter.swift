import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - R-07.

/// The result of splitting a message body into new text, quoted history and a
/// trailing signature.
struct QuoteSplit: Equatable, Sendable {
    /// The text before the first recognised separator - the whole body when nothing
    /// matched.
    var newText: String
    /// Everything from the first recognised separator onward, `nil` when no
    /// separator matched (SPEC "Quoted-text rules": "When no separator matches, the
    /// body stays whole").
    var quotedHistory: String?
    /// Text after the signature marker (`^-- $`, or the sender's display name
    /// followed by ≤6 short lines), moved out of `newText`/`quotedHistory` into its
    /// own `Firma` block. `nil` when no signature was found.
    var signature: String?
}

/// Splits a body on the **first** recognised separator (SPEC "Quoted-text rules"):
/// `Il giorno … ha scritto:`/`On … wrote:`, `--- Messaggio originale/Original
/// Message ---`, a `Da:/Inviato:/A:/Oggetto:` header block, an all-`>` tail, or an
/// Outlook `_{10,}` divider. A pure function with a fixture corpus of at least five
/// styles (`Tests/EmailFixtureCorpus.swift`).
enum QuoteSplitter {
    static func split(_ body: String) -> QuoteSplit {
        // Coder-owned: the five separator regexes plus the signature rule, in that
        // order. Stubbed as "nothing recognised" so every positive
        // `quotedHistory`/`signature` assertion in `Tests/QuoteSplitterTests.swift` is
        // red until the real rules land - the one negative case ("no quote stays
        // whole") is correctly green against this same stub, which is expected, not a
        // weak test (see tester memory on stub patterns).
        QuoteSplit(newText: body, quotedHistory: nil, signature: nil)
    }
}
