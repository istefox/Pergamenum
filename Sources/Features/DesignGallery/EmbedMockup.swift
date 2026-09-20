import SwiftUI

// MARK: - Embed incorporato (M8, ADR-0018 slice 3, realizzato)

/// An image or a PDF's first page, drawn where `![[foto.jpg]]` or `![alt](capitolato.pdf)`
/// sits today - the third and last construct of ADR-0018, and the one that reopened it: a
/// picture that is only ever thirteen or more characters of text has no gesture for removing
/// it, and twenty-seven presses of Backspace is not one.
///
/// What decides every scene here is D3's own answer: the attachment is rebuilt on every
/// layout pass from the text and never written back, so the drawing changes nothing about
/// what undo, an external reload, or the conflict banner see. Six scenes, in the order D5 and
/// D6 raise the questions, not the order they were written.
struct EmbedMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        MockupPage {
            scene("Immagine al posto di ![[foto-1-chi-siamo.jpg]]", EditorMock(style: .image))
            scene("PDF, prima pagina di ![alt](capitolato.pdf)", EditorMock(style: .pdf))
            scene("Un click seleziona tutto il blocco, non un carattere", EditorMock(style: .selected))
            scene("Il cursore rivela l'enfasi, non l'immagine", EditorMock(style: .caretContrast))
            scene("Riferimento non trovato nel vault", EditorMock(style: .missing))
            deleteInOneStep
        }
    }

    private func scene(_ caption: String, _ content: some View) -> some View {
        MockupScene(caption) {
            content.frame(maxWidth: 620, alignment: .leading)
        }
    }

    /// D5's whole point, drawn rather than described: one Backspace at the block's right edge
    /// removes it entirely, through one `shouldChangeText` call, so one Cmd+Z brings it back -
    /// not forty.
    private var deleteInOneStep: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Backspace sul bordo rimuove tutto il blocco, un solo Cmd+Z lo riporta")
                .themedText(.caption, color: .textTertiary)
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                labelled("Prima", EditorMock(style: .beforeDelete))
                labelled("Dopo un Backspace", EditorMock(style: .afterDelete))
            }
        }
    }

    private func labelled(_ caption: String, _ content: some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(caption).themedText(.caption, color: .textTertiary)
            content.frame(width: 300, alignment: .leading)
        }
    }
}

// MARK: - The editor

private struct EditorMock: View {
    @Environment(\.theme) private var theme

    enum Style { case image, pdf, selected, caretContrast, missing, beforeDelete, afterDelete }

    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        case .text(let emphasised):
            Text(line.text)
                .font(theme.font(.mono))
                .foregroundStyle(theme.color(emphasised ? .textPrimary : .textSecondary))
                .padding(.horizontal, theme.spacing(.xs))
        case .embed(let kind, let selected, let caption):
            embedBlock(kind: kind, caption: caption, selected: selected)
        case .missing(let filename):
            missingBlock(filename: filename)
        }
    }

    /// The picture or the PDF's first page, standing for the file the way a Workspace card
    /// already stands for it (SPEC §6.5) - the same rule applied to a second surface, and the
    /// reason there is no third look invented for the editor.
    private func embedBlock(kind: EmbedKind, caption: String, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: theme.spacing(.s)) {
            ZStack {
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .fill(theme.color(.surfaceSunken))
                Image(systemName: kind == .image ? "photo" : "doc.richtext")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.color(.textTertiary))
            }
            .frame(width: 96, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .themedText(.caption, color: .textTertiary)
                if kind == .pdf {
                    Text("prima pagina").themedText(.caption, color: .textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.xs))
        .background(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(selected ? theme.color(.canvasSelection) : .clear)
        )
    }

    /// The transclusion mockup's own missing row, reused rather than redrawn: both say a file
    /// named in the text is not there, and a reader should not have to learn two icons for it.
    private func missingBlock(filename: String) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(theme.color(.textTertiary))
            Text("file non trovato: \(filename)")
                .themedText(.caption, color: .textTertiary)
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.s))
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }

    private enum EmbedKind { case image, pdf }

    private struct Line {
        enum Kind {
            case text(emphasised: Bool)
            case embed(kind: EmbedKind, selected: Bool, caption: String)
            case missing(filename: String)
        }

        let text: String
        let kind: Kind

        static func text(_ text: String, emphasised: Bool = false) -> Line {
            Line(text: text, kind: .text(emphasised: emphasised))
        }
    }

    private var lines: [Line] {
        switch style {
        case .image:
            [
                .text("Il fornitore ha confermato la curva."),
                Line(text: "", kind: .embed(kind: .image, selected: false, caption: "foto-1-chi-siamo.jpg")),
                .text("Misure ripetute a freddo e a caldo."),
            ]
        case .pdf:
            [
                .text("Il capitolato tecnico è allegato qui sotto."),
                Line(text: "", kind: .embed(kind: .pdf, selected: false, caption: "capitolato.pdf")),
                .text("Resta da confermare la revisione B."),
            ]
        case .selected:
            [
                .text("Il fornitore ha confermato la curva."),
                Line(text: "", kind: .embed(kind: .image, selected: true, caption: "foto-1-chi-siamo.jpg")),
                .text("Misure ripetute a freddo e a caldo."),
            ]
        case .caretContrast:
            [
                .text("Il fornitore ha confermato **la curva**.", emphasised: true),
                Line(text: "", kind: .embed(kind: .image, selected: false, caption: "foto-1-chi-siamo.jpg")),
                .text("Misure ripetute a freddo e a caldo."),
            ]
        case .missing:
            [
                .text("Il fornitore ha confermato la curva."),
                Line(text: "", kind: .missing(filename: "foto-2-officina.jpg")),
                .text("Misure ripetute a freddo e a caldo."),
            ]
        case .beforeDelete:
            [
                .text("Il fornitore ha confermato la curva."),
                Line(text: "", kind: .embed(kind: .image, selected: false, caption: "foto-1-chi-siamo.jpg")),
                .text("Misure ripetute a freddo e a caldo."),
            ]
        case .afterDelete:
            [
                .text("Il fornitore ha confermato la curva."),
                .text("Misure ripetute a freddo e a caldo."),
            ]
        }
    }
}
