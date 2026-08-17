import SwiftUI

// MARK: - Ripiegare le sezioni (M8)

/// Folding, and the one thing about it that is a design decision rather than a mechanism.
///
/// Hiding the lines works - measured before this was drawn, and confirmed on screen in a
/// real editor. But a folded section becomes indistinguishable from a section with nothing
/// in it, and that is the failure worth designing against: it reads as lost text.
///
/// Two ways to say it, and they cost very differently. The cheap one uses attributes that
/// already reach the drawing. The expensive one needs a custom `NSTextLayoutFragment`,
/// because a badge is visible characters and the note's text may not gain any.
struct FoldingMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.l)) {
                scene("Aperta, come adesso", EditorMock(style: .open))
                scene("Piegata, marcatore economico: sfondo sul titolo", EditorMock(style: .tinted))
                scene("Piegata, marcatore caro: badge con il conteggio", EditorMock(style: .badge))
                outlineControl
                edgeCase
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.color(.backgroundPrimary))
    }

    private func scene(_ caption: String, _ content: some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(caption).themedText(.caption, color: .textTertiary)
            content
        }
    }

    /// The control itself, in the index that already exists.
    private var outlineControl: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Il comando sta nell'indice, che c'è già")
                .themedText(.caption, color: .textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                outlineRow("Curva di trasmissibilità", level: 1, chevron: .down)
                outlineRow("Prove in laboratorio", level: 2, chevron: .right)
                outlineRow("Comandi usati", level: 2, chevron: .down)
                outlineRow("Blocchi di codice", level: 3, chevron: .none, isEmbed: true)
            }
            .padding(theme.spacing(.s))
            .frame(width: 280, alignment: .leading)
            .background(theme.color(.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        }
    }

    private enum Chevron { case down, right, none }

    private func outlineRow(_ title: String, level: Int, chevron: Chevron, isEmbed: Bool = false) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            // The chevron appears only where there is something to fold: an embed has no
            // section, and a heading with no body under it would fold to nothing.
            Group {
                switch chevron {
                case .down: Image(systemName: "chevron.down")
                case .right: Image(systemName: "chevron.right")
                case .none: Color.clear
                }
            }
            .frame(width: 10)
            .themedText(.caption, color: .textTertiary)
            if isEmbed {
                Image(systemName: "doc.richtext").themedText(.caption, color: .textTertiary)
            }
            Text(title)
                .themedText(.body, color: chevron == .right ? .textTertiary : .textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(level - 1) * theme.spacing(.m))
        .padding(.vertical, 3)
    }

    /// The case that decides whether a marker is needed at all: a folded section beside a
    /// heading that genuinely has nothing under it. Without a marker the two are the same
    /// picture.
    private var edgeCase: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Il caso che decide: sezione piegata contro sezione davvero vuota")
                .themedText(.caption, color: .textTertiary)
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                EditorMock(style: .ambiguousPlain).frame(width: 330)
                EditorMock(style: .ambiguousMarked).frame(width: 330)
            }
        }
    }
}

// MARK: - The editor

private struct EditorMock: View {
    @Environment(\.theme) private var theme

    enum Style { case open, tinted, badge, ambiguousPlain, ambiguousMarked }

    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                self.line(line)
            }
        }
        .padding(theme.spacing(.m))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundPrimary))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }

    @ViewBuilder
    private func line(_ line: Line) -> some View {
        switch line.kind {
        case .heading(let folded, let count):
            HStack(spacing: theme.spacing(.xs)) {
                Text(line.text)
                    .font(theme.font(.mono))
                    .foregroundStyle(theme.color(.textPrimary))
                    .fontWeight(.semibold)
                if let count {
                    // The expensive half: this badge is not text in the note, so it can
                    // only exist as something drawn over the line by a custom layout
                    // fragment.
                    Text("⌄ \(count) righe")
                        .themedText(.caption, color: .textTertiary)
                        .padding(.horizontal, theme.spacing(.xs))
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(theme.color(.backgroundTertiary))
                        )
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing(.xs))
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .fill(folded ? theme.color(.backgroundTertiary) : .clear)
            )
        case .body:
            Text(line.text)
                .font(theme.font(.mono))
                .foregroundStyle(theme.color(.textSecondary))
                .padding(.horizontal, theme.spacing(.xs))
        }
    }

    private struct Line {
        enum Kind {
            case heading(folded: Bool, count: Int?)
            case body
        }

        let text: String
        let kind: Kind
    }

    private var lines: [Line] {
        switch style {
        case .open:
            [
                Line(text: "# Curva di trasmissibilità", kind: .heading(folded: false, count: nil)),
                Line(text: "Il fornitore ha confermato la curva.", kind: .body),
                Line(text: "", kind: .body),
                Line(text: "## Prove in laboratorio", kind: .heading(folded: false, count: nil)),
                Line(text: "Tre campioni, 60, 70 e 80 shore.", kind: .body),
                Line(text: "Misure ripetute a freddo e a caldo.", kind: .body),
                Line(text: "", kind: .body),
                Line(text: "## Comandi usati", kind: .heading(folded: false, count: nil)),
            ]
        case .tinted:
            [
                Line(text: "# Curva di trasmissibilità", kind: .heading(folded: false, count: nil)),
                Line(text: "Il fornitore ha confermato la curva.", kind: .body),
                Line(text: "", kind: .body),
                Line(text: "## Prove in laboratorio", kind: .heading(folded: true, count: nil)),
                Line(text: "## Comandi usati", kind: .heading(folded: false, count: nil)),
            ]
        case .badge:
            [
                Line(text: "# Curva di trasmissibilità", kind: .heading(folded: false, count: nil)),
                Line(text: "Il fornitore ha confermato la curva.", kind: .body),
                Line(text: "", kind: .body),
                Line(text: "## Prove in laboratorio", kind: .heading(folded: true, count: 3)),
                Line(text: "## Comandi usati", kind: .heading(folded: false, count: nil)),
            ]
        case .ambiguousPlain:
            [
                Line(text: "## Piegata", kind: .heading(folded: false, count: nil)),
                Line(text: "## Vuota davvero", kind: .heading(folded: false, count: nil)),
                Line(text: "## Terza", kind: .heading(folded: false, count: nil)),
            ]
        case .ambiguousMarked:
            [
                Line(text: "## Piegata", kind: .heading(folded: true, count: 4)),
                Line(text: "## Vuota davvero", kind: .heading(folded: false, count: nil)),
                Line(text: "## Terza", kind: .heading(folded: false, count: nil)),
            ]
        }
    }
}
