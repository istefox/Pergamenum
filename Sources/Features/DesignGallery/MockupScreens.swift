import SwiftUI

// Static compositions of the screens M1 to M5 will build for real. They render from
// the same tokens as production code, so approving one here is approving its look,
// not a picture of it. None of them touch a vault, an index or EventKit.

// MARK: - Editor (M1)

struct EditorMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    Text("Trasmissibilità e rapporto di frequenza")
                        .themedText(.title)

                    frontmatter

                    Text("Il rapporto fra frequenza di eccitazione e frequenza propria decide se un isolatore attenua o amplifica. Sotto radice di due l'inserimento peggiora la situazione.")
                        .themedText(.body)

                    sourceLine("## ", "Note correlate", heading: true)
                    bullet("Curva di trasmissibilità", reason: "fornisce i dati sperimentali")
                    bullet("Scelta del supporto antivibrante", reason: "applica il criterio a un caso reale")

                    sourceLine("## ", "Task", heading: true)
                    task("Rivedere la curva sotto 4 Hz", schedule: ">2026-08-15", state: .open)
                    task("Verificare i dati di targa", schedule: "!2026-08-13", state: .overdue)
                    task("Esportare il grafico", schedule: nil, state: .done)
                }
                .padding(theme.spacing(.l))
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.color(.backgroundPrimary))

            Divider()
            inspector
        }
    }

    private var frontmatter: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach([
                "date: 2026-08-11",
                "tags:",
                "  - type-note",
                "  - topic-vibration-isolation",
                "related:",
                "  - \"[[Curva di trasmissibilità]]\"",
            ], id: \.self) { line in
                Text(line).themedText(.mono, color: .textSecondary)
            }
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }

    /// Source stays visible with style applied, the "Obsidian source mode improved"
    /// level SPEC §5 asks for, rather than hiding the syntax.
    private func sourceLine(_ syntax: String, _ text: String, heading: Bool) -> some View {
        HStack(spacing: 0) {
            Text(syntax).themedText(.mono, color: .textTertiary)
            Text(text).themedText(heading ? .heading : .body)
        }
    }

    private func bullet(_ title: String, reason: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("- ").themedText(.mono, color: .textTertiary)
            Text("[[").themedText(.mono, color: .textTertiary)
            Text(title).themedText(.body, color: .accentPrimary)
            Text("]] — ").themedText(.mono, color: .textTertiary)
            Text(reason).themedText(.body, color: .textSecondary)
        }
    }

    private enum TaskState { case open, overdue, done }

    private func task(_ text: String, schedule: String?, state: TaskState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
            Image(systemName: state == .done ? "checkmark.square" : "square")
                .foregroundStyle(theme.color(state == .done ? .taskDone : .taskOpen))
            Text(text)
                .themedText(.body, color: state == .done ? .taskDone : .textPrimary)
                .strikethrough(state == .done, color: theme.color(.taskDone))
            if let schedule {
                Text(schedule)
                    .themedText(.mono, color: state == .overdue ? .taskOverdue : .taskScheduled)
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            inspectorGroup("BACKLINK", items: [
                "Scelta del supporto antivibrante",
                "20260804 Riunione tecnica",
            ])
            inspectorGroup("TASK COLLEGATI", items: [
                "Preparare la relazione di calcolo",
            ])
            inspectorGroup("LINK NON RISOLTI", items: [
                "Smorzamento viscoso equivalente",
            ])
            Spacer()
        }
        .padding(theme.spacing(.m))
        .frame(width: 260, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
    }

    private func inspectorGroup(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(title).themedText(.caption, color: .textTertiary)
            ForEach(items, id: \.self) { item in
                Text(item).themedText(.body, color: .accentPrimary)
            }
        }
    }
}

// MARK: - Workspace (M2, M3)

struct WorkspaceMockup: View {
    @Environment(\.theme) private var theme

    private static let tools: [(String, String, String)] = [
        ("cursorarrow", "Seleziona", "V"),
        ("note.text", "Nota", "N"),
        ("textformat", "Testo", "T"),
        ("folder", "Cartella", "F"),
        ("photo", "Immagine", "I"),
        ("doc.text", "Documento", "D"),
        ("link", "Link", "L"),
        ("checklist", "To Do", "K"),
        ("rectangle.on.rectangle.slash", "Moduli (v2)", ""),
        ("pencil.tip", "Disegno", "P"),
        ("arrow.up.right", "Freccia", "A"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            Divider()
            HStack(spacing: 0) {
                toolbar
                Divider()
                board
            }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: theme.spacing(.s)) {
            Circle().fill(theme.color(.accentPrimary)).frame(width: 8, height: 8)
            Text("Labs").themedText(.body)
            ForEach(["Workspace", "01 Progetti", "vibrofer-emea"], id: \.self) { segment in
                Text("›").themedText(.body, color: .textTertiary)
                Text(segment).themedText(.body, color: segment == "vibrofer-emea" ? .textPrimary : .textSecondary)
            }
            Spacer()
            Label("Salvato", systemImage: "checkmark.circle")
                .themedText(.caption, color: .textSecondary)
            Image(systemName: "magnifyingglass").foregroundStyle(theme.color(.textSecondary))
            Image(systemName: "gearshape").foregroundStyle(theme.color(.textSecondary))
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
        .background(theme.color(.backgroundPrimary))
    }

    private var toolbar: some View {
        VStack(spacing: theme.spacing(.xs)) {
            ForEach(Array(Self.tools.enumerated()), id: \.offset) { index, tool in
                let selected = index == 0
                let excluded = tool.2.isEmpty
                Image(systemName: tool.0)
                    .frame(width: 30, height: 30)
                    .foregroundStyle(theme.color(excluded ? .textTertiary : (selected ? .onAccent : .textSecondary)))
                    .background(selected ? theme.color(.accentPrimary) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                    .opacity(excluded ? 0.4 : 1)
                    .help(tool.2.isEmpty ? tool.1 : "\(tool.1) (\(tool.2))")
            }
            Spacer()
        }
        .padding(theme.spacing(.xs))
        .frame(width: 44)
        .background(theme.color(.backgroundPrimary))
    }

    private var board: some View {
        ZStack(alignment: .bottomTrailing) {
            theme.color(.canvasBackground)
            grid
            cards
            zoomControls.padding(theme.spacing(.m))
        }
    }

    private var grid: some View {
        Canvas { context, size in
            let step: CGFloat = 24
            var path = Path()
            for x in stride(from: 0, through: size.width, by: step) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: step) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(theme.color(.canvasGrid)), lineWidth: 1)
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                folderCard("02 Rilievi", count: 14)
                documentCard("Trasmissibilità e rapporto di frequenza", words: 812)
                stickyCard("Chiedere a Marco i dati di targa del ventilatore", color: .stickyYellow)
            }
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                pdfCard("Datasheet supporto AV-45", pages: 6)
                emailCard()
                linkCard()
            }
        }
        .padding(theme.spacing(.l))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func folderCard(_ name: String, count: Int) -> some View {
        ThemedCard(padding: .s) {
            HStack(spacing: theme.spacing(.s)) {
                Image(systemName: "folder.fill").foregroundStyle(theme.color(.accentPrimary))
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).themedText(.body)
                    Text("\(count) elementi").themedText(.caption, color: .textTertiary)
                }
            }
        }
        .frame(width: 190)
    }

    private func documentCard(_ title: String, words: Int) -> some View {
        ThemedCard(padding: .s) {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                Label(title, systemImage: "doc.text").themedText(.body).lineLimit(2)
                Text("\(words) parole").themedText(.caption, color: .textTertiary)
            }
        }
        .frame(width: 210)
    }

    private func stickyCard(_ text: String, color: ColorToken) -> some View {
        Text(text)
            .themedText(.body)
            .padding(theme.spacing(.s))
            .frame(width: 170, alignment: .topLeading)
            .background(theme.color(color))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.sticky), style: .continuous))
            .themedShadow(.card)
    }

    private func pdfCard(_ title: String, pages: Int) -> some View {
        ThemedCard(padding: .s) {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.color(.backgroundTertiary))
                    .frame(width: 174, height: 110)
                    .overlay(Image(systemName: "doc.richtext").foregroundStyle(theme.color(.textTertiary)))
                HStack {
                    Text(title).themedText(.caption).lineLimit(1)
                    Spacer()
                    Text("\(pages)p").themedText(.caption, color: .textTertiary)
                }
                .frame(width: 174)
            }
        }
    }

    private func emailCard() -> some View {
        ThemedCard(padding: .s) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Rossi Impianti", systemImage: "envelope").themedText(.body)
                Text("Richiesta offerta supporti").themedText(.caption, color: .textSecondary)
                Text("4 ago 2026").themedText(.caption, color: .textTertiary)
            }
        }
        .frame(width: 190)
    }

    private func linkCard() -> some View {
        ThemedCard(padding: .s) {
            HStack(spacing: theme.spacing(.s)) {
                Image(systemName: "link").foregroundStyle(theme.color(.accentPrimary))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Scheda in DEVONthink").themedText(.body).lineLimit(1)
                    Text("x-devonthink-item://").themedText(.caption, color: .textTertiary)
                }
            }
        }
        .frame(width: 210)
    }

    private var zoomControls: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "minus")
            Text("100%").themedText(.caption)
            Image(systemName: "plus")
            Divider().frame(height: 12)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .foregroundStyle(theme.color(.textSecondary))
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.surfaceRaised))
        .clipShape(Capsule())
        .themedShadow(.card)
    }
}

// MARK: - Today (M5)

struct TodayMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    HStack {
                        Text("20260811").themedText(.title)
                        Text("martedì 11 agosto").themedText(.body, color: .textSecondary)
                        Spacer()
                        Image(systemName: "chevron.left")
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(theme.color(.textSecondary))

                    references
                    Text("Sopralluogo in reparto stampaggio. La pressa 4 trasmette al solaio più di quanto previsto: rifare il calcolo con i dati di targa reali.")
                        .themedText(.body)
                }
                .padding(theme.spacing(.l))
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.color(.backgroundPrimary))

            Divider()
            timeline
        }
    }

    /// Scheduling links, never copies: the task lives in its own note and shows up
    /// here by reference (SPEC §7.3).
    private var references: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                Text("PIANIFICATI OGGI").themedText(.caption, color: .textTertiary)
                reference("Rivedere la curva sotto 4 Hz", origin: "Trasmissibilità e rapporto di frequenza", overdue: false)
                reference("Verificare i dati di targa", origin: "20260804 Riunione tecnica", overdue: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reference(_ text: String, origin: String, overdue: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
            Image(systemName: "square").foregroundStyle(theme.color(overdue ? .taskOverdue : .taskOpen))
            Text(text).themedText(.body)
            Text("↗ \(origin)").themedText(.caption, color: .textTertiary)
        }
    }

    private var timeline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(6..<20) { hour in
                    HStack(alignment: .top, spacing: theme.spacing(.s)) {
                        Text(String(format: "%02d:00", hour))
                            .themedText(.caption, color: .textTertiary)
                            .frame(width: 40, alignment: .trailing)
                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(theme.color(.borderSubtle)).frame(height: 1)
                            if hour == 9 { block("Sopralluogo pressa 4", token: .accentMuted) }
                            if hour == 14 { block("Calcolo trasmissibilità", token: .stickyBlue) }
                        }
                    }
                    .frame(height: 34, alignment: .top)
                }
            }
            .padding(theme.spacing(.s))
        }
        .frame(width: 260)
        .background(theme.color(.backgroundSecondary))
    }

    private func block(_ title: String, token: ColorToken) -> some View {
        Text(title)
            .themedText(.caption)
            .padding(.horizontal, theme.spacing(.xs))
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(token))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}

// MARK: - Tasks (M4)

struct TasksMockup: View {
    @Environment(\.theme) private var theme
    @State private var view = "Oggi"

    private static let views = ["Inbox", "Oggi", "Prossimi", "Per progetto", "Tutti"]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                Text("ATTIVITÀ").themedText(.caption, color: .textTertiary)
                ForEach(Self.views, id: \.self) { item in
                    HStack {
                        Text(item).themedText(.body, color: item == view ? .textPrimary : .textSecondary)
                        Spacer()
                        Text(item == "Oggi" ? "4" : "").themedText(.caption, color: .textTertiary)
                    }
                    .padding(.horizontal, theme.spacing(.s))
                    .padding(.vertical, theme.spacing(.xs))
                    .background(item == view ? theme.color(.accentMuted) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                    .onTapGesture { view = item }
                }
                Spacer()
            }
            .padding(theme.spacing(.s))
            .frame(width: 190, alignment: .leading)
            .background(theme.color(.backgroundSecondary))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    group("In ritardo", [
                        MockTask(
                            text: "Verificare i dati di targa", date: "!2026-08-08",
                            isOverdue: true, source: "20260804 Riunione tecnica"
                        ),
                    ])
                    group("Oggi", [
                        MockTask(
                            text: "Rivedere la curva sotto 4 Hz", date: ">2026-08-11",
                            isOverdue: false, source: "Trasmissibilità e rapporto di frequenza"
                        ),
                        MockTask(
                            text: "Rispondere a Rossi Impianti", date: ">2026-08-11",
                            isOverdue: false, source: "00 Inbox/Capture"
                        ),
                    ])
                    group("Completati", [
                        MockTask(
                            text: "Esportare il grafico", date: "@done(2026-08-11)",
                            isOverdue: false, source: "Curva di trasmissibilità"
                        ),
                    ])
                }
                .padding(theme.spacing(.l))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.color(.backgroundPrimary))
        }
    }

    /// One row of the mockup, named rather than a four-member tuple: `row.2` says
    /// nothing about what it holds.
    struct MockTask: Identifiable {
        var id: String { text }
        var text: String
        var date: String
        var isOverdue: Bool
        var source: String
    }

    private func group(_ title: String, _ rows: [MockTask]) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(title).themedText(.heading)
            ForEach(rows) { row in
                ThemedCard(padding: .s) {
                    HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
                        Image(systemName: title == "Completati" ? "checkmark.square" : "square")
                            .foregroundStyle(theme.color(row.isOverdue ? .taskOverdue : .taskOpen))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.text)
                                .themedText(.body, color: title == "Completati" ? .taskDone : .textPrimary)
                            Text("↗ \(row.source)").themedText(.caption, color: .textTertiary)
                        }
                        Spacer()
                        Text(row.date)
                            .themedText(.mono, color: row.isOverdue ? .taskOverdue : .taskScheduled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
