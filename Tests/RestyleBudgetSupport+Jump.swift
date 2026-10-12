import AppKit
import Foundation
@testable import Pergamenum

// ADR-0094 §D1, plan docs/plans/sublinear-offset-state-pg-405.md, Task 1 (PG-405, R-06, R-11).
//
// The bench row for the first keystroke after a caret jump: the caret leaves the middle paragraph for
// the top of the note, types there, and comes back. The first keystroke back pays whatever the offset
// state pays to follow the caret across the lines in between. On the code before ADR-0094 that is what a
// plain keystroke costs; after it, the step crosses those lines once. Kept apart from
// `RestyleBudgetSupport.swift` for `file_length`.

extension RestyleBudget {
    /// Whether the jump rows run. They do when `RESTYLE_BUDGET_JUMP=1`, which
    /// `scripts/editor-restyle-bench.sh --jump` sets; the per-turn suite leaves them out.
    static var includesJumpRows: Bool {
        ProcessInfo.processInfo.environment["RESTYLE_BUDGET_JUMP"] == "1"
    }

    /// `restyle-budget-jump size=<bytes> variant=<prose|fences> cpu_ms=<min> wall_ms=<min>
    /// crossed=<lines> runs=<K>`, the line `scripts/editor-restyle-bench.sh --jump` greps for its fourth
    /// table. It starts `restyle-budget-jump`, so none of the other tables' patterns match it.
    static func jumpLine(_ c: Case, cpuMs: Double, wallMs: Double, crossed: Int, runs: Int) -> String {
        "restyle-budget-jump size=\(c.bytes) variant=\(c.variant.rawValue) "
            + "cpu_ms=\(String(format: "%.2f", cpuMs)) wall_ms=\(String(format: "%.2f", wallMs)) "
            + "crossed=\(crossed) runs=\(runs)"
    }

    /// The end of the first `Altro testo con` line, near the top of the note: a place where one `x`
    /// changes no construct, far above `insertionPoint(in:)`.
    static func jumpPoint(in note: String) -> Int {
        let nsNote = note as NSString
        let line = nsNote.range(of: "Altro testo con")
        guard line.location != NSNotFound else { return 0 }
        return nsNote.lineRange(for: line).upperBound - 1
    }
}

/// A hosted editor prepared for the jump row. `jumpAway()` types at the top of the note and is never
/// timed; `keystroke()` is the measured one, typed back at the middle paragraph's end.
///
/// Both places are tracked as the note grows: each `jumpAway` puts one character above the middle
/// paragraph, and each keystroke one at it, so every run types at the end of the same paragraph.
@MainActor
final class JumpScenario {
    let fixture: ScrolledEditorFixture
    /// Where `jumpAway()` types: the end of the first `Altro testo con` line, which never moves.
    private let jumpLocation: Int
    /// Where `keystroke()` types, in the note as it is now.
    private var middleLocation: Int
    /// The number of line breaks between the two places, in the note as prepared.
    private let linesBetween: Int

    init(_ c: RestyleBudget.Case) {
        let note = RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        let fixture = ScrolledEditorFixture(text: note)
        let jump = RestyleBudget.jumpPoint(in: note)
        let middle = RestyleBudget.insertionPoint(in: note)
        let between = (note as NSString).substring(with: NSRange(location: jump, length: middle - jump))
        fixture.openLikeTheApp()
        self.fixture = fixture
        jumpLocation = jump
        middleLocation = middle
        linesBetween = between.filter { $0 == "\n" }.count
    }

    /// The number of lines between the two edit points, counted from the text, for reading.
    var crossed: Int { linesBetween }

    /// The middle paragraph's end now.
    var middle: Int { middleLocation }

    /// The caret leaves for the top of the note and types a character there. Untimed.
    func jumpAway() {
        fixture.type("x", at: jumpLocation)
        middleLocation += 1
    }

    /// The measured keystroke: a character at the end of the middle paragraph.
    func keystroke() {
        fixture.type("x", at: middleLocation)
        middleLocation += 1
    }
}
