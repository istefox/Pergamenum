import SwiftUI

// MARK: - I link (N3)

/// What a link does under the pointer and the keyboard, before it is built (ADR-0083, SPEC R-20,
/// R-22, R-23): the preview Cmd+hover opens, the choice a shared title asks for, and the offer a
/// dangling link makes.
///
/// Four things are put to the person here, and each scene is captioned with the rule it makes
/// visible so the answer is given against the decision rather than against a picture:
///
/// 1. **The preview's size and cut.** 360 points wide and the target's first twelve body lines is
///    the proposal; the cut is drawn twice, a fade and an ellipsis, and the person picks.
/// 2. **The four other things the same popover says** (a section, a missing section, a board,
///    several notes, no note), each a sentence rather than an empty box.
/// 3. **Where there is no popover:** an external link, drawn so its absence reads as a decision.
/// 4. **The choice at a click and from the keyboard**, the one-row «Crea «X»» a dangling link
///    offers on both, and the `[[` popup's one new row.
///
/// Cmd+Shift+click and Cmd+Opt+click have nothing to draw; the page's header names them with the
/// three Vista items, so the page is the whole of ADR-0083 at a glance.
///
/// Everything here is literal. No controller, no index, no vault.
struct LinkPreviewMockup: View {
    @Environment(\.theme) private var theme

    /// The proposed width of the preview popover (ADR-0083 §D7). A proposal, put to the person;
    /// the code PR takes the approved value.
    static let previewWidth: CGFloat = 360

    var body: some View {
        MockupPage {
            header
            preview
            cuts
            otherStates
            external
            choiceAtClick
            choiceFromKeyboard
            completion
        }
    }

    // MARK: Il gesto

    private var header: some View {
        MockupScene(
            "Cmd+clic segue il link; Cmd+Shift+clic lo apre in una nuova tab; Cmd+Opt+clic "
                + "nell'altra colonna (con entrambi, vince Opt). Dalla tastiera, col cursore "
                + "dentro il link, le tre voci di Vista. «Segui il link» ha Cmd+Opt+Invio come tasto "
                + "provvisorio: il PR del codice lo confronta con le scorciatoie di sistema prima di "
                + "assegnarlo. «Apri il link in una nuova tab» e «Apri il link nell'altra colonna» "
                + "nascono senza tasto e si assegnano in Impostazioni ▸ Scorciatoie (ADR-0083 §D2, §D3)."
        ) {
            LinkMockupMenu(items: [
                .header("Vista"),
                .row("Indietro", shortcut: "⌘["),
                .row("Avanti", shortcut: "⌘]"),
                .separator,
                .row("Segui il link", shortcut: "⌥⌘↩", highlighted: true),
                .row("Apri il link in una nuova tab"),
                .row("Apri il link nell'altra colonna"),
            ], width: 280)
        }
    }

    // MARK: L'anteprima

    private var preview: some View {
        MockupScene(
            "Cmd tenuto premuto e il puntatore fermo sul link da 250 ms. L'anteprima è un "
                + "NSPopover ancorato al rettangolo del link, con la freccia sul bordo sotto il link: "
                + "sta accanto al link e mai sopra, così un Cmd+clic mirato al link lo raggiunge. "
                + "Se sotto non c'è spazio, AppKit lo sposta sul bordo opposto, sopra il link. "
                + "Dentro, il titolo e le prime dodici righe, e nessun controllo: niente prende la "
                + "tastiera. Si chiude al rilascio di Cmd, uscendo dal link, con Esc, con un tasto o "
                + "uno scorrimento. Proposta: 360 pt di larghezza, dodici righe (ADR-0083 §D7)."
        ) {
            LinkMockupNote {
                Text("Prova banco 12").themedText(.heading)
                VStack(alignment: .linkAnchor, spacing: 0) {
                    LinkMockupLine(before: "Decisioni prese in ", link: "Riunione settimanale",
                                   after: ", da girare al cliente.", pointer: true)
                    LinkMockupPopover(width: Self.previewWidth) {
                        previewBody(LinkPreviewText.opening, cut: .fade)
                    }
                }
                Text("Il banco 2 resta fermo fino a giovedì.").themedText(.body, color: .textSecondary)
            }
        }
    }

    private var cuts: some View {
        MockupScene(
            "Il taglio dopo la dodicesima riga, da scegliere: a sinistra la dissolvenza, a destra "
                + "i puntini. Disegnate le ultime tre righe."
        ) {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                LinkMockupPopover(width: MockupGalleryView.pairWidth) {
                    previewBody(Array(LinkPreviewText.opening.suffix(3)), cut: .fade, title: nil)
                }
                LinkMockupPopover(width: MockupGalleryView.pairWidth) {
                    previewBody(Array(LinkPreviewText.opening.suffix(3)), cut: .ellipsis, title: nil)
                }
            }
        }
    }

    private enum Cut { case fade, ellipsis }

    /// The title and the lines, the last one cut the way `cut` says. The fade masks the final line
    /// the way `TranscludedNoteView` masks a capped transclusion.
    @ViewBuilder
    private func previewBody(_ lines: [String], cut: Cut, title: String? = "Riunione settimanale")
        -> some View {
        if let title {
            Text(title).themedText(.body, color: .textPrimary).fontWeight(.semibold)
        }
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            let isLast = index == lines.count - 1
            Group {
                if isLast && cut == .ellipsis {
                    Text(line + "…")
                } else {
                    Text(line)
                }
            }
            .themedText(.caption, color: line.hasPrefix("## ") ? .textPrimary : .textSecondary)
            .lineLimit(1)
            .mask(LinearGradient(
                colors: isLast && cut == .fade ? [.black, .black.opacity(0)] : [.black, .black],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }

    // MARK: Gli altri stati

    private var otherStates: some View {
        MockupScene(
            "Lo stesso popover negli altri casi: una sezione, una sezione che non c'è, una board, "
                + "più note con lo stesso titolo, nessuna nota. Ogni caso è una frase, mai un "
                + "riquadro vuoto."
        ) {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                HStack(alignment: .top, spacing: theme.spacing(.m)) {
                    state("[[Riunione settimanale#Decisioni]]") {
                        Text("Riunione settimanale › Decisioni")
                            .themedText(.body, color: .textPrimary).fontWeight(.semibold)
                        ForEach(LinkPreviewText.section, id: \.self) { line in
                            Text(line).themedText(.caption, color: .textSecondary).lineLimit(1)
                        }
                    }
                    state("[[Riunione settimanale#Decisioni]]") {
                        Text("Riunione settimanale").themedText(.body, color: .textPrimary).fontWeight(.semibold)
                        Text("Nessuna sezione «Decisioni»").themedText(.caption, color: .textTertiary)
                    }
                }
                HStack(alignment: .top, spacing: theme.spacing(.m)) {
                    state("[[Banco prove.canvas]]") {
                        HStack(spacing: theme.spacing(.xs)) {
                            Image(systemName: "square.grid.2x2").themedText(.body, color: .textSecondary)
                            Text("Banco prove").themedText(.body, color: .textPrimary).fontWeight(.semibold)
                        }
                    }
                    state("[[Riunione]]") {
                        Text("3 note si chiamano «Riunione»").themedText(.body, color: .textPrimary)
                        LinkMockupFolder(label: "Clienti/Nexion")
                        LinkMockupFolder(label: "Progetti")
                        LinkMockupFolder(label: "radice del vault")
                    }
                }
                state("[[Bozza]]") {
                    Text("Nessuna nota si chiama «Bozza»").themedText(.body, color: .textPrimary)
                    Text("Cmd+clic per crearla").themedText(.caption, color: .textTertiary)
                }
            }
        }
    }

    /// One cell of the row: the link it was opened on, then the popover, its arrow centred under
    /// the link as `NSPopover` centres it on the anchor.
    private func state(_ link: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .center, spacing: 0) {
            Text(link).themedText(.body, color: .accentPrimary).lineLimit(1)
            LinkMockupPopover(width: MockupGalleryView.pairWidth) { content() }
        }
        .frame(width: MockupGalleryView.pairWidth, alignment: .leading)
    }

    // MARK: Nessuna anteprima

    private var external: some View {
        MockupScene(
            "Un indirizzo esterno o un file incorporato non hanno anteprima, anche con Cmd premuto e "
                + "il puntatore fermo: Cmd+clic apre il browser o Quick Look, come oggi."
        ) {
            LinkMockupNote {
                LinkMockupLine(before: "Scheda del supporto: ", link: "https://example.org/scheda-supporto",
                               after: ".", pointer: true)
                Spacer(minLength: theme.spacing(.m))
            }
        }
    }

    // MARK: La scelta

    private var choiceAtClick: some View {
        MockupScene(
            "Cmd+clic su un titolo che hanno più note: un menu nel punto del clic, una riga per "
                + "nota con la sua cartella. Mai la prima a caso (ADR-0083 §D5). A destra, Cmd+clic "
                + "su un link senza nota: un menu di una riga, «Crea «Bozza»», che apre il "
                + "compositore e da solo non crea niente (§D6). Il menu vero è un NSMenu e ha "
                + "l'aspetto di quello di sistema."
        ) {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                LinkMockupNote {
                    LinkMockupLine(before: "Vedi anche ", link: "Riunione", after: " per le date.")
                    LinkMockupMenu(items: [
                        .header("Più note si chiamano «Riunione»"),
                        .row("Clienti/Nexion", glyph: "folder"),
                        .row("Progetti", glyph: "folder", highlighted: true),
                        .row("radice del vault", glyph: "folder"),
                    ], width: 240)
                    .padding(.leading, theme.spacing(.l))
                }
                .frame(width: MockupGalleryView.pairWidth)
                LinkMockupNote {
                    LinkMockupLine(before: "Riprendere da ", link: "Bozza", after: " domani.")
                    LinkMockupMenu(items: [
                        .row("Crea «Bozza»", glyph: "plus.square", highlighted: true),
                    ], width: 180)
                    .padding(.leading, theme.spacing(.l) * 3)
                }
                .frame(width: MockupGalleryView.pairWidth)
            }
        }
    }

    private var choiceFromKeyboard: some View {
        MockupScene(
            "Dalla tastiera, da «Apri collegamento», da una card del Workspace, dal chip di "
                + "un'attività o dalla board non c'è un punto a cui ancorare un menu: la stessa "
                + "scelta in un foglio, «LinkChoiceSheet». Invio apre la riga "
                + "scelta. A destra il link senza nota: la sola riga «Crea «Bozza»», che apre il "
                + "compositore con titolo e cartella già scritti (ADR-0083 §D6)."
        ) {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                LinkMockupSheet(width: MockupGalleryView.pairWidth, title: "Quale «Riunione»?", confirm: "Apri") {
                    VStack(alignment: .leading, spacing: 2) {
                        LinkMockupChoiceRow(title: "Clienti/Nexion", selected: true)
                        LinkMockupChoiceRow(title: "Progetti")
                        LinkMockupChoiceRow(title: "radice del vault")
                    }
                }
                LinkMockupSheet(
                    width: MockupGalleryView.pairWidth, title: "Nessuna nota si chiama «Bozza»", confirm: "Crea"
                ) {
                    LinkMockupChoiceRow(title: "Crea «Bozza»", glyph: "plus.square", selected: true)
                }
            }
        }
    }

    // MARK: Il popup di [[

    private var completion: some View {
        MockupScene(
            "Il popup di «[[» quando nessuna nota corrisponde e il testo scritto è un titolo valido: "
                + "una riga sola, «Crea «Bozza»». Completa il link, poi apre il compositore. Con un "
                + "titolo non valido («Piano.md») il popup resta com'è oggi."
        ) {
            LinkMockupNote {
                HStack(spacing: 0) {
                    Text("Riprendere da [[Bozza").themedText(.body, color: .textSecondary)
                    Rectangle().fill(theme.color(.accentPrimary)).frame(width: 1, height: 16)
                }
                LinkMockupCompletionPanel()
                    .padding(.leading, 96)
            }
        }
    }
}

/// The `[[` completion panel as `CompletionPanelView` draws it, with the one row N3 adds.
private struct LinkMockupCompletionPanel: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.spacing(.s)) {
                Image(systemName: "plus.square")
                    .frame(width: 16)
                    .foregroundStyle(theme.color(.textPrimary))
                Text("Crea «Bozza»").themedText(.body, color: .textPrimary)
                Spacer(minLength: theme.spacing(.s))
            }
            .padding(.horizontal, theme.spacing(.s))
            .padding(.vertical, theme.spacing(.xs))
            .background(
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .fill(theme.color(.accentMuted))
                    .padding(.horizontal, theme.spacing(.xs) / 2)
            )
            Divider().padding(.vertical, theme.spacing(.xs))
            HStack(spacing: theme.spacing(.s)) {
                Text("↑↓ scegli").themedText(.caption, color: .textTertiary)
                Text("↩ inserisci").themedText(.caption, color: .textTertiary)
                Spacer()
                Text("esc").themedText(.caption, color: .textTertiary)
            }
            .padding(.horizontal, theme.spacing(.s))
        }
        .padding(.vertical, theme.spacing(.xs))
        .frame(width: 340)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
        .themedShadow(.raised)
    }
}

/// The note the preview shows, literal.
private enum LinkPreviewText {
    /// The first twelve body lines of «Riunione settimanale», what `Transclusion.excerpt` would
    /// hand the popover.
    static let opening = [
        "Presenti: Ferri, Bassi, Conti.",
        "## Ordine del giorno",
        "- Stato delle prove a banco sui supporti",
        "- Curva di trasmissibilità della serie 40",
        "- Tempi del campionario per Nexion",
        "## Decisioni",
        "- Si rifà la prova con il carico reale",
        "- Il campionario parte lunedì",
        "- [ ] Mandare il verbale a Conti >2026-10-09",
        "## Note",
        "Il banco 2 resta fermo fino a giovedì: manca il sensore.",
        "La prossima riunione si sposta a mercoledì, stessa ora.",
    ]

    /// The «Decisioni» section alone, what a `[[…#Decisioni]]` link previews.
    static let section = [
        "- Si rifà la prova con il carico reale",
        "- Il campionario parte lunedì",
        "- [ ] Mandare il verbale a Conti >2026-10-09",
    ]
}
