import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - §D4.

/// Locates the `.emlx` file for one row, with «not found» distinguished from «the
/// fan-out rule drifted» (ADR §D4) - the two must never be confused, or a locator bug
/// gets shown to the user as R-16's legitimate «non più in Mail».
enum EMLXLocator {
    enum LocateResult: Equatable, Sendable {
        /// The ordinary, complete container.
        case found(URL)
        /// Mail's headers-only form (`<ROWID>.partial.emlx`, ADR §D4 follow-up) - the
        /// caller writes a `pending` message (R-15), never «non più in Mail».
        case foundPartial(URL)
        /// Neither form exists anywhere this locator looked - a message genuinely
        /// gone from Mail (R-16).
        case notInStore
        /// The predicted path (and its `.partial.emlx` sibling) missed, and the
        /// bounded enumeration this case triggers found nothing either - a rule that
        /// has drifted, reported as a diagnostic rather than shown as R-16's caption.
        case ruleFailed(candidatesTried: [String])
    }

    /// `predictedURL` is `MailStoreReader.emlxPath(forRow:)`'s answer (the digit-fan
    /// rule, reused rather than re-derived here) - `nil` when the mailbox url could
    /// not even be turned into a directory.
    ///
    /// On a miss at the predicted path (and its `.partial.emlx` sibling), this
    /// enumerates that mailbox's `Messages/` directories once, bounded, cached per
    /// mailbox for the caller's lifetime (ADR §D4) - the cache itself is the coder's
    /// concern; this signature takes the one predicted candidate a unit test can
    /// build without a live store.
    static func locate(
        predictedURL: URL?,
        fileManager: FileManager = .default
    ) -> LocateResult {
        // Coder-owned. Stubbed to the state that requires no filesystem read, so a
        // test asserting `.found`/`.foundPartial` is red until the real check lands.
        .notInStore
    }
}
