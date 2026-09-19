import SwiftUI

// Static compositions of the screens M1 to M5 will build for real. They render from
// the same tokens as production code, so approving one here is approving its look,
// not a picture of it. None of them touch a vault, an index or EventKit.
// One file per screen since PG-148 (ADR-0051); they shared nothing but this note.

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
