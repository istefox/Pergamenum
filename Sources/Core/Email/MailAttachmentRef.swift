import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-03.

/// One row of the index's `attachments` table (probed schema, Task 1 PROBE 1:
/// `ROWID`, `message INTEGER NOT NULL`, `attachment_id TEXT`, `name TEXT`) - a name
/// recorded against a message, before any file is located or copied. `EMLXReader`
/// only computes the sibling `Attachments/` directory's path (Task 2, R-04); the
/// bytes themselves, when the inline MIME payload is empty, are read from it by
/// `PraticaSyncEngine+Messages.swift`'s `resolveExternalized` (ADR-0048).
struct MailAttachmentRef: Equatable, Sendable {
    var messageRowID: Int
    var attachmentID: String?
    var name: String?
}
