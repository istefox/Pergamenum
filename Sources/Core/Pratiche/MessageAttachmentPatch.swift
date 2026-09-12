import Foundation

// ADR-0040 (Pratiche attachment reliability bugs) §D4, plan
// docs/superpowers/plans/2026-09-11-pratiche-attachment-reliability-bugs.md, Task 3 -
// R-04.

/// Patches only the `pergamenum-mail-attachments:` line of an already-rendered message
/// file, leaving every other byte untouched - a full `MessageDocument.render`
/// re-render would destroy any prose a person added below the quoted-history
/// `<details>` block (ADR §D6), which is the whole reason this exists instead of a
/// re-render-and-diff.
///
/// The line surgery itself lives in `MessageFrontmatterPatch` (ADR-0042 §D8, extracted
/// so a second patched key - `pergamenum-mail-inline-pending` - cannot drift from this
/// one's insertion-order rule). This type keeps its exact signature: none of its
/// existing tests move.
enum MessageAttachmentPatch {
    /// `nil` when `text` carries no `pergamenum-mail` frontmatter to patch: no opening
    /// `---` delimiter, no closing one, or a closed block that carries no top-level
    /// `pergamenum-mail` key.
    static func applying(entries: [String], to text: String) -> String? {
        MessageFrontmatterPatch.applying(
            line: entries.isEmpty ? nil : MessageDocument.attachmentsLine(for: entries),
            forKey: MessageDocument.attachmentsKey,
            before: [MessageDocument.inlinePendingKey, MessageDocument.storeReferencesKey, "pergamenum-mail-body"],
            to: text
        )
    }
}
