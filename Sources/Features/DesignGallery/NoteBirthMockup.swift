import SwiftUI

// MARK: - Nascita di una nota (N4)

/// How a note is born and filed, before it is built (ADR-0085, ADR-0086, SPEC R-01, R-04, R-11 to
/// R-14, R-16): the «Da classificare» pane, the «Classifica…» sheet on a note and on a scheda, the
/// composer's sheet host («Documento», «Estrai»), the half-done extraction, and the creation toast.
///
/// **Variants, as built.** Gate M was not held as a separate PR for this milestone (the plan's
/// Task 1); the variants the code adopts are recorded here instead, and the label reads approved:
///
/// - 4a: no count badge on the sidebar row (the pane's own header carries the count, and a
///   `.badge` is one more thing that must sit before `.tag`); the symbol is `tray`.
/// - 4b: list only, no frontmatter preview column; the preview lives in «Classifica…».
/// - 4c-4e: as drawn below, one form per subject, the toast at constant height.
///
/// Everything here is literal. No controller, no index, no vault.
struct NoteBirthMockup: View {
    @Environment(\.theme) private var theme

    /// The app sidebar's width as drawn: two of them side by side fit the row.
    static let sidebarWidth: CGFloat = 220
    /// The pane drawn at the full row.
    static let paneWidth: CGFloat = MockupGalleryView.rowWidth
    /// The real sheets' width (`ClassificaSheet`, `NoteClassificaForm`).
    static let sheetWidth: CGFloat = 520
    /// The toast's one height, with or without its refusal sentence: the built strip's.
    static let toastHeight: CGFloat = CreationUndoStrip.height

    var body: some View {
        MockupPage {
            sidebar
            pane
            emptyPane
            classifyNote
            classifyScheda
            composerSheets
            halfDone
            toast
        }
    }

    // MARK: 4a, 4b

    private var sidebar: some View {
        MockupScene(
            "4a. LAVORO: «Da classificare» subito dopo «Attività», Ctrl+Cmd+I. Nessun contatore sulla "
                + "riga; il conteggio è nell'intestazione del pannello."
        ) {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                NoteBirthMockupSidebar()
                NoteBirthMockupSidebar(selected: "Attività")
            }
        }
    }

    private var pane: some View {
        MockupScene(
            "4b. Il pannello: le note con status-inbox, dalla più recente; una scheda del Contenitore "
                + "porta il simbolo del documento. Il filtro per cartella mostra i conteggi."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                paneHeader(count: "4 note", filter: "Tutte le cartelle")
                NoteBirthMockupRow(title: "Idea per il campionario", folder: "00 Inbox", date: "3 ott 2026", isSelected: true)
                NoteBirthMockupRow(title: "Telefonata Nexion", folder: "00 Inbox", date: "2 ott 2026")
                NoteBirthMockupRow(title: "20261001 Fattura", folder: "Contenitore/2026", date: "1 ott 2026", isScheda: true)
                NoteBirthMockupRow(title: "Appunti riunione", folder: "Eventi", date: "1 ott 2026")
            }
            .frame(width: Self.paneWidth, alignment: .leading)
            .background(theme.color(.backgroundPrimary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        }
    }

    private var emptyPane: some View {
        MockupScene("4b. Vuoto: il filtro sparisce, resta la frase.") {
            VStack(spacing: theme.spacing(.s)) {
                Image(systemName: "tray").font(theme.font(.iconDisplay)).foregroundStyle(theme.color(.textTertiary))
                Text("Niente da classificare").themedText(.title)
                Text("Le note nate senza argomento arrivano qui con status-inbox.")
                    .themedText(.body, color: .textSecondary)
            }
            .padding(theme.spacing(.l))
            .frame(width: Self.paneWidth)
            .background(theme.color(.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        }
    }

    private func paneHeader(count: String, filter: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Da classificare").themedText(.title)
                Text(count).themedText(.caption, color: .textSecondary)
            }
            Spacer()
            Text("\(filter) ▾").themedText(.caption, color: .textSecondary)
        }
        .padding(theme.spacing(.m))
    }

    // MARK: 4c

    private var classifyNote: some View {
        MockupScene(
            "4c. «Classifica…» su una nota: argomenti con completamento e rifiuto, cartella facoltativa, "
                + "anteprima con status-inbox barrato e «N di 7 tag». Nota con modifiche: «Salva e classifica»."
        ) {
            NoteBirthMockupSheet(title: "Classifica «Idea per il campionario»") {
                NoteBirthMockupLabel(text: "ARGOMENTI · OBBLIGATORIO")
                HStack(spacing: theme.spacing(.xs)) {
                    NoteBirthMockupChip(tag: "topic-campionario", added: true)
                    Text("type-fattura").themedText(.caption, color: .textSecondary)
                }
                Text("type-fattura non si sceglie qui: type-* lo assegna la nota.").themedText(.caption, color: .taskOverdue)
                NoteBirthMockupLabel(text: "CARTELLA · FACOLTATIVA")
                Text("03 Risorse ▾").themedText(.body)
                NoteBirthMockupLabel(text: "RISULTATO")
                HStack(spacing: theme.spacing(.xs)) {
                    NoteBirthMockupChip(tag: "type-note")
                    NoteBirthMockupChip(tag: "status-inbox", struck: true)
                    NoteBirthMockupChip(tag: "topic-campionario", added: true)
                    Spacer()
                    Text("2 di 7 tag").themedText(.caption, color: .textSecondary)
                }
                NoteBirthMockupButtons(titles: ["Annulla", "Salva e classifica"])
            }
        }
    }

    private var classifyScheda: some View {
        MockupScene("4c. Su una scheda: nessuna cartella (resta nel Contenitore), il tipo facoltativo.") {
            NoteBirthMockupSheet(title: "Classifica «20261001 Fattura»") {
                NoteBirthMockupLabel(text: "ARGOMENTI · OBBLIGATORIO")
                NoteBirthMockupChip(tag: "topic-fornitori", added: true)
                NoteBirthMockupLabel(text: "TIPO · FACOLTATIVO")
                Text("type-fattura ▾").themedText(.body)
                NoteBirthMockupButtons(titles: ["Annulla", "Classifica"])
            }
        }
    }

    // MARK: 4d, 4e

    private var composerSheets: some View {
        MockupScene(
            "4d. Il compositore in un foglio. «Documento» del Workspace: cartella fissa, menu dei modelli. "
                + "«Estrai»: anteprima della selezione, titolo dalla prima riga, nessun modello."
        ) {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                NoteBirthMockupSheet(title: "Nuovo documento") {
                    Text("Titolo: Verbale prova banco").themedText(.body)
                    Text("Cartella: Progetti/Banco").themedText(.caption, color: .textSecondary)
                    Text("Modello: Riunione ▾").themedText(.body)
                    HStack(spacing: theme.spacing(.xs)) {
                        NoteBirthMockupChip(tag: "client-nexion")
                        NoteBirthMockupChip(tag: "project-banco")
                        Text("area-xyz non è nel vocabolario.").themedText(.caption, color: .taskOverdue)
                    }
                    NoteBirthMockupButtons(titles: ["Annulla", "Crea"])
                }
                NoteBirthMockupSheet(title: "Estrai in una nota") {
                    Text("Prima riga del pensiero\nSeconda riga").themedText(.body, color: .textSecondary)
                    Text("Titolo: Prima riga del pensiero").themedText(.body)
                    Text("La nota viene salvata prima di estrarre.").themedText(.caption, color: .textSecondary)
                    NoteBirthMockupButtons(titles: ["Annulla", "Salva ed estrai"])
                }
            }
        }
    }

    private var halfDone: some View {
        MockupScene("4d. A metà: la nota nuova resta, la sorgente è stata rifiutata; il foglio nomina entrambe.") {
            NoteBirthMockupSheet(title: "Estrai in una nota") {
                Text("Creata «Altro/Prima riga del pensiero.md».").themedText(.body)
                Text("«Progetti/Sorgente.md» non aggiornata: la nota è cambiata nel frattempo.")
                    .themedText(.caption, color: .taskOverdue)
                NoteBirthMockupButtons(titles: ["Chiudi"])
            }
        }
    }

    private var toast: some View {
        MockupScene("4e. In fondo all'editor, sempre alla stessa altezza, anche con il rifiuto.") {
            HStack(spacing: theme.spacing(.m)) {
                NoteBirthMockupToast()
                NoteBirthMockupToast(refusal: "Nota modificata dopo la creazione: non eliminata.")
            }
        }
    }
}
