import SwiftUI

/// The bar that appears over a selection, as the approved mockup drew it (SPEC §10, M8).
///
/// `FormatBarMockup` in the design gallery is the reference and stays there: this draws the
/// same six buttons from the same tokens.
///
/// **No headings and no lists**, which are the obvious things to want. Those are line
/// operations, and a bar that appears over a selection and then acts on the whole line would
/// be doing something other than what is selected. They stay on `/`, which writes at the caret
/// and is honest about it. The line this bar draws is «it wraps the selection, nothing else».
struct FormatBar: View {
    @Environment(\.theme) private var theme

    /// What a button press means. Two kinds, because the two are genuinely different: a format
    /// toggles and can be already-on, a link always writes something new.
    enum Action: Equatable, Sendable {
        case format(InlineFormat)
        /// `[[selezione]]`, which stays in the vault.
        case wikilink
        /// `[selezione]()`, which leads out of it, with the caret left between the brackets.
        case link
    }

    let applied: Set<InlineFormat>
    let onChoose: (Action) -> Void

    /// One button, named rather than a three-member tuple: `button.2` says nothing about what
    /// it holds, which is the objection `TasksMockup.MockTask` already carries.
    private struct Entry: Identifiable {
        var id: String
        var symbol: String
        var help: String
        var action: Action
    }

    private static let formats: [Entry] = [
        Entry(id: "bold", symbol: "bold", help: "Grassetto", action: .format(.bold)),
        Entry(id: "italic", symbol: "italic", help: "Corsivo", action: .format(.italic)),
        Entry(
            id: "strikethrough", symbol: "strikethrough", help: "Barrato",
            action: .format(.strikethrough)
        ),
        Entry(
            id: "code", symbol: "chevron.left.forwardslash.chevron.right", help: "Codice",
            action: .format(.code)
        ),
    ]

    private static let links: [Entry] = [
        Entry(id: "wikilink", symbol: "doc.text", help: "Collega a una nota del vault", action: .wikilink),
        Entry(id: "link", symbol: "link", help: "Collega a un indirizzo", action: .link),
    ]

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            ForEach(Self.formats) { entry in
                button(entry, isOn: isOn(entry.action))
            }
            Divider().frame(height: 16).padding(.horizontal, 2)
            ForEach(Self.links) { entry in
                button(entry, isOn: false)
            }
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 4)
        .background(theme.color(.surfaceRaised))
        .clipShape(Capsule())
        // No stroke. SPEC §11.2 asks for hierarchy from weight and space «più che da linee e
        // riquadri», and a bordered capsule floating over a note is exactly a box - it read as
        // a frame drawn on the text rather than as something resting above it. The raised
        // shadow is what separates it, which is the same tool every other floating surface in
        // this app uses.
        .themedShadow(.raised)
        .accessibilityIdentifier("format-bar")
    }

    private func isOn(_ action: Action) -> Bool {
        guard case let .format(format) = action else { return false }
        return applied.contains(format)
    }

    private func button(_ entry: Entry, isOn: Bool) -> some View {
        Button { onChoose(entry.action) } label: {
            Image(systemName: entry.symbol)
                .frame(width: 26, height: 22)
                .foregroundStyle(theme.color(isOn ? .onAccent : .textSecondary))
                .background(isOn ? theme.color(.accentPrimary) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                // A button whose background is `.clear` - every one of these, unless the
                // format is already on - hit-tests only the glyph's own opaque pixels
                // without this: Stefano found it by having to aim at the letter itself.
                // The shape names the whole 26×22 frame as the target instead of leaving
                // it to what happens to be drawn there.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.help)
        .accessibilityLabel(entry.help)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("format-\(entry.id)")
    }
}
