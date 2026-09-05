import Foundation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 7 -
// R-04, R-10; ADR §D9, §D12.
//
// The review sheet's pure state (recording header, per-speaker rename fields, per-theme task
// checkboxes, `no_action_items` / `warnings` banners) built from a `PlaudProposal`, the
// suppression set of already-imported quote fingerprints (ADR §D9), and - when one still
// matches the proposal's own `generated_at` - a persisted `PlaudVaultStore.Draft` (R-10).
// Grouped in one file, following `PlaudPayloads.swift`'s own precedent for a family of small
// value types that only make sense read together. `ReviewSheet`'s `View` body is not yet
// written - Task 7's coder builds it on top of this type.
//
// `makeInitial`/`restoring`'s bodies below are **tester-declared stubs** (ADR-0155): both
// return an empty sheet with every task defaulted away from the blueprint's own table, so
// every assertion in `Tests/RecordingsViewModelTests.swift` is red until the coder builds the
// real per-theme/per-task mapping and the draft-reconstruction rule.
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
    /// Pre-filled with each speaker's label as given (C6) - never a synthesised "Speaker N".
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
    ///
    /// Tester-declared stub: ignores `proposal` and returns an empty sheet, so every
    /// assertion built on its themes/tasks is red until the coder implements the real
    /// mapping.
    static func makeInitial(
        proposal: PlaudProposal,
        suppressedFingerprints: Set<String>
    ) -> ReviewSheetState {
        ReviewSheetState(
            recordingName: "", localDate: nil, durationMs: 0, recordingKind: .unknown(""),
            speakerRenames: [:], themes: [], showsNoActionItemsBanner: false, warnings: [],
            isImportEnabled: true
        )
    }

    /// Reconstructs the sheet from a persisted draft (R-10) when one exists and its
    /// `generatedAt` still matches this proposal's own - discarding it and falling back to
    /// `makeInitial`'s fresh defaults otherwise (task ids are stable only within one proposal,
    /// ADR §D12).
    ///
    /// Tester-declared stub: always behaves as if no draft was found (falls through to
    /// `makeInitial`), so both the "restores the draft" and the "discards the stale draft"
    /// assertions are red until the coder writes the comparison.
    static func restoring(
        proposal: PlaudProposal,
        suppressedFingerprints: Set<String>,
        draft: PlaudVaultStore.Draft?
    ) -> ReviewSheetState {
        makeInitial(proposal: proposal, suppressedFingerprints: suppressedFingerprints)
    }
}
