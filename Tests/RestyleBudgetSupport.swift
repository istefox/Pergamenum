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

    /// Whether the 1 MB cases run. A keystroke in a 1 MB note cost about eleven minutes of CPU on
    /// the untouched code (ADR-0082 §D9), so the per-turn suite cannot afford them. They
    /// run when `RESTYLE_BUDGET_1MB=1` (`scripts/editor-restyle-bench.sh --large`), or alone when
    /// it is `only` (`--large-only`).
    static var includesLargeNotes: Bool {
        ["1", "only"].contains(ProcessInfo.processInfo.environment["RESTYLE_BUDGET_1MB"])
    }

    /// Whether the 200 KB cases run. One keystroke in a 200 KB note costs 20 to 26 s of CPU before
    /// and after the N2 work, and with their warm-ups the two rows are most of the 397 s the four
    /// rows added to the suite when measured, which the Stop hook's 600 s cannot carry beside the
    /// rest of it (ADR-0082 §D9). They run when
    /// `RESTYLE_BUDGET_200KB=1`, which `scripts/editor-restyle-bench.sh` sets on every run but
    /// `--large-only`; the per-turn suite asserts the two 50 KB rows only.
    static var includesMediumNotes: Bool {
        ProcessInfo.processInfo.environment["RESTYLE_BUDGET_200KB"] == "1"
    }

    /// Whether the warm-up keystroke runs. `RESTYLE_BUDGET_NO_WARMUP=1` skips it, only for a
    /// measurement where one keystroke already takes minutes.
    static var warmsUp: Bool {
        ProcessInfo.processInfo.environment["RESTYLE_BUDGET_NO_WARMUP"] != "1"
    }

    /// The cases this run measures, smallest first: the 50 KB rows unless only the 1 MB ones were
    /// asked for, the 200 KB rows behind `includesMediumNotes`, the 1 MB rows behind
    /// `includesLargeNotes`.
    static var activeCases: [Case] {
        let largeOnly = ProcessInfo.processInfo.environment["RESTYLE_BUDGET_1MB"] == "only"
        return ceilings.keys
            .filter { c in
                if c.bytes >= 1024 * kilobyte { return includesLargeNotes }
                if largeOnly { return false }
                return c.bytes < 200 * kilobyte || includesMediumNotes
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
    /// is one-sided, so the minimum is the estimate (§D5).
    static func minimum(runs: Int, warmUp: Bool = true, _ body: () -> Void) -> (cpuMs: Double, wallMs: Double) {
        if warmUp { body() }
        var cpu = Double.infinity
        var wall = Double.infinity
        for _ in 0..<max(1, runs) {
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

    /// The six ceilings, in milliseconds of thread CPU time per keystroke. Provisional: three
    /// times the "before" column of ADR-0082 §D9, written here after the first measured run on
    /// untouched code. The person fixes the final six at G-ceiling.
    static let ceilings: [Case: Double] = [
        Case(bytes: 50 * kilobyte, variant: .prose): 4_410,  // before 1469.68 ms
        Case(bytes: 50 * kilobyte, variant: .fences): 4_264,  // before 1421.30 ms
        Case(bytes: 200 * kilobyte, variant: .prose): 64_670,  // before 21556.50 ms
        Case(bytes: 200 * kilobyte, variant: .fences): 59_909,  // before 19969.66 ms
        Case(bytes: 1024 * kilobyte, variant: .prose): 1_939_387,  // before 646462.33 ms, one cold run
        Case(bytes: 1024 * kilobyte, variant: .fences): 1_965_244,  // before 655081.13 ms, one cold run
    ]

    /// `restyle-budget size=<bytes> variant=<prose|fences> cpu_ms=<min> wall_ms=<min> runs=<K>`,
    /// the line `scripts/editor-restyle-bench.sh` greps.
    static func line(_ c: Case, cpuMs: Double, wallMs: Double, runs: Int) -> String {
        "restyle-budget size=\(c.bytes) variant=\(c.variant.rawValue) "
            + "cpu_ms=\(String(format: "%.2f", cpuMs)) wall_ms=\(String(format: "%.2f", wallMs)) runs=\(runs)"
    }
}
