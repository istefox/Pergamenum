import SwiftUI

// MARK: - L'ispettore: i link (N3)

/// What the inspector says about a note's links, before it is built (ADR-0084, SPEC R-24, R-25,
/// R-27, R-28): why each backlink is there, what this note fails to link, how a structural link is
/// made and taken back, and where the note appears outside the notes.
///
/// Drawn at the inspector's real width (`UnlinkedMentionsMockup.inspectorWidth`), each section the
/// way `TraySection` draws one today, the open note being «Riunione settimanale». Two questions
/// are put to the person:
///
/// 1. **The «strutturale» badge's form**: a word in a capsule (the proposal) or a glyph with a
///    tooltip, drawn side by side.
/// 2. **The reverse reason while it follows the forward one**: in the field's normal text (the
///    proposal) or in a tenuous colour until the person edits it.
///
/// «Dove compare» is not a question any more: the SPEC settled it on request on 2026-10-07
/// (ADR-0084 §D6), so only the shape behind its button is drawn, and no automatic one.
///
/// Everything here is literal. No controller, no index, no vault.
struct InspectorLinksMockup: View {
    @Environment(\.theme) private var theme

    /// The structural-link sheet's real width (`RelatedLinkSheet`'s frame), which fits the row.
    static let sheetWidth: CGFloat = 560
    /// Two mirror cells across: `MockupGalleryView.pairWidth` (the outer width) less the 16 points
    /// of padding a `MockupCell` adds around its frame (`spacing(.s)` each side), so the row is 672.
    static let mirrorCellWidth: CGFloat = MockupGalleryView.pairWidth - 16

    var body: some View {
        MockupPage {
            backlinks
            badgeForms
            rowMenus
            unlink
            unresolved
            structuralSheet
            mirror
            appearances
        }
    }

    // MARK: Backlink

    private var backlinks: some View {
        MockupScene(
            "BACKLINK con il perché: sotto il titolo la riga che linka, il link nell'accento, una "
                + "riga sola tagliata in coda. Il conteggio solo sopra uno; «strutturale» quando il "
                + "«related» dell'altra nota nomina questa (ADR-0084 §D1)."
        ) {
            InspectorMockupPanel { backlinkSection(badge: .word) }
        }
    }

    private func backlinkSection(badge: InspectorMockupBacklink.Badge) -> some View {
        InspectorMockupSection(title: "BACKLINK", count: "3") {
            InspectorMockupBacklink(
                title: "Prova banco 12", before: "Decisioni prese in ", after: ", da girare al cliente."
            )
            InspectorMockupBacklink(
                title: "Campionario Nexion", before: "Tempi fissati in ", after: ": parte lunedì.", count: 3
            )
            InspectorMockupBacklink(
                title: "Piano prove 2026", before: "- ", after: ": qui si decidono le prove", badge: badge
            )
        }
    }

    private var badgeForms: some View {
        MockupScene(
            "La forma del contrassegno, da scegliere: la parola (proposta) o un simbolo che spiega "
                + "sé stesso al passaggio del puntatore."
        ) {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                InspectorMockupPanel { backlinkSection(badge: .word) }
                InspectorMockupPanel { backlinkSection(badge: .glyph) }
            }
        }
    }

    // MARK: Il menu della riga

    private var rowMenus: some View {
        MockupScene(
            "Il menu della riga. Su una riga semplice «Rendi strutturale», che apre il foglio con "
                + "quella nota già scelta; su una strutturale «Scollega». Le stesse voci sono le "
                + "azioni di accessibilità della riga."
        ) {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                rowWithMenu(
                    InspectorMockupBacklink(
                        title: "Prova banco 12", before: "Decisioni prese in ", after: ", da girare al cliente."
                    ),
                    last: "Rendi strutturale"
                )
                rowWithMenu(
                    InspectorMockupBacklink(
                        title: "Piano prove 2026", before: "- ", after: ": qui si decidono le prove", badge: .word
                    ),
                    last: "Scollega"
                )
            }
        }
    }

    private func rowWithMenu(_ row: InspectorMockupBacklink, last: String) -> some View {
        InspectorMockupPanel {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                row
                LinkMockupMenu(items: [
                    .row("Apri"),
                    .row("Apri nell'altra colonna"),
                    .separator,
                    .row(last, highlighted: true),
                ], width: 200)
                .padding(.leading, theme.spacing(.l))
            }
        }
    }

    private var unlink: some View {
        MockupScene(
            "«Scollega» chiede prima. Toglie il legame da entrambe le note con due scritture "
                + "protette; se la seconda è rifiutata, la prima resta e il messaggio lo dice (§D4)."
        ) {
            LinkMockupSheet(
                width: MockupGalleryView.pairWidth,
                title: "Scollegare «Riunione settimanale» e «Piano prove 2026»?",
                confirm: "Scollega",
                destructive: true
            ) {
                Text("Il legame e i due motivi spariscono da entrambe le note.")
                    .themedText(.caption, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Link non risolti

    private var unresolved: some View {
        MockupScene(
            "LINK NON RISOLTI di questa nota, non più dell'intero vault (quell'elenco diventa una "
                + "vista d'esempio). «Crea nota» apre il compositore nella cartella di questa nota; "
                + "«Vai al link» porta il cursore sulla riga. «Piano.md» non è un titolo valido: "
                + "solo «Vai al link». L'intestazione resta «LINK NON RISOLTI» col conteggio; "
                + "VoiceOver la legge «Link non risolti in questa nota: 3» (§D2). A destra, la "
                + "sezione vuota."
        ) {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                InspectorMockupPanel {
                    InspectorMockupSection(
                        title: "LINK NON RISOLTI", count: "3", spokenLabel: "Link non risolti in questa nota: 3"
                    ) {
                        InspectorMockupUnresolved(target: "Verbale Conti")
                        InspectorMockupUnresolved(target: "Banco 3")
                        InspectorMockupUnresolved(target: "Piano.md", creatable: false)
                    }
                }
                InspectorMockupPanel {
                    InspectorMockupSection(
                        title: "LINK NON RISOLTI", spokenLabel: "Link non risolti in questa nota: 0",
                        emptyText: "nessun link non risolto in questa nota"
                    ) { EmptyView() }
                }
            }
        }
    }

    // MARK: Il foglio del legame strutturale

    private var structuralSheet: some View {
        MockupScene(
            "Il foglio del legame strutturale, aperto da «Rendi strutturale»: la nota della riga è "
                + "già scelta, qui una «Riunione» in Clienti/Nexion, e l'omonima si distingue dalla "
                + "cartella. "
                + "Il motivo del ritorno segue quello scritto, nel testo normale del campo "
                + "(proposta), finché non lo si tocca (§D4)."
        ) {
            LinkMockupSheet(width: Self.sheetWidth, title: "Nota correlata", confirm: "Collega") {
                Text("Un legame strutturale si scrive su entrambe le note, ciascuna con il suo motivo.")
                    .themedText(.caption, color: .textSecondary)
                InspectorMockupField(label: nil, text: "Riunione")
                VStack(alignment: .leading, spacing: 2) {
                    LinkMockupChoiceRow(
                        title: "Riunione", glyph: "doc.text", trailing: "Clienti/Nexion", selected: true
                    )
                    LinkMockupChoiceRow(title: "Riunione", glyph: "doc.text", trailing: "Progetti")
                    LinkMockupChoiceRow(title: "Riunioni di cantiere", glyph: "doc.text", trailing: "Progetti")
                }
                reasons(forward: "stessa commessa Nexion", reverse: "stessa commessa Nexion", following: true)
            }
        }
    }

    private var mirror: some View {
        MockupScene(
            "A sinistra la variante da scegliere: il ritorno che segue in colore tenue, finché non "
                + "lo si modifica. A destra, dopo una modifica: il ritorno non segue più e il "
                + "motivo d'andata può cambiare senza toccarlo."
        ) {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                MockupCell("Segue, in colore tenue", width: Self.mirrorCellWidth, alignment: .leading) {
                    reasons(forward: "stessa commessa Nexion", reverse: "stessa commessa Nexion",
                            following: true, tenuous: true)
                }
                MockupCell("Modificato: non segue più", width: Self.mirrorCellWidth, alignment: .leading) {
                    reasons(forward: "stessa commessa Nexion, serie 40", reverse: "qui si decidono le sue prove",
                            following: false)
                }
            }
        }
    }

    private func reasons(forward: String, reverse: String, following: Bool, tenuous: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            InspectorMockupField(
                label: "Perché «Riunione settimanale» rimanda a «Riunione»", text: forward, caret: following
            )
            InspectorMockupField(
                label: "Perché «Riunione» rimanda a «Riunione settimanale»", text: reverse,
                textColor: tenuous ? .textTertiary : .textPrimary, caret: !following
            )
        }
    }

    // MARK: Dove compare

    private var appearances: some View {
        MockupScene(
            "DOVE COMPARE: le board i cui nodi puntano alla nota e le pratiche che la linkano, in sola "
                + "lettura; ogni riga apre il suo posto. Si chiede col pulsante e mai da sé, perché "
                + "legge ogni board e ogni messaggio: a riposo, durante la lettura, con i risultati "
                + "(una board illeggibile è saltata e contata in nota), senza risultati (§D6)."
        ) {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                HStack(alignment: .top, spacing: theme.spacing(.m)) {
                    InspectorMockupPanel { InspectorMockupAppearances(state: .resting) }
                    InspectorMockupPanel { InspectorMockupAppearances(state: .scanning) }
                }
                HStack(alignment: .top, spacing: theme.spacing(.m)) {
                    InspectorMockupPanel { InspectorMockupAppearances(state: .found) }
                    InspectorMockupPanel { InspectorMockupAppearances(state: .empty) }
                }
            }
        }
    }
}
