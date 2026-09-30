import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D11, plan docs/plans/contenitore.md, Task 7 - R-13, R-14, R-25. The
// pane built for real in a window that is never shown (`HostedViewSupport.swift`, R-15 of the
// harness): three schede, one in the inbox, one classified, one whose file is gone.
//
// **Why no `accessibilityIdentifier` lookup.** The plan asks for one, and it was tried first:
// measured on macOS 27 / Xcode 27 (2026-09-30), every `NSView` and every accessibility element
// reachable from the hosting view reports an empty identifier, the pane's own
// `contenitore-pane` included, and each list cell's `CellHostingView` has no accessibility
// children. That is `HostedViewSupport.swift`'s own finding ("a single childless group
// in-process"). What *is* reachable is AppKit's table under each SwiftUI `List`, so the test
// counts the documents table's rows, telling it from the container column's table by where
// the pane puts it (right of the 230 pt column), never by a private SwiftUI class name or by
// visible text. The inbox count and «file mancante» cannot be read off the tree; they are
// checked through `ContenitoreDocuments.rows(vault:contenitore:)` and
// `ContenitoreListModel.inboxCount`, the two calls the views draw them from.

/// Every `NSTableView` under `view`, with its frame in `view`'s coordinates.
@MainActor
private func tables(in view: NSView) -> [(table: NSTableView, frame: CGRect)] {
    func collect(_ subview: NSView) -> [NSTableView] {
        ((subview as? NSTableView).map { [$0] } ?? []) + subview.subviews.flatMap(collect)
    }
    return collect(view).map { ($0, $0.convert($0.bounds, to: view)) }
}

@MainActor
@Test func thePaneListsThreeRowsCountsOneInTheInboxAndMarksTheMissingFile() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: "20260929 Da classificare", in: "Contenitore/2026", date: "2026-09-29", vault: vault)
    try ContenitoreFixture.seed(
        stem: "20260314 Fattura", in: "Contenitore/Fatture/2026", tags: ContenitoreFixture.classified,
        colour: .verde, vault: vault
    )
    try ContenitoreFixture.seed(
        stem: "20260101 Persa", in: "Contenitore/2026", date: "2026-01-01", tags: ContenitoreFixture.classified,
        withFile: false, vault: vault
    )
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    harness.navigation.pane = .contenitore

    let host = HostedView(
        ContenitoreView()
            .environment(\.theme, .emergency)
            .environment(harness.vault)
            .environment(harness.navigation)
            .environment(harness.contenitore),
        size: CGSize(width: 1400, height: 800)
    )
    defer { host.tearDown() }
    await host.settle()

    let found = tables(in: host.hosting)
    let documents = found.filter { $0.frame.minX >= 230 }
    let column = found.filter { $0.frame.maxX <= 231 }
    #expect(documents.count == 1, "one documents list beside the container column")
    #expect(documents.first?.table.numberOfRows == 3)
    // «Tutti», «Da classificare», the «Sottocontenitori» header and «Fatture»: never the year folders.
    #expect(column.first?.table.numberOfRows == 4)

    let rows = ContenitoreDocuments.rows(vault: harness.vault, contenitore: harness.contenitore)
    #expect(rows.count == 3)
    #expect(rows.filter(\.isFileMissing).map(\.name) == ["20260101 Persa"])
    let session = try #require(harness.vault.session)
    #expect(ContenitoreListModel.inboxCount(index: session.index, root: harness.contenitore.root) == 1)
    #expect(host.snapshot().map { $0.distinctColors > 1 } == true, "the pane drew something")

    #expect(host.neverShown)
    #expect(host.refusals.isEmpty)
}
