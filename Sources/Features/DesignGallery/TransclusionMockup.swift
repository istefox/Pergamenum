import SwiftUI

// MARK: - Transclusione (M8, ADR-0010)

/// `![[nota]]` che mostra la nota invece di dire che manca un file.
///
/// Five scenes, because the appearance decisions here are five and not one. The third is
/// the one that matters: without a cap, the length of a note on screen depends on how long
/// somebody else's note is, and that is not a property a page should have.
///
/// What is *not* a decision, and is drawn the same way in every scene: the transcluded
/// content is set apart by a rule and a header naming its source. Text that reads like the
/// host note's own but is not is the one failure that makes a person edit the wrong file.
struct TransclusionMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        MockupPage {
            scene("Nota intera", NoteMock(scene: .whole))
            scene("Una sezione sola: ![[Prove in laboratorio#Campioni]]", NoteMock(scene: .section))
            scene("Oltre il tetto: si taglia e si offre la nota", NoteMock(scene: .capped))
            scene("Bersaglio che non esiste (chiude PG-020)", NoteMock(scene: .missing))
            scene("Profondità uno: dentro una resa, un ![[…]] è un link", NoteMock(scene: .nested))
            scene("Nell'editor: la riga sorgente resta, la nota sta sotto", EditorMock())
        }
    }

    private func scene(_ caption: String, _ content: some View) -> some View {
        MockupScene(caption) {
            content.frame(maxWidth: 620, alignment: .leading)
        }
    }
}

// MARK: - The editor half

/// The same transclusion in Modifica, where the rules are different.
///
/// Two things this scene decides. The source line **stays**: it is what the file says, it is
/// selectable and editable, and keeping it is what leaves the door open for the display
/// transform of PG-018 instead of closing it. And what is drawn under it is the target's
/// *styled source*, not the typeset rendering of Lettura - the editor shows source with
/// style applied everywhere, so a note that arrived typeset would be the one thing on the
/// page that is not text.
private struct EditorMock: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            source("# Progetto forno", .textPrimary, weight: .semibold)
            source("", .textSecondary)
            source("Il fornitore ha confermato la curva.", .textSecondary)
            source("", .textSecondary)
            source("![[Prove in laboratorio]]", .accentPrimary)
            card
            source("", .textSecondary)
            source("Resta da decidere la durezza dei tamponi.", .textSecondary)
        }
        .padding(theme.spacing(.l))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundPrimary))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }

    /// The space this occupies is bought with `paragraphSpacing` on the line above, measured
    /// before it was designed: the reserved height lands inside that line's own layout
    /// fragment, so the drawing has somewhere to go and the note gains no character.
    private var card: some View {
        HStack(alignment: .top, spacing: theme.spacing(.m)) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(theme.color(.accentPrimary).opacity(0.35))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("Prove in laboratorio")
                    .themedText(.caption, color: .textTertiary)
                source("# Prove in laboratorio", .textPrimary, weight: .semibold)
                source("Tre serie di misure.", .textSecondary)
                source("## Campioni", .textPrimary, weight: .semibold)
                source("Tre campioni, 60, 70 e 80 shore.", .textSecondary)
            }
        }
        .padding(.leading, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
    }

    private func source(
        _ text: String,
        _ color: ColorToken,
        weight: Font.Weight = .regular
    ) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(theme.font(.mono).weight(weight))
            .foregroundStyle(theme.color(color))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The host note, with the transclusion inside it

private struct NoteMock: View {
    @Environment(\.theme) private var theme

    enum Scene { case whole, section, capped, missing, nested }

    let scene: Scene

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Progetto forno")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.color(.textPrimary))
            Text("Il fornitore ha confermato la curva. Il dettaglio delle prove sta nella nota "
                + "dedicata, e da qui si legge senza aprirla.")
                .themedText(.body)
            transclusion
            Text("Resta da decidere la durezza dei tamponi.")
                .themedText(.body)
        }
        .padding(theme.spacing(.l))
        .background(theme.color(.backgroundPrimary))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }

    // MARK: The rendition

    @ViewBuilder
    private var transclusion: some View {
        if scene == .missing {
            missing
        } else {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                // The rule, not a box: a framed card would read as a different kind of
                // object, and this is the same note seen from here.
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(theme.color(.accentPrimary).opacity(0.35))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                    header
                    body(of: scene)
                    if scene == .capped { openTheNote }
                }
            }
        }
    }

    /// Where this text comes from, and the only way back to it.
    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "text.append")
                .themedText(.caption, color: .textTertiary)
            Text(scene == .section ? "Prove in laboratorio › Campioni" : "Prove in laboratorio")
                .themedText(.caption, color: .accentPrimary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func body(of scene: Scene) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            switch scene {
            case .section:
                heading("Campioni", size: 15)
                Text("Tre campioni, 60, 70 e 80 shore, misurati a freddo e a caldo.")
                    .themedText(.body, color: .textSecondary)
            case .nested:
                Text("Tre campioni, misurati secondo il protocollo interno.")
                    .themedText(.body, color: .textSecondary)
                nestedLink
            default:
                heading("Prove in laboratorio", size: 17)
                Text("Tre campioni, 60, 70 e 80 shore, misurati a freddo e a caldo.")
                    .themedText(.body, color: .textSecondary)
                Text("La curva si appiattisce sopra i 45 Hz su tutti e tre.")
                    .themedText(.body, color: .textSecondary)
                if scene == .capped {
                    Text("Il campione a 80 shore ha mostrato una deriva di 1,2 dB fra la "
                        + "prima e la terza ripetizione, che il fornitore attribuisce…")
                        .themedText(.body, color: .textSecondary)
                        .frame(height: 22, alignment: .top)
                        .clipped()
                        .mask(LinearGradient(
                            colors: [.black, .black.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                }
            }
        }
    }

    private func heading(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(theme.color(.textPrimary))
    }

    /// Depth one, drawn: the second level is a link, so a note transcluding itself is one
    /// row rather than a loop.
    private var nestedLink: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "text.append").themedText(.caption, color: .textTertiary)
            Text("Contatti fornitore").themedText(.body, color: .accentPrimary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, theme.spacing(.xs))
        .padding(.horizontal, theme.spacing(.s))
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }

    private var openTheNote: some View {
        Text("apri la nota")
            .themedText(.caption, color: .accentPrimary)
    }

    /// The line that closes PG-020. It says a *note* is missing, because that is what was
    /// asked for; today the same case claims a file is not in the vault.
    private var missing: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(theme.color(.textTertiary))
            Text("nota non trovata: Prove in laboratorio")
                .themedText(.caption, color: .textTertiary)
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.s))
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}
