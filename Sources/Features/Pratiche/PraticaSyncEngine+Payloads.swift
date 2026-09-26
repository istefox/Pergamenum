import Foundation

extension PraticaSyncEngine {
    /// One `sync(_:)` call's request (SPEC "Sync algorithm").
    struct SyncRequest: Sendable {
        /// Vault-relative path of the pratica folder, e.g.
        /// `"01 Progetti/Rossi/Offerta 2026"` - `email/` and `allegati/` are resolved
        /// under it.
        var praticaFolder: String
        var dossier: Dossier
        /// Already rule-evaluated (`MembershipRule.candidates(...).messages`),
        /// newest-first is not assumed here - `PraticaSyncPlan.workItems` re-derives
        /// the order and resolves §D15's mailbox duplicates before anything is
        /// written.
        var candidates: [MailMessageRow]
        /// `Message-ID`s this pratica has already written, from the ledger - what
        /// makes a resumed sync after a cancellation pick up only what is missing
        /// (R-11).
        var onDisk: Set<String>
        var settings: PraticheSettings
        /// The one message an explicit «Rigenera» (§D6's second exception) may
        /// rewrite. `nil` for every ordinary sync, which is what keeps §D6's guard
        /// absolute everywhere else (ADR §D21).
        ///
        /// Defaulted, and declared last, so every existing `SyncRequest(...)` call
        /// site (production and test) keeps compiling unchanged.
        var regenerating: String? = nil
        /// The ledger's §D3 bridge triples for this pratica - `regeneratePending`'s
        /// `rowID` fallback for a message the index cannot resolve by `Message-ID`
        /// alone, the same fallback `regenerationPreview` already has via its own
        /// `rowID` parameter. Defaulted for the same reason as `regenerating` above.
        var ledgerEntries: [PraticaLedger.Entry] = []
    }

    /// What one `sync(_:)` call did, for the caller that records it in the ledger and
    /// updates the tray.
    struct SyncOutcome: Equatable, Sendable {
        /// Vault-relative path of every message **note** this run finished writing, in
        /// the order they were written - R-11: only ever files that are complete,
        /// never a partial one.
        ///
        /// One entry per message, not one per file: an `.eml` sidecar (R-09) and a
        /// copied attachment (R-10) are parts of the message this list already names,
        /// and counting them would make "how much did this run import" depend on the
        /// retention setting and on how many files the sender happened to attach.
        var writtenFiles: [String]
        /// `Message-ID`s successfully imported this run - what the caller appends to
        /// `PraticaLedger.PraticaState.importedMessageIDs`.
        var importedMessageIDs: [String]
        /// `Message-ID`s this run found imported before but whose row is now gone
        /// from the store (R-16) - the caller marks these "not in Mail" in the
        /// ledger; their files are never touched.
        var noLongerInMail: [String]
        /// Vault-relative paths of `pending` files this run rewrote because the body
        /// had since arrived (R-15) - the only files a sync ever rewrites unasked.
        var regeneratedPendingFiles: [String]
        /// `true` when `cancel()` stopped this run before every candidate was
        /// processed - `writtenFiles`/`importedMessageIDs` still hold everything
        /// finished before the boundary where cancellation was observed (R-11).
        var cancelled: Bool
        /// §D3's bridge triples for every message this run wrote - a fresh import and a
        /// regeneration alike, since a regeneration is exactly when a stale ROWID gets
        /// corrected. A row Mail did not thread (`conversationID == nil`) produces no
        /// triple: there is no conversation for R-14 to re-derive.
        var bridge: [PraticaLedger.Entry]
        /// Note paths whose attachment list this run amended - a pending entry that
        /// resolved, or a corrupt file that was trashed and downgraded (ADR-0040 §D5,
        /// §D7). Never a full rewrite: `regeneratedPendingFiles` keeps its exact
        /// ADR-0036 meaning, a `pending` body that arrived, and nothing is added to it
        /// by this fix.
        ///
        /// Defaulted and declared last (ADR-0040 §D10), so every existing
        /// construction site, production and test, keeps compiling unchanged.
        var resolvedAttachmentFiles: [String] = []
        /// Sentences for the pane's `problem` line: a file that could not be trashed, a
        /// downgrade that could not be written (ADR-0040 §D7.3). Empty on every
        /// healthy run.
        var attachmentProblems: [String] = []

        static let empty = SyncOutcome(
            writtenFiles: [], importedMessageIDs: [], noLongerInMail: [],
            regeneratedPendingFiles: [], cancelled: false, bridge: []
        )
    }

    /// One event per message boundary (SPEC "Sync algorithm": "emit progress
    /// (n/total)") - what a UI progress bar and this batch's cancellation tests both
    /// subscribe to.
    struct Progress: Equatable, Sendable {
        var completed: Int
        var total: Int
    }
}
