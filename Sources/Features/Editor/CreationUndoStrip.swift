import SwiftUI

// PG-387 (N4), ADR-0085 §D9, plan docs/plans/pg-387-n4-birth-of-note.md, Task 6 -
// R-16.

/// «Nota creata · Annulla» at the foot of the Note pane's editor, after a pane-host creation.
///
/// One height whatever it says: a refusal replaces the line rather than adding one, so the strip
/// never pushes anything (ADR-0075's rule against a layout row above the split view). Drawn as
/// an overlay by `NoteBirthPresentation`.
struct CreationUndoStrip: View {
    @Environment(\.theme) private var theme
    /// The strip's one height, with or without a refusal sentence.
    static let height: CGFloat = 32

    /// Why «Annulla» refused, nil while the offer stands.
    let refusal: String?
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text(refusal ?? "Nota creata")
                .themedText(.caption, color: refusal == nil ? .textPrimary : .taskOverdue)
                .lineLimit(1)
                .truncationMode(.tail)
            if refusal == nil {
                Button("Annulla", action: onUndo)
                    .buttonStyle(.link)
                    .accessibilityIdentifier("creation-undo")
            }
        }
        .padding(.horizontal, theme.spacing(.m))
        .frame(height: Self.height)
        .background(theme.color(.surfaceCard), in: Capsule())
        .overlay(Capsule().strokeBorder(theme.color(.borderSubtle), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("creation-undo-strip")
    }
}
