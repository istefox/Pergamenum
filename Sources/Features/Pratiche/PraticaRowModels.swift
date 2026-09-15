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
}

/// One attachment chip's file (R-10). `url` is absolute and may not exist: a copy that
/// failed leaves the wikilink in the message file, and a chip that says so is better
/// than a row that silently drops it.
struct PraticaAttachmentRef: Equatable, Sendable, Identifiable {
    var name: String
    var url: URL

    var id: String { name }
}
