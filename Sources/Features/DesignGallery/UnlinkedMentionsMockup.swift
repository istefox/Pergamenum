import SwiftUI

// MARK: - Le menzioni non linkate (M10)

/// The last of the three visual elements ADR-0012 says to draw before building (the tab bar and
/// the tag browser were the other two), and the screen for D9.
///
/// The decision D9 already took is the one this has to make visible: **the mentions are computed
/// on request and never on opening a note**. Finding every note whose text contains this note's
/// title or an alias is a full-vault text scan - the same read loop a search runs - and doing it
/// every time a note opens would put that cost on the gesture people make most. It is also not
/// cached: `IndexCache`'s schema version is spent by M11 (ADR-0009 §D2).
///
/// That is why the section has a button in it. A panel that fills itself is the thing D9 rules
/// out, so the resting state has to say what it will do and wait to be asked.
///
/// Three choices are put here for approval:
///
/// 1. **In the inspector, under BACKLINK.** The two answer the same question a step apart - who
///    points here, and who talks about this without pointing. Anywhere else and the comparison
///    costs a look somewhere else.
/// 2. **A row is the note and the line the mention falls on**, with the mention itself in
///    semibold. A list of titles would make you open each one to find out why it is there.
/// 3. **A row opens the note and nothing else.** No «Collega» button that writes `[[…]]` into
///    the other note: that is a write into a note you are not looking at, and the one write
///    guardrail this app has is that you see what changes. It can be added later on its own
///    reasoning; it is not part of computing the mentions.
///
///    *Amended by ADR-0084 §D3 (N3):* a row gains «Collega», because the diff it opens is the
///    guardrail the refusal asked for: nothing is written before the person has seen the exact
///    bytes that will land, so the condition is met rather than waived. The row itself still
///    opens the note. The N3 half is drawn at the bottom of the page.
///
/// Everything here is literal. No controller, no index, no vault.
struct UnlinkedMentionsMockup: View {
    @Environment(\.theme) private var theme

    /// The inspector at the width it actually has in `VaultBrowser` (ideal 230, max 320).
    /// `InspectorLinksMockup` draws at this width too, so the two inspector pages cannot disagree.
    static let inspectorWidth: CGFloat = 260
    var body: some View {
        MockupPage {
            inPlace
            states
            withResults
            LinkMentionScenes()
        }
    }

    // MARK: Dove sta

    /// The whole inspector column, because what is being approved is the section's place in it
    /// rather than the section on its own.
    private var inPlace: some View {
        MockupScene("Nell'inspector, sotto i backlink: chi punta qui, e chi ne parla senza puntare.") {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                starRow
                group("BACKLINK") {
                    link("Scelta del supporto antivibrante")
                    link("20260804 Riunione tecnica")
                }
                mentions(.resting)
                group("TASK COLLEGATI") {
                    Text("nessun task linka questa nota").themedText(.caption, color: .textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(theme.spacing(.m))
            .frame(width: Self.inspectorWidth, alignment: .leading)
            .background(theme.color(.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        }
    }

    private var starRow: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "star").themedText(.body, color: .textTertiary)
            Text("Aggiungi alle preferite").themedText(.caption, color: .textSecondary)
            Spacer()
        }
    }

    // MARK: Gli stati

    private var states: some View {
        HStack(alignment: .top, spacing: theme.spacing(.m)) {
            MockupScene("Durante la scansione.") {
                panel { mentions(.scanning) }
            }
            MockupScene("Nessuna menzione: lo dice, non lascia il vuoto.") {
                panel { mentions(.empty) }
            }
        }
    }

    private var withResults: some View {
        MockupScene("Con i risultati: la nota, e la riga in cui il titolo compare senza essere un link.") {
            panel(width: Self.inspectorWidth) { mentions(.found) }
        }
    }

    private func panel(width: CGFloat = MockupGalleryView.pairWidth, @ViewBuilder _ content: () -> some View)
        -> some View {
        content()
            .padding(theme.spacing(.m))
            .frame(width: width, alignment: .leading)
            .background(theme.color(.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }

    // MARK: La sezione

    private enum State { case resting, scanning, empty, found }

    @ViewBuilder
    private func mentions(_ state: State) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                Text("MENZIONI NON LINKATE").themedText(.caption, color: .textTertiary)
                Spacer()
                // The count where the answer is, and only once there is one: a «0» before the
                // scan would be a number nobody has computed.
                if state == .found {
                    Text("3").themedText(.caption, color: .textTertiary)
                }
            }

            switch state {
            case .resting:
                // Says what it will do and waits. A panel that fills itself is exactly what D9
                // rules out: this is a full-vault text scan, not a lookup in the index.
                Text("Cerca il titolo di questa nota nel testo delle altre.")
                    .themedText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                button("Cerca nel vault", systemImage: "magnifyingglass")
            case .scanning:
                HStack(spacing: theme.spacing(.xs)) {
                    ProgressView().controlSize(.small)
                    Text("Scansione delle note…").themedText(.caption, color: .textSecondary)
                }
            case .empty:
                Text("Nessuna nota nomina questa senza linkarla.")
                    .themedText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                button("Cerca di nuovo", systemImage: "arrow.clockwise")
            case .found:
                row("20260805 Sopralluogo pressa 4",
                    before: "Rifare il calcolo con la ", mention: "curva di trasmissibilità",
                    after: " reale.")
                row("Scelta del supporto antivibrante",
                    before: "Il criterio nasce dalla ", mention: "curva di trasmissibilità",
                    after: ", non dalla rigidezza.")
                row("00 Inbox/Appunti fiera",
                    before: "Chiedere se hanno la ", mention: "curva di trasmissibilità",
                    after: " a catalogo.")
                button("Cerca di nuovo", systemImage: "arrow.clockwise")
            }
        }
    }

    /// A note and the line the mention falls on. Titles alone would make you open each one to
    /// find out why it is in the list.
    private func row(_ title: String, before: String, mention: String, after: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).themedText(.body, color: .accentPrimary).lineLimit(1)
            Text("\(before)\(Text(mention).fontWeight(.semibold))\(after)")
                .themedText(.caption, color: .textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func button(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .themedText(.caption, color: .accentPrimary)
            .padding(.top, 2)
    }

    private func group(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(title).themedText(.caption, color: .textTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func link(_ title: String) -> some View {
        Text(title).themedText(.body, color: .accentPrimary).lineLimit(1)
    }
}

// MARK: - «Collega» (N3)

/// The N3 half of the page (ADR-0084 §D3, SPEC R-26): «Collega» on a row, and the sheet that shows
/// the diff of the exact bytes before anything is written. The diff is the real `DiffView`, fed a
/// literal unified diff in the shape `UnifiedDiff.between` produces.
private struct LinkMentionScenes: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.l)) { scenes }
    }

    @ViewBuilder
    private var scenes: some View {
        MockupScene(
            "N3. Ogni riga guadagna «Collega»; la riga stessa apre ancora la nota. «Collega» non "
                + "scrive: apre il confronto."
        ) {
            panel {
                section {
                    row("Prova banco", before: "", mention: "Curva di trasmissibilità", after: " misurata a 20 °C.")
                    row("Scelta del supporto antivibrante",
                        before: "Il criterio nasce dalla ", mention: "curva di trasmissibilità",
                        after: ", non dalla rigidezza.")
                    row("00 Inbox/Appunti fiera", before: "Chiedere la ", mention: "curva T", after: " a catalogo.")
                }
            }
        }
        MockupScene(
            "Il foglio di conferma: il confronto dei byte che verranno scritti, «Collega» come "
                + "pulsante predefinito. Il testo coincide col titolo, quindi «[[Curva di trasmissibilità]]»."
        ) {
            sheet(diff: [
                " ## Misure",
                "-Curva di trasmissibilità misurata a 20 °C.",
                "+[[Curva di trasmissibilità]] misurata a 20 °C.",
                " Da rifare a 60 °C con il carico reale.",
            ], header: "@@ -3,3 +3,3 @@")
        }
        MockupScene(
            "Una menzione trovata per alias: si scrive «[[Curva di trasmissibilità|curva T]]», così "
                + "la frase si legge come prima e il link punta al titolo, che è ciò che l'indice "
                + "risolve. Lo stesso per una menzione che differisce solo per maiuscole o accenti."
        ) {
            sheet(path: "00 Inbox/Appunti fiera.md", diff: [
                " - Stand 4B, referente Bassi",
                "-Chiedere la curva T a catalogo.",
                "+Chiedere la [[Curva di trasmissibilità|curva T]] a catalogo.",
            ], header: "@@ -7,2 +7,2 @@", title: "Collegare «Curva di trasmissibilità» in «Appunti fiera»?")
        }
        MockupScene(
            "La nota è cambiata fra il confronto e il clic: la scrittura è rifiutata, il confronto "
                + "si rifà sul testo nuovo e il foglio lo dice. Si conferma di nuovo."
        ) {
            sheet(diff: [
                " ## Misure",
                "-Curva di trasmissibilità misurata a 20 °C e a 40 °C.",
                "+[[Curva di trasmissibilità]] misurata a 20 °C e a 40 °C.",
                " Da rifare a 60 °C con il carico reale.",
            ], header: "@@ -3,3 +3,3 @@", movedOn: true)
        }
        MockupScene(
            "Niente da collegare: il nome non c'è più, o nel frattempo è arrivato un link. La riga "
                + "lascia il posto a una frase e sparisce alla prossima ricerca."
        ) {
            panel {
                section {
                    Text("«Prova banco» non nomina più questa nota, o la linka già: niente da collegare.")
                        .themedText(.caption, color: .textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                    row("Scelta del supporto antivibrante",
                        before: "Il criterio nasce dalla ", mention: "curva di trasmissibilità",
                        after: ", non dalla rigidezza.")
                }
            }
        }
    }

    // MARK: The pieces

    private func panel(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(theme.spacing(.m))
            .frame(width: UnlinkedMentionsMockup.inspectorWidth, alignment: .leading)
            .background(theme.color(.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }

    private func section(@ViewBuilder _ rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                Text("MENZIONI NON LINKATE").themedText(.caption, color: .textTertiary)
                Spacer()
                Text("3").themedText(.caption, color: .textTertiary)
            }
            rows()
        }
    }

    /// The approved row (title, the line, the mention in semibold) with «Collega» trailing on its
    /// title line.
    private func row(_ title: String, before: String, mention: String, after: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: theme.spacing(.xs)) {
                Text(title).themedText(.body, color: .accentPrimary).lineLimit(1)
                Spacer(minLength: theme.spacing(.xs))
                Text("Collega")
                    .themedText(.caption, color: .accentPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                            .fill(theme.color(.backgroundTertiary))
                    )
            }
            Text("\(before)\(Text(mention).fontWeight(.semibold))\(after)")
                .themedText(.caption, color: .textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sheet(
        path: String = "Prova banco.md", diff: [String], header: String,
        title: String = "Collegare «Curva di trasmissibilità» in «Prova banco»?", movedOn: Bool = false
    ) -> some View {
        // `RelatedLinkSheet`'s width, the other sheet that writes a link; wide enough for the
        // diff's mono lines, which `DiffView` cuts at one line each.
        LinkMockupSheet(width: InspectorLinksMockup.sheetWidth, title: title, confirm: "Collega") {
            if movedOn {
                Label("La nota è cambiata: il confronto è stato aggiornato", systemImage: "arrow.triangle.2.circlepath")
                    .themedText(.caption, color: .textSecondary)
            }
            DiffView(path: path, diff: (["--- a/\(path)", "+++ b/\(path)", header] + diff).joined(separator: "\n"))
        }
    }
}
