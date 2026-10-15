import Foundation
import Testing
@testable import Pergamenum

// ADR-0087 §D5, plan docs/plans/note-workflow-n5.md, Task 3 (R-42).
//
// How a tag or a date splits into the part read in the secondary colour and the part read in the
// accent. Pure: the counts are UTF-16 units of the chip's own text, the unit the editor's attributes
// are applied in.

@Suite struct InlineChipParts {
    /// A namespaced tag (SPEC §4.4): `#client-` is the namespace and its dash, `acme-srl` the value.
    @Test func aNamespacedTagSplitsAtTheDashAfterItsNamespace() { // R-42
        #expect(InlineChip.tagParts("#client-acme-srl") == InlineChip.Parts(leading: 8, trailing: 8))
        #expect(InlineChip.tagParts("#project-av45") == InlineChip.Parts(leading: 9, trailing: 4))
    }

    /// Outside the closed pattern the tag has no namespace to dim: the `#` only, the rest accent.
    @Test func aTagOutsideTheClosedPatternDimsTheHashOnly() { // R-42
        #expect(InlineChip.tagParts("#idea") == InlineChip.Parts(leading: 1, trailing: 4))
    }

    @Test func aDateKeepsItsAngleBracketInTheLeadingPart() { // R-42
        #expect(InlineChip.dateParts(">2026-10-14 10:30") == InlineChip.Parts(leading: 1, trailing: 16))
        #expect(InlineChip.dateParts(">2026-10-14") == InlineChip.Parts(leading: 1, trailing: 10))
    }

    /// A bare ISO date in prose is not a scheduling token, so it is no chip (SPEC decision).
    @Test func aBareIsoDateIsNoChip() { // R-42
        #expect(InlineChip.dateParts("2026-10-14") == nil)
    }
}
