import AppKit
import Testing
@testable import Pergamenum

// PG-102: `TableAttachmentViewProvider.attachmentBounds` is nonisolated and read the
// grid's `intrinsicContentSize` (main-actor state) across the isolation boundary. The
// grid now records the size at the end of every `layoutGrid()` in a lock-guarded box
// (`TableSizeBox`, ADR-0035's shape) and the provider reads the record.

@MainActor
@Test func aGridRecordsTheSizeItMeasuredForTheNonisolatedAttachment() throws {
    let grid = TableGridView()
    #expect(grid.measuredSize.size == nil, "nothing is recorded before the first layout")

    let lines = ["| a | b |", "|---|---|", "| 1 | 2 |"]
    let table = try #require(GFMTable.parse(lines[...]))
    grid.update(with: table, theme: .emergency)

    let recorded = try #require(grid.measuredSize.size)
    #expect(recorded == grid.intrinsicContentSize)
    #expect(recorded.width > 0 && recorded.height > 0)
}

@MainActor
@Test func aReshapedGridRecordsItsNewSize() throws {
    let grid = TableGridView()
    let two = try #require(GFMTable.parse(["| a | b |", "|---|---|", "| 1 | 2 |"][...]))
    grid.update(with: two, theme: .emergency)
    let before = try #require(grid.measuredSize.size)

    let three = try #require(GFMTable.parse(["| a | b |", "|---|---|", "| 1 | 2 |", "| 3 | 4 |"][...]))
    grid.update(with: three, theme: .emergency)
    let after = try #require(grid.measuredSize.size)

    #expect(after.height > before.height)
    #expect(after == grid.intrinsicContentSize)
}

@Test func theSizeBoxIsReadableOffTheMainActor() async {
    let box = TableSizeBox()
    #expect(box.size == nil)
    box.size = NSSize(width: 10, height: 20)
    let read = await Task.detached { box.size }.value
    #expect(read == NSSize(width: 10, height: 20))
}
