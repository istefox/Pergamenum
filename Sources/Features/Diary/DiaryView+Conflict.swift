import SwiftUI

/// The strip shown when the diary's file moved on while it was being written (ADR-0057 §D6).
///
/// The shape of the editor's own (`EditorColumn+Conflict.swift`), because the Diario's
/// writing column is that editor (ADR-0029). Non-modal: the text stays editable while it is
/// up, and each button calls one of the controller's two resolution verbs and nothing else.
extension DiaryView {
    var conflictBanner: some View {
        HStack(spacing: theme.spacing(.s)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.color(.taskOverdue))
            Text("Il diario è cambiato su disco mentre lo stavi scrivendo.")
                .themedText(.caption)
            Spacer()
            Button("Ricarica da disco") { controller.reloadDiaryFromDisk() }
                .accessibilityIdentifier("diary-conflict-reload")
            Button("Tieni la mia versione") { controller.keepLocalDiary() }
                .accessibilityIdentifier("diary-conflict-keep-local")
        }
        .padding(theme.spacing(.s))
        .background(theme.color(.accentMuted))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diary-conflict-banner")
    }
}
