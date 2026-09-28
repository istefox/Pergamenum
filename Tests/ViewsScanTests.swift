import Foundation
import Testing
@testable import Pergamenum

// PG-260 (Audit Fable chain 7), R-13: the «Viste» scan is cooperative - the same entries as
// before, a pause between chunks of notes, and nothing when cancelled. Cancellation is forced
// through a `Gate` (ADR-0043 §D9), never a timing race.

private let front = "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n"

private func tagged(_ tag: String) -> String {
    "---\ndate: 2026-08-11\ntags:\n  - type-note\n  - \(tag)\n---\n\n"
}

private let fence = "```"

private let noteA = front + """
\(fence)pergamenum-view
render: list
where: tag("client-*")
\(fence)

"""

private let noteB = front + """
# Clienti

## Acme

\(fence)pergamenum-view
render: table
where: tag("client-acme")
\(fence)

## Rotta

\(fence)pergamenum-view
outsider: mistero
\(fence)

"""

/// Six notes: `A.md` with one valid view, `B.md` with a valid view under a heading and a
/// broken one, `C.md` with none, and three tagged notes so the counts are not trivial.
@MainActor
private func openViewsVault(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(noteA, to: "A.md")
    try vault.write(noteB, to: "B.md")
    try vault.write(front + "Nessuna vista.\n", to: "C.md")
    try vault.write(tagged("client-acme") + "Acme.\n", to: "D.md")
    try vault.write(tagged("client-beta") + "Beta.\n", to: "E.md")
    try vault.write(tagged("client-acme-industriale") + "Industriale.\n", to: "F.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

private func parseError(_ source: String) -> String? {
    do {
        _ = try ViewBlock.parse(source)
        return nil
    } catch {
        return (error as? ViewBlockError)?.description
    }
}

@MainActor
private final class PauseLog {
    var count = 0
}

private let today = CalendarDate(iso: "2026-09-28")!

@MainActor
@Test func theScanListsEveryViewInPathOrder() async throws {
    let vault = try TemporaryVault()
    let session = try await openViewsVault(vault)

    let entries = try await ViewCatalogue.scan(session, today: today) {}

    let brokenError: String = try #require(parseError("outsider: mistero"))
    let expected = [
        ViewEntry(
            path: "A.md", noteTitle: "A", ordinal: 0, lineIndex: 6, heading: nil,
            block: try ViewBlock.parse("render: list\nwhere: tag(\"client-*\")"), error: nil, matches: 3
        ),
        ViewEntry(
            path: "B.md", noteTitle: "B", ordinal: 0, lineIndex: 10, heading: "Acme",
            block: try ViewBlock.parse("render: table\nwhere: tag(\"client-acme\")"), error: nil, matches: 1
        ),
        ViewEntry(
            path: "B.md", noteTitle: "B", ordinal: 1, lineIndex: 17, heading: "Rotta",
            block: nil, error: brokenError, matches: nil
        ),
    ]
    #expect(entries == expected)
    #expect(entries.map(\.renderName) == ["elenco", "tabella", nil])

    // The same views the connector lists, in the same order.
    let connector = VaultAPI.views(session).map { "\($0.path)#\($0.ordinal)" }
    #expect(entries.map(\.id) == connector)
}

@MainActor
@Test func theScanPausesBetweenChunks() async throws {
    let vault = try TemporaryVault()
    let session = try await openViewsVault(vault)
    let log = PauseLog()

    let entries = try await ViewCatalogue.scan(session, today: today, chunkSize: 1) { log.count += 1 }

    // One chunk is one note - read, parsed and its views evaluated - whether it holds a view
    // or not: six notes, five pauses, none after the last.
    #expect(session.index.allNotes.count == 6)
    #expect(log.count == 5)
    #expect(entries.count == 3)
}

@MainActor
@Test func aCancelledScanPublishesNothing() async throws {
    let vault = try TemporaryVault()
    let session = try await openViewsVault(vault)
    let log = PauseLog()
    let parked = Gate()
    let release = Gate()

    let scan = Task { @MainActor in
        try await ViewCatalogue.scan(session, today: today, chunkSize: 1) {
            log.count += 1
            parked.open()
            await release.wait()
        }
    }
    await parked.wait()
    scan.cancel()
    release.open()

    await #expect(throws: CancellationError.self) { try await scan.value }
    #expect(log.count == 1)
}

private extension ViewEntry {
    var renderName: String? { block.map { ViewCatalogue.rendererName($0.render) } }
}
