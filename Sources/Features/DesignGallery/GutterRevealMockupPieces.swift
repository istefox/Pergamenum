import SwiftUI

// The rows and the sheet the gutter mockup is drawn out of, apart for the reason
// `TagBrowserMockupPieces` gives: the scenes say what is being asked, the pieces say what it
// looks like. `GutterRevealMockup` alone uses them.

/// The dash of a ghost guide, on and off in points. No spacing token is this fine (the
/// smallest, `spacing.xs`, is 4), and a dash is a stroke style rather than a space between
/// elements; so it is named once here instead of borrowed from a token it does not mean.
private let ghostGuideDash: [CGFloat] = [3, 3]

/// A page of text with its column guides: solid at each content column, dashed where something
/// used to be (today's text start, or the text container's edge).
struct GutterMockupSheet<Content: View>: View {
    @Environment(\.theme) private var theme
    private let width: CGFloat
    private let guides: [CGFloat]
    private let ghosts: [CGFloat]
    private let trailing: CGFloat
    private let bleed: CGFloat
    private let content: Content

    init(
        width: CGFloat, guides: [CGFloat], ghosts: [CGFloat] = [], trailing: CGFloat = 0,
        bleed: CGFloat = 0, @ViewBuilder content: () -> Content
    ) {
        self.width = width
        self.guides = guides
        self.ghosts = ghosts
        self.trailing = trailing
        self.bleed = bleed
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            content
        }
        .padding(.trailing, trailing)
        .padding(.vertical, theme.spacing(.m))
        .frame(width: width, alignment: .leading)
        .background { lines }
        .padding(.leading, bleed)
        .background(theme.color(.backgroundPrimary))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
    }

    private var lines: some View {
        GeometryReader { geo in
            ZStack {
                Self.verticals(at: guides, height: geo.size.height)
                    .stroke(theme.color(.borderSubtle), lineWidth: 1)
                Self.verticals(at: ghosts, height: geo.size.height)
                    .stroke(theme.color(.borderStrong), style: StrokeStyle(lineWidth: 1, dash: ghostGuideDash))
            }
        }
    }

    private static func verticals(at xs: [CGFloat], height: CGFloat) -> Path {
        Path { path in
            for x in xs {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
            }
        }
    }
}

/// The item concealed, then revealed, directly under each other.
struct GutterMockupPair: View {
    @Environment(\.theme) private var theme
    private let column: CGFloat
    private let concealed: Text?
    private let revealed: Text?
    private let text: Text
    private let labelled: Bool
    private let badgeGap: CGFloat

    init(
        _ column: CGFloat, _ concealed: Text?, _ revealed: Text?, _ text: Text,
        labelled: Bool = true, badgeGap: CGFloat = 0
    ) {
        self.column = column
        self.concealed = concealed
        self.revealed = revealed
        self.text = text
        self.labelled = labelled
        self.badgeGap = badgeGap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            GutterMockupRow(
                column: column, marker: concealed, text: text,
                state: labelled ? "nascosto" : nil, markerGap: badgeGap
            )
            GutterMockupRow(column: column, marker: revealed, text: text, state: labelled ? "rivelato" : nil)
        }
    }
}

/// One line: the marker right-aligned in a frame that ends at the column, so the text starts on
/// the column whatever the marker's width; a marker wider than the frame spills left.
struct GutterMockupRow: View {
    let column: CGFloat
    let marker: Text?
    let text: Text
    var state: String?
    var markerGap: CGFloat = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Group {
                if let marker {
                    marker.fixedSize().padding(.trailing, markerGap)
                } else {
                    // A concealed heading's `#` run is 0.01 pt wide: nothing to draw.
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            .frame(width: column, alignment: .trailing)
            text
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let state {
                GutterMockupStateLabel(state)
            }
        }
    }
}

/// A task line, both states: the checkbox is never revealed (ADR-0028 §D2), so the two rows are
/// one picture twice, at the file's own indentation rather than on the list column.
struct GutterMockupTaskPair: View {
    @Environment(\.theme) private var theme
    let start: CGFloat
    let checkbox: Text
    let text: Text

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            row("nascosto")
            row("rivelato")
        }
    }

    private func row(_ state: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
            checkbox
            text.fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            GutterMockupStateLabel(state)
        }
        .padding(.leading, start)
    }
}

/// Which of the pair a row is, in the right margin of the wide scenes.
struct GutterMockupStateLabel: View {
    @Environment(\.theme) private var theme
    private let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        // 64, `spacing.xl + spacing.l`: room for «nascosto» and «rivelato» in `font.caption`.
        Text(text)
            .themedText(.caption, color: .textTertiary)
            .frame(width: theme.spacing(.xl) + theme.spacing(.l), alignment: .trailing)
    }
}
