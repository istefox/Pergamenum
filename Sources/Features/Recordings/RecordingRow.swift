import SwiftUI

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 7 -
// R-01, R-02, R-04, R-07, R-09; ADR §D15; UX-BLUEPRINT.md "Accessibility checklist".
//
// The row's pure presentation: status -> badge text + available actions, per the blueprint's
// per-status table ("nuova/in corso/pronta/fallita/importata", UI flows §2). Kept apart from
// `RecordingRow`'s `View` body (below in this file, following
// `RecordingsController`/`PlaudQuote`'s own precedent of a pure type a suite can drive
// without a window) so `Tests/RecordingsViewModelTests.swift` can assert every status with
// nothing but this type in the picture.
struct RecordingRowPresentation: Equatable, Sendable {
    /// One row action, named once here and read by both the row's button and its context
    /// menu (ADR-0023's "declare once, render twice" precedent) rather than re-derived from
    /// `state` in two places that could disagree.
    enum Action: String, Equatable, Sendable, CaseIterable {
        case elabora
        case rivedi
        case riprova
        case apriNota
        case elimina
        case rielabora

        /// The button's label and its VoiceOver name, which are the same words on purpose:
        /// the buttons are icon-only in the row, and the blueprint's accessibility checklist
        /// asks for a label on every one of them.
        var title: String {
            switch self {
            case .elabora: "Elabora"
            case .rivedi: "Rivedi"
            case .riprova: "Riprova"
            case .apriNota: "Apri nota"
            case .elimina: "Elimina"
            case .rielabora: "Rielabora"
            }
        }

        var symbol: String {
            switch self {
            case .elabora: "play.circle"
            case .rivedi: "eye"
            case .riprova: "arrow.clockwise"
            case .apriNota: "doc.text"
            case .elimina: "trash"
            case .rielabora: "arrow.triangle.2.circlepath"
            }
        }

        /// The one action that moves a note to the Trash (R-09): it asks first, and the
        /// dialog is the caller's - `RecordingsController.delete` deletes when told.
        var isDestructive: Bool { self == .elimina }

        /// Stable and lowercase, never the Italian title: a UI test must not find a control
        /// by the words on it (CLAUDE.md).
        var accessibilityIdentifier: String { "recordings-action-\(rawValue)" }
    }

    /// The blueprint's own words, verbatim: "nuova/in corso/pronta/fallita/importata"
    /// (UX-BLUEPRINT.md, Accessibility checklist) - exposed as text so a status badge is
    /// never colour alone (R-04's accessibility deliverable).
    var badgeText: String
    /// An SF Symbol name. The blueprint fixes no per-status symbol (only the toolbar's
    /// `arrow.clockwise`), so this is asserted present rather than pinned to one string.
    var badgeSymbol: String
    var actions: [Action]
    /// The readable message shown in place of the badge for a `failed` row (R-07) - always
    /// `nil` for every other status. Already mapped through `PlaudError.readableLastError` by
    /// the controller; this type only carries it through, never re-derives it.
    var errorMessage: String?
    /// The step name (`transcript`/`extract`/`cleanup`) shown beside a `processing` row's
    /// progress indicator when the service reported one - `nil` otherwise, including when the
    /// state is not `.processing` at all.
    var stepName: String?

    /// Builds a row's presentation from its wire state plus the two pieces of local context a
    /// status alone cannot carry: a `failed` row's already-readable error, and a `processing`
    /// row's step name.
    ///
    /// The blueprint's table, and nothing else: `new`->Elabora, `processing`->no action
    /// (progress + step name), `ready`->Rivedi, `failed`->Riprova, `imported`->Apri
    /// nota/Elimina/Rielabora. A state this app has never seen (`PlaudRecordingState.unknown`,
    /// the tolerant decode of `PlaudPayloads.swift`) offers nothing and says so with the
    /// service's own word rather than pretending to be one of the five.
    static func make(
        state: PlaudRecordingState,
        rowError: String? = nil,
        stepName: String? = nil
    ) -> RecordingRowPresentation {
        switch state {
        case .new:
            RecordingRowPresentation(
                badgeText: "nuova", badgeSymbol: "circle.dashed", actions: [.elabora],
                errorMessage: nil, stepName: nil
            )
        case .processing:
            RecordingRowPresentation(
                badgeText: "in corso", badgeSymbol: "arrow.triangle.2.circlepath", actions: [],
                errorMessage: nil, stepName: stepName
            )
        case .ready:
            RecordingRowPresentation(
                badgeText: "pronta", badgeSymbol: "checkmark.circle", actions: [.rivedi],
                errorMessage: nil, stepName: nil
            )
        case .failed:
            // The message arrives already readable (R-07) and is carried through verbatim:
            // truncating it here is how a mapping table's one useful sentence gets lost.
            RecordingRowPresentation(
                badgeText: "fallita", badgeSymbol: "exclamationmark.triangle", actions: [.riprova],
                errorMessage: rowError, stepName: nil
            )
        case .imported:
            RecordingRowPresentation(
                badgeText: "importata", badgeSymbol: "tray.and.arrow.down",
                actions: [.apriNota, .elimina, .rielabora], errorMessage: nil, stepName: nil
            )
        case let .unknown(raw):
            RecordingRowPresentation(
                badgeText: raw.isEmpty ? "sconosciuta" : raw, badgeSymbol: "questionmark.circle",
                actions: [], errorMessage: nil, stepName: nil
            )
        }
    }

    /// Which token paints the badge. A token and never a colour (CLAUDE.md's binding rule),
    /// and beside the badge's own words rather than instead of them - colour alone is exactly
    /// what the accessibility checklist forbids here.
    var badgeColor: ColorToken {
        switch badgeSymbol {
        case "exclamationmark.triangle": .taskOverdue
        case "checkmark.circle": .accentPrimary
        case "tray.and.arrow.down": .taskDone
        case "arrow.triangle.2.circlepath": .taskScheduled
        default: .textTertiary
        }
    }
}

/// How a recording's own numbers are written for a person: the local instant of a UTC
/// timestamp (ADR §D8, C2) and a duration in hours and minutes.
///
/// Here rather than in each view, because `RecordingRow` and `ReviewSheet` both write the
/// same two values and two spellings of "1 h 03 min" is one spelling too many.
enum RecordingFormat {
    /// `nil` when the service sent a timestamp none of `PlaudTimestamp`'s three shapes
    /// parse - shown as a dash rather than as today's date, which would be a quiet lie.
    static func localInstant(_ raw: String) -> Date? { PlaudTimestamp.parse(raw) }

    static func date(_ instant: Date?) -> String {
        guard let instant else { return "—" }
        return instant.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(Locale(identifier: "it_IT"))
        )
    }

    /// The recordings in the order the person chose, by `recorded_at` and by nothing the
    /// service happened to send.
    ///
    /// Every timestamp goes through `localInstant(_:)`, so the sort cannot disagree with the date
    /// a row prints. It is read once per recording rather than inside the comparator, since
    /// `PlaudTimestamp` builds a formatter per call.
    ///
    /// A `recorded_at` nobody can read is *unknown*, neither old nor new: the row prints «—» for
    /// it rather than guess, so it sorts after every dated recording in both directions
    /// (`TaskArrangement.sort`'s rule for an undated task). Ties, and the unreadable block itself,
    /// break on `name` then `id` ascending and never invert with the direction, so no row swaps
    /// place between two redraws.
    ///
    /// `nonisolated` for the reason `RecordingsPane.effectiveState` is: a pure function that
    /// silently carries a `View`'s main-actor isolation is a trap for a unit test calling it.
    nonisolated static func ordered(
        _ recordings: [PlaudRecording], by order: ChronologicalOrder
    ) -> [PlaudRecording] {
        let stamped = recordings.map { (recording: $0, instant: localInstant($0.recordedAt)) }
        let stable = { (left: PlaudRecording, right: PlaudRecording) in
            left.name == right.name ? left.id < right.id : left.name < right.name
        }
        let sorted = stamped.sorted { left, right in
            switch (left.instant, right.instant) {
            case let (leftInstant?, rightInstant?):
                leftInstant == rightInstant
                    ? stable(left.recording, right.recording)
                    : order.precedes(leftInstant, rightInstant)
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): stable(left.recording, right.recording)
            }
        }
        return sorted.map(\.recording)
    }

    static func duration(milliseconds: Int) -> String {
        let totalMinutes = max(0, milliseconds) / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours) h \(String(format: "%02d", minutes)) min" : "\(minutes) min"
    }
}

/// One recording in the Registrazioni pane (R-01).
///
/// Follows the sidebar-section/list visual language the blueprint asks for -
/// `StarredPane`'s `ThemedCard` row, every colour and font through the theme, no new design
/// token. The actions are `presentation.actions` rendered twice, as buttons and as a context
/// menu, from the one declaration above.
struct RecordingRow: View {
    @Environment(\.theme) private var theme

    let recording: PlaudRecording
    let presentation: RecordingRowPresentation
    /// The readable message of a two-phase import whose confirmation `POST` has not landed
    /// yet (ADR §D13). Its own affordance rather than a seventh `Action`: retrying it writes
    /// no note and re-reads no proposal, so offering it beside «Rielabora» would invite the
    /// one recovery that duplicates work.
    let confirmationFailure: String?
    /// The poll gave up at the 30-minute bound (ADR §D4) - the row says so instead of
    /// resuming a request nobody asked for again.
    let isPollExpired: Bool
    let onAction: (RecordingRowPresentation.Action) -> Void
    let onRetryConfirmation: () -> Void

    var body: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                headline
                subtitle
                if let message = presentation.errorMessage {
                    Text(message)
                        .themedText(.caption, color: .taskOverdue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let failure = confirmationFailure { confirmationNotice(failure) }
                if isPollExpired {
                    Text(
                        "L'elaborazione ha superato i 30 minuti: l'attesa è stata interrotta, "
                            + "aggiorna per vedere com'è finita."
                    )
                        .themedText(.caption, color: .textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu { ForEach(presentation.actions, id: \.self) { menuEntry($0) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recordings-row")
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
            Text(recording.name).themedText(.body).lineLimit(2)
            Spacer(minLength: theme.spacing(.s))
            badge
            ForEach(presentation.actions, id: \.self) { button($0) }
        }
    }

    private var subtitle: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text(RecordingFormat.date(RecordingFormat.localInstant(recording.recordedAt)))
            Text("·")
            Text(RecordingFormat.duration(milliseconds: recording.durationMs))
            if let step = presentation.stepName {
                Text("·")
                ProgressView().controlSize(.small)
                Text(step)
            }
        }
        .themedText(.caption, color: .textTertiary)
    }

    /// Text as well as symbol and colour, per the accessibility checklist: a status a
    /// screen reader can only reach as "orange" is a status it cannot reach.
    private var badge: some View {
        Label(presentation.badgeText, systemImage: presentation.badgeSymbol)
            .themedText(.caption, color: presentation.badgeColor)
            .accessibilityLabel("Stato: \(presentation.badgeText)")
    }

    private func button(_ action: RecordingRowPresentation.Action) -> some View {
        Button(role: action.isDestructive ? .destructive : nil) {
            onAction(action)
        } label: {
            Image(systemName: action.symbol)
        }
        .buttonStyle(.borderless)
        .help(action.title)
        .accessibilityLabel(action.title)
        .accessibilityIdentifier(action.accessibilityIdentifier)
    }

    private func menuEntry(_ action: RecordingRowPresentation.Action) -> some View {
        Button(action.title, systemImage: action.symbol, role: action.isDestructive ? .destructive : nil) {
            onAction(action)
        }
    }

    private func confirmationNotice(_ failure: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
            Text("La nota è stata scritta, la conferma al servizio no: \(failure)")
                .themedText(.caption, color: .taskOverdue)
                .fixedSize(horizontal: false, vertical: true)
            Button("Riprova la conferma") { onRetryConfirmation() }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("recordings-retry-confirmation")
        }
    }
}
