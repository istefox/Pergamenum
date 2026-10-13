import Foundation
@testable import Pergamenum

// ADR-0096 (planned), plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 1 (PG-406, R-01).
//
// The bench row for a keystroke through SwiftUI's update: the editor column hosted in a window that is
// never shown, a character typed at the middle paragraph's end, and SwiftUI made to run the update that
// follows the binding write before the keystroke returns. The other rows measure the editor's own work
// and never call `updateNSView`; this one is what the person's hand check measured. Kept apart from
// `RestyleBudgetSupport.swift` for `file_length`.

extension RestyleBudget {
    /// Whether the update-path rows run. They do when `RESTYLE_BUDGET_UPDATE=1`, which
    /// `scripts/editor-restyle-bench.sh --update` sets; the per-turn suite leaves them out.
    static var includesUpdateRows: Bool {
        ProcessInfo.processInfo.environment["RESTYLE_BUDGET_UPDATE"] == "1"
    }

    /// `restyle-budget-update size=<bytes> variant=<prose|fences> cpu_ms=<min> wall_ms=<min> runs=<K>`,
    /// the line `scripts/editor-restyle-bench.sh --update` greps for its fifth table. It starts
    /// `restyle-budget-update`, so none of the other tables' patterns match it.
    static func updateLine(_ c: Case, cpuMs: Double, wallMs: Double, runs: Int) -> String {
        "restyle-budget-update size=\(c.bytes) variant=\(c.variant.rawValue) "
            + "cpu_ms=\(String(format: "%.2f", cpuMs)) wall_ms=\(String(format: "%.2f", wallMs)) runs=\(runs)"
    }
}
