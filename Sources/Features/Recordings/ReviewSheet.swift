import SwiftUI

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 7 -
// R-04, R-10; ADR §D9, §D12.
//
// The review sheet's pure state (recording header, per-speaker rename fields, per-theme task
// checkboxes, `no_action_items` / `warnings` banners) built from a `PlaudProposal`, the
// suppression set of already-imported quote fingerprints (ADR §D9), and - when one still
// matches the proposal's own `generated_at` - a persisted `PlaudVaultStore.Draft` (R-10).
// Grouped in one file, following `PlaudPayloads.swift`'s own precedent for a family of small
// value types that only make sense read together; `ReviewSheet`'s `View` body sits at the
// bottom, built on top of them.
struct ReviewTaskPresentation: Equatable, Sendable {
    var taskID: String
    var title: String
    var quote: String
    var urgencyImportanceText: String
    var dueDate: Date?
    /// All checked by default (R-04), except a task whose quote fingerprint is already in the
    /// suppression set, which starts unchecked with a «già importato» mark (ADR §D9) - shown,
    /// never hidden and never forbidden.
    var isInitiallyChecked: Bool
    var isAlreadyImported: Bool
}

struct ReviewThemePresentation: Equatable, Sendable {
    var name: String
    var tasks: [ReviewTaskPresentation]
}

struct ReviewSheetState: Equatable, Sendable {
    var recordingName: String
    var localDate: Date?
    var durationMs: Int
    var recordingKind: PlaudRecordingKind
    /// Only the speakers a person actually renamed, never an identity entry: the field in the
    /// sheet is pre-filled with the label as given (C6), so a proposal nobody has touched
    /// carries no decisions at all and a stale draft leaves nothing behind when it is
    /// discarded.
    var speakerRenames: [String: String]
    var themes: [ReviewThemePresentation]
    /// `themes` is empty (`no_action_items`, SPEC Edge cases) - shown as a banner, and
    /// `isImportEnabled` stays true regardless: a transcript-only import is valid.
    var showsNoActionItemsBanner: Bool
    /// e.g. `cleanup_ratio_low` - shown as a dismissible, informational-only notice.
    var warnings: [String]
    /// Never derived from "at least one task checked" - zero accepted tasks is a valid import
    /// (SPEC), so this is a stored fact rather than a computed guess a future edit could get
    /// backwards.
    var isImportEnabled: Bool

    /// A fresh review with no persisted draft: every task starts checked except one whose
    /// fingerprint is already in `suppressedFingerprints`.
    static func makeInitial(
        proposal: PlaudProposal,
        suppressedFingerprints: Set<String>
    ) -> ReviewSheetState {
        let themes = proposal.themes.map { theme in
            ReviewThemePresentation(
                name: theme.name,
                tasks: theme.tasks.map { task($0, suppressedFingerprints: suppressedFingerprints) }
            )
        }
        return ReviewSheetState(
            recordingName: proposal.recording.name,
            localDate: PlaudTimestamp.parse(proposal.recording.recordedAt),
            durationMs: proposal.recording.durationMs,
            recordingKind: proposal.recordingKind,
            speakerRenames: [:],
            themes: themes,
            // Derived from the proposal's own content rather than from the `no_action_items`
            // warning string: a proposal carrying themes with no tasks in them is the same
            // thing for the person reading it, and the banner has to say so either way.
            showsNoActionItemsBanner: themes.allSatisfy(\.tasks.isEmpty),
            // Minus the one warning that already has a banner of its own above, or the sheet
            // says the same thing twice in two different voices.
            warnings: proposal.warnings.filter { $0 != Self.noActionItemsWarning },
            isImportEnabled: true
        )
    }

    /// Reconstructs the sheet from a persisted draft (R-10) when one exists and its
    /// `generatedAt` still matches this proposal's own - discarding it and falling back to
    /// `makeInitial`'s fresh defaults otherwise (task ids are stable only within one proposal,
    /// ADR §D12).
    static func restoring(
        proposal: PlaudProposal,
        suppressedFingerprints: Set<String>,
        draft: PlaudVaultStore.Draft?
    ) -> ReviewSheetState {
        var state = makeInitial(proposal: proposal, suppressedFingerprints: suppressedFingerprints)
        guard let draft, draft.generatedAt == proposal.generatedAt else { return state }

        state.themes = state.themes.map { theme in
            var theme = theme
            theme.tasks = theme.tasks.map { task in
                var task = task
                // A decision the draft does not carry keeps the fresh default, suppression
                // included: a draft is what the person changed, not a full snapshot.
                task.isInitiallyChecked = draft.decisions[task.taskID] ?? task.isInitiallyChecked
                return task
            }
            return theme
        }
        // Restricted to the speakers this proposal actually has: a re-run that dropped a
        // speaker must not carry a rename for a label no line can match.
        let speakers = Set(proposal.transcript.speakers)
        state.speakerRenames = draft.speakerRenames.filter { speakers.contains($0.key) }
        return state
    }

    /// The service's own word for "nothing to act on", matched rather than paraphrased.
    static let noActionItemsWarning = "no_action_items"

    private static func task(
        _ task: PlaudTask, suppressedFingerprints: Set<String>
    ) -> ReviewTaskPresentation {
        let alreadyImported = suppressedFingerprints.contains(PlaudQuote.fingerprint(task.quote))
        return ReviewTaskPresentation(
            taskID: task.id,
            title: task.title,
            quote: task.quote,
            urgencyImportanceText: "urgenza \(task.urgency)/5, importanza \(task.importance)/5",
            // Through `CalendarDate(iso:)`, which is the same rule `TranscriptNote.taskLine`
            // applies: the sheet shows a date exactly when the note will carry a `>date`
            // marker for it, never one the writer would then drop (C7).
            dueDate: task.dueHint.flatMap(Self.dueDate),
            isInitiallyChecked: !alreadyImported,
            isAlreadyImported: alreadyImported
        )
    }

    private static func dueDate(_ hint: String) -> Date? {
        guard let date = CalendarDate(iso: hint) else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: date.year, month: date.month, day: date.day)
        )
    }
}

/// Everything the sheet needs to open, in one value `.sheet(item:)` can key on.
///
/// The proposal travels with the state rather than being re-fetched by the sheet: the
/// speakers to list and the ids to accept are in it, and a second `GET` on presentation
/// could answer with a different `generated_at` than the state was built from.
struct ReviewContext: Identifiable, Equatable, Sendable {
    var recordingID: String
    var proposal: PlaudProposal
    var state: ReviewSheetState

    var id: String { recordingID }
}

/// The review sheet of R-04: header, per-speaker renames, per-theme task checkboxes, and one
/// «Importa» that writes the note and confirms the accepted ids (ADR §D13).
///
/// Every change to a checkbox or a rename field writes the draft through the store
/// immediately (R-10), so a sheet dismissed by accident - or an app quit mid-review - comes
/// back to the same decisions.
struct ReviewSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(RecordingsController.self) private var recordings

    let context: ReviewContext

    @State private var decisions: [String: Bool] = [:]
    @State private var renames: [String: String] = [:]
    @State private var hasDismissedWarnings = false
    @State private var isImporting = false

    private var state: ReviewSheetState { context.state }
    private var acceptedTaskIDs: Set<String> {
        Set(decisions.filter(\.value).map(\.key))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 620, height: 560)
        .background(theme.color(.backgroundPrimary))
        .onAppear(perform: seed)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recordings-review-sheet")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(state.recordingName).themedText(.title).lineLimit(2)
            Text(subtitle).themedText(.caption, color: .textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing(.l))
    }

    private var subtitle: String {
        [
            RecordingFormat.date(state.localDate),
            RecordingFormat.duration(milliseconds: state.durationMs),
            kindText,
        ].joined(separator: " · ")
    }

    /// The service's own word for a kind it names and this app does not know, rather than a
    /// blank: `PlaudRecordingKind` decodes tolerantly on purpose (`PlaudPayloads.swift`).
    private var kindText: String {
        switch state.recordingKind {
        case .meeting: "riunione"
        case .lecture: "lezione"
        case .update: "aggiornamento"
        case .personal: "personale"
        case let .unknown(raw): raw.isEmpty ? "tipo sconosciuto" : raw
        }
    }

    // MARK: Body

    private var form: some View {
        Form {
            if state.showsNoActionItemsBanner {
                Section {
                    Text(
                        "Nessuna attività proposta per questa registrazione. "
                            + "Importare solo la trascrizione è comunque valido."
                    )
                        .themedText(.caption, color: .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !state.warnings.isEmpty && !hasDismissedWarnings { warningsSection }
            if !context.proposal.transcript.speakers.isEmpty { speakersSection }
            // By position rather than by name: two themes may carry the same name in one
            // proposal, and a duplicated `ForEach` id draws one of them and drops the other.
            ForEach(Array(state.themes.enumerated()), id: \.offset) { _, section in
                Section(section.name) {
                    ForEach(section.tasks, id: \.taskID) { task in
                        taskRow(task)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var warningsSection: some View {
        Section {
            ForEach(state.warnings, id: \.self) { warning in
                Text(warning).themedText(.caption, color: .textSecondary)
            }
            Button("Va bene") { hasDismissedWarnings = true }
                .accessibilityIdentifier("recordings-review-dismiss-warnings")
        } header: {
            Text("Segnalazioni del servizio")
        }
    }

    /// Pre-filled with the label as given (C6): the service has already resolved most
    /// speakers to real names, and overwriting them with «Speaker N» would be this app
    /// throwing away what the service worked out.
    private var speakersSection: some View {
        Section("Interlocutori") {
            ForEach(context.proposal.transcript.speakers, id: \.self) { label in
                TextField(label, text: renameBinding(for: label))
                    .accessibilityLabel("Nome per \(label)")
            }
        }
    }

    private func taskRow(_ task: ReviewTaskPresentation) -> some View {
        Toggle(isOn: decisionBinding(for: task)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).themedText(.body)
                Text("«\(task.quote)»")
                    .themedText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail(of: task)).themedText(.caption, color: .textTertiary)
            }
        }
        // The title inside the label, per the accessibility checklist: a checkbox that
        // reads as "attivato" out of visual context says nothing about what it accepts.
        .accessibilityLabel(task.isAlreadyImported ? "\(task.title) (già importato)" : task.title)
        .accessibilityIdentifier("recordings-review-task")
    }

    private func detail(of task: ReviewTaskPresentation) -> String {
        var parts = [task.urgencyImportanceText]
        if let due = task.dueDate {
            parts.append("scadenza \(CalendarDate(due).italianForm)")
        }
        if task.isAlreadyImported { parts.append("già importato") }
        return parts.joined(separator: " · ")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text(acceptedSummary).themedText(.caption, color: .textTertiary)
            Spacer()
            Button("Annulla", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Importa") { runImport() }
                .keyboardShortcut(.defaultAction)
                .disabled(!state.isImportEnabled || isImporting)
                .accessibilityIdentifier("recordings-review-import")
        }
        .padding(theme.spacing(.l))
    }

    private var acceptedSummary: String {
        let accepted = acceptedTaskIDs.count
        return accepted == 1 ? "1 attività accettata" : "\(accepted) attività accettate"
    }

    // MARK: Decisions, written through as they are taken (R-10)

    private func seed() {
        decisions = Dictionary(
            uniqueKeysWithValues: state.themes.flatMap(\.tasks).map { ($0.taskID, $0.isInitiallyChecked) }
        )
        renames = state.speakerRenames
    }

    private func decisionBinding(for task: ReviewTaskPresentation) -> Binding<Bool> {
        Binding(
            get: { decisions[task.taskID] ?? task.isInitiallyChecked },
            set: { accepted in
                decisions[task.taskID] = accepted
                persistDraft()
            }
        )
    }

    private func renameBinding(for label: String) -> Binding<String> {
        Binding(
            get: { renames[label] ?? label },
            set: { typed in
                let trimmed = typed.trimmingCharacters(in: .whitespaces)
                // Only a real deviation is a decision: typing the label back in clears the
                // rename rather than recording an identity the writer would apply to every
                // line of the transcript for nothing.
                if trimmed.isEmpty || trimmed == label {
                    renames[label] = nil
                } else {
                    renames[label] = trimmed
                }
                persistDraft()
            }
        )
    }

    private func persistDraft() {
        recordings.saveDraft(
            PlaudVaultStore.Draft(
                generatedAt: context.proposal.generatedAt,
                decisions: decisions,
                speakerRenames: renames
            ),
            for: context.recordingID
        )
    }

    private func runImport() {
        isImporting = true
        let accepted = acceptedTaskIDs
        let renames = renames
        Task {
            await recordings.importAccepted(
                recordingID: context.recordingID,
                proposal: context.proposal,
                acceptedTaskIDs: accepted,
                speakerRenames: renames
            )
            // The decisions have been acted on: keeping the draft would restore them over a
            // later, different proposal for the same recording.
            recordings.clearDraft(for: context.recordingID)
            isImporting = false
            dismiss()
        }
    }
}
