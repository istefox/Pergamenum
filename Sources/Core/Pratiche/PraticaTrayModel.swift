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
    /// The most recent message names the proposal - a thread is known by its latest
    /// subject («Re: Preventivo»), not by the one it opened with, and its sender is the
    /// address a person recognises the conversation by.
    ///
    /// A conversation whose messages carry no date at all is still offered, dated
    /// `.distantPast`: dropping it would hide a proposal rather than explain it.
    static func proposals(from entries: [MembershipRule.TrayEntry]) -> [PraticaTrayProposal] {
        entries.compactMap { entry in
            let dates = entry.messages.map(date(of:))
            guard let earliest = dates.min(), let latest = dates.max(),
                  let newest = entry.messages.max(by: { date(of: $0) < date(of: $1) })
            else { return nil }
            return PraticaTrayProposal(
                conversationID: entry.conversationID,
                subject: newest.subject ?? "",
                counterpart: newest.sender ?? "",
                dateRange: earliest...latest,
                messageCount: entry.messages.count
            )
        }
    }

    /// `MembershipRule`'s own date rule, which is `private` there: the sent date, the
    /// received date, and only then nothing at all.
    private static func date(of row: MailMessageRow) -> Date {
        row.dateSent ?? row.dateReceived ?? .distantPast
    }

    /// R-30: "the strip is hidden when empty" - real logic, not a stub, since it is
    /// exactly `.isEmpty` and pins down nothing the coder still has to build.
    static func isHidden(_ proposals: [PraticaTrayProposal]) -> Bool {
        proposals.isEmpty
    }

    /// «Ignora»: dismisses `conversationID` from this pratica's tray only
    /// (`pergamenum-dossier-ignored`), touching no other key.
    ///
    /// One key changes and no other: «Ignora» is this pratica dismissing a proposal,
    /// never a statement about the conversation itself, so nothing is added to
    /// `conversations`, `excluded` or anything else - a second pratica following the
    /// same counterpart still gets to offer it.
    static func ignoring(conversationID: Int, in dossier: Dossier) -> Dossier {
        var updated = dossier
        if !updated.ignored.contains(conversationID) { updated.ignored.append(conversationID) }
        return updated
    }

    /// «Aggiungi»: follows `conversationID` from now on
    /// (`pergamenum-dossier-conversations`, the same field `WizardState.makeDossier()`
    /// and `MembershipRule.candidates`'s rule 1 already read/write).
    ///
    /// Appended rather than inserted or sorted: `conversations` is a list a person can
    /// read in their own `pratica.md`, and the order it grew in is the order they
    /// followed things in.
    static func following(conversationID: Int, in dossier: Dossier) -> Dossier {
        var updated = dossier
        if !updated.conversations.contains(conversationID) {
            updated.conversations.append(conversationID)
        }
        return updated
    }
}
