import SwiftUI

/// The "Vai a data" sheet of the Calendario menu.
///
/// The month is the app's own calendar, the one the task panels use: SwiftUI's
/// graphical `DatePicker` drew `Aug 2026` and `Mo Tu We` in system blue inside an
/// interface that is Italian and themed everywhere else, and no token could reach it.
struct DayDatePicker: View {
    @Environment(\.theme) private var theme
    let controller: DayController

    @State private var chosen: CalendarDate?
    @State private var typed = ""

    private var day: CalendarDate { chosen ?? controller.day }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Vai a data").themedText(.title)

            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.color(.textTertiary))
                TextField("Data", text: $typed)
                    .textFieldStyle(.plain)
                    .font(theme.font(.body))
                    .accessibilityIdentifier("go-to-date-field")
                    .onChange(of: typed) { _, now in
                        if let parsed = DateEntry.parse(now, today: .today) { chosen = parsed }
                    }
                    .onSubmit(go)
            }
            .padding(theme.spacing(.s))
            .background(theme.color(.surfaceSunken))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))

            MonthCalendar(selection: Binding(get: { day }, set: { chosen = $0 }), today: .today)

            HStack {
                Spacer()
                Button("Annulla") { controller.isChoosingDate = false }
                    .keyboardShortcut(.cancelAction)
                Button("Vai", action: go)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("go-to-date-confirm")
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 360)
        .background(theme.color(.surfaceCard))
        // Starts on the day being shown rather than on today: "vai a data" from the
        // 14th usually means somewhere near the 14th.
        .onAppear { chosen = controller.day }
    }

    private func go() {
        controller.show(day)
        controller.isChoosingDate = false
    }
}
