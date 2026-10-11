import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0091 §D7, plan docs/plans/per-paragraph-restyle.md, Task 3 (R-09).
//
// The transclusion pass scans the dirty range and not the whole note after a line-local edit. Each
// test reads what the scan covered (`lastScannedRange`) and compares the rendition table with its
// twin's, whose full restyle scans the whole note every time.
//
// A whole scan records no range, so the dirty-range assertions also pin that the scan was scoped,
// and `restyleLog` that the styling before it took the incremental path.

/// The scan covered the whole note: nothing recorded, or the whole range.
@MainActor
private func scannedTheWholeNote(_ controller: TransclusionController, length: Int) -> Bool {
    controller.lastScannedRange == nil || controller.lastScannedRange == NSRange(location: 0, length: length)
}

@MainActor
@Suite(.serialized) struct TransclusionScope {
    // (R-09) After a prose keystroke the scan covers the dirty range, and the table of renditions is
    // the one a whole scan gives.
    @Test func aProseKeystrokeScansTheDirtyRangeAndNothingElse() async throws {
        let twin = try await RestyleTwin.rich()
        defer { twin.tearDown() }
        let before = twin.incremental.coordinator.transclusion.lastRenditions
        #expect(!before.isEmpty, "no transclusion to keep")

        twin.type("x", at: 12)

        let controller = twin.incremental.coordinator.transclusion
        let dirty = try #require(twin.incremental.coordinator.restyleLog.lastDirtyRange, "the keystroke was not restyled by the dirty range")
        let scanned = try #require(controller.lastScannedRange, "the scan was whole")
        #expect(scanned == dirty)
        #expect(NSLocationInRange(12, scanned) || NSMaxRange(scanned) == 12)
        #expect(scanned.length < twin.incremental.textView.string.utf16.count / 2, "the scan is not small: \(scanned)")

        #expect(controller.lastRenditions.keys.sorted() == twin.full.coordinator.transclusion.lastRenditions.keys.sorted())
        #expect(controller.lastRenditions.count == before.count)
        #expect(twin.differences().isEmpty, "\(twin.differences())")
    }

    // (R-09) A keystroke on the transclusion line is the new occurrence: the target gains a letter, the
    // line is rescanned, and the note it now names is the one drawn.
    @Test func aKeystrokeOnATransclusionLineYieldsTheNewOccurrence() async throws {
        let twin = try await RestyleTwin.rich()
        defer { twin.tearDown() }
        let line = (twin.incremental.textView.string as NSString).range(of: RichNote.transclusionLine)
        #expect(line.location != NSNotFound)
        // After "![[" and "Prove", before "]]".
        let insideTarget = line.location + 3 + 5

        twin.type("x", at: insideTarget)

        let controller = twin.incremental.coordinator.transclusion
        #expect(twin.incremental.textView.string.contains("![[Provex]]"), "the keystroke did not land in the target")
        #expect(controller.lastRenditions.keys.contains(line.location), "no rendition on the line the keystroke was typed on")
        #expect(controller.renditionCache.keys.contains { $0.hasPrefix("Provex#") }, "the new target was not resolved: \(controller.renditionCache.keys.sorted())")
        let scanned = try #require(controller.lastScannedRange, "the scan was whole")
        #expect(NSIntersectionRange(scanned, line).length > 0, "the scan \(scanned) missed the line \(line)")
        #expect(controller.lastRenditions.keys.sorted() == twin.full.coordinator.transclusion.lastRenditions.keys.sorted())
        #expect(twin.differences().isEmpty, "\(twin.differences())")
    }

    // (R-09) A keystroke on a fence line is a full restyle, and the scan is whole.
    @Test func aFenceLineKeystrokeScansTheWholeNote() async throws {
        let twin = try await RestyleTwin.rich()
        defer { twin.tearDown() }
        let fence = (twin.incremental.textView.string as NSString).range(of: "```pergamenum-view")
        // The caret goes onto the fence first, and the count is taken after. Moving it there crosses
        // the view-block fence, which is a full restyle of its own (plan Task 5 §5, ADR-0091 §D10), and
        // typing from elsewhere would count that crossing as well as the keystroke: the +1 below is
        // the keystroke's own full restyle, and the crossing is not what this test is about.
        twin.both { $0.textView.setSelectedRange(NSRange(location: fence.location + 3, length: 0)) }
        twin.both { $0.runPasses() }
        let before = twin.incremental.coordinator.restyleLog

        twin.type("`", at: fence.location + 3)

        let log = twin.incremental.coordinator.restyleLog
        #expect(log.full == before.full + 1, "a fence-line keystroke was not a full restyle: \(before) then \(log)")
        let controller = twin.incremental.coordinator.transclusion
        #expect(scannedTheWholeNote(controller, length: twin.incremental.textView.string.utf16.count))
        #expect(controller.lastRenditions.keys.sorted() == twin.full.coordinator.transclusion.lastRenditions.keys.sorted())
        #expect(twin.differences().isEmpty, "\(twin.differences())")
    }
}
