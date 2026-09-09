import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D15.

/// The pure half of the sync algorithm (SPEC "Sync algorithm"): turns an already
/// rule-evaluated candidate list into an ordered, deduplicated list of work items the
/// actor (`PraticaSyncEngine`) writes one at a time.
///
/// Foundation-only, under `Sources/Core/Pratiche` (globbed into `sharedSources`) -
/// `perg` and `pergamenum-mcp` compile this file even though neither ever calls it
/// (ADR §D19's own boundary: compiling is not calling).
///
/// TESTER NOTE (ADR-0155 §D1): this is the declared boundary, not the implementation.
/// `workItems` is a deliberate stub - it does not yet apply §D15's mailbox
/// preference, does not honor `onDisk`, and does not sort - so that
/// `Tests/PraticaSyncTests.swift`'s red assertions fail on real, missing behaviour
/// rather than on a missing symbol. The coder fills this in; the signature is the
/// contract.
enum PraticaSyncPlan {
    /// One message this sync will attempt to write this run, in the order the engine
    /// processes them (newest first, SPEC "Sync algorithm": "what changed lands
    /// first").
    struct WorkItem: Equatable, Sendable {
        var row: MailMessageRow
    }

    /// Turns `candidates` (already rule-evaluated, e.g. `MembershipRule.candidates(...)
    /// .messages`) into the ordered work list for one sync run.
    ///
    /// - `onDisk`: `Message-ID`s this pratica has already written (from the ledger,
    ///   `PraticaLedger.PraticaState.importedMessageIDs` union `.pending`) - never
    ///   re-queued, which is what makes a resumed sync after a cancellation pick up
    ///   only what R-11 promises it will.
    /// - §D15: when `candidates` holds the same `Message-ID` under two different
    ///   `MailMessageRow.mailbox` entries (Sent and Archive routinely hold the same
    ///   message), exactly one `WorkItem` survives for it - the row whose mailbox is
    ///   neither Trash nor Junk, and among the rest the lowest `rowID`. Direction is
    ///   decided elsewhere (`MessageDocument.direction`, R-12) from `From` against own
    ///   addresses, never from which duplicate this resolution keeps - so which one
    ///   survives here must never change which lane a message draws in.
    /// - Ordered newest-first by `dateSent ?? dateReceived`, ties broken by `rowID` so
    ///   the order is a function of the input, not of a dictionary's iteration.
    static func workItems(
        dossier: Dossier,
        candidates: [MailMessageRow],
        onDisk: Set<String>,
        settings: PraticheSettings
    ) -> [WorkItem] {
        // STUB: the coder implements the §D15 mailbox-preference dedup, the `onDisk`
        // exclusion and the newest-first sort. Returning the input unfiltered and
        // unsorted keeps every caller compiling while leaving every one of this
        // batch's red assertions red.
        candidates.map(WorkItem.init)
    }
}
