import Foundation
import Testing
@testable import Pergamenum

// ADR-0082 §D3, plan docs/plans/pg-385-n2-page.md, Task 1 (PG-385, R-18).
//
// `MarkdownStyler`'s output pinned for every case of `StylerGoldenCorpus`: a case's current
// canonical output equals its `captured` bytes, or, once Task 3 has classed it, its class's own
// `expected`. Green on untouched code by construction, because `captured` is what the old styler
// printed. Beside it, three properties of the corpus itself, and the capture helper.

// (n2-page R-18)
@MainActor
@Test(arguments: StylerGoldenCorpus.cases)
func stylerOutputMatchesTheGolden(_ golden: StylerGoldenCase) {
    let output = StylerGoldenCorpus.canonical(golden.markdown)
    #expect(output == golden.expected, "\(golden.name): \(output.debugDescription)")
}

// (n2-page R-18) G0 item 2: a case added to the export corpus without a styler case is a gap.
@Test func everyExportCaseHasAStylerCase() {
    let styled = Set(StylerGoldenCorpus.cases.map(\.name))
    let exported = NoteExportGoldenCorpus.bodies + NoteExportGoldenPages.all
    #expect(exported.count >= 59, "the export corpus is E01 to E48 plus X01 to X09 plus W01, W02")
    for golden in exported {
        #expect(styled.contains(golden.name), "\(golden.name) has no styler case")
    }
    // And the styler case carries the export case's own markdown, never a copy that could drift.
    let byName = Dictionary(uniqueKeysWithValues: StylerGoldenCorpus.cases.map { ($0.name, $0.markdown) })
    for golden in exported {
        #expect(byName[golden.name] == golden.markdown, "\(golden.name): markdown differs from the export corpus")
    }
}

// (n2-page R-18) ADR-0082 §D3: a class carries a reason, and a classed case is one that moved.
@Test func everyClassedCaseCarriesAReasonAndAMovedOutput() {
    for golden in StylerGoldenCorpus.cases {
        switch golden.change {
        case .unchanged:
            break
        case .fix(let reason, let expected), .deliberate(let reason, let expected):
            #expect(!reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(golden.name): empty reason")
            #expect(expected != golden.captured, "\(golden.name): a classed case must differ from its capture")
        }
    }
    let names = Set(StylerGoldenCorpus.cases.map(\.name))
    for name in StylerGoldenCorpus.changes.keys {
        #expect(names.contains(name), "\(name) is classed but is not a case")
    }
}

// (n2-page R-18) Every case was captured, none twice, and no capture is left without an input.
@Test func everyCaseIsCapturedExactlyOnce() {
    let names = StylerGoldenCorpus.cases.map(\.name)
    #expect(Set(names).count == names.count, "duplicate case names")
    for golden in StylerGoldenCorpus.cases {
        #expect(golden.captured != "<not captured>", "\(golden.name) has no captured output")
    }
    #expect(StylerGoldenCorpus.editorInputs.count >= 40, "the editor's own constructs (ADR-0082 §D3)")
}

// (n2-page R-18) The canonical form itself: spans sorted, hidden kinds, then overlap order.
@MainActor
@Test func theCanonicalFormListsSpansThenHiddenKindsThenOverlapOrder() {
    let output = StylerGoldenCorpus.canonical("# Titolo")
    #expect(output.contains("0..<2 headingMarker"))
    #expect(output.contains("0..<8 heading(level: 1)"))
    #expect(output.contains("hidden 0..<2 heading"))
    #expect(output.contains("order 0..<8 heading(level: 1) < 0..<2 headingMarker"))
    // Sorted spans first, then `hidden`, then `order`: the three groups never interleave.
    let lines = output.split(separator: "\n").map(String.init)
    let kinds = lines.map { $0.hasPrefix("hidden ") ? 1 : $0.hasPrefix("order ") ? 2 : 0 }
    #expect(kinds == kinds.sorted())
    #expect(StylerGoldenCorpus.canonical("") == "")
}

// MARK: - The capture helper

/// Prints the captured entry of every input, as Swift literals to paste: the `E`, `X` and `W`
/// entries into `StylerGoldenCapturedExport.swift`, the `S` entries into
/// `StylerGoldenCapturedEditor.swift`. Gated on
/// `TEST_RUNNER_STYLER_GOLDEN_CAPTURE=1`, which `xcodebuild` hands the test process as
/// `STYLER_GOLDEN_CAPTURE=1`; both spellings are read. Kept in the file so N5 can reuse it for
/// the constructs it adds: capture first, change the styler after, class the differences.
private let capturing = {
    let environment = ProcessInfo.processInfo.environment
    return environment["TEST_RUNNER_STYLER_GOLDEN_CAPTURE"] == "1" || environment["STYLER_GOLDEN_CAPTURE"] == "1"
}()

@MainActor
@Test(.enabled(if: capturing))
func stylerGoldenCapture() {
    var out = "// BEGIN STYLER GOLDEN CAPTURE\n"
    for input in StylerGoldenCorpus.inputs {
        let body = StylerGoldenCorpus.canonical(input.markdown)
        // A raw literal with enough `#` that nothing inside the body can close it.
        var hashes = "#"
        while body.contains("\"\"\"" + hashes) { hashes += "#" }
        out += "    \"\(input.name)\": \(hashes)\"\"\"\n"
        if !body.isEmpty {
            for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
                out += "        \(line)\n"
            }
        }
        out += "        \"\"\"\(hashes),\n"
    }
    out += "// END STYLER GOLDEN CAPTURE\n"
    print(out)
    if let path = ProcessInfo.processInfo.environment["STYLER_GOLDEN_CAPTURE_PATH"] {
        try? out.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
