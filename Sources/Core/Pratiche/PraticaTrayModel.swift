import Foundation

// ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 -
// R-30; ADR §D-tray, `MembershipRule.trayCandidates`.
//
// The pure model `PraticaTrayStrip.swift` (the coder's SwiftUI view) renders: one
// entry per not-yet-followed conversation the sync already found touching this
// pratica's counterparts (`MembershipRule.trayCandidates`), reduced to exactly what
// the strip draws (subject, counterpart, date range, count), plus the two actions the
// strip's own buttons perform on the pratica's `Dossier` - «Aggiungi» (follow) and
// «Ignora» (dismiss, this pratica only).
//
// Every function below is a tester-declared boundary (ADR-0155 §D1): `proposals(from:)`,
// `ignoring(conversationID:in:)` and `following(conversationID:in:)` are stubbed to a
// wrong-but-safe constant, never `fatalError`. `isHidden(_:)` is real: it is exactly
// `.isEmpty`, the same kind of trivial deterministic mapping `WizardState`'s gates
// already ship as real logic rather than stubbed.
enum PraticaTrayModel {
    /// One tray row - what `PraticaTrayStrip` actually draws, reduced from
    /// `MembershipRule.TrayEntry`'s raw `[MailMessageRow]`.
    struct PraticaTrayProposal: Equatable, Sendable {
        var conversationID: Int
        var subject: String
        var counterpart: String
        var dateRange: ClosedRange<Date>
        var messageCount: Int
    }

    /// Reduces `MembershipRule.trayCandidates`'s own `TrayEntry` (conversation id +
    /// every live message in it) to the four fields the strip draws - no second store
    /// read, `TrayEntry.messages` already carries everything this needs.
    ///
    /// RED stub: always `[]` - every assertion pinning a real subject, counterpart,
    /// date range or count fails until the coder reduces `entry.messages` for real
    /// (e.g. the most recent message's subject/sender, `min...max` of
    /// `dateSent ?? dateReceived` across the entry, `messages.count`).
    static func proposals(from entries: [MembershipRule.TrayEntry]) -> [PraticaTrayProposal] {
        []
    }

    /// R-30: "the strip is hidden when empty" - real logic, not a stub, since it is
    /// exactly `.isEmpty` and pins down nothing the coder still has to build.
    static func isHidden(_ proposals: [PraticaTrayProposal]) -> Bool {
        proposals.isEmpty
    }

    /// «Ignora»: dismisses `conversationID` from this pratica's tray only
    /// (`pergamenum-dossier-ignored`), touching no other key.
    ///
    /// RED stub: returns `dossier` unchanged - a test expecting the id to land in
    /// `ignored` fails on the assertion; a test comparing every other rendered key via
    /// `Dossier.render` still passes, since the stub genuinely changes nothing.
    static func ignoring(conversationID: Int, in dossier: Dossier) -> Dossier {
        dossier
    }

    /// «Aggiungi»: follows `conversationID` from now on
    /// (`pergamenum-dossier-conversations`, the same field `WizardState.makeDossier()`
    /// and `MembershipRule.candidates`'s rule 1 already read/write).
    ///
    /// RED stub: returns `dossier` unchanged.
    static func following(conversationID: Int, in dossier: Dossier) -> Dossier {
        dossier
    }
}
