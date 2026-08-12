import SwiftUI

/// The two Aiuto entries of SPEC §10.
///
/// The text is written here rather than opening the repository documents: the app has
/// to be usable on a Mac where the harness-system checkout is not present, and a Help
/// menu that points at a file the user may not have is a Help menu that fails exactly
/// when it is needed.
struct HelpSheet: View {
    @Environment(\.theme) private var theme
    let topic: Topic
    let onClose: () -> Void

    enum Topic {
        case taskSyntax
        case conventions

        var title: String {
            switch self {
            case .taskSyntax: "Guida sintassi task"
            case .conventions: "Convenzioni harness"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(topic.title).themedText(.title)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    ForEach(sections, id: \.heading) { section in
                        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                            Text(section.heading).themedText(.heading)
                            ForEach(section.rows, id: \.syntax) { row in
                                HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
                                    Text(row.syntax)
                                        .themedText(.mono, color: .accentPrimary)
                                        .frame(width: 190, alignment: .leading)
                                        .textSelection(.enabled)
                                    Text(row.meaning)
                                        .themedText(.caption, color: .textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Chiudi", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 620, height: 520)
        .background(theme.color(.surfaceCard))
    }

    private struct Section {
        var heading: String
        var rows: [(syntax: String, meaning: String)]
    }

    private var sections: [Section] {
        switch topic {
        case .taskSyntax: Self.taskSyntax
        case .conventions: Self.conventions
        }
    }

    /// SPEC §7.1, ASCII only.
    private static let taskSyntax: [Section] = [
        Section(heading: "Stato", rows: [
            ("- [ ] testo", "task aperto"),
            ("- [x] testo", "completato"),
            ("- [-] testo", "annullato"),
        ]),
        Section(heading: "Date", rows: [
            (">2026-08-20", "pianificato per quel giorno"),
            ("!2026-08-25", "scadenza"),
            ("@done(2026-08-19)", "quando è stato completato"),
            ("@remind(2026-08-20 09:00)", "notifica locale"),
        ]),
        Section(heading: "Collegamenti", rows: [
            ("#project-nome", "assegna il task a un progetto"),
            ("[[Nota]]", "collega una nota: cliccabile nelle viste task"),
            ("[[Board.canvas]]", "collega una board"),
        ]),
        Section(heading: "Scorciatoie", rows: [
            ("Cmd+Invio", "completa o riapri"),
            ("Cmd+0 / 1 / 2 / 3", "oggi, domani, +2 giorni, settimana prossima"),
            ("Cmd+Maiusc+N", "cattura rapida in 00 Inbox/Capture.md"),
        ]),
    ]

    /// The rules the linter checks, in the words of the harness-system documents.
    private static let conventions: [Section] = [
        Section(heading: "Nomi dei file (naming.md 4.6)", rows: [
            ("Titolo della nota.md", "il titolo è il nome del file, senza suffissi di versione"),
            ("20260811.md", "daily note: YYYYMMDD, mai con trattini"),
            ("60 caratteri", "lunghezza massima del titolo"),
        ]),
        Section(heading: "Frontmatter (schema chiuso)", rows: [
            ("date", "obbligatoria, YYYY-MM-DD"),
            ("tags", "obbligatoria, lista a blocco"),
            ("aliases", "facoltativa, servono la ricerca e mai il link"),
            ("related", "facoltativa, allineata a ## Note correlate"),
        ]),
        Section(heading: "Tag (tag.md)", rows: [
            ("client, competitor, project", "famiglie aperte"),
            ("type, topic, status, area, source", "famiglie chiuse: solo valori a vocabolario"),
            ("#area-training", "minuscolo, parole separate da trattino"),
        ]),
        Section(heading: "Wikilink (wikilink.md)", rows: [
            ("[[Titolo esatto]]", "W-01: il primo segmento è il titolo, mai un alias"),
            ("## Note correlate", "W-04: ogni legame strutturale ha un motivo"),
            ("massimo 5", "W-09: oltre, la nota va spezzata o serve un indice"),
        ]),
    ]
}
