import Foundation

// ADR-0036 §D16/§D18 (over-threshold attachments stay in Mail's own store and are recorded
// as `MessageDocument.StoreReference` rather than copied - R-10), plan
// docs/superpowers/plans/2026-09-09-pratiche.md Task 6 - R-27; ADR-0040 §D8 (R-08, R-09).
//
// `AttachmentChip`'s decisions - which symbol it draws, what Quick Look/double-click/
// "Mostra nel Finder"/"Copia" target, and whether that target exists at all - depend only
// on its `Content` plus whether a candidate file is really on disk and, once there,
// whether its bytes are usable. Pulled out of the SwiftUI view (ADR-0155: this
// declaration is tester-owned, the coder fills gaps) so those decisions are testable
// with Foundation alone, no AppKit/SwiftUI in the loop.
//
// `state` is injected rather than read from `FileManager`/`AttachmentIntegrity` directly:
// the states under test (usable, missing, unusable) are otherwise unreachable without
// touching the real filesystem from every call site.
enum AttachmentChipModel {
    /// Whether a candidate file at a `URL` is there and readable (ADR-0040 §D8, R-09).
    /// `.missing` is "nothing at that path"; `.unusable` is "something is there and
    /// `AttachmentIntegrity` rejects it" - a damaged file must read differently from an
    /// absent one, which a `Bool` could never carry.
    enum FileState: Equatable {
        case usable
        case missing
        case unusable
    }

    /// `paperclip` for a copied, usable file in `allegati/`, `exclamationmark.triangle`
    /// for a copied file `AttachmentIntegrity` rejects, `questionmark.folder` for a file
    /// reference whose copy is not on disk, `icloud.slash` for an over-threshold
    /// attachment left in Mail's own store (R-10), `clock.badge.questionmark` for an
    /// attachment still waiting for its bytes (R-08) - distinct regardless of whether a
    /// store path still resolves, since the symbol is what tells them apart at a glance.
    static func symbol(for content: AttachmentChip.Content, state: (URL) -> FileState) -> String {
        switch content {
        case .file(let reference):
            switch state(reference.url) {
            case .usable: "paperclip"
            case .missing: "questionmark.folder"
            case .unusable: "exclamationmark.triangle"
            }
        case .storeReference:
            "icloud.slash"
        case .pending:
            "clock.badge.questionmark"
        }
    }

    /// Quick Look's target (R-27). Only a copied, usable file already on disk has one -
    /// a store reference is never previewed in place (it opens from its store path
    /// instead, `openURL`, a different action from Quick Look), and a pending attachment
    /// has no bytes to preview at all (R-08).
    static func previewURL(for content: AttachmentChip.Content, state: (URL) -> FileState) -> URL? {
        guard case .file(let reference) = content, state(reference.url) == .usable else { return nil }
        return reference.url
    }

    /// The default-app / double-click target (R-27): the local copy for a file
    /// reference when usable, or the file at `storePath` for a store reference when it
    /// is still there and usable. `nil` for `.pending` without ever probing anything
    /// (R-08).
    static func openURL(for content: AttachmentChip.Content, state: (URL) -> FileState) -> URL? {
        targetURL(for: content, state: state)
    }

    /// The "Mostra nel Finder" target (R-27): the same rule as `openURL`.
    static func revealURL(for content: AttachmentChip.Content, state: (URL) -> FileState) -> URL? {
        targetURL(for: content, state: state)
    }

    /// What "Copia" puts on the pasteboard (R-27): the resolved file URL, when there is
    /// one to point to - empty otherwise, never a placeholder.
    static func copyItems(for content: AttachmentChip.Content, state: (URL) -> FileState) -> [URL] {
        guard let url = targetURL(for: content, state: state) else { return [] }
        return [url]
    }

    /// R-27's context menu, exact wording and order.
    static let contextMenuTitles = ["Mostra nel Finder", "Copia"]

    private static func targetURL(for content: AttachmentChip.Content, state: (URL) -> FileState) -> URL? {
        switch content {
        case .file(let reference):
            return state(reference.url) == .usable ? reference.url : nil
        case .storeReference(let reference):
            let url = URL(fileURLWithPath: reference.storePath)
            return state(url) == .usable ? url : nil
        case .pending:
            return nil
        }
    }
}
