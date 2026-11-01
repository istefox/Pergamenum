import Foundation
import Testing
@testable import Pergamenum

// R-09 (PG-441): both `pergamenum://` entry points go through `AppDelegate.handle(urls:)`. The
// controller's own queue is pinned by `PendingRouteTests`; what is pinned here is the door in
// front of it - links parked while the delegate has no vault, replayed in order once it has one,
// batches chained behind each other, and a link the parser refuses neither parked nor performed.
//
// Only `.note` routes are used, so `ForegroundHandBack.handBack` (which may activate another app)
// is never reached. The Console line a refused link leaves is an OSLog entry with no in-process
// seam; what these tests pin is the other half, that the link is refused rather than acted on.

private let noteText = """
---
date: 2026-10-31
tags:
  - type-note
---

Corpo.
"""

private func link(_ text: String) -> URL {
    URL(string: text) ?? URL(fileURLWithPath: "/")
}

private func noteLink(_ path: String) -> URL {
    link("pergamenum://note?file=\(path)")
}

@MainActor
private func openController(with paths: [String], in vault: borrowing TemporaryVault) async throws -> VaultController {
    for path in paths { try vault.write(noteText, to: path) }
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

@MainActor
@Test func linksThatArriveBeforeTheDelegateHasAVaultAreReplayedInOrderOnceItDoes() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(with: ["a.md", "b.md", "c.md"], in: vault)
    let delegate = AppDelegate()

    // Two entry points, three calls, a refused link in the middle: all before `vault` is set.
    delegate.handle(urls: [noteLink("a.md"), noteLink("b.md")])
    delegate.handle(urls: [link("pergamenum://nonsense?file=zzz.md")])
    delegate.handle(urls: [noteLink("c.md")])
    #expect(controller.openNote?.relativePath != "c.md", "nothing is performed while the delegate has no vault")

    delegate.vault = controller

    try await waitUntil { controller.openNote?.relativePath == "c.md" }
    #expect(Array(controller.recentNotePaths.prefix(3)) == ["c.md", "b.md", "a.md"])
    #expect(controller.routeState.pending.isEmpty)
    controller.close()
}

@MainActor
@Test func successiveBatchesAreRoutedOneBehindTheOther() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(with: ["a.md", "b.md", "c.md"], in: vault)
    let delegate = AppDelegate()
    delegate.vault = controller

    // What `.onOpenURL` and `application(_:open:)` do when both fire for one launch.
    delegate.handle(urls: [noteLink("a.md")])
    delegate.handle(urls: [noteLink("b.md"), noteLink("c.md")])

    try await waitUntil { controller.openNote?.relativePath == "c.md" }
    #expect(Array(controller.recentNotePaths.prefix(3)) == ["c.md", "b.md", "a.md"])
    controller.close()
}

@MainActor
@Test func aRefusedLinkIsNeitherParkedNorPerformed() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(with: ["a.md"], in: vault)
    let delegate = AppDelegate()

    let refused = [
        link("pergamenum://nonsense?file=a.md"),
        link("pergamenum://note"),
        link("pergamenum://note?file="),
        link("https://example.com/a.md"),
    ]
    delegate.handle(urls: refused)
    delegate.vault = controller
    // A valid link behind them proves the delegate is live, and that the refused ones left
    // nothing to replay ahead of it.
    delegate.handle(urls: [noteLink("a.md")])

    try await waitUntil { controller.openNote?.relativePath == "a.md" }
    #expect(controller.recentNotePaths.filter { $0 == "a.md" }.count == 1)
    #expect(controller.routeState.pending.isEmpty)
    controller.close()
}

@MainActor
@Test func aLinkAfterTheDelegateHasAVaultIsPerformedAtOnceNotParked() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(with: ["a.md", "b.md"], in: vault)
    let delegate = AppDelegate()
    delegate.vault = controller

    delegate.handle(urls: [noteLink("b.md")])

    try await waitUntil { controller.openNote?.relativePath == "b.md" }
    // Setting the vault again replays nothing: the link was performed, not left parked, so
    // moving to another note is not undone by a second visit to b.md.
    controller.openNote(at: "a.md")
    delegate.vault = controller
    // No wait-until: the replay must never happen, so there is no condition to poll for.
    try await Task.sleep(for: .milliseconds(100))
    #expect(controller.openNote?.relativePath == "a.md")
    controller.close()
}
