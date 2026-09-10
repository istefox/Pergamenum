import AppKit
import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
// R-10, R-27; UX-BLUEPRINT "Timeline column anatomy".
//
// One attachment of a message row. Click previews it through the Quick Look panel this
// app already has (`Sources/Features/QuickLook/QuickLookPresenter.swift`, the same
// panel Workspace cards use), double-click opens it with its default app, and the
// context menu reaches the Finder and the pasteboard.
//
// An over-threshold attachment (R-10) was never copied into `allegati/`: its chip
// carries `icloud.slash` and says where it still lives, rather than pretending to a
// file this vault does not have.
struct AttachmentChip: View {
    enum Content: Equatable {
        case file(PraticaAttachmentRef)
        /// An attachment past `PraticheSettings.attachmentThresholdMB`, recorded rather
        /// than copied (R-10).
        case storeReference(MessageDocument.StoreReference)
    }

    @Environment(\.theme) private var theme

    let content: Content
    /// `pratiche-attachment-<hash>-<n>` (UX-BLUEPRINT's checklist).
    let identifier: String
    /// Handed up to the timeline, which owns the Quick Look host: the panel needs one
    /// responder for the whole list, not one per chip.
    let onQuickLook: (URL) -> Void

    var body: some View {
        Button(action: preview) {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: symbol)
                Text(name).lineLimit(1)
            }
            .themedText(.caption, color: isMissing ? .textTertiary : .textSecondary)
            .padding(.horizontal, theme.spacing(.xs))
            .padding(.vertical, 2)
            .background(theme.color(.backgroundTertiary))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(identifier)
        .simultaneousGesture(TapGesture(count: 2).onEnded { openWithDefaultApp() })
        .contextMenu {
            Button("Anteprima") { preview() }
                .disabled(previewURL == nil)
            Button("Apri") { openWithDefaultApp() }
                .disabled(openURL == nil)
            Button("Mostra nel Finder") { showInFinder() }
                .disabled(revealURL == nil)
            Button("Copia nome") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(name, forType: .string)
            }
        }
    }

    // MARK: What the chip is

    private var name: String {
        switch content {
        case .file(let reference): reference.name
        case .storeReference(let reference): reference.name
        }
    }

    /// Injected into `AttachmentChipModel` rather than read there directly (ADR-0155):
    /// keeps the pure decision testable with an arbitrary filesystem state.
    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Quick Look's target (R-27): `nil` for a store reference and for a file whose copy
    /// is not on disk - both are chips with nothing to preview.
    private var previewURL: URL? { AttachmentChipModel.previewURL(for: content, fileExists: fileExists) }

    /// The default-app / double-click target (R-27): the local copy, or a store
    /// reference's own store path when it is still there.
    private var openURL: URL? { AttachmentChipModel.openURL(for: content, fileExists: fileExists) }

    /// The "Mostra nel Finder" target (R-27): the same rule as `openURL`.
    private var revealURL: URL? { AttachmentChipModel.revealURL(for: content, fileExists: fileExists) }

    /// A file whose copy is not on disk: the difference between it and a store reference
    /// is the message the tooltip carries, not this flag, which only ever asks "is this a
    /// file reference with nothing to preview".
    private var isMissing: Bool {
        guard case .file = content else { return true }
        return previewURL == nil
    }

    private var symbol: String { AttachmentChipModel.symbol(for: content, fileExists: fileExists) }

    private var helpText: String {
        switch content {
        case .file:
            previewURL == nil
                ? "\(name) — il file non è in allegati/"
                : name
        case .storeReference(let reference):
            "\(name) — \(Self.megabytes(reference.size)) MB, resta nell'archivio di Mail: \(reference.storePath)"
        }
    }

    private var accessibilityText: String {
        switch content {
        case .file: "Allegato \(name)"
        case .storeReference: "Allegato \(name), non copiato"
        }
    }

    /// Whole megabytes: the number is there to explain why a 400 MB file was not
    /// copied, and a decimal place adds nothing to that sentence.
    static func megabytes(_ bytes: Int) -> Int {
        max(1, bytes / (1024 * 1024))
    }

    // MARK: Actions

    private func preview() {
        guard let previewURL else { return }
        onQuickLook(previewURL)
    }

    private func openWithDefaultApp() {
        guard let openURL else { return }
        NSWorkspace.shared.open(openURL)
    }

    private func showInFinder() {
        guard let revealURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([revealURL])
    }
}
