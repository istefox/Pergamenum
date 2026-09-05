import Foundation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 7 -
// R-01, R-02, R-04, R-07, R-09; ADR §D15; UX-BLUEPRINT.md "Accessibility checklist".
//
// The row's pure presentation: status -> badge text + available actions, per the blueprint's
// per-status table ("nuova/in corso/pronta/fallita/importata", UI flows §2). Kept apart from
// `RecordingRow`'s `View` body (not yet written - Task 7's coder builds it against this type,
// following `RecordingsController`/`PlaudQuote`'s own precedent of a pure type a suite can
// drive without a window) so `Tests/RecordingsViewModelTests.swift` can assert every status
// with nothing but this file in the picture.
//
// `make(...)`'s body below is a **tester-declared stub** (ADR-0155): it deliberately answers
// every status alike, so every assertion in that suite is red until Task 7's coder writes the
// real per-status mapping this doc comment describes.
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
    /// Tester-declared stub (ADR-0155): returns the same empty value for every status, so
    /// `RecordingsViewModelTests` is red on every status until the coder fills in the
    /// blueprint's table:
    /// `new`->Elabora, `processing`->no action (progress + step name),
    /// `ready`->Rivedi, `failed`->Riprova, `imported`->Apri nota/Elimina/Rielabora.
    static func make(
        state: PlaudRecordingState,
        rowError: String? = nil,
        stepName: String? = nil
    ) -> RecordingRowPresentation {
        RecordingRowPresentation(badgeText: "", badgeSymbol: "", actions: [], errorMessage: nil, stepName: nil)
    }
}
