import SwiftUI

// PG-387 (N4), ADR-0085 §D8/§D9, plan docs/plans/pg-387-n4-birth-of-note.md,
// Tasks 6 and 7 - R-13, R-14, R-16. What the note's birth draws over the Note pane's editor.

/// The creation toast at the foot of the editor and the «Estrai in una nota» sheet, applied to
/// `VaultBrowser.editor` in one modifier so the browser gains one line, not two presentations.
struct NoteBirthPresentation: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    /// Why the last «Annulla» refused, shown in the strip's own height until the offer ends.
    @State private var refusal: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let offer = vault.creationUndo {
                    CreationUndoStrip(refusal: refusal) { undo() }
                        .padding(.bottom, theme.spacing(.m))
                        // Ends the offer at its expiry; a new creation restarts it.
                        .task(id: offer) { await expire(offer) }
                }
            }
            .sheet(item: Binding(get: { vault.extraction }, set: { vault.extraction = $0 })) { draft in
                ExtractNoteSheet(draft: draft)
            }
    }

    private func expire(_ offer: CreationUndo.Offer) async {
        refusal = nil
        let delay = offer.expiresAt.timeIntervalSinceNow
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        guard !Task.isCancelled, vault.creationUndo == offer else { return }
        vault.creationUndo = nil
    }

    private func undo() {
        Task { @MainActor in
            refusal = await vault.undoCreation(now: Date()).sentence
        }
    }
}

/// «Estrai in una nota»: the composer in its extract host, and the half-done state when the new
/// note landed but the source refused its replacement (ADR-0085 §D8). No toast: the note is not
/// opened, the source stays in front.
struct ExtractNoteSheet: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    let draft: VaultController.ExtractionDraft

    /// The new note's path and why the source was not updated, once that happened.
    @State private var halfDone: (created: String, refusal: String)?

    var body: some View {
        if let halfDone {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                Text("Estrai in una nota").themedText(.heading)
                Text("Creata «\(halfDone.created)».").themedText(.body)
                Text(halfDone.refusal).themedText(.caption, color: .taskOverdue)
                HStack {
                    Spacer()
                    Button("Chiudi") { vault.extraction = nil }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(theme.spacing(.l))
            .frame(width: NewNoteComposer.sheetWidth, alignment: .leading)
        } else {
            NewNoteComposer(
                draft: VaultController.NoteDraft(),
                host: .extract(draft),
                perform: { composition in
                    let outcome = try await vault.extract(draft, as: composition, savingFirst: draft.sourceIsDirty)
                    if case .refused(let sentence) = outcome.source {
                        halfDone = (outcome.created.path, sentence)
                    }
                    return outcome.created.path
                },
                onCreated: { _ in if halfDone == nil { vault.extraction = nil } },
                onCancel: { vault.extraction = nil }
            )
        }
    }
}
