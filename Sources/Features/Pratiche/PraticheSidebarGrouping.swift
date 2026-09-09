import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
// R-33.
//
// The pane list column's own grouping rule (SPEC "Sidebar"): pratiche grouped by
// client folder, ordered by most recent activity, with `status-archived`/
// `status-final` collapsed into a separate «Chiuse» group at the bottom. Pure and
// Foundation-only on purpose, decoupled from `Navigation.Pane`/`SidebarItem` (the
// app-sidebar row "Pratiche sits in LAVORO before Registrazioni" is a placement
// claim, not a grouping one) - see this batch's report for why that placement is
// deferred rather than declared here.
//
// Tester-declared boundary (ADR-0155 §D1): `grouped(_:)` is stubbed to a
// wrong-but-safe constant, never `fatalError`.

/// One pratica as the sidebar list needs it (SPEC "Sidebar"): enough to group, order,
/// badge and dim it, never the full timeline.
struct PraticaListItem: Equatable, Sendable, Identifiable {
    /// The pratica folder's vault-relative path - stable across a rename (ADR
    /// "Edge cases": a pratica is recognised by its `pratica.md`, not by this path,
    /// but the path is what a `List(selection:)` row needs as its identity today).
    var id: String
    var title: String
    var client: String
    /// `active`/`waiting`/`archived`/`final`, the bare tag suffix (SPEC's own
    /// `status-*` vocabulary) - `archived`/`final` collapse under «Chiuse» (R-33).
    var status: String
    var lastActivity: Date
    /// The badge (R-33): messages that arrived since `PraticaLedger.PraticaState.
    /// lastOpenedAt` - computed by the caller from the ledger, carried through
    /// unchanged here.
    var messagesSinceLastOpen: Int
    /// The dot (R-33): whether `MembershipRule.trayCandidates` is non-empty for this
    /// pratica.
    var hasNonEmptyTray: Bool
}

/// One client's pratiche, in the pane list's own order (most recent first).
struct PraticaClientGroup: Equatable, Sendable, Identifiable {
    var client: String
    var pratiche: [PraticaListItem]

    var id: String { client }
}

enum PraticheSidebarGrouping {
    private static let closedStatuses: Set<String> = ["archived", "final"]

    /// R-33: groups the open pratiche (`active`/`waiting`, and anything not
    /// recognised as closed) by client, both the groups and the pratiche inside each
    /// group ordered by most recent activity descending; `status-archived`/
    /// `status-final` pratiche are returned flat, under the caller's own «Chiuse»
    /// section, in the same recency order.
    ///
    /// Stubbed to `(open: [], closed: pratiche)` - wrong whenever `pratiche` contains
    /// anything that is not closed.
    static func grouped(_ pratiche: [PraticaListItem]) -> (open: [PraticaClientGroup], closed: [PraticaListItem]) {
        (open: [], closed: pratiche)
    }

    /// Whether `status` is one of the two «Chiuse» statuses (R-33, R-34's own
    /// `status-active`/`status-archived` swap). A free function rather than inlined
    /// in `grouped(_:)` alone, since Task 7's Chiudi/Riapri command needs the same
    /// answer.
    static func isClosed(status: String) -> Bool {
        closedStatuses.contains(status)
    }
}
