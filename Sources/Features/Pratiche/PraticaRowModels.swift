import Foundation

/// What a timeline row needs beyond `PraticaTimelineEntry` (see `details`).
struct PraticaRowDetail: Equatable, Sendable {
    /// The file this row was read from, vault-relative - `email/<name>.md` for a
    /// message, `pratica.md` for a manual entry (which is one heading of it, ADR §D5).
    var notePath: String
    /// The markdown an expanded row renders through `MarkdownBlocksView` (R-27).
    var body: String
    /// The `<details>` block's own text, drawn under «Testo citato» when there is one.
    var quotedHistory: String?
    var signature: String?
    var attachments: [PraticaAttachmentRef]
    /// Over-threshold attachments, recorded rather than copied (R-10): a chip with no
    /// local file behind it.
    var storeReferences: [MessageDocument.StoreReference]
    /// `pergamenum-mail-body: pending` - the body has not been downloaded by Mail yet
    /// (R-15). The row dims and offers «Apri in Mail» instead of a body.
    var isPending: Bool
    var senderAddress: String?
    /// Attachment entries still waiting for their bytes (ADR-0040 §D8, R-08): the bare
    /// name, as `MessageDocument.MailFrontmatter.pendingAttachmentNames` reads it back -
    /// a chip with no file and no store path behind it at all. Declared last so every
    /// existing call site (which lists `attachments:` through `senderAddress:`
    /// positionally or by keyword) keeps compiling unchanged.
    var pendingAttachments: [String] = []
    /// R-02/R-05 (ADR-0049 §D6): the wikilink text of `pergamenum-mail-note`, when this
    /// message has a linked note - `nil` when it does not. Declared last, the same
    /// convention this file's own comment states for `pendingAttachments` above.
    /// Populated by `PraticheController+TimelineRead.swift` (Task 5); read here already
    /// so `PraticaCommandActions.commands(for:)` can compute `MessageCommand`'s
    /// `hasLinkedNote:` argument without a second field added later.
    var linkedNote: String?
}

/// One attachment chip's file (R-10). `url` is absolute and may not exist: a copy that
/// failed leaves the wikilink in the message file, and a chip that says so is better
/// than a row that silently drops it.
struct PraticaAttachmentRef: Equatable, Sendable, Identifiable {
    var name: String
    var url: URL

    var id: String { name }
}

/// ADR-0049 (Pratiche links to notes, tasks and boards), plan
/// docs/plans/pratiche-note-task-workspace-links.md, Task 5 - R-06.
///
/// One row of the inspector's aggregate "note collegate" list: the union of a
/// pratica's own general note links (`PraticaLinks.notes`) and every message's own
/// `linkedNote`, de-duplicated by title. `messagePaths` is empty for a link that is
/// general-only; non-empty names which message(s) also carry the same note, which is
/// what makes a per-message link attributable rather than merely present (R-06).
struct PraticaAggregatedNoteLink: Equatable, Sendable, Identifiable {
    var title: String
    var messagePaths: [String]

    var id: String { title }
}
