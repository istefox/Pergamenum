import SwiftUI

// MARK: - Codice, citazioni e chip (N5)

/// The inline constructs of the page before they are built (ADR-0087 §D5 to §D7, SPEC R-36,
/// R-37, R-39, R-42): the inline-code pill and the highlight, off the caret and on it; a fence's
/// header and quiet closing line; «Copia il blocco»; a three-level quote with full-height bars;
/// the tag and date chips.
///
/// The quote replaces the `▏` glyphs of «Margine dei marcatori» (N2): its content column is
/// `EditorGutter.quoteColumn`, the column the editor already hangs a quote at (ADR-0081 §D3), so
/// the bar approved here sits where the code will put it. Everything here is literal: no styler.
struct PageConstructsMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let faces = PageMockupFaces(theme: theme)
        MockupPage {
            MockupScene("Codice in linea: sopra fuori dal cursore, sotto con il cursore dentro, i backtick visibili.") {
                PageMockupSheet {
                    PageMockupLine([
                        .text(faces.prose("Lancia ")), faces.code([.text(faces.mono("perg index"))]),
                        .text(faces.prose(" dopo il cambio di cartella.")),
                    ])
                    PageMockupLine([
                        .text(faces.prose("Lancia ")),
                        faces.code([
                            .text(faces.mono("`", .textSecondary)), .text(faces.mono("perg")), .caret,
                            .text(faces.mono(" index")), .text(faces.mono("`", .textSecondary)),
                        ]),
                        .text(faces.prose(" dopo il cambio di cartella.")),
                    ])
                }
            }
            MockupScene("Evidenziato: «==conforme==» fuori dal cursore e con il cursore; «`a==b==`» resta codice.") {
                PageMockupSheet {
                    PageMockupLine([
                        .text(faces.prose("Il campione è ")),
                        .chip(.highlight, [.text(faces.prose("conforme"))]),
                        .text(faces.prose(" alla curva.")),
                    ])
                    PageMockupLine([
                        .text(faces.prose("Il campione è ")),
                        .chip(.highlight, [
                            .text(faces.prose("==", .textSecondary)), .text(faces.prose("confor")), .caret,
                            .text(faces.prose("me")), .text(faces.prose("==", .textSecondary)),
                        ]),
                        .text(faces.prose(" alla curva.")),
                    ])
                    PageMockupLine([
                        .text(faces.prose("Il confronto ")), faces.code([.text(faces.mono("a==b=="))]),
                        .text(faces.prose(" non evidenzia nulla.")),
                    ])
                }
            }
            MockupScene(
                "Blocco di codice: intestazione con linguaggio e righe, chiusura discreta; il corpo, qui "
                    + "accorciato a una riga, resta modificabile. Sotto, il cursore sull'intestazione la rivela."
            ) {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    PageMockupFence(revealed: false)
                    PageMockupFence(revealed: true)
                }
            }
            MockupScene("Il menu contestuale dentro un blocco: «Copia il blocco» copia il corpo, senza i backtick.") {
                LinkMockupMenu(items: [
                    .row("Taglia", shortcut: "⌘X"), .row("Copia", shortcut: "⌘C"), .row("Incolla", shortcut: "⌘V"),
                    .separator, .row("Copia il blocco", glyph: "doc.on.doc", highlighted: true),
                ])
            }
            MockupScene(
                "Citazione a tre livelli: una barra per livello a tutta altezza, testo secondario, rientro dalla "
                    + "colonna della citazione. Il terzo paragrafo va a capo e la barra lo segue."
            ) {
                PageMockupSheet(spacing: 0) {
                    PageMockupLine([.text(faces.prose("Dalla corrispondenza con il fornitore:"))])
                        .padding(.bottom, theme.spacing(.paragraph))
                    PageMockupQuote(level: 1, text: "Confermiamo la curva di trasmissibilità.")
                    PageMockupQuote(level: 2, text: "Vale anche per la mescola a 70 shore?")
                    PageMockupQuote(
                        level: 3,
                        text: "La prova a freddo è stata ripetuta tre volte sul banco e i valori restano dentro "
                            + "la tolleranza dichiarata nella scheda tecnica di settembre."
                    )
                }
            }
            MockupScene("Tag e data: il namespace in secondario, il valore nell'accento; la data di pianificazione.") {
                PageMockupSheet {
                    PageMockupLine([
                        .text(faces.prose("Riunione con ")),
                        .chip(.accentMuted, [
                            .text(faces.prose("#client-", .textSecondary) + faces.prose("acme", .accentPrimary)),
                        ]),
                        .text(faces.prose(" fissata ")),
                        .chip(.surfaceSunken, [
                            .text(faces.prose(">", .textSecondary) + faces.prose("2026-10-14 10:30", .taskScheduled)),
                        ]),
                    ])
                }
            }
        }
    }
}

// MARK: - The pieces the three N5 pages share

/// The note page a construct is drawn on: `background.primary`, the ground ADR-0087 §D4's
/// thresholds are measured against, with the text starting at the gutter as in the editor.
struct PageMockupSheet<Content: View>: View {
    @Environment(\.theme) private var theme
    var spacing: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing ?? theme.spacing(.paragraph)) { content }
            .padding(.vertical, theme.spacing(.m))
            .padding(.leading, theme.spacing(.gutter))
            .padding(.trailing, theme.spacing(.m))
            .frame(width: MockupGalleryView.rowWidth, alignment: .leading)
            .background(theme.color(.backgroundPrimary))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                    .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
            )
    }
}

/// One run of a mockup line: text, the caret, or a chip around runs (ADR-0087 §D5's painter).
enum PageMockupPiece {
    case text(Text)
    case caret
    case chip(ColorToken, [PageMockupPiece])
}

/// One line of the page that never wraps, drawn run by run on a shared baseline.
struct PageMockupLine: View {
    @Environment(\.theme) private var theme
    private let pieces: [PageMockupPiece]

    init(_ pieces: [PageMockupPiece]) { self.pieces = pieces }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(pieces.indices, id: \.self) { index in
                switch pieces[index] {
                case .text(let text): text
                case .caret:
                    Rectangle().fill(theme.color(.accentPrimary))
                        .frame(width: 1, height: ProseTypography.prose(theme).pointSize)
                case .chip(let ground, let inner):
                    PageMockupLine(inner)
                        .padding(.horizontal, theme.spacing(.xs) / 2)
                        .background(theme.color(ground), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
                }
            }
        }
        .lineLimit(1)
    }
}

/// The faces the editor draws the page's runs with, through tokens only.
struct PageMockupFaces {
    let theme: Theme

    func prose(_ text: String, _ color: ColorToken = .textPrimary) -> Text {
        Text(text).font(theme.font(.prose)).foregroundStyle(theme.color(color))
    }

    func mono(_ text: String, _ color: ColorToken = .textPrimary) -> Text {
        Text(text).font(theme.font(.mono)).foregroundStyle(theme.color(color))
    }

    /// The inline-code pill: primary text, revealed backticks secondary, on the inline ground
    /// (the pair ADR-0087 §D4 holds to 4.5:1).
    func code(_ inner: [PageMockupPiece]) -> PageMockupPiece { .chip(.codeInlineBackground, inner) }
}

// MARK: - Scene pieces

/// A `swift` fence: header with badge and line count, one body line, a quiet closing rule.
/// Revealed, the header is the file's own line with the caret on it; the closing line stays quiet.
private struct PageMockupFence: View {
    @Environment(\.theme) private var theme
    let revealed: Bool

    var body: some View {
        let faces = PageMockupFaces(theme: theme)
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            if revealed {
                PageMockupLine([.text(faces.mono("```swift", .textTertiary)), .caret])
            } else {
                HStack(spacing: theme.spacing(.s)) {
                    Text("swift").themedText(.caption, color: .textSecondary)
                        .padding(.horizontal, theme.spacing(.xs))
                        .background(
                            theme.color(.backgroundPrimary), in: RoundedRectangle(cornerRadius: theme.radius(.control))
                        )
                    Text("12 righe").themedText(.caption, color: .textTertiary)
                }
            }
            PageMockupLine([
                .text(faces.mono("let ", .codeKeyword) + faces.mono("mescola: ") + faces.mono("Mescola", .codeType)
                    + faces.mono(" = .init(shore: ") + faces.mono("70", .codeNumber) + faces.mono(")")),
            ])
            Rectangle().fill(theme.color(.borderSubtle)).frame(height: 1)
        }
        .padding(theme.spacing(.s))
        .frame(width: MockupGalleryView.rowWidth, alignment: .leading)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}

/// One quoted paragraph at `level`: its content at `EditorGutter.quoteColumn`, one bar per level
/// centred in that level's step, over the paragraph's full height and its spacing, so consecutive
/// lines draw one unbroken bar (ADR-0087 §D7).
private struct PageMockupQuote: View {
    @Environment(\.theme) private var theme
    let level: Int
    let text: String

    /// The bar's width: geometry, not a token, like the transclusion rule's 3 points.
    private static let barWidth: CGFloat = 3

    var body: some View {
        let font = ProseTypography.prose(theme)
        let gutter = theme.spacing(.gutter)
        let step = EditorGutter.quoteStepInEms * font.pointSize
        // The sheet already starts the text at the gutter, so both are measured from there.
        let indent = EditorGutter.quoteColumn(level: level, font: font, gutter: gutter) - gutter
        Text(text)
            .font(theme.font(.prose))
            .foregroundStyle(theme.color(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, indent)
            .padding(.vertical, theme.spacing(.paragraph) / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                ZStack(alignment: .leading) {
                    ForEach(1...level, id: \.self) { bar in
                        Rectangle().fill(theme.color(.quoteBar))
                            .frame(width: Self.barWidth)
                            .padding(.leading, step * CGFloat(bar - 1) + (step - Self.barWidth) / 2)
                    }
                }
            }
    }
}
