import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0091 §Gates, plan PG-401 (R-14, R-15 and G-ceiling-2): the three acceptance gates that were a
// person looking at a Release build, turned into numbers with a fixed limit each.
//
// They are opt-in (`PG401_GATES=1`, which `scripts/pg-401-gates.sh` sets) because the 1 MB rows
// take minutes in a Debug build and a measurement is only a verdict on a Release one: every line
// carries `build=`, and the script refuses to certify a Debug run. The per-turn suite runs the pure
// helpers at the top and skips the rest.
//
// What this does not cover, on purpose: the deferred display pass, the SwiftUI update after the
// binding write, and whether a number under the limit *feels* smooth. The limits are the
// proposals the SPEC and the ADR name (20 ms of CPU per keystroke; one 60 Hz frame for a typed
// sentence), not a perception test. Thread CPU time, never wall time, is what a limit is set on
// (PG-331); wall time is printed beside it.

enum PG401Gates {
    enum Gate: String, CaseIterable {
        case ceiling = "G-ceiling-2"
        case grow = "G-grow"
        case type = "G-type"

        /// The `PG401_GATE` value that selects only this gate.
        var key: String {
            switch self {
            case .ceiling: "ceiling"
            case .grow: "grow"
            case .type: "type"
            }
        }
    }

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Whether the gates run at all. `PG401_GATES=1`.
    static var enabled: Bool { environment["PG401_GATES"] == "1" }

    /// Whether `gate` runs: enabled, and not excluded by `PG401_GATE=<ceiling|grow|type>`.
    static func selected(_ gate: Gate) -> Bool {
        guard enabled else { return false }
        guard let only = environment["PG401_GATE"], !only.isEmpty else { return true }
        return only == gate.key
    }

    /// G-ceiling-2: milliseconds of thread CPU per keystroke, all six rows. The SPEC proposes 20.
    static var ceilingMs: Double { Double(environment["PG401_CEILING_MS"] ?? "") ?? 20 }
    /// G-type: milliseconds of thread CPU per typed character, 95th percentile. One 60 Hz frame.
    static var typeLimitMs: Double { Double(environment["PG401_TYPE_MS"] ?? "") ?? 16 }
    /// G-grow: wall milliseconds one step of the sequence may take before it counts as a freeze.
    /// Unset by default: the ADR's G-grow is about where the view and the caret end up, and nobody
    /// has fixed a time for a step, so the wall times are printed and not judged until
    /// `PG401_STEP_MS` names one.
    static var stepLimitMs: Double? { Double(environment["PG401_STEP_MS"] ?? "") }

    static let buildName: String = {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }()

    /// The six G-ceiling-2 rows, smallest first.
    static let ceilingCases: [RestyleBudget.Case] = RestyleBudget.ceilings.keys
        .sorted { ($0.bytes, $0.variant.rawValue) < ($1.bytes, $1.variant.rawValue) }

    /// Nearest-rank percentile, `p` in 0...1. Empty input is 0.
    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(sorted.count - 1, max(0, rank - 1))]
    }

    /// `pg401-gate gate=<id> case=<name> metric=<name> value=<v> limit=<l|-> verdict=<pass|fail|info>
    /// build=<debug|release> scale=<backing scale>`, the line `scripts/pg-401-gates.sh` greps. A limit
    /// of nil is a number printed for reading (`info`), never judged.
    static func line(
        _ gate: Gate, case name: String, metric: String, value: Double, limit: Double?, scale: Double
    ) -> String {
        let verdict = limit.map { value <= $0 ? "pass" : "fail" } ?? "info"
        let limitText = limit.map { String(format: "%.2f", $0) } ?? "-"
        return format(gate, name, metric, String(format: "%.2f", value), limitText, verdict, scale)
    }

    /// A pass/fail fact with no number: the value is 1 when it holds and 0 when it does not, the
    /// limit 1, so the same grep reads it.
    static func checkLine(_ gate: Gate, case name: String, metric: String, holds: Bool, scale: Double) -> String {
        format(gate, name, metric, holds ? "1.00" : "0.00", "1.00", holds ? "pass" : "fail", scale)
    }

    private static func format(
        _ gate: Gate, _ name: String, _ metric: String, _ value: String, _ limit: String, _ verdict: String, _ scale: Double
    ) -> String {
        "pg401-gate gate=\(gate.rawValue) case=\(name) metric=\(metric) value=\(value) limit=\(limit) "
            + "verdict=\(verdict) build=\(buildName) scale=\(String(format: "%.1f", scale))"
    }

    @MainActor static var scale: Double { Double(NSScreen.main?.backingScaleFactor ?? 1) }

    /// Prints a measured row and says whether it passed.
    @MainActor @discardableResult
    static func report(_ gate: Gate, case name: String, metric: String, value: Double, limit: Double?) -> Bool {
        print(line(gate, case: name, metric: metric, value: value, limit: limit, scale: scale))
        return limit.map { value <= $0 } ?? true
    }

    /// Prints a yes/no row and returns it.
    @MainActor @discardableResult
    static func check(_ gate: Gate, case name: String, metric: String, holds: Bool) -> Bool {
        print(checkLine(gate, case: name, metric: metric, holds: holds, scale: scale))
        return holds
    }
}

@MainActor
@Suite(.serialized) struct PG401GateTests {
    // MARK: Pure (always on)

    @Test func thePercentileIsTheNearestRank() {
        let values = (1...20).map(Double.init)
        #expect(PG401Gates.percentile(values, 0.95) == 19)
        #expect(PG401Gates.percentile(values, 1) == 20)
        #expect(PG401Gates.percentile(values.reversed(), 0.5) == 10)
        #expect(PG401Gates.percentile([7], 0.95) == 7)
        #expect(PG401Gates.percentile([], 0.95) == 0)
    }

    @Test func aLineCarriesTheNineFieldsTheScriptGreps() {
        let pass = PG401Gates.line(.type, case: "50KB-prose", metric: "p95_cpu_ms", value: 3.456, limit: 16, scale: 2)
        #expect(pass.hasPrefix("pg401-gate gate=G-type case=50KB-prose metric=p95_cpu_ms value=3.46 limit=16.00 verdict=pass build="))
        #expect(pass.hasSuffix("scale=2.0"))
        #expect(PG401Gates.line(.ceiling, case: "c", metric: "m", value: 20.01, limit: 20, scale: 1).contains("verdict=fail"))
        #expect(PG401Gates.line(.ceiling, case: "c", metric: "m", value: 20, limit: 20, scale: 1).contains("verdict=pass"))
        #expect(PG401Gates.line(.grow, case: "c", metric: "m", value: 5, limit: nil, scale: 1).contains("limit=- verdict=info"))
    }

    @Test func aCheckLineIsPassOnlyWhenItHolds() {
        #expect(PG401Gates.checkLine(.grow, case: "c", metric: "m", holds: true, scale: 1).contains("value=1.00 limit=1.00 verdict=pass"))
        #expect(PG401Gates.checkLine(.grow, case: "c", metric: "m", holds: false, scale: 1).contains("value=0.00 limit=1.00 verdict=fail"))
    }

    @Test func theCeilingGateHasTheSixRows() {
        #expect(PG401Gates.ceilingCases.count == 6)
        #expect(PG401Gates.ceilingCases.first?.bytes == 50 * 1024)
        #expect(PG401Gates.ceilingCases.last?.bytes == 1024 * 1024)
    }

    // MARK: G-ceiling-2

    // One keystroke in the middle of the note, measured as the budget test measures it, against the
    // proposed 20 ms. The six ceilings in `RestyleBudget.ceilings` are not touched: fixing them is the
    // person's decision, this only says which rows the proposal would hold on this build.
    @Test(.enabled(if: PG401Gates.selected(.ceiling)), arguments: PG401Gates.ceilingCases)
    func aKeystrokeStaysUnderTheProposedCeiling(_ c: RestyleBudget.Case) {
        let note = RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        let fixture = ScrolledEditorFixture(text: note)
        defer { fixture.window.orderOut(nil) }
        let at = RestyleBudget.insertionPoint(in: note)
        fixture.openLikeTheApp()

        let measured = RestyleBudget.minimum(runs: RestyleBudget.runs(for: c), warmUp: RestyleBudget.warmsUp) {
            fixture.type("x", at: at)
        }

        let name = "\(c.bytes / 1024)KB-\(c.variant.rawValue)"
        PG401Gates.report(.ceiling, case: name, metric: "wall_ms", value: measured.wallMs, limit: nil)
        let ok = PG401Gates.report(.ceiling, case: name, metric: "cpu_ms", value: measured.cpuMs, limit: PG401Gates.ceilingMs)
        #expect(ok, "\(c): \(measured.cpuMs) ms of thread CPU against \(PG401Gates.ceilingMs)")
    }

    // MARK: G-grow (R-14)

    private func caretIsVisible(_ fixture: ScrolledEditorFixture) -> Bool {
        let caret = fixture.textView.caretRectOnScreen()
        guard caret.height > 0 else { return false }
        let inView = fixture.textView.convert(fixture.window.convertFromScreen(caret), from: nil)
        return fixture.textView.visibleRect.contains(CGPoint(x: inView.midX, y: inView.midY))
    }

    private func wallMilliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    // The hand check of ADR-0091 §Gates, in its own order, on a 1 MB note: type at the end and in the
    // middle, Cmd+Down, scroll to the end, click low in the pane. After each step the caret or the
    // view is where it should be (and, when `PG401_STEP_MS` is set, the step took no longer than that in
    // wall time); at the end no height in the note is an estimate (the symptom the first G-grow found on 2026-10-10).
    @Test(.enabled(if: PG401Gates.selected(.grow)))
    func theGrowSequenceOnAOneMegabyteNoteLeavesTheViewWhereThePersonPutIt() throws {
        let note = RestyleBudget.syntheticNote(bytes: 1024 * 1024, variant: .fences)
        let fixture = ScrolledEditorFixture(text: note)
        defer { fixture.window.orderOut(nil) }
        let layout = try #require(fixture.textView.textLayoutManager)
        let limit = PG401Gates.stepLimitMs
        let name = "1MB-fences"
        fixture.openLikeTheApp()

        func judge(_ step: String, wall: Double, holds: Bool) {
            let fast = PG401Gates.report(.grow, case: "\(name)/\(step)", metric: "wall_ms", value: wall, limit: limit)
            let right = PG401Gates.check(.grow, case: "\(name)/\(step)", metric: "state", holds: holds)
            #expect(fast, "\(step) took \(wall) ms, more than \(limit ?? 0)")
            #expect(right, "\(step) left the view in the wrong state")
        }

        // 1. Type at the end of the note.
        let end = (fixture.textView.string as NSString).length
        var wall = wallMilliseconds { fixture.type("x", at: end); fixture.runPasses() }
        judge("type-end", wall: wall, holds: caretIsVisible(fixture))

        // 2. Type in the middle.
        let middle = RestyleBudget.insertionPoint(in: fixture.textView.string)
        wall = wallMilliseconds { fixture.type("x", at: middle); fixture.runPasses() }
        judge("type-middle", wall: wall, holds: caretIsVisible(fixture))

        // 3. Cmd+Down: the caret goes to the end and the viewport is laid out there.
        wall = wallMilliseconds {
            fixture.textView.moveToEndOfDocument(nil)
            layout.textViewportLayoutController.layoutViewport()
            fixture.textView.scrollRangeToVisible(fixture.textView.selectedRange())
            layout.textViewportLayoutController.layoutViewport()
        }
        judge("cmd-down", wall: wall, holds: caretIsVisible(fixture))

        // 4. Scroll to the end of the frame.
        let clip = fixture.scrollView.contentView
        wall = wallMilliseconds {
            clip.scroll(to: NSPoint(x: 0, y: max(0, fixture.textView.frame.height - clip.bounds.height)))
            fixture.scrollView.reflectScrolledClipView(clip)
            layout.textViewportLayoutController.layoutViewport()
        }
        judge("scroll-end", wall: wall, holds: fixture.textView.visibleRect.maxY >= fixture.textView.frame.height - 1)

        // 5. Click low in the pane. The click's own update runs the passes; the view must stay on the
        // same text, and the caret must land where the click was, not select the note.
        func index(atFraction fraction: CGFloat) -> Int {
            let visible = fixture.textView.visibleRect
            return fixture.textView.characterIndexForInsertion(
                at: CGPoint(x: visible.midX, y: visible.minY + visible.height * fraction)
            )
        }
        let topBefore = index(atFraction: 0.01)
        let clicked = index(atFraction: 0.92)
        wall = wallMilliseconds {
            fixture.textView.setSelectedRange(NSRange(location: clicked, length: 0))
            fixture.runPasses()
        }
        let topAfter = index(atFraction: 0.01)
        let selection = fixture.textView.selectedRange()
        judge(
            "click-low", wall: wall,
            holds: abs(topAfter - topBefore) < 200 && selection.length == 0 && selection.location == clicked
        )

        // 6. After the passes nothing in the note is an estimate: laying it all out changes no height.
        let grown = layout.usageBoundsForTextContainer.height
        layout.ensureLayout(for: layout.documentRange)
        let complete = layout.usageBoundsForTextContainer.height
        let exact = PG401Gates.check(.grow, case: "\(name)/layout-complete", metric: "state", holds: abs(grown - complete) < 0.5)
        #expect(exact, "the note measured \(grown) pt after the passes and \(complete) pt laid out whole")
    }

    // MARK: G-type (R-15)

    private static let sentence = "Questa e una frase scritta di seguito, senza fermarsi, per sentire se la nota ritarda."

    // A sentence typed one character at a time in the middle of a 50 KB note, each character through
    // the keystroke and the passes the update runs after it. The 95th percentile of thread CPU per
    // character against one frame; the worst CPU and wall times are printed beside it.
    @Test(.enabled(if: PG401Gates.selected(.type)), arguments: RestyleBudget.Variant.allCases)
    func aTypedSentenceStaysUnderOneFramePerCharacter(_ variant: RestyleBudget.Variant) {
        let note = RestyleBudget.syntheticNote(bytes: 50 * 1024, variant: variant)
        let fixture = ScrolledEditorFixture(text: note)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()
        let start = RestyleBudget.insertionPoint(in: note)

        func typeSentence(at origin: Int) -> (cpu: [Double], wall: [Double]) {
            var cpu: [Double] = []
            var wall: [Double] = []
            for (offset, character) in Self.sentence.enumerated() {
                let cpuStart = RestyleBudget.threadCPUNanoseconds()
                let wallStart = DispatchTime.now().uptimeNanoseconds
                fixture.type(String(character), at: origin + offset)
                fixture.runPasses()
                let wallEnd = DispatchTime.now().uptimeNanoseconds
                let cpuEnd = RestyleBudget.threadCPUNanoseconds()
                cpu.append(Double(cpuEnd &- cpuStart) / 1_000_000)
                wall.append(Double(wallEnd - wallStart) / 1_000_000)
            }
            return (cpu, wall)
        }

        _ = typeSentence(at: start)  // warm-up: the first keystrokes pay for caches
        let measured = typeSentence(at: start + (Self.sentence as NSString).length + 2)

        let name = "50KB-\(variant.rawValue)"
        let p95 = PG401Gates.percentile(measured.cpu, 0.95)
        PG401Gates.report(.type, case: name, metric: "max_cpu_ms", value: measured.cpu.max() ?? 0, limit: nil)
        PG401Gates.report(.type, case: name, metric: "max_wall_ms", value: measured.wall.max() ?? 0, limit: nil)
        let ok = PG401Gates.report(.type, case: name, metric: "p95_cpu_ms", value: p95, limit: PG401Gates.typeLimitMs)
        #expect(ok, "\(name): the 95th percentile of CPU per character was \(p95) ms against \(PG401Gates.typeLimitMs)")
    }
}
