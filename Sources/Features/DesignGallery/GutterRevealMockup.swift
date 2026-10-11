import SwiftUI

// MARK: - Margine dei marcatori (N2)

/// Block markers that hang in a gutter, so revealing one moves no text (PG-385, SPEC R-13 and
/// R-14). The picture ADR-0081's gates G1 and G2 are decided on: the gutter's value, the heading
/// marker's face, the quote step, the narrow-width shift and the permanent `H2` badge.
///
/// The one thing it has to prove is that the content does not move, so every scene draws a thin
/// guide at the content column and each item twice, concealed above revealed (the gutter values
/// draw the revealed runs only, the widest the gutter has to hold). A marker hangs by
/// being laid out right-aligned in a frame that ends at the column: the content lands on the
/// column whatever the marker's width, without measuring anything here. The code PR measures the
/// run and sets paragraph indents in TextKit; this file only draws the result.
///
/// The arithmetic is ADR-0081's, restated rather than owned (`G` is the gutter, `em` the prose
/// face's point size, `w` the displayed run's width):
///
/// - a list item at level `L` puts its content at `C(L) = G + 1.5 em × L + 0.75 em`, and its
///   first line at `max(0, C(L) − w)`, bullet or digits, concealed or revealed (§D2);
/// - a quote at level `Q` puts its content at `C_q(Q) = G + step × Q`, step 0.75 em or 0, its
///   bars or its `> >` run hanging the same way (§D3);
/// - a heading's content is at `G` in both states; revealed, its `#` run is drawn in
///   `font.caption`, `color.textTertiary`, and hangs from `G` (§D4).
///
/// No new token: the gutter candidates are sums of the spacing tokens that exist, 40
/// (`spacing.xl`), 48 (`+ spacing.s`, the proposal every scene but the last uses) and 56
/// (`+ spacing.m`). The code PR adds `spacing.gutter` with the approved value.
struct GutterRevealMockup: View {
    @Environment(\.theme) private var theme

    /// The narrow host: the Diario pane's writing column, `.frame(minWidth: 420)` on
    /// `writingColumn` in `DiaryView.body`, the same minimum as `noteColumn` in
    /// `TodayView.daySplit`. Its minimum, where the shift weighs most against the column; the
    /// running app this would have been read from was another worktree's build. A copy, not a
    /// reference, and nothing pins the three together: if either site changes its minimum,
    /// update this value with it.
    static let narrowWidth: CGFloat = 420

    /// The readable host, reduced. A Note pane wide enough for «Larghezza leggibile» to centre
    /// its 720-point column does not fit `MockupGalleryView.rowWidth`, and a wider scene is
    /// clipped at both edges; so a 960-point pane is drawn at two thirds, margins in proportion
    /// and text at its real size. The caption says so.
    static let readableWidth: CGFloat = 640

    /// The pane `readableWidth` stands for.
    private static let readableModelWidth: CGFloat = 960

    /// `lineFragmentPadding`, which `NoteTextView` leaves at the container's default: the 5 in
    /// ADR-0081's "24 + 5 points to the left of the text".
    private static let fragmentPadding = NSTextContainer().lineFragmentPadding

    var body: some View {
        MockupPage {
            MockupScene(
                "Elenco annidato. In ogni coppia, sopra il marcatore nascosto e sotto quello "
                    + "rivelato: il testo parte dalla stessa linea guida, anche la seconda riga di "
                    + "una voce che va a capo. L'attività non si sposta già oggi e resta dove sta "
                    + "(ADR-0081 §D2)."
            ) {
                NestedListScene(columns: columns(base: proposal))
            }
            MockupScene(
                "Titoli. Rivelato, il cancelletto è nel carattere delle didascalie e pende nel "
                    + "margine; il titolo resta sulla linea guida a \(Int(proposal)) pt."
            ) {
                HeadingScene(columns: columns(base: proposal))
            }
            MockupScene("Citazioni a uno e due livelli, appese alla colonna della citazione (G1).") {
                QuoteScene(columns: columns(base: proposal))
            }
            MockupScene(
                "Larghezza stretta e leggibile. In ogni coppia, sopra il nascosto e sotto il "
                    + "rivelato. La linea tratteggiata è dove il testo comincia oggi."
            ) {
                widthScenes
            }
            MockupScene(
                "Variante: livello del titolo sempre visibile (G2). Nascosto, un H1, H2, H3 tenue "
                    + "nel margine; rivelato, al suo posto il cancelletto."
            ) {
                BadgeScene(columns: columns(base: proposal))
            }
            MockupScene(
                "Valori del margine (G1): il titolo H6 e una citazione a tre livelli, rivelati. La linea "
                    + "tratteggiata è il bordo del testo: un marcatore che la supera sposterebbe "
                    + "il testo della differenza."
            ) {
                gutterValues
            }
        }
    }

    /// 48, ADR-0081 §D1's proposal.
    private var proposal: CGFloat { theme.spacing(.xl) + theme.spacing(.s) }

    private func columns(base: CGFloat, quoteStep: CGFloat = 0.75) -> Columns {
        Columns(base: base, em: ProseTypography.prose(theme).pointSize, quoteStep: quoteStep)
    }

    // MARK: Scene 4

    private var widthScenes: some View {
        // Narrow: the inset is `NoteTextView`'s fixed minimum, which the gutter swallows whole
        // (ADR-0081 §D1's table): today `24 + 5`, after `max(0, 24 − G) + 5 + G`.
        let inset = NoteTextView.Coordinator.minimumHorizontalInset
        let narrowToday = inset + Self.fragmentPadding
        let narrowAfter = max(0, inset - proposal) + Self.fragmentPadding + proposal
        // Readable: `(W − 720) / 2 + 5` before and after, the inset shrinking by what the
        // gutter adds; scaled to the reduced drawing.
        let model = Self.readableModelWidth
        let readableStart = ((model - theme.spacing(.readable)) / 2 + Self.fragmentPadding)
            * Self.readableWidth / model
        return VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            subCaption(
                "Stretta, \(Int(Self.narrowWidth)) pt come la colonna del Diario: tutta la colonna "
                    + "si sposta di \(Int(narrowAfter - narrowToday)) pt a destra, una volta, e poi "
                    + "non si muove più."
            )
            ShortNoteScene(
                width: Self.narrowWidth, columns: columns(base: narrowAfter), ghost: narrowToday
            )
            subCaption(
                "Leggibile, ridotta: \(Int(Self.readableWidth)) pt per un pannello di "
                    + "\(Int(model)), margini in proporzione e testo a grandezza reale. La colonna "
                    + "non si muove e i marcatori stanno in quello che era margine."
            )
            ShortNoteScene(
                width: Self.readableWidth, columns: columns(base: readableStart), ghost: readableStart
            )
        }
    }

    // MARK: Scene 6

    private var gutterValues: some View {
        let candidates: [(value: CGFloat, name: String)] = [
            (theme.spacing(.xl), "spacing.xl"),
            (theme.spacing(.xl) + theme.spacing(.s), "spacing.xl + spacing.s"),
            (theme.spacing(.xl) + theme.spacing(.m), "spacing.xl + spacing.m"),
        ]
        return HStack(alignment: .top, spacing: theme.spacing(.m)) {
            ForEach(candidates.indices, id: \.self) { index in
                let candidate = candidates[index]
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    subCaption("G = \(Int(candidate.value)), \(candidate.name)")
                    GutterValueCell(columns: columns(base: candidate.value))
                }
                .frame(width: MockupGalleryView.tripleWidth, alignment: .leading)
            }
        }
    }

    private func subCaption(_ text: String) -> some View {
        Text(text)
            .themedText(.caption, color: .textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Arithmetic and faces

/// The list step and the glyph slot, in `em`. Mirrored from `ListMarkerRendering.stepInEms` and
/// `.glyphInEms`, which are `private` there: a copy for the drawing, kept in step by hand.
private let listStepInEms: CGFloat = 1.5
private let listGlyphInEms: CGFloat = 0.75

/// Where this drawing puts each column, measured from the sheet's leading edge: the positions of
/// the doc comment on `GutterRevealMockup` (ADR-0081 §D2 to §D4), evaluated for one picture.
/// Not the arithmetic itself: the code PR owns that, in TextKit's paragraph indents.
private struct Columns {
    /// Where body text, and a heading's title, starts.
    let base: CGFloat
    let em: CGFloat
    /// The quote's step per level, in `em`: 0.75 or 0 (gate G1).
    let quoteStep: CGFloat

    func list(_ level: Int) -> CGFloat {
        base + listStepInEms * em * CGFloat(level) + listGlyphInEms * em
    }

    func quote(_ level: Int) -> CGFloat { base + quoteStep * em * CGFloat(level) }

    /// Where a task's checkbox starts: the file's own indentation, approximated as one list step
    /// per level, shifted by the gutter. ADR-0081 §D2 leaves the task's layout as it is.
    func task(_ level: Int) -> CGFloat { base + listStepInEms * em * CGFloat(level - 1) }

    func withQuoteStep(_ step: CGFloat) -> Columns { Columns(base: base, em: em, quoteStep: step) }
}

/// Every run a scene draws, through the tokens the editor draws it with.
private struct Faces {
    let theme: Theme

    /// A no-break space ends every marker run: the file's is a plain space, and a plain space
    /// at the end of a `Text` is not reliably counted in its width.
    private static let space = "\u{00A0}"

    func body(_ text: String) -> Text {
        Text(text).font(theme.font(.prose)).foregroundStyle(theme.color(.textPrimary))
    }

    func marker(_ run: String) -> Text {
        Text(run + Self.space).font(theme.font(.prose)).foregroundStyle(theme.color(.textTertiary))
    }

    func heading(_ text: String, level: Int) -> Text {
        Text(text)
            .font(Font(ProseTypography.heading(level: level, theme) as CTFont))
            .foregroundStyle(theme.color(ProseTypography.headingColor(level: level)))
    }

    /// The revealed `#` run in the marker face of ADR-0081 §D4.
    func headingRun(_ level: Int) -> Text { label(String(repeating: "#", count: level) + Self.space) }

    func label(_ text: String) -> Text {
        Text(text).font(theme.font(.caption)).foregroundStyle(theme.color(.textTertiary))
    }

    /// Concealed quote: one `▏` per level, the separating spaces collapsed (ADR-0029 §D1).
    func bars(_ level: Int) -> Text { marker(String(repeating: "▏", count: level)) }

    /// Revealed quote: the file's `> >` run.
    func quoteRun(_ level: Int) -> Text {
        marker(Array(repeating: ">", count: level).joined(separator: " "))
    }

    func checkbox() -> Text {
        Text("☐").font(Font(ProseTypography.checkbox(theme) as CTFont))
            .foregroundStyle(theme.color(.taskOpen))
    }
}

// MARK: - Scenes

private struct NestedListScene: View {
    @Environment(\.theme) private var theme
    let columns: Columns

    var body: some View {
        let faces = Faces(theme: theme)
        let bullet = faces.marker("•")
        let dash = faces.marker("-")
        GutterMockupSheet(width: MockupGalleryView.rowWidth, guides: (1...3).map(columns.list)) {
            GutterMockupPair(columns.list(1), bullet, dash, faces.body("Fornitori di mescola"))
            GutterMockupPair(
                columns.list(2), faces.marker("1."), faces.marker("1."), faces.body("Gommatex, EPDM e NBR")
            )
            GutterMockupPair(
                columns.list(2), faces.marker("10."), faces.marker("10."),
                faces.body(
                    "Una voce lunga che va a capo: la seconda riga si allinea sotto il testo della "
                        + "prima, non sotto il numero, nei due stati"
                )
            )
            GutterMockupPair(columns.list(3), bullet, dash, faces.body("Campioni a 60 shore"))
            GutterMockupTaskPair(
                start: columns.task(2), checkbox: faces.checkbox(), text: faces.body("Chiedere la scheda tecnica")
            )
        }
    }
}

private struct HeadingScene: View {
    @Environment(\.theme) private var theme
    let columns: Columns

    var body: some View {
        let faces = Faces(theme: theme)
        let titles = ["Prove in laboratorio", "Campioni", "A freddo", "Misure", "Ripetizioni", "Note a margine"]
        GutterMockupSheet(width: MockupGalleryView.rowWidth, guides: [columns.base]) {
            ForEach(1...6, id: \.self) { level in
                GutterMockupPair(
                    columns.base, nil, faces.headingRun(level),
                    faces.heading(titles[level - 1], level: level)
                )
            }
        }
    }
}

private struct QuoteScene: View {
    @Environment(\.theme) private var theme
    let columns: Columns

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            caption("Passo 0,75 em per livello, come gli elenchi")
            sheet(columns.withQuoteStep(0.75))
            caption("Passo 0: il testo sulla colonna del corpo, le barre tutte nel margine")
            sheet(columns.withQuoteStep(0))
        }
    }

    private func sheet(_ columns: Columns) -> some View {
        let faces = Faces(theme: theme)
        let guides = Array(Set([columns.base, columns.quote(1), columns.quote(2)])).sorted()
        return GutterMockupSheet(width: MockupGalleryView.rowWidth, guides: guides) {
            GutterMockupPair(
                columns.quote(1), faces.bars(1), faces.quoteRun(1), faces.body("Il fornitore conferma la curva.")
            )
            GutterMockupPair(
                columns.quote(2), faces.bars(2), faces.quoteRun(2), faces.body("Citata dentro la sua risposta.")
            )
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).themedText(.caption, color: .textSecondary)
    }
}

/// The same short note at one width: the view's leading edge is the sheet's, the text inset
/// both sides as the editor's would be.
private struct ShortNoteScene: View {
    @Environment(\.theme) private var theme
    let width: CGFloat
    let columns: Columns
    let ghost: CGFloat

    var body: some View {
        let faces = Faces(theme: theme)
        GutterMockupSheet(
            width: width, guides: [columns.base, columns.quote(1), columns.list(1), columns.list(2)],
            ghosts: [ghost], trailing: columns.base
        ) {
            GutterMockupPair(
                columns.base, nil, faces.headingRun(2), faces.heading("Prova a freddo", level: 2),
                labelled: false
            )
            GutterMockupRow(column: columns.base, marker: nil, text: faces.body("Tre campioni, misurati a −20 °C."))
            ForEach(1...2, id: \.self) { level in
                GutterMockupPair(
                    columns.list(level), faces.marker("•"), faces.marker("-"),
                    faces.body(level == 1 ? "Campioni" : "60 shore"), labelled: false
                )
            }
            GutterMockupPair(
                columns.quote(1), faces.bars(1), faces.quoteRun(1), faces.body("Curva confermata."),
                labelled: false
            )
        }
    }
}

private struct BadgeScene: View {
    @Environment(\.theme) private var theme
    let columns: Columns

    var body: some View {
        let faces = Faces(theme: theme)
        let titles = ["Prove in laboratorio", "Campioni", "A freddo"]
        GutterMockupSheet(width: MockupGalleryView.rowWidth, guides: [columns.base]) {
            ForEach(1...3, id: \.self) { level in
                GutterMockupPair(
                    columns.base,
                    // A badge is not the file's text, so it carries no trailing space of its
                    // own: the gap to the title is padding, drawn by the heading's fragment.
                    faces.label("H\(level)"),
                    faces.headingRun(level),
                    faces.heading(titles[level - 1], level: level),
                    badgeGap: theme.spacing(.s)
                )
            }
        }
    }
}

/// One gutter candidate, revealed only: the widest runs are the revealed ones, and room is left
/// of the text's edge so a run too wide for the gutter shows.
private struct GutterValueCell: View {
    @Environment(\.theme) private var theme
    let columns: Columns

    var body: some View {
        let faces = Faces(theme: theme)
        let bleed = theme.spacing(.m)
        GutterMockupSheet(
            width: MockupGalleryView.tripleWidth - bleed, guides: [columns.base, columns.quote(3)],
            ghosts: [0], bleed: bleed
        ) {
            GutterMockupRow(
                column: columns.base, marker: faces.headingRun(6), text: faces.heading("Allegati", level: 6)
            )
            GutterMockupRow(column: columns.quote(3), marker: faces.quoteRun(3), text: faces.body("Tre livelli"))
        }
    }
}
