import SwiftUI

// Static compositions of the screens M1 to M5 will build for real. They render from
// the same tokens as production code, so approving one here is approving its look,
// not a picture of it. None of them touch a vault, an index or EventKit.
// One file per screen since PG-148 (ADR-0051); they shared nothing but this note.

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
