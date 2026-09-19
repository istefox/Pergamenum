import SwiftUI

// Static compositions of the screens M1 to M5 will build for real. They render from
// the same tokens as production code, so approving one here is approving its look,
// not a picture of it. None of them touch a vault, an index or EventKit.
// One file per screen since PG-148 (ADR-0051); they shared nothing but this note.

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
