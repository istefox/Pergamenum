import SwiftUI

// ADR-0083 §D7 (PG-386, N3 session B). Drawn as the approved N3 page draws it
// (`LinkPreviewMockup`, «N3, approvato»): every case is a sentence, never an empty card.

/// What the Cmd+hover popover draws for a `LinkPreviewContent`.
///
/// Nothing in it takes focus: the popover is a card to read while Command is held, and the keyboard
/// stays with the editor (§D7). The theme is handed in rather than read from the environment,
/// because an `NSHostingController` inside an `NSPopover` is outside the SwiftUI tree the app's
/// theme is injected into.
struct LinkPreviewView: View {
    let content: LinkPreviewContent
    var theme: Theme = .emergency

    /// The card's width, the mockup's.
    static let width: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            kind
        }
        .padding(theme.spacing(.s))
        .frame(width: Self.width, alignment: .leading)
        .environment(\.theme, theme)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("link-preview")
    }

    @ViewBuilder
    private var kind: some View {
        switch content.kind {
        case let .note(title, lines, missingSection):
            heading(title)
            if let missingSection {
                Text("Nessuna sezione «\(missingSection)»").themedText(.caption, color: .textTertiary)
            } else {
                excerpt(lines)
            }
        case .board(let name):
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "square.grid.2x2").themedText(.body, color: .textSecondary)
                heading(name)
            }
        case let .ambiguous(title, folders):
            Text("\(folders.count) note si chiamano «\(title)»").themedText(.body, color: .textPrimary)
            ForEach(Array(folders.enumerated()), id: \.offset) { _, folder in
                HStack(spacing: theme.spacing(.xs)) {
                    Image(systemName: "folder").themedText(.caption, color: .textTertiary)
                    Text(folder).themedText(.body, color: .textSecondary).lineLimit(1)
                }
            }
        case let .missing(title, creatable):
            Text("Nessuna nota si chiama «\(title)»").themedText(.body, color: .textPrimary)
            if creatable {
                Text("Cmd+clic per crearla").themedText(.caption, color: .textTertiary)
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).themedText(.body, color: .textPrimary).fontWeight(.semibold).lineLimit(1)
    }

    /// The opening lines, a heading line in the primary colour. When the cap was reached the last
    /// line fades out, the way `TranscludedNoteView` masks a capped transclusion: the cut the
    /// mockup's main scene draws.
    private func excerpt(_ lines: [String]) -> some View {
        let isCapped = lines.count >= LinkPreviewContent.lineLimit
        return ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            let text = Text(line)
                .themedText(.caption, color: Self.isHeading(line) ? .textPrimary : .textSecondary)
                .lineLimit(1)
            if isCapped && index == lines.count - 1 {
                text.mask(Self.fadeOut)
            } else {
                text
            }
        }
    }

    private static let fadeOut = LinearGradient(
        colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom
    )

    /// `## Decisioni`, not `#tag`: hashes, then a space.
    private static func isHeading(_ line: String) -> Bool {
        let rest = line.drop(while: { $0 == "#" })
        return rest.count < line.count && rest.hasPrefix(" ")
    }
}
