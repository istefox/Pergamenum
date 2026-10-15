import SwiftUI

// MARK: - Embed, transclusioni e tabelle (N5)

/// Embeds, transclusions and tables before they are built (ADR-0087 §D9 to §D11, SPEC R-40,
/// R-41): the box an embed reserves before its picture, an inline and a whole-line file chip, the
/// transclusion caption in its source row and the same line revealed, and a table column's menu.
///
/// Everything here is literal. No thumbnail store, no Quick Look, no table model.
struct PageEmbedsMockup: View {
    @Environment(\.theme) private var theme

    /// `![[banco.png|480]]`: the written width, inside the sheet's text column (608).
    static let placeholderWidth: CGFloat = 480
    /// The default ratio a `|W` embed is reserved at before its picture says otherwise: 3:2.
    static let placeholderRatio: CGFloat = 3.0 / 2.0
    /// One table column as drawn; three of them fit the sheet's text column.
    static let columnWidth: CGFloat = 160
    /// The column menu, `LinkMockupMenu`'s default width.
    static let menuWidth: CGFloat = 220

    var body: some View {
        let faces = PageMockupFaces(theme: theme)
        MockupPage {
            MockupScene(
                "«![[banco.png|480]]» prima che arrivi la miniatura: lo spazio è già quello scritto, a 3:2; "
                    + "l'immagine poi prende il posto di un riquadro della stessa larghezza."
            ) {
                PageMockupSheet { placeholder }
            }
            MockupScene("Un file in linea è un chip: icona e nome; un clic fuori dal cursore apre Quick Look.") {
                PageMockupSheet {
                    PageMockupLine([
                        .text(faces.prose("Vedi ")), fileChip("doc.richtext", "scheda.pdf"),
                        .text(faces.prose(" per i valori di durezza.")),
                    ])
                }
            }
            MockupScene("Su una riga da solo, un file che non si disegna è lo stesso chip.") {
                PageMockupSheet {
                    PageMockupLine([fileChip("doc.text", "contratto.docx")])
                }
            }
            MockupScene(
                "Transclusione: la riga sorgente diventa la didascalia, il corpo sotto. Sotto, il cursore "
                    + "sulla riga la rivela."
            ) {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    PageMockupSheet {
                        Text("da «Riunione 3 ottobre» › Decisioni").themedText(.caption, color: .textSecondary)
                        transcluded
                    }
                    PageMockupSheet {
                        PageMockupLine([
                            .text(faces.prose("![[Riunione 3 ottobre#Decisioni]]", .textSecondary)), .caret,
                        ])
                        transcluded
                    }
                }
            }
            MockupScene(
                "Il menu di una colonna, aperto su «Prezzo», allineata a destra: allineamento (quello attuale "
                    + "spuntato) e ordinamento. Ogni voce è un solo passo di Annulla."
            ) {
                PageMockupSheet {
                    table
                    LinkMockupMenu(
                        items: [
                            .header("Colonna «Prezzo»"),
                            .row("Allinea a sinistra", glyph: "text.alignleft"),
                            .row("Allinea al centro", glyph: "text.aligncenter"),
                            .row("Allinea a destra", glyph: "text.alignright", shortcut: "✓"),
                            .separator,
                            .row("Ordina A→Z", glyph: "arrow.up", highlighted: true),
                            .row("Ordina Z→A", glyph: "arrow.down"),
                        ],
                        width: Self.menuWidth
                    )
                    .padding(.leading, 3 * Self.columnWidth - Self.menuWidth)
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "photo").themedText(.heading, color: .textTertiary)
            Text("banco.png").themedText(.caption, color: .textTertiary)
        }
        .frame(width: Self.placeholderWidth, height: Self.placeholderWidth / Self.placeholderRatio)
        .background(theme.color(.surfaceSunken), in: RoundedRectangle(cornerRadius: theme.radius(.card)))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card))
                .strokeBorder(theme.color(.borderStrong), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    private func fileChip(_ symbol: String, _ name: String) -> PageMockupPiece {
        let faces = PageMockupFaces(theme: theme)
        let icon = Text(Image(systemName: symbol)).font(theme.font(.prose))
            .foregroundStyle(theme.color(.textSecondary))
        return .chip(.surfaceSunken, [.text(icon + faces.prose(" " + name))])
    }

    /// The target's section, as its styled source, beside the rule the editor draws today.
    private var transcluded: some View {
        let faces = PageMockupFaces(theme: theme)
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            faces.prose("- Si ordina la mescola a 70 shore.")
            faces.prose("- Campioni al banco entro venerdì.")
        }
        .padding(.leading, theme.spacing(.s))
        .overlay(alignment: .leading) {
            // 0.35 copies TransclusionMockup's rule, not a second derived colour (ADR-0087 §D4).
            Rectangle().fill(theme.color(.accentPrimary).opacity(0.35)).frame(width: 3)
        }
    }

    private var table: some View {
        let rows = [["Mescola", "Shore", "Prezzo"], ["EPDM", "70", "12,40"], ["NBR", "60", "9,80"],
                    ["Silicone", "80", "21,00"]]
        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { column in
                        cell(rows[row][column], header: row == 0, trailing: column == 2)
                    }
                }
            }
        }
        .overlay(Rectangle().strokeBorder(theme.color(.borderSubtle), lineWidth: 1))
    }

    private func cell(_ text: String, header: Bool, trailing: Bool) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            if trailing { Spacer(minLength: 0) }
            Text(text).font(theme.font(.prose).weight(header ? .semibold : .regular))
                .foregroundStyle(theme.color(.textPrimary))
            if header && trailing {
                Image(systemName: "chevron.down.circle.fill").themedText(.caption, color: .accentPrimary)
            }
            if !trailing { Spacer(minLength: 0) }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .frame(width: Self.columnWidth)
        .background(header ? theme.color(.backgroundSecondary) : .clear)
        .overlay(Rectangle().strokeBorder(theme.color(.borderSubtle), lineWidth: 0.5))
    }
}
