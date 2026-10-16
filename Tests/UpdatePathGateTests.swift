import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0096 G-ceiling-406 (PG-406 follow-up), run by `scripts/pg-401-gates.sh --gate update`.
//
// A keystroke in the middle of a note through SwiftUI's update, thread CPU, six rows, each against
// `PG406_CEILING_MS` (default 20, the SPEC's R-01 proposal; the ceilings stay the person's). The judged row
// hosts the person's window (`UpdatePathFixture(window:)`); the same keystroke on the editor column alone is
// printed beside it as `G-ceiling-406-editor`, never judged, so what the window adds stays visible. Both
// rows type into the same note, frontmatter included (`UpdatePathFixture.frontmatter`); the editor-only
// column of ADR-0096's "After, the update rows" table had none, so the two editor figures are not the same
// note.

enum UpdatePathGate {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// The judged row: the whole window.
    static let gateName = "G-ceiling-406"
    /// The printed row: the editor column alone, the host PR #1006's row measures.
    static let editorGateName = "G-ceiling-406-editor"

    /// `PG401_GATES=1`, and `PG401_GATE` unset or `update`.
    static var selected: Bool {
        guard environment["PG401_GATES"] == "1" else { return false }
        guard let only = environment["PG401_GATE"], !only.isEmpty else { return true }
        return only == "update"
    }

    /// Optional `PG406_ONLY=<bytes>-<variant>`, e.g. `1048576-fences`, to run one case.
    static func wanted(_ c: RestyleBudget.Case) -> Bool {
        guard let only = environment["PG406_ONLY"], !only.isEmpty else { return true }
        return only == "\(c.bytes)-\(c.variant.rawValue)"
    }

    static var ceilingMs: Double { Double(environment["PG406_CEILING_MS"] ?? "") ?? 20 }

    /// The `pg401-gate` line `scripts/pg-401-gates.sh` greps, in `PG401Gates.line`'s shape. A nil limit is
    /// a number printed for reading (`info`), never judged.
    static func line(
        gate: String, case name: String, metric: String, value: Double, limit: Double?, scale: Double
    ) -> String {
        let verdict = limit.map { value <= $0 ? "pass" : "fail" } ?? "info"
        let limitText = limit.map { String(format: "%.2f", $0) } ?? "-"
        return "pg401-gate gate=\(gate) case=\(name) metric=\(metric) value=\(String(format: "%.2f", value)) "
            + "limit=\(limitText) verdict=\(verdict) build=\(PG401Gates.buildName) scale=\(String(format: "%.1f", scale))"
    }
}

@MainActor
@Suite(.serialized) struct UpdatePathGateTests {
    // The script counts `gate=G-ceiling-406 .*metric=cpu_ms`: the window's row matches, the editor's does not.
    @Test func theGateLineIsTheOneTheScriptCounts() {
        let judged = UpdatePathGate.line(
            gate: UpdatePathGate.gateName, case: "50KB-prose", metric: "cpu_ms", value: 11.824, limit: 20, scale: 2
        )
        #expect(judged.hasPrefix("pg401-gate gate=G-ceiling-406 case=50KB-prose metric=cpu_ms value=11.82 limit=20.00 verdict=pass build="))
        #expect(judged.hasSuffix("scale=2.0"))
        let editor = UpdatePathGate.line(
            gate: UpdatePathGate.editorGateName, case: "50KB-prose", metric: "cpu_ms", value: 4.41, limit: nil, scale: 2
        )
        #expect(editor.contains("limit=- verdict=info"))
        let counted = "gate=G-ceiling-406 .*metric=cpu_ms"
        #expect(judged.range(of: counted, options: .regularExpression) != nil)
        #expect(editor.range(of: counted, options: .regularExpression) == nil)
        let over = UpdatePathGate.line(
            gate: UpdatePathGate.gateName, case: "1024KB-fences", metric: "cpu_ms", value: 223.58, limit: 20, scale: 2
        )
        #expect(over.contains("verdict=fail"))
    }

    // Always on: the window fixture really makes SwiftUI run its update after every key, so the gate's row
    // never times a keystroke that skipped it, and the window's inspector reads a real frontmatter block.
    @Test func theWindowFixtureRunsSwiftUIsUpdateAfterEveryKeystroke() async throws {
        let fixture = try await UpdatePathFixture(window: .init(bytes: 50 * 1024, variant: .fences))
        defer { fixture.tearDown() }
        #expect(fixture.host.neverShown)
        let opened = try #require(fixture.vault.openNote?.text)
        #expect(CategoryFrontmatter.slug(in: NoteDocument.frontmatter(in: opened).foreignKeys) == "presse")

        // The window really has three panes around the editor. Accessibility identifiers are empty in-process
        // (`ContenitoreHostedViewTests`), so this reads AppKit's views: the note list's table left of the
        // editor's scroll view, and the inspector's scroll view right of it.
        let hosting = fixture.host.hosting
        let editor = try #require(fixture.textView.enclosingScrollView)
        let editorFrame = editor.convert(editor.bounds, to: hosting)
        func frames<V: NSView>(of _: V.Type, in view: NSView) -> [CGRect] {
            ((view as? V).map { [$0.convert($0.bounds, to: hosting)] } ?? []) + view.subviews.flatMap { frames(of: V.self, in: $0) }
        }
        let tables = frames(of: NSTableView.self, in: hosting)
        let scrollViews = frames(of: NSScrollView.self, in: hosting)
        #expect(tables.contains { $0.maxX <= editorFrame.minX + 1 }, "no note list left of the editor: \(tables), editor \(editorFrame)")
        #expect(scrollViews.contains { $0.minX >= editorFrame.maxX - 1 }, "no inspector right of the editor: \(scrollViews), editor \(editorFrame)")

        // The first keystroke after the open restyles in full; the gate's untimed warm-up absorbs it.
        fixture.keystroke()
        var advances: [Int] = []
        for key in 1...3 {
            let before = fixture.coordinator.restyleLog
            fixture.keystroke()
            let after = fixture.coordinator.restyleLog
            #expect(after.skipped >= before.skipped + 1, "key \(key): SwiftUI's update did not run: \(before) then \(after)")
            advances.append(after.skipped - before.skipped)
        }
        // How many updates one key costs in the window (2 in the first measurement, against 1 for the column).
        // Whether the second is the app's own or an artifact of `layoutSubtreeIfNeeded()` on a never-shown
        // window (plus the run-loop spin when the layout ran none) is unverified; a second update that landed
        // only after `keystroke()` returned would also fall outside the gate's timed region.
        print(
            "update-path-window-skipped per-key=\(advances) layout=\(fixture.forcedByLayout) "
                + "runloop=\(fixture.forcedByRunLoop)"
        )

        let text = fixture.textView.string as NSString
        let end = RestyleBudget.insertionPoint(in: text as String)
        let line = text.lineRange(for: NSRange(location: end - 1, length: 0))
        #expect(text.substring(with: line).hasSuffix("xxxx\n"), "the middle paragraph lost a typed character")
        #expect(fixture.vault.openNote?.text == fixture.textView.string)
    }

    @Test(.enabled(if: UpdatePathGate.selected), arguments: PG401Gates.ceilingCases)
    func theUpdateGate(_ c: RestyleBudget.Case) async throws {
        guard UpdatePathGate.wanted(c) else { return }
        let name = "\(c.bytes / 1024)KB-\(c.variant.rawValue)"
        let note = UpdatePathFixture.frontmatter + RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        let runs = RestyleBudget.runs(for: c)

        let window = try await UpdatePathFixture(c, note: note, host: .window)
        // Marker for whoever samples the process: the fixture is built and the keystrokes start now.
        print("update-gate-measuring case=\(name) host=window")
        fflush(stdout)
        let measured = RestyleBudget.minimum(runs: runs, warmUp: RestyleBudget.warmsUp) { window.keystroke() }
        let windowAdvances = window.skippedAdvances
        window.tearDown()

        let editor = try await UpdatePathFixture(c, note: note)
        print("update-gate-measuring case=\(name) host=editor")
        fflush(stdout)
        let editorMeasured = RestyleBudget.minimum(runs: runs, warmUp: RestyleBudget.warmsUp) { editor.keystroke() }
        let editorMissed = editor.missedUpdates
        editor.tearDown()

        let scale = PG401Gates.scale
        let ceiling = UpdatePathGate.ceilingMs
        print(UpdatePathGate.line(gate: UpdatePathGate.gateName, case: name, metric: "wall_ms", value: measured.wallMs, limit: nil, scale: scale))
        print(UpdatePathGate.line(gate: UpdatePathGate.gateName, case: name, metric: "cpu_ms", value: measured.cpuMs, limit: ceiling, scale: scale))
        print(UpdatePathGate.line(gate: UpdatePathGate.editorGateName, case: name, metric: "cpu_ms", value: editorMeasured.cpuMs, limit: nil, scale: scale))
        print("update-gate-forcing case=\(name) window-skipped=\(windowAdvances.sorted { $0.key < $1.key }) editor-missed=\(editorMissed)")

        #expect(windowAdvances[0, default: 0] == 0, "SwiftUI's update did not run after \(windowAdvances[0, default: 0]) keystrokes")
        #expect(editorMissed == 0, "the editor column's update did not run after \(editorMissed) keystrokes")
        #expect(measured.cpuMs <= ceiling, "\(c): \(measured.cpuMs) ms against \(ceiling)")
    }
}
