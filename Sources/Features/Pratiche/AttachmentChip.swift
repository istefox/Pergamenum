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
        /// An attachment entry Mail has not delivered bytes for yet (ADR-0040 §D8,
        /// R-08). Carries only the bare name - there is no file and no store path to
        /// point a URL function at, which is why every `AttachmentChipModel` function
        /// answers `nil`/`[]` for this case without ever calling `state`.
        case pending(name: String)
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
                Text(label).lineLimit(1)
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
        .popover(isPresented: $isShowingPendingExplanation) {
            Text("L'allegato non è ancora disponibile in Mail. Verrà riprovato alla prossima sincronizzazione.")
                .themedText(.body)
                .padding(theme.spacing(.s))
        }
        .contextMenu {
            Button("Anteprima") { preview() }
                .disabled(previewURL == nil)
            Button("Apri") { openWithDefaultApp() }
                .disabled(openURL == nil)
            Button(AttachmentChipModel.contextMenuTitles[0]) { showInFinder() }
                .disabled(revealURL == nil)
            Button(AttachmentChipModel.contextMenuTitles[1]) { copy() }
        }
    }

    @State private var isShowingPendingExplanation = false

    // MARK: What the chip is

    private var name: String {
        switch content {
        case .file(let reference): reference.name
        case .storeReference(let reference): reference.name
        case .pending(let name): name
        }
    }

    /// Injected into `AttachmentChipModel` rather than read there directly (ADR-0155):
    /// keeps the pure decision testable with an arbitrary filesystem state. Reads a
    /// prefix and a suffix only (`AttachmentIntegrity.verdict(ofFileAt:named:)`), never
    /// the whole file (ADR-0040 §D8, R-07, R-09).
    private func state(_ url: URL) -> AttachmentChipModel.FileState {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return .missing }
        return AttachmentIntegrity.verdict(ofFileAt: url, named: name) == .usable ? .usable : .unusable
    }

    /// Quick Look's target (R-27): `nil` for a store reference and for a file whose copy
    /// is not on disk - both are chips with nothing to preview.
    private var previewURL: URL? { AttachmentChipModel.previewURL(for: content, state: state) }

    /// The default-app / double-click target (R-27): the local copy, or a store
    /// reference's own store path when it is still there.
    private var openURL: URL? { AttachmentChipModel.openURL(for: content, state: state) }

    /// The "Mostra nel Finder" target (R-27): the same rule as `openURL`.
    private var revealURL: URL? { AttachmentChipModel.revealURL(for: content, state: state) }

    /// The chip's visible text (R-08): `.pending` shows «In attesa», not the file name -
    /// the name is still reachable through `helpText`.
    private var label: String {
        switch content {
        case .pending: "In attesa"
        default: name
        }
    }

    /// A file whose copy is not on disk: the difference between it and a store reference
    /// is the message the tooltip carries, not this flag, which only ever asks "is this a
    /// file reference with nothing to preview".
    private var isMissing: Bool {
        guard case .file = content else { return true }
        return previewURL == nil
    }

    private var symbol: String { AttachmentChipModel.symbol(for: content, state: state) }

    private var helpText: String {
        switch content {
        case .file:
            if previewURL == nil {
                "\(name) — il file non è in allegati/"
            } else if openURL == nil {
                "\(name) — file eseguibile: si apre solo dal Finder"
            } else {
                name
            }
        case .storeReference(let reference):
            "\(name) — \(Self.megabytes(reference.size)) MB, resta nell'archivio di Mail: \(reference.storePath)"
        case .pending:
            "\(name) — non ancora disponibile in Mail"
        }
    }

    private var accessibilityText: String {
        switch content {
        case .file: "Allegato \(name)"
        case .storeReference: "Allegato \(name), non copiato"
        case .pending: "Allegato \(name), in attesa"
        }
    }

    /// Whole megabytes: the number is there to explain why a 400 MB file was not
    /// copied, and a decimal place adds nothing to that sentence.
    static func megabytes(_ bytes: Int) -> Int {
        max(1, bytes / (1024 * 1024))
    }

    // MARK: Actions

    /// A click: previews a usable file, or - for `.pending` - opens the popover
    /// explaining why (ADR-0040 §D8, R-08). Neither `onQuickLook` nor `NSWorkspace` is
    /// ever called for a pending chip.
    private func preview() {
        if case .pending = content {
            isShowingPendingExplanation = true
            return
        }
        guard let previewURL else { return }
        onQuickLook(previewURL)
    }

    /// «Apri» and double-click. A usable file `AttachmentChipModel.refusesToOpen`
    /// rejects (PG-123: executable, bundle, disk image, script) has no `openURL` and is
    /// revealed in the Finder instead, where Gatekeeper's own prompt applies.
    private func openWithDefaultApp() {
        if let openURL {
            NSWorkspace.shared.open(openURL)
        } else if revealURL != nil {
            showInFinder()
        }
    }

    /// R-27's «Copia»: the file itself when a copy is on disk (or the store path still
    /// resolves), so a paste into Finder or Mail carries the attachment; the bare name
    /// otherwise, which is the only thing a missing file still has.
    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = AttachmentChipModel.copyItems(for: content, state: state)
        if items.isEmpty {
            pasteboard.setString(name, forType: .string)
        } else {
            pasteboard.writeObjects(items as [NSURL])
        }
    }

    private func showInFinder() {
        guard let revealURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([revealURL])
    }
}
