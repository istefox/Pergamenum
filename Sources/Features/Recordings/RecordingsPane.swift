import SwiftUI

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 7 -
// R-01, R-02, R-04, R-07, R-09; ADR §D2, §D15.
//
// Pure presentation for the health banner (R-02): replaces the whole list while
// `RecordingsController.health` is `.unavailable`, and carries the one command the person can
// copy - selectable text plus a copy button, per the blueprint. The app never executes it: no
// `Process`, no `NSTask`, anywhere in this chain (SPEC, ADR §D2). `RecordingsPane`'s `View`
// body sits below it in this file.
struct HealthBannerPresentation: Equatable, Sendable {
    var message: String
    var copyableCommand: String

    /// The exact command the SPEC and the blueprint name, verbatim - a named constant so the
    /// pane and `Tests/RecordingsViewModelTests.swift` read the same string rather than two
    /// copies that can drift apart.
    static let launchctlCommand = "launchctl load ~/Library/LaunchAgents/it.stefer.plaud-service.plist"

    /// The message is whatever the controller already made readable (R-13); the command is
    /// always the same one, because there is exactly one way to load the agent again.
    static func make(message: String) -> HealthBannerPresentation {
        HealthBannerPresentation(message: message, copyableCommand: launchctlCommand)
    }
}

/// The Registrazioni pane (R-01): the recordings of the last `days`, one row each, with the
/// health banner in place of the list whenever the service is not answering (R-02).
///
/// Follows the sidebar-section/list visual language of `StarredPane`, the blueprint's own
/// instruction - no new design token, every colour and font through the theme.
struct RecordingsPane: View {
    @Environment(\.theme) private var theme
    @Environment(ThemeEngine.self) private var themeEngine
    @Environment(RecordingsController.self) private var recordings
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation

    @State private var review: ReviewContext?
    @State private var pendingDeletion: PlaudRecording?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                header
                content
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.color(.backgroundPrimary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recordings-pane")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                refreshButton
                themeToggleToolbarItem(themeEngine)
            }
        }
        // When the pane is shown, and at no other moment: no timer, no launch check, no
        // background task (ADR §D4/§D14). Choosing the row is the ask; `isIsolated` makes
        // this a no-op under `-disablePlaud YES` and inside the unit suite's host.
        .task { await load() }
        .onDisappear { recordings.stop() }
        .sheet(item: $review) { ReviewSheet(context: $0) }
        .confirmationDialog(
            "Eliminare la nota di «\(pendingDeletion?.name ?? "")»?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Sposta nel Cestino", role: .destructive) {
                if let recording = pendingDeletion { recordings.delete(recordingID: recording.id) }
                pendingDeletion = nil
            }
            Button("Annulla", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(
                "Va nel Cestino del Finder, non è una cancellazione definitiva. "
                    + "La registrazione resta sul servizio: nessuna richiesta viene inviata."
            )
        }
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text("Registrazioni").themedText(.title)
            Text(countText).themedText(.caption, color: .textTertiary)
            Spacer()
        }
        .padding(.bottom, theme.spacing(.xs))
    }

    private var countText: String {
        let count = recordings.recordings.count
        return count == 1 ? "1 registrazione" : "\(count) registrazioni"
    }

    private var refreshButton: some View {
        Button {
            Task { await load() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("Aggiorna registrazioni")
        .accessibilityLabel("Aggiorna registrazioni")
        .accessibilityIdentifier("recordings-refresh")
    }

    @ViewBuilder
    private var content: some View {
        if case let .unavailable(message) = recordings.health {
            healthBanner(HealthBannerPresentation.make(message: message))
        } else {
            if let banner = recordings.bannerMessage {
                Text(banner)
                    .themedText(.caption, color: .taskOverdue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if recordings.recordings.isEmpty { empty }
            ForEach(recordings.recordings, id: \.id) { recording in
                row(recording)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Nessuna registrazione nell'intervallo scelto.")
                .themedText(.body, color: .textSecondary)
            Text("""
                L'intervallo è «Giorni registrazioni Plaud» in Impostazioni › Generali, \
                predefinito 14 giorni. Le note importate finiscono in Registrazioni/ dentro il vault.
                """)
                .themedText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// R-02: the command is shown as selectable text beside a copy button, and this app never
    /// runs it - there is no `Process` and no `NSTask` in this chain, on purpose.
    private func healthBanner(_ banner: HealthBannerPresentation) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                Label(banner.message, systemImage: "exclamationmark.triangle")
                    .themedText(.body, color: .taskOverdue)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Il servizio si riavvia da Terminale con:")
                    .themedText(.caption, color: .textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
                    Text(banner.copyableCommand)
                        .font(theme.font(.mono))
                        .foregroundStyle(theme.color(.textPrimary))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(banner.copyableCommand, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copia il comando")
                    .accessibilityLabel("Copia il comando")
                    .accessibilityIdentifier("recordings-health-copy")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recordings-health-banner")
    }

    private func row(_ recording: PlaudRecording) -> some View {
        RecordingRow(
            recording: recording,
            presentation: RecordingRowPresentation.make(
                state: Self.effectiveState(recording: recording, pollingIDs: recordings.pollingRecordingIDs),
                rowError: recordings.rowErrors[recording.id] ?? recording.lastError.map(PlaudError.readableLastError),
                stepName: recordings.pollSteps[recording.id]
            ),
            confirmationFailure: recordings.confirmationFailures[recording.id],
            isPollExpired: recordings.pollExpired.contains(recording.id),
            onAction: { perform($0, on: recording) },
            onRetryConfirmation: { Task { await recordings.retryConfirmation(recordingID: recording.id) } }
        )
    }

    // MARK: Actions

    private func load() async {
        await recordings.checkHealth()
        await recordings.refresh()
    }

    private func perform(_ action: RecordingRowPresentation.Action, on recording: PlaudRecording) {
        switch action {
        case .elabora:
            Task { await recordings.process(recording.id) }
        // Both are the same request with `force=1` (blueprint): «Riprova» after a failure and
        // «Rielabora» on an imported recording differ in what the person is looking at, not
        // in what is asked of the service.
        case .riprova, .rielabora:
            Task { await recordings.process(recording.id, force: true) }
        case .rivedi:
            Task { await openReview(for: recording) }
        case .apriNota:
            openNote(of: recording)
        case .elimina:
            // The confirmation is this pane's job (R-09): the controller deletes when told.
            pendingDeletion = recording
        }
    }

    private func openReview(for recording: PlaudRecording) async {
        guard let proposal = await recordings.loadProposal(recordingID: recording.id) else { return }
        review = ReviewContext(
            recordingID: recording.id,
            proposal: proposal,
            state: .restoring(
                proposal: proposal,
                suppressedFingerprints: recordings.suppressedFingerprints(recordingID: recording.id),
                draft: recordings.draft(recordingID: recording.id, generatedAt: proposal.generatedAt)
            )
        )
    }

    private func openNote(of recording: PlaudRecording) {
        guard let path = recordings.entries[recording.id]?.notePath else { return }
        vault.openChosenNote(at: path)
        navigation.pane = .notes
    }
}

// Task 10's live HITL walkthrough of ADR-0032 (bug-fix follow-up to Tasks 7/8, not a new task
// number) - `row(_:)` above builds `RecordingRowPresentation` straight from
// `recording.state`, the wire value as last fetched by `refresh()`, and never consults
// `RecordingsController.pollingRecordingIDs`. A recording being polled after `process()`
// therefore keeps showing its OLD status ("fallita"/"nuova") for the whole poll: the person
// watching sees nothing move until a manual refresh, by which point the job has usually
// already finished and the "in corso" state was never shown at all.
extension RecordingsPane {
    /// The state a row must present: `.processing` while `pollingIDs` says a poll for this
    /// recording is in flight, `recording.state` (the wire value) otherwise. A static, pure
    /// function of its two arguments so `Tests/RecordingsViewModelTests.swift` can drive it
    /// with no `View`/environment in the picture - `nonisolated` for the same reason
    /// `WorkspaceBrowser+Tree.swift`'s own statics are (`selection(for:)` et al.): a pure
    /// function that silently carries this `View`'s main-actor isolation is a trap for the
    /// first caller that is not on the main actor, and a unit test calling it synchronously
    /// is exactly that caller.
    ///
    /// The poll's own set wins over the wire value while a poll is in flight, and only then:
    /// the list is fetched once per «Aggiorna» and never on a timer (ADR §D4), so a recording
    /// whose job is running still carries whatever state the last fetch happened to see. The
    /// set is the only thing that knows better, and
    /// `RecordingsController.finishPolling(_:expired:)` drops the id from it only after the
    /// re-fetch has landed - so the fallback below is never a value the poll has outrun.
    nonisolated static func effectiveState(
        recording: PlaudRecording, pollingIDs: Set<String>
    ) -> PlaudRecordingState {
        pollingIDs.contains(recording.id) ? .processing : recording.state
    }
}
