import Foundation

// ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 8 -
// R-21; UX-BLUEPRINT.md: "«Aggiungi a pratica da Mail…» … list of pratiche (recent
// first, filter field)".
//
// `AddToPraticaSheet.swift` (the coder's SwiftUI view) is the one declaration this
// batch does not add - it is a View, and this pure ordering function is what it calls,
// kept separate on purpose so declaring it here never collides with the coder's own
// `struct AddToPraticaSheet: View`.
//
// Deliberately independent of `PraticheSidebarGrouping.byRecency` (`Sources/Features/
// Pratiche/PraticheSidebarGrouping.swift`), which is `private` and serves a different
// surface (the pane's own sidebar list, grouped by client) - the two happen to share a
// sort key today, but nothing here depends on that staying true.
enum AddToPraticaOrdering {
    /// Most recent `lastActivity` first, ties broken by `id` for a deterministic order
    /// across runs (`PraticheSidebarGrouping.byRecency`'s own tie-break, applied here
    /// independently).
    ///
    static func recentFirst(_ pratiche: [PraticaListItem]) -> [PraticaListItem] {
        pratiche.sorted { left, right in
            left.lastActivity == right.lastActivity
                ? left.id < right.id
                : left.lastActivity > right.lastActivity
        }
    }
}
