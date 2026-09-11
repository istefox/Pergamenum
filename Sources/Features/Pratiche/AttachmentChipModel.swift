import Foundation

// ADR-0036 §D16/§D18 (over-threshold attachments stay in Mail's own store and are recorded
// as `MessageDocument.StoreReference` rather than copied - R-10), plan
// docs/superpowers/plans/2026-09-09-pratiche.md Task 6 - R-27.
//
// `AttachmentChip`'s decisions - which symbol it draws, what Quick Look/double-click/
// "Mostra nel Finder"/"Copia" target, and whether that target exists at all - depend only
// on its `Content` plus whether a candidate file is really on disk. Pulled out of the
// SwiftUI view (ADR-0155: this declaration is tester-owned, the coder fills gaps) so those
// decisions are testable with Foundation alone, no AppKit/SwiftUI in the loop.
//
// `fileExists` is injected rather than read from `FileManager.default` directly: the three
// states under test (present, missing, store-path-present, store-path-absent) are otherwise
// unreachable without touching the real filesystem from every call site.
enum AttachmentChipModel {
    /// `paperclip` for a copied file present in `allegati/`, `questionmark.folder` for a
    /// file reference whose copy is not on disk, `icloud.slash` for an over-threshold
    /// attachment left in Mail's own store (R-10) - distinct regardless of whether that
    /// store path still resolves, since the symbol is what tells the two apart at a glance.
    static func symbol(for content: AttachmentChip.Content, fileExists: (URL) -> Bool) -> String {
        switch content {
        case .file(let reference):
            fileExists(reference.url) ? "paperclip" : "questionmark.folder"
        case .storeReference:
            "icloud.slash"
        }
    }

    /// Quick Look's target (R-27). Only a copied file already on disk has one - a store
    /// reference is never previewed in place, it opens from its store path instead
    /// (`openURL`), which is a different action from Quick Look.
    static func previewURL(for content: AttachmentChip.Content, fileExists: (URL) -> Bool) -> URL? {
        guard case .file(let reference) = content, fileExists(reference.url) else { return nil }
        return reference.url
    }

    /// The default-app / double-click target (R-27): the local copy for a file reference,
    /// or the file at `storePath` for a store reference when it is still there.
    static func openURL(for content: AttachmentChip.Content, fileExists: (URL) -> Bool) -> URL? {
        targetURL(for: content, fileExists: fileExists)
    }

    /// The "Mostra nel Finder" target (R-27): the same rule as `openURL`.
    static func revealURL(for content: AttachmentChip.Content, fileExists: (URL) -> Bool) -> URL? {
        targetURL(for: content, fileExists: fileExists)
    }

    /// What "Copia" puts on the pasteboard (R-27): the resolved file URL, when there is one
    /// to point to - empty otherwise, never a placeholder.
    static func copyItems(for content: AttachmentChip.Content, fileExists: (URL) -> Bool) -> [URL] {
        guard let url = targetURL(for: content, fileExists: fileExists) else { return [] }
        return [url]
    }

    /// R-27's context menu, exact wording and order.
    static let contextMenuTitles = ["Mostra nel Finder", "Copia"]

    private static func targetURL(for content: AttachmentChip.Content, fileExists: (URL) -> Bool) -> URL? {
        switch content {
        case .file(let reference):
            return fileExists(reference.url) ? reference.url : nil
        case .storeReference(let reference):
            let url = URL(fileURLWithPath: reference.storePath)
            return fileExists(url) ? url : nil
        }
    }
}
