import Foundation

// ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 8 -
// R-20; screen 1d.
//
// The pure state of «Nuova pratica…»'s three-step sheet (UX-BLUEPRINT.md: "Steps 1
// Nome e cliente · 2 Seme · 3 Proposte", DESIGN.md screen 1d). `NuovaPraticaWizard.swift`
// (the coder's SwiftUI view) holds one of these as `@State` and drives its own
// progress/seed-fetch/create actions off it; nothing here touches the vault, Mail, or
// `VaultSession.write` - those are async, I/O, and the coder's.
//
// Every declaration below is a tester-declared boundary (ADR-0155 §D1): stubbed to a
// wrong-but-safe constant, never `fatalError`.
struct WizardState: Equatable, Sendable {
    /// The three steps, in the order the sheet moves through them (screen 1d's
    /// «PASSO n DI 3» eyebrow).
    enum Step: Int, CaseIterable, Comparable, Sendable {
        case nameAndClient
        case seed
        case proposals

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Step 2's three choices (UX-BLUEPRINT.md: "seed from Mail's selection, from the
    /// in-app picker, or later").
    enum Seed: Equatable, Sendable {
        case mailSelection(MailLink.Link)
        case search
        case later
    }

    /// One same-counterpart conversation offered in step 3 (R-30's tray shares the
    /// same shape of information - subject, counterpart, date range, count - but this
    /// is its own type: the wizard's proposals are fetched for a pratica that does not
    /// exist yet, so they cannot be `PraticaTrayStrip`'s tray, which is keyed by an
    /// existing dossier's own conversations).
    struct Proposal: Equatable, Sendable, Identifiable {
        /// The Mail `conversation_id`, in string form - what `makeDossier()` below
        /// parses back into `Dossier.conversations`.
        var id: String
        var subject: String
        var counterpart: String
        var dateRange: ClosedRange<Date>
        var messageCount: Int
    }

    var step: Step = .nameAndClient
    var title: String = ""
    /// The client folder name, e.g. `"Rossi"` in `"01 Progetti/Rossi/Offerta 2026"` -
    /// not a full path (`PraticaNaming.client(forPraticaAt:root:)` reads it back the
    /// other way once the folder exists).
    var clientFolder: String = ""
    /// The Pratiche root folder (Settings › Pratiche, screen 1d's "Cartella radice +
    /// link Impostazioni") - editable per-wizard-run rather than only in Settings, so
    /// a person is never blocked mid-creation by a wrong default.
    var rootFolder: String = ""
    var seed: Seed = .later
    var proposals: [Proposal] = []
    var selectedProposalIDs: Set<String> = []
    /// Step 3's free-text «Parole chiave» field, comma/newline separated - see
    /// `keywordList` for the parsed form `Dossier.keywords` actually stores.
    var keywords: String = ""

    /// Step 1's gate (R-20): a pratica needs a non-blank title and a chosen client
    /// folder before advancing - screen 1d draws «Continua» disabled until both hold.
    var canContinueFromNameAndClient: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !clientFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether «Continua»/«Indietro» may move the sheet forward from `step` - steps 2
    /// and 3 have no further gate of their own (a seed of `.later` and an empty
    /// proposals selection are both legitimate states, not errors).
    var canAdvance: Bool {
        switch step {
        case .nameAndClient: canContinueFromNameAndClient
        case .seed, .proposals: true
        }
    }

    /// «Crea» (R-20): only reachable from the last step, and only once step 1's own
    /// gate still holds (nothing between steps can un-set it, but nothing should
    /// assume that either).
    var canCreate: Bool {
        step == .proposals && canContinueFromNameAndClient
    }

    /// The pratica folder's vault-relative path, built from the three fields above -
    /// what the coder's «Crea» action hands `VaultSession.createNote`/`write`.
    var relativePath: String {
        [rootFolder, clientFolder, title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    /// Free text into `Dossier.keywords` (R-20/ADR §D12): comma- or newline-separated,
    /// blank entries dropped, order preserved, no case folding - a subject match is
    /// literal, the same rule `Dossier.parse`'s own key already carries.
    var keywordList: [String] {
        keywords
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// R-20: the `Dossier` «Crea» writes into `pratica.md`'s frontmatter - the
    /// conversations admitted are exactly the proposals ticked in step 3 (the coder's
    /// step-2/3 fetch is expected to list the seed's own conversation first and
    /// pre-select it, so it needs no special case here).
    ///
    /// RED stub: always the empty dossier at schema version `0` - every assertion
    /// pinning a real conversation id, keyword or schema version fails until the coder
    /// implements this for real.
    func makeDossier() -> Dossier {
        Dossier(
            schemaVersion: 0, counterparts: [], conversations: [], keywords: [],
            included: [], excluded: [], ignored: []
        )
    }
}
