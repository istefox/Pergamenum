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
/// Pure and synchronous on purpose: the ordering, the §D15 duplicate resolution and the
/// "never twice" rule are the parts of the sync a test can pin down without a store, a
/// vault or an actor - `Tests/PraticaSyncTests.swift`'s `PraticaSyncPlanTests` builds
/// rows by hand and calls this directly.
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
        // Never re-imported, whatever the candidate list says: what a person removed by
        // hand (`excluded`) and what this pratica already wrote (`onDisk`). Both are
        // checked here as well as in `MembershipRule`, because this function is what
        // the engine actually walks and a candidate list assembled any other way must
        // meet the same two rules.
        let refused = Set(dossier.excluded).union(onDisk)

        var preferred: [String: MailMessageRow] = [:]
        var order: [String] = []
        for row in candidates {
            if let messageID = row.messageID, refused.contains(messageID) { continue }
            // A row the store could not give an RFC id for is still one message: keyed
            // on its ROWID, it cannot collide with another row's key.
            let key = row.messageID ?? "rowid:\(row.rowID)"
            guard let rival = preferred[key] else {
                preferred[key] = row
                order.append(key)
                continue
            }
            if prefers(row, over: rival) { preferred[key] = row }
        }

        return order
            .compactMap { preferred[$0] }
            .sorted { left, right in
                let leftDate = date(of: left)
                let rightDate = date(of: right)
                if leftDate != rightDate { return leftDate > rightDate }
                // The ROWID breaks the tie so two messages sent in the same second land
                // in an order that is a function of the input rather than of the sort's
                // own stability.
                return left.rowID < right.rowID
            }
            .map(WorkItem.init)
    }

    /// §D15: the copy that survives is the one whose mailbox is neither Trash nor Junk,
    /// and among the rest the lowest ROWID.
    private static func prefers(_ candidate: MailMessageRow, over rival: MailMessageRow) -> Bool {
        let candidateSidelined = isSidelined(candidate.mailbox)
        let rivalSidelined = isSidelined(rival.mailbox)
        if candidateSidelined != rivalSidelined { return rivalSidelined }
        return candidate.rowID < rival.rowID
    }

    /// Mail's own Trash and Junk, in the spellings the mailbox url carries on an IMAP,
    /// an Exchange and a local account. Matched on a whole path component, never as a
    /// substring: a mailbox legitimately named «Trashware» is not the Trash.
    private static let sidelinedMailboxNames: Set<String> = [
        "trash", "cestino", "deleted messages", "deleted items",
        "junk", "junk e-mail", "spam", "posta indesiderata", "bulk mail",
    ]

    private static func isSidelined(_ mailbox: MailboxRef) -> Bool {
        let components: [String]
        if let parsed = URL(string: mailbox.url) {
            components = parsed.pathComponents.filter { $0 != "/" }
        } else {
            components = mailbox.url.split(separator: "/").map(String.init)
        }
        return components.contains { sidelinedMailboxNames.contains($0.lowercased()) }
    }

    /// The header `Date` is what governs ordering (SPEC "Message file frontmatter"), and
    /// `date_sent` is the index's own copy of it; `date_received` is the fallback for a
    /// message whose sender sent no readable `Date`.
    private static func date(of row: MailMessageRow) -> Date {
        row.dateSent ?? row.dateReceived ?? .distantPast
    }
}
