import AppKit
import SwiftUI

/// The composer of a diary entry: what it was, when, how long, and what came of it.
///
/// The title uses `ComposerTextField` rather than SwiftUI's: the colour picker and the
/// time menus take focus and give it back, and SwiftUI restores focus to a `TextField`
/// by selecting all of it, so the next keystroke would replace what had been typed
/// (ADR-0003 §D5).
struct DiaryEntrySheet: View {
    @Environment(\.theme) private var theme

    @Bindable var controller: DiaryController

    /// Bumped once when the sheet appears, which puts the caret in the title.
    @State private var focusRequest = 0

    private var draft: Binding<DiaryController.DiaryDraft> {
        Binding(
            get: { controller.draft ?? Self.placeholder },
            set: { controller.draft = $0 }
        )
    }

    private var entry: Binding<DiaryEntry> { draft.entry }

    /// What the binding reads while the sheet is being dismissed and the draft is
    /// already nil. Never seen: SwiftUI asks for it once on the way out.
    private static let placeholder = DiaryController.DiaryDraft(
        entry: DiaryEntry(startMinutes: 9 * 60, durationMinutes: 60, title: ""),
        isExisting: false
    )

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(draft.wrappedValue.isExisting ? "Modifica blocco" : "Nuovo blocco")
                .themedText(.title)
            Text("\(controller.day.italianForm) · \(entry.wrappedValue.timeText)")
                .themedText(.caption, color: .textSecondary)
                .accessibilityIdentifier("diary-sheet-range")

            titleField
            times
            colours
            noteField

            HStack(spacing: theme.spacing(.s)) {
                if draft.wrappedValue.isExisting {
                    Button("Elimina", role: .destructive) {
                        controller.remove(entry.wrappedValue)
                        controller.cancelDraft()
                    }
                    .accessibilityIdentifier("diary-sheet-delete")
                }
                Spacer()
                Button("Annulla") { controller.cancelDraft() }
                    .keyboardShortcut(.cancelAction)
                Button("Salva") { controller.commitDraft() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("diary-sheet-save")
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 480)
        .background(theme.color(.surfaceCard))
        .onAppear { focusRequest += 1 }
        // No identifier on this stack. SwiftUI hands a container's identifier down to
        // every child that is drawn inside it, so naming the sheet renamed the title
        // field, the pickers and both buttons to "diary-sheet" - and nothing in it
        // could be found by the name it was given.
    }

    // MARK: Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("TITOLO").themedText(.caption, color: .textTertiary)
            ComposerTextField(
                text: entry.title,
                placeholder: "Cosa è successo in questo tempo",
                font: theme.nsFont(.body),
                color: NSColor(theme.color(.textPrimary)),
                focusRequest: focusRequest,
                identifier: "diary-sheet-title",
                onSubmit: { controller.commitDraft() }
            )
            .padding(theme.spacing(.xs))
            .background(theme.color(.surfaceSunken))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        }
    }

    /// Start and length, both on the ten-minute grid the diary is cut to.
    private var times: some View {
        HStack(alignment: .bottom, spacing: theme.spacing(.m)) {
            labelled("INIZIO") {
                HStack(spacing: theme.spacing(.xs)) {
                    Picker("Ora", selection: hourBinding) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d", hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 72)
                    .accessibilityIdentifier("diary-sheet-hour")

                    Picker("Minuti", selection: minuteBinding) {
                        ForEach(DiaryGrid.minuteMarks, id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 72)
                    .accessibilityIdentifier("diary-sheet-minute")
                }
            }

            labelled("DURATA") {
                Picker("Durata", selection: entry.durationMinutes) {
                    ForEach(DiaryGrid.durations, id: \.self) { minutes in
                        Text(durationLabel(minutes)).tag(minutes)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .accessibilityIdentifier("diary-sheet-duration")
            }

            labelled("FINE") {
                Text(entry.wrappedValue.endText)
                    .themedText(.body, color: .textSecondary)
                    .padding(.bottom, 4)
            }
            Spacer(minLength: 0)
        }
    }

    private var colours: some View {
        labelled("COLORE") {
            HStack(spacing: theme.spacing(.xs)) {
                ForEach(DiaryColour.allCases) { colour in
                    Button { entry.colour.wrappedValue = colour } label: {
                        RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                            .fill(theme.color(colour.token))
                            .frame(width: 34, height: 22)
                            .overlay {
                                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                                    .strokeBorder(
                                        theme.color(isChosen(colour) ? .accentPrimary : .borderSubtle),
                                        lineWidth: isChosen(colour) ? 2 : 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help(colour.label)
                    .accessibilityIdentifier("diary-sheet-colour-\(colour.rawValue)")
                }
            }
        }
    }

    private var noteField: some View {
        labelled("NOTA") {
            TextEditor(text: entry.note)
                .font(theme.font(.body))
                .foregroundStyle(theme.color(.textPrimary))
                .scrollContentBackground(.hidden)
                .padding(theme.spacing(.xs))
                .frame(height: 120)
                .background(theme.color(.surfaceSunken))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                .accessibilityIdentifier("diary-sheet-note")
        }
    }

    private func labelled<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(label).themedText(.caption, color: .textTertiary)
            content()
        }
    }

    // MARK: Bindings

    /// The hour and the minutes are edited apart and put back together, so neither
    /// picker can produce a time that is not on the grid.
    private var hourBinding: Binding<Int> {
        Binding(
            get: { entry.wrappedValue.startMinutes / 60 },
            set: { entry.startMinutes.wrappedValue = $0 * 60 + entry.wrappedValue.startMinutes % 60 }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { DiaryGrid.snapDown(entry.wrappedValue.startMinutes % 60) },
            set: { entry.startMinutes.wrappedValue = (entry.wrappedValue.startMinutes / 60) * 60 + $0 }
        )
    }

    private func isChosen(_ colour: DiaryColour) -> Bool { entry.wrappedValue.colour == colour }

    /// `1h 30m`, which is how a person says it.
    private func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}
