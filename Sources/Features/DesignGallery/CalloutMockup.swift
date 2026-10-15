import SwiftUI

// MARK: - Callout (N5)

/// The callout card before it is built (ADR-0087 §D3, §D4, §D8, SPEC R-38): the five types open,
/// a folded `-` callout and the same one open, a written title, an unknown type drawn neutral, a
/// quote nested in a body, the title line as a Workspace card colours it, and the slash entry.
///
/// The card's ground is the type colour at `cardOpacity`, the one derived colour §D4 allows; the
/// type colour itself draws the bar, the icon and the title. Body lines are quote lines, so their
/// text is secondary (§D7). Everything here is literal. No parser, no fold state.
struct CalloutMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        MockupPage {
            MockupScene("I cinque tipi, aperti. Nel file la parola chiave inglese; a schermo l'etichetta italiana.") {
                VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                    ForEach(CalloutMockupKind.typed, id: \.self) { kind in
                        CalloutMockupCard(
                            kind: kind, lines: ["Prima riga del corpo, in testo secondario.", "Seconda riga del corpo."]
                        )
                    }
                }
            }
            MockupScene("«> [!avviso]-»: chiuso, solo la riga del titolo con la freccia; sotto, lo stesso aperto.") {
                VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                    CalloutMockupCard(kind: .warning, fold: .closed, lines: [])
                    CalloutMockupCard(
                        kind: .warning, fold: .open,
                        lines: ["La consegna slitta di una settimana.", "Avvisare il cliente."]
                    )
                }
            }
            MockupScene("«> [!tip] Prova a freddo prima del banco»: la riga nomina il proprio titolo.") {
                CalloutMockupCard(kind: .tip, title: "Prova a freddo prima del banco", lines: ["Bastano tre campioni."])
            }
            MockupScene("«> [!faq]»: un tipo sconosciuto è un callout neutro, con il tipo scritto come titolo.") {
                CalloutMockupCard(kind: .other("Faq"), lines: ["Si legge come gli altri, senza colore."])
            }
            MockupScene("Una citazione dentro il corpo di un callout.") {
                CalloutMockupCard(
                    kind: .note, lines: ["Il fornitore scrive:"], nested: "La curva resta quella di agosto."
                )
            }
            MockupScene(
                "Su una scheda del Workspace solo la riga del titolo prende il colore; «[!warning]» resta scritto."
            ) {
                HStack(alignment: .top, spacing: theme.spacing(.m)) {
                    workspaceCard(ground: .surfaceCard)
                    workspaceCard(ground: .stickyYellow)
                }
            }
            MockupScene("Menu /: la voce «Callout» scrive «> [!note] » al cursore.") {
                slashRows
            }
        }
    }

    private func workspaceCard(ground: ColorToken) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("> [!warning] Consegna in ritardo").themedText(.body, color: .calloutWarning)
            Text("> Il corriere conferma lunedì.").themedText(.body, color: .textPrimary)
        }
        .padding(theme.spacing(.s))
        .frame(width: MockupGalleryView.pairWidth, alignment: .leading)
        .background(theme.color(ground))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.sticky), style: .continuous))
        .themedShadow(.card)
    }

    /// Three rows of the slash panel's «SCRIVI» half, «Callout» selected (`SlashMenuMockup`'s row).
    private var slashRows: some View {
        let rows: [(title: String, symbol: String)] = [
            ("Blocco di codice", "curlybraces"), ("Callout", "text.bubble"), ("Tabella", "tablecells"),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            Text("SCRIVI").themedText(.caption, color: .textTertiary)
                .padding(.horizontal, theme.spacing(.s))
                .padding(.vertical, theme.spacing(.xs))
            ForEach(rows, id: \.title) { row in
                let selected = row.title == "Callout"
                HStack(spacing: theme.spacing(.s)) {
                    Image(systemName: row.symbol).themedText(.body, color: selected ? .textPrimary : .textSecondary)
                    Text(row.title).themedText(.body, color: selected ? .textPrimary : .textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, theme.spacing(.s))
                .padding(.vertical, theme.spacing(.xs))
                .background(
                    RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                        .fill(selected ? theme.color(.accentMuted) : .clear)
                )
            }
        }
        .padding(.vertical, theme.spacing(.xs))
        .frame(width: MockupGalleryView.pairWidth, alignment: .leading)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
        .themedShadow(.raised)
    }
}

// MARK: - The kinds

/// ADR-0087 §D3's five kinds plus `other`, with the colour, label and symbol the card draws.
private enum CalloutMockupKind: Hashable {
    case note, tip, important, warning, caution
    case other(String)

    static let typed: [CalloutMockupKind] = [.note, .tip, .important, .warning, .caution]

    /// An unknown type draws bar, icon and title in `quote.bar` (§D4).
    var color: ColorToken {
        switch self {
        case .note: .calloutNote
        case .tip: .calloutTip
        case .important: .calloutImportant
        case .warning: .calloutWarning
        case .caution: .calloutCaution
        case .other: .quoteBar
        }
    }

    var label: String {
        switch self {
        case .note: "Nota"
        case .tip: "Suggerimento"
        case .important: "Importante"
        case .warning: "Avviso"
        case .caution: "Attenzione"
        case .other(let written): written
        }
    }

    var symbol: String {
        switch self {
        case .note: "info.circle"
        case .tip: "lightbulb"
        case .important: "exclamationmark.bubble"
        case .warning: "exclamationmark.triangle"
        case .caution: "xmark.octagon"
        case .other: "quote.bubble"
        }
    }
}

// MARK: - The card

/// One callout as the editor will draw it: a bar and a tinted card, the title row (icon, title,
/// chevron when foldable), the body lines, and an optional quote nested in the body.
private struct CalloutMockupCard: View {
    @Environment(\.theme) private var theme

    enum Fold { case none, open, closed }

    let kind: CalloutMockupKind
    var title: String?
    var fold: Fold = .none
    let lines: [String]
    var nested: String?

    /// ADR-0087 §D4's one derived colour; the code PR names it `CalloutStyle.backgroundOpacity`.
    static let cardOpacity: Double = 0.08
    private static let barWidth: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: kind.symbol).themedText(.body, color: kind.color)
                Text(title ?? kind.label).font(theme.font(.prose).weight(.semibold))
                    .foregroundStyle(theme.color(kind.color))
                if fold != .none {
                    Image(systemName: fold == .closed ? "chevron.right" : "chevron.down")
                        .themedText(.caption, color: kind.color)
                }
            }
            if fold != .closed {
                ForEach(lines, id: \.self) { line in
                    Text(line).font(theme.font(.prose)).foregroundStyle(theme.color(.textSecondary))
                }
                if let nested {
                    Text(nested).font(theme.font(.prose)).foregroundStyle(theme.color(.textSecondary))
                        .padding(.leading, theme.spacing(.s))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(theme.color(.quoteBar)).frame(width: Self.barWidth)
                        }
                }
            }
        }
        .padding(.vertical, theme.spacing(.s))
        .padding(.leading, theme.spacing(.m))
        .padding(.trailing, theme.spacing(.s))
        .frame(width: MockupGalleryView.rowWidth, alignment: .leading)
        .background(ground)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.color(kind.color)).frame(width: Self.barWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }

    /// The type colour at `cardOpacity` over the page; an unknown type sits on `surface.sunken`.
    private var ground: Color {
        if case .other = kind { return theme.color(.surfaceSunken) }
        return theme.color(kind.color).opacity(Self.cardOpacity)
    }
}
