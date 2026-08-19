import SwiftUI

/// The note's index, under the note list in the sidebar (M8).
///
/// In the sidebar rather than in the inspector, chosen from the mockup: the inspector
/// holds things *about* the note - conformance, backlinks, tasks that point here - and
/// the sidebar holds things you navigate to. An index is the second kind.
///
/// It reads `NoteOutline`, which both this and the reading view use, so a click here and
/// what appears there cannot disagree about what the sections are.
struct OutlinePane: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let entries: [NoteOutline.Entry]
    /// Called with the entry's line and its position in the index. Two numbers because
    /// the editor scrolls by character and the reading view by block.
    let onSelect: (NSRange, Int) -> Void
    /// The whole note, needed only to turn a `String.Index` range into the `NSRange` the
    /// text view speaks. Converted here, once per click, rather than kept as two ranges.
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("INDICE").themedText(.caption, color: .textTertiary)
            if entries.isEmpty {
                // Says what is missing rather than showing an empty box, the same refusal
                // the slash menu makes when nothing matches its query.
                Text("nessun titolo in questa nota")
                    .themedText(.caption, color: .textTertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            row(entry, at: index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("outlinePane")
    }

    private func row(_ entry: NoteOutline.Entry, at index: Int) -> some View {
        let isCurrent = vault.currentOutlineEntry == index
        return HStack(spacing: 0) {
            chevron(for: entry, at: index)
            button(entry, at: index, isCurrent: isCurrent)
        }
        .padding(.leading, CGFloat(entry.level - 1) * theme.spacing(.m))
    }

    /// The fold control, and only where there is something to fold: an embed has no
    /// section, and a heading with nothing under it would fold to nothing.
    @ViewBuilder
    private func chevron(for entry: NoteOutline.Entry, at index: Int) -> some View {
        if case .heading = entry.kind, foldable.contains(index) {
            Button {
                vault.toggleFold(index)
            } label: {
                Image(systemName: vault.foldedEntries.contains(index) ? "chevron.right" : "chevron.down")
                    .themedText(.caption, color: .textTertiary)
                    .frame(width: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(vault.foldedEntries.contains(index) ? "Espandi la sezione" : "Ripiega la sezione")
        } else {
            Color.clear.frame(width: 12)
        }
    }

    /// The entries that have at least one line under them. Computed once per rebuild rather
    /// than per row, because each answer costs a pass over the note.
    private var foldable: Set<Int> {
        Set(entries.indices.filter { index in
            !NoteFolding.hiddenParagraphs(in: text, foldedEntries: [index]).isEmpty
        })
    }

    private func button(_ entry: NoteOutline.Entry, at index: Int, isCurrent: Bool) -> some View {
        Button {
            onSelect(NSRange(entry.range, in: text), index)
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                // Only the embeds carry a symbol. A bullet on every row would be a column
                // of noise; a symbol where the kind changes is information.
                if entry.kind == .embed {
                    Image(systemName: "doc.richtext")
                        .themedText(.caption, color: .textTertiary)
                }
                Text(entry.title)
                    .themedText(.body, color: isCurrent ? .textPrimary : .textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing(.xs))
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .fill(isCurrent ? theme.color(.accentMuted) : .clear)
            )
        }
        .buttonStyle(.plain)
        .help(entry.title)
    }
}
