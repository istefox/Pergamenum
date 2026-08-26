import Foundation
import Testing
@testable import Pergamenum

// ADR-0025 (Workspace resizable board list + concentrazione). `WorkspacePaneDivider.clamp`
// is the pure logic behind the drag handle: it keeps the board list wide enough for its
// own header and filter field, and narrow enough to still read as a sidebar.

@Test func clampLeavesAWidthInsideTheRangeUnchanged() {
    #expect(WorkspacePaneDivider.clamp(240) == 240)
}

@Test func clampFloorsAtTheMinimumWidth() {
    #expect(WorkspacePaneDivider.clamp(40) == WorkspacePaneDivider.minWidth)
}

@Test func clampCeilsAtTheMaximumWidth() {
    #expect(WorkspacePaneDivider.clamp(900) == WorkspacePaneDivider.maxWidth)
}
