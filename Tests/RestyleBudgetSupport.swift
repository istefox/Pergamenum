import AppKit
import Foundation
@testable import Pergamenum

// ADR-0082 §D5, plan docs/plans/pg-385-n2-page.md, Task 1 (PG-385, R-15).
//
// What `EditorRestyleBudgetTests` measures with: a deterministic synthetic note, the calling
// thread's CPU time, the minimum of K runs, the ceilings and the one-line printout the bench
// script greps. Kept apart from the test for `file_length` and so the pure parts can be tested
// without a text view.

enum RestyleBudget {
    enum Variant: String, Sendable, CaseIterable {
        case prose, fences
    }

    /// One of the six measurements: a size in UTF-8 bytes and a variant.
    struct Case: Hashable, Sendable, CustomStringConvertible {
        let bytes: Int
        let variant: Variant
        var description: String { "\(bytes / 1024) KB \(variant.rawValue)" }
    }

    static let kilobyte = 1024
    /// 50 KB, 200 KB and 1 MB, as UTF-8 bytes.
    static let sizes = [50 * kilobyte, 200 * kilobyte, 1024 * kilobyte]

    /// How many runs after the warm-up: 5 at 50 KB and 200 KB, 3 at 1 MB (§D5).
    /// `RESTYLE_BUDGET_RUNS` overrides it (the bench script's `--runs`), for a measurement too slow
    /// to repeat.
    static func runs(for c: Case) -> Int {
        if let text = ProcessInfo.processInfo.environment["RESTYLE_BUDGET_RUNS"], let runs = Int(text), runs > 0 {
            return runs
        }
        return c.bytes >= 1024 * kilobyte ? 3 : 5
    }

    /// Whether the 1 MB cases run. A keystroke in a 1 MB note costs 6 to 12 s of CPU (about eleven
    /// minutes before the `wikilinkSpans` fix, ADR-0082 §D9), so the per-turn suite leaves them
    /// to the bench script. They run when `RESTYLE_BUDGET_1MB=1` (`scripts/editor-restyle-bench.sh --large`), or alone when
    /// it is `only` (`--large-only`).
    static var includesLargeNotes: Bool {
        ["1", "only"].contains(ProcessInfo.processInfo.environment["RESTYLE_BUDGET_1MB"])
    }

    /// Whether the 200 KB cases run. One keystroke in a 200 KB note costs about 1 s of CPU (20 to
    /// 26 s before the `wikilinkSpans` fix, when the two rows added most of 397 s to the suite and
    /// the Stop hook's 600 s could not carry them, ADR-0082 §D9). They stay on demand by the
    /// person's decision at G-ceiling. They run when
    /// `RESTYLE_BUDGET_200KB=1`, which `scripts/editor-restyle-bench.sh` sets on every run but
    /// `--large-only`; the per-turn suite asserts the two 50 KB rows only.
    static var includesMediumNotes: Bool {
        ProcessInfo.processInfo.environment["RESTYLE_BUDGET_200KB"] == "1"
    }

    /// Whether the 50 KB cases run. They do, except when `RESTYLE_BUDGET_50KB=0`, which the CI workflow
    /// sets: the ceilings are three times a "before" measured on the development machine, and the
    /// hosted runner takes 4.8 and 5.1 s of CPU against 4.3 and 4.4 s allowed (PR #921). A machine
    /// dependent absolute ceiling cannot gate a different machine; the budget is a local measure
    /// until G-ceiling fixes a ratio that travels (ADR-0082 §D9).
    static var includesSmallNotes: Bool {
        ProcessInfo.processInfo.environment["RESTYLE_BUDGET_50KB"] != "0"
    }

    /// Whether the warm-up keystroke runs. `RESTYLE_BUDGET_NO_WARMUP=1` skips it, only for a
    /// measurement where one keystroke already takes minutes.
    static var warmsUp: Bool {
        ProcessInfo.processInfo.environment["RESTYLE_BUDGET_NO_WARMUP"] != "1"
    }

    /// The cases this run measures, smallest first: the 50 KB rows unless only the 1 MB ones were
    /// asked for or `includesSmallNotes` is off, the 200 KB rows behind `includesMediumNotes`, the 1 MB rows behind
    /// `includesLargeNotes`.
    static var activeCases: [Case] {
        let largeOnly = ProcessInfo.processInfo.environment["RESTYLE_BUDGET_1MB"] == "only"
        return ceilings.keys
            .filter { c in
                if c.bytes >= 1024 * kilobyte { return includesLargeNotes }
                if largeOnly { return false }
                if c.bytes < 200 * kilobyte { return includesSmallNotes }
                return includesMediumNotes
            }
            .sorted { ($0.bytes, $0.variant.rawValue) < ($1.bytes, $1.variant.rawValue) }
    }

    // MARK: - The synthetic note

    /// A note of `bytes` UTF-8 bytes, within 1%, built with no randomness: every unit is a pure
    /// function of its index, so two calls return the same string.
    ///
    /// Prose: headings, emphasis, links, tags, both date tokens, nested lists, tasks and quotes.
    /// Fences: the same plus a code fence about every 40 lines and a `pergamenum-view` fence about
    /// every 200 (the view block has no query source in the test, so it draws its no-vault branch
    /// and still hosts its view).
    static func syntheticNote(bytes: Int, variant: Variant) -> String {
        var note = ""
        note.reserveCapacity(bytes + 1024)
        var group = 0
        while note.utf8.count < bytes {
            for unit in units(ofGroup: group, variant: variant) {
                guard note.utf8.count < bytes else { break }
                note += unit
            }
            group += 1
        }
        return note
    }

    /// The units of one group of 20 lines, a fence being one unit so the note never stops inside
    /// one. Each unit ends in a newline.
    private static func units(ofGroup n: Int, variant: Variant) -> [String] {
        let day = 1 + n % 28
        var lines = [
            "# Titolo della sezione \(n)\n",
            "\n",
            "Paragrafo con **grassetto**, *corsivo*, ~~barrato~~ e `codice`, un [[Nota \(n)]] e un "
                + "[link](https://example.com/\(n)) #project-av\(n % 50) >2026-10-\(day < 10 ? "0" : "")\(day) "
                + "!2026-11-\(day < 10 ? "0" : "")\(day) @done(2026-10-01).\n",
            "\n",
            "- primo punto con **forte**\n",
            "  - annidato con *enfasi*\n",
            "    - terzo livello\n",
            "- [ ] attivita \(n) >2026-10-04\n",
            "- [x] fatta\n",
            "\n",
            "1. uno\n",
            "2. due\n",
            "3. tre\n",
            "\n",
            "> citazione di primo livello\n",
            "> > citazione annidata\n",
            "\n",
            "Altro testo con file_name_here e 2 * 3 * 4 e un [[Altra nota|alias]].\n",
            "## Sottotitolo \(n)\n",
            "\n",
        ]
        if variant == .fences {
            if n % 2 == 1 {
                lines.append("```swift\nlet valore\(n) = \(n) // commento\n```\n\n")
            }
            if n % 10 == 9 {
                lines.append("```pergamenum-view\nrender: list\nwhere: tag(\"topic-\(n)\")\n```\n\n")
            }
        }
        return lines
    }

    // MARK: - Measuring

    /// The calling thread's CPU time, in nanoseconds. Not wall time: the Stop-hook suite shares
    /// the machine with other builds, and wall-clock tests here have flaked under that load
    /// (PG-331).
    static func threadCPUNanoseconds() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    }

    /// One warm-up run, then the minimum CPU and the minimum wall time of `runs` runs. The noise
    /// is one-sided, so the minimum is the estimate (§D5). `prepare` runs before every call of `body`,
    /// the warm-up included, and is never timed: a fallback row puts the note back with it, so each
    /// run starts from the same text (ADR-0091 §D11).
    static func minimum(
        runs: Int, warmUp: Bool = true, prepare: () -> Void = {}, _ body: () -> Void
    ) -> (cpuMs: Double, wallMs: Double) {
        if warmUp { prepare(); body() }
        var cpu = Double.infinity
        var wall = Double.infinity
        for _ in 0..<max(1, runs) {
            prepare()
            let cpuStart = threadCPUNanoseconds()
            let wallStart = DispatchTime.now().uptimeNanoseconds
            body()
            let wallEnd = DispatchTime.now().uptimeNanoseconds
            let cpuEnd = threadCPUNanoseconds()
            cpu = min(cpu, Double(cpuEnd &- cpuStart) / 1_000_000)
            wall = min(wall, Double(wallEnd &- wallStart) / 1_000_000)
        }
        return (cpu, wall)
    }

    /// Three times the measured "before", rounded up to a whole millisecond (§D5's provisional
    /// ceiling: the build stays green while the work lands).
    static func provisionalCeiling(before ms: Double, factor: Double = 3) -> Double {
        (ms * factor).rounded(.up)
    }

    /// The six ceilings, in milliseconds of thread CPU time per keystroke: three times the "after"
    /// column of ADR-0082 §D9 (the 2026-10-10 run with the `wikilinkSpans` fix), rounded up to a
    /// whole millisecond, as fixed by the person at G-ceiling on 2026-10-10.
    static let ceilings: [Case: Double] = [
        Case(bytes: 50 * kilobyte, variant: .prose): 596,  // before 1469.68 ms, after 198.43 ms
        Case(bytes: 50 * kilobyte, variant: .fences): 677,  // before 1421.30 ms, after 225.34 ms
        Case(bytes: 200 * kilobyte, variant: .prose): 2_735,  // before 21556.50 ms, after 911.37 ms
        Case(bytes: 200 * kilobyte, variant: .fences): 3_200,  // before 19969.66 ms, after 1066.64 ms
        Case(bytes: 1024 * kilobyte, variant: .prose): 18_927,  // before 646462.33 ms (one cold run), after 6308.79 ms
        Case(bytes: 1024 * kilobyte, variant: .fences): 35_532,  // before 655081.13 ms (one cold run), after 11843.73 ms
    ]

    /// `restyle-budget size=<bytes> variant=<prose|fences> cpu_ms=<min> wall_ms=<min> runs=<K>`,
    /// the line `scripts/editor-restyle-bench.sh` greps.
    static func line(_ c: Case, cpuMs: Double, wallMs: Double, runs: Int) -> String {
        "restyle-budget size=\(c.bytes) variant=\(c.variant.rawValue) "
            + "cpu_ms=\(String(format: "%.2f", cpuMs)) wall_ms=\(String(format: "%.2f", wallMs)) runs=\(runs)"
    }
}

// MARK: - The fallback rows (ADR-0091 §D11, R-12)

extension RestyleBudget {
    /// The three keystrokes that cost what a restyle of the note costs, or the table run: printed,
    /// never asserted. Their raw values are what the bench script prints in its `path` column.
    enum FallbackPath: String, Sendable, CaseIterable {
        case fenceOpen = "fence-open"
        case table
        case listEnter = "list-enter"
    }

    /// Whether the fallback rows run. They do when `RESTYLE_BUDGET_FALLBACK=1`, which
    /// `scripts/editor-restyle-bench.sh` sets; the per-turn suite leaves them out, since each is a
    /// measurement of a whole-note restyle and the budget test already pays for six of them.
    static var includesFallbackRows: Bool {
        ProcessInfo.processInfo.environment["RESTYLE_BUDGET_FALLBACK"] == "1"
    }

    /// `restyle-budget-fallback size=<bytes> variant=<prose|fences> path=<fence-open|table|list-enter>
    /// cpu_ms=<min> wall_ms=<min> runs=<K>`, the line `scripts/editor-restyle-bench.sh` greps for its
    /// second table. It starts `restyle-budget-fallback`, so the first table's `^restyle-budget size=`
    /// does not match it.
    static func fallbackLine(_ c: Case, path: FallbackPath, cpuMs: Double, wallMs: Double, runs: Int) -> String {
        "restyle-budget-fallback size=\(c.bytes) variant=\(c.variant.rawValue) path=\(path.rawValue) "
            + "cpu_ms=\(String(format: "%.2f", cpuMs)) wall_ms=\(String(format: "%.2f", wallMs)) runs=\(runs)"
    }

    /// The end of the first paragraph line at or after the middle of the note: a place where one
    /// `x` changes no construct, and the same place on every run.
    static func insertionPoint(in note: String) -> Int {
        let nsNote = note as NSString
        let middle = nsNote.length / 2
        let line = nsNote.range(
            of: "Altro testo con", options: [], range: NSRange(location: middle, length: nsNote.length - middle)
        )
        guard line.location != NSNotFound else { return middle }
        return nsNote.lineRange(for: line).upperBound - 1
    }
}

// MARK: - The structural rows (ADR-0093 §D9, R-13)

extension RestyleBudget {
    /// The four edits that change structure beyond their line, so the restyle falls back to a wide
    /// one: printed, never asserted. Their raw values are what the bench script prints in its `path`
    /// column.
    enum StructuralPath: String, Sendable, CaseIterable {
        case fenceOpenLast = "fence-open-last"
        case fenceOpenAbove = "fence-open-above"
        case wikilinkOpen = "wikilink-open"
        case wikilinkCloseFar = "wikilink-close-far"
    }

    /// Whether the structural rows run. They do when `RESTYLE_BUDGET_STRUCTURAL=1`, which
    /// `scripts/editor-restyle-bench.sh --structural` sets; the per-turn suite leaves them out.
    static var includesStructuralRows: Bool {
        ProcessInfo.processInfo.environment["RESTYLE_BUDGET_STRUCTURAL"] == "1"
    }

    /// `restyle-budget-structural size=<bytes> variant=<prose|fences> path=<fence-open-last|
    /// fence-open-above|wikilink-open|wikilink-close-far> cpu_ms=<min> wall_ms=<min> dirty=<utf16 length>
    /// runs=<K>`, the line `scripts/editor-restyle-bench.sh --structural` greps for its third table. It
    /// starts `restyle-budget-structural`, so neither of the other two tables' patterns match it.
    static func structuralLine(
        _ c: Case, path: StructuralPath, cpuMs: Double, wallMs: Double, dirty: Int, runs: Int
    ) -> String {
        "restyle-budget-structural size=\(c.bytes) variant=\(c.variant.rawValue) path=\(path.rawValue) "
            + "cpu_ms=\(String(format: "%.2f", cpuMs)) wall_ms=\(String(format: "%.2f", wallMs)) "
            + "dirty=\(dirty) runs=\(runs)"
    }
}

/// A hosted editor prepared for one fallback keystroke, which it types and takes back.
///
/// Each path is prepared before any measurement, so the six rows' synthetic notes do not change:
/// - `fence-open`: a line holding two backticks is inserted, and the keystroke is the third, typed at
///   the line's start;
/// - `table`: a table is inserted, and the keystroke is a letter typed in a cell of its row;
/// - `list-enter`: the keystroke is Return at the end of a bullet item, through the command the
///   coordinator claims (`claimsListCommand`).
@MainActor
struct FallbackScenario {
    /// How the coordinator's styling counters moved across one keystroke.
    struct Outcome {
        var before: RestyleLog
        var after: RestyleLog
        var fulls: Int { after.full - before.full }
        var incrementals: Int { after.incremental - before.incremental }
    }

    static let table = "| a | b |\n| --- | --- |\n| 1 | 2 |"

    let fixture: ScrolledEditorFixture
    let path: RestyleBudget.FallbackPath
    /// Where the keystroke lands, in the note as prepared.
    let location: Int
    /// The length of the note as prepared, which `restore()` returns to.
    private let baseLength: Int
    /// For `table`: the run of table lines the restyle should cover once the letter is typed, the last
    /// line's terminator included.
    let expectedTableRun: NSRange?

    init(_ c: RestyleBudget.Case, path: RestyleBudget.FallbackPath) {
        let note = RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        let fixture = ScrolledEditorFixture(text: note)
        let at = RestyleBudget.insertionPoint(in: note)
        var location = at
        var run: NSRange?
        switch path {
        case .fenceOpen:
            fixture.replace(NSRange(location: at, length: 0), with: "\n\n``")
            location = at + 2
        case .table:
            fixture.replace(NSRange(location: at, length: 0), with: "\n\n" + Self.table)
            let start = at + 2
            let header = ("| a | b |\n| --- | --- |\n" as NSString).length
            location = start + header + 3
            // The table, the letter typed in it, and the terminator the original line already had.
            run = NSRange(location: start, length: (Self.table as NSString).length + 1 + 1)
        case .listEnter:
            let ns = note as NSString
            let middle = ns.length / 2
            let item = ns.range(
                of: "- primo punto con **forte**", options: [], range: NSRange(location: middle, length: ns.length - middle)
            )
            location = item.location == NSNotFound ? at : NSMaxRange(item)
        }
        fixture.openLikeTheApp()
        self.fixture = fixture
        self.path = path
        self.location = location
        expectedTableRun = run
        baseLength = (fixture.textView.string as NSString).length
    }

    /// The measured keystroke.
    func keystroke() {
        switch path {
        case .fenceOpen:
            fixture.type("`", at: location)
        case .table:
            fixture.type("x", at: location)
        case .listEnter:
            fixture.textView.setSelectedRange(NSRange(location: location, length: 0))
            fixture.textView.doCommand(by: #selector(NSTextView.insertNewline(_:)))
        }
    }

    /// Takes back whatever the keystroke inserted, so the next run starts from the prepared note.
    /// Nothing when the note is as it was prepared.
    func restore() {
        let extra = (fixture.textView.string as NSString).length - baseLength
        guard extra > 0 else { return }
        fixture.replace(NSRange(location: location, length: extra), with: "")
    }

    /// One keystroke, and how it moved the styling counters; the note is restored afterwards.
    func outcome() -> Outcome {
        restore()
        let before = fixture.coordinator.restyleLog
        keystroke()
        let after = fixture.coordinator.restyleLog
        restore()
        return Outcome(before: before, after: after)
    }
}
