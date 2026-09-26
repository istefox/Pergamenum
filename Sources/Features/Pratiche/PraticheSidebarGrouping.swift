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
    /// A client's own recency is the recency of its most recent pratica, not an
    /// average and not the alphabet: the group a person worked in this morning is the
    /// one that should be under the pointer when the pane opens.
    ///
    /// The title breaks a tie on both axes, so two pratiche touched in the same second
    /// (a sync writing several files) keep one stable order between reloads instead of
    /// swapping rows under the reader.
    ///
    /// `order` is the person's choice, `.newestFirst` being everything above. `.oldestFirst`
    /// inverts all three axes at once - the pratiche inside a client, the client groups, and
    /// «Chiuse» - because they are one question asked at three levels: groups running one way
    /// over rows running the other is not a reversed list. A group then ranks by the pratica
    /// that leads it *as ordered*, which is the correct reading in both directions.
    ///
    /// The tie-break never inverts: title inside a group, client between groups. It exists so
    /// same-second rows keep one order between reloads, and flipping it with the direction would
    /// reshuffle them on every toggle for a reason nobody can read off the screen. So
    /// `.oldestFirst` is the exact reverse of `.newestFirst` except inside a block of pratiche
    /// sharing one instant, which stays alphabetical in both.
    static func grouped(
        _ pratiche: [PraticaListItem], order: ChronologicalOrder = .newestFirst
    ) -> (open: [PraticaClientGroup], closed: [PraticaListItem]) {
        let recency = { (left: PraticaListItem, right: PraticaListItem) in
            byRecency(left, right, order: order)
        }
        let closed = pratiche.filter { isClosed(status: $0.status) }.sorted(by: recency)
        let open = pratiche.filter { !isClosed(status: $0.status) }

        var byClient: [String: [PraticaListItem]] = [:]
        for pratica in open { byClient[pratica.client, default: []].append(pratica) }

        let groups = byClient
            .map { PraticaClientGroup(client: $0.key, pratiche: $0.value.sorted(by: recency)) }
            .sorted { left, right in
                let leftLead = left.pratiche.first?.lastActivity ?? .distantPast
                let rightLead = right.pratiche.first?.lastActivity ?? .distantPast
                return leftLead == rightLead
                    ? left.client < right.client
                    : order.precedes(leftLead, rightLead)
            }

        return (open: groups, closed: closed)
    }

    private static func byRecency(
        _ left: PraticaListItem, _ right: PraticaListItem, order: ChronologicalOrder
    ) -> Bool {
        left.lastActivity == right.lastActivity
            ? left.title < right.title
            : order.precedes(left.lastActivity, right.lastActivity)
    }

    /// Whether `status` is one of the two «Chiuse» statuses (R-33, R-34's own
    /// `status-active`/`status-archived` swap). A free function rather than inlined
    /// in `grouped(_:)` alone, since Task 7's Chiudi/Riapri command needs the same
    /// answer.
    static func isClosed(status: String) -> Bool {
        closedStatuses.contains(status)
    }
}
