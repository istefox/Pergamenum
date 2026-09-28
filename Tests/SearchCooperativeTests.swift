import Foundation
import Testing
@testable import Pergamenum

// PG-260 (Audit Fable chain 7), R-10 and R-11: the app's cooperative search door runs the
// synchronous door's own plan and per-candidate step in chunks, pausing between them and
// stopping on cancellation. Cancellation is forced through a `Gate` (ADR-0043 §D9), never a
// timing race.

private let front = "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n"

private func tagged(_ tag: String) -> String {
    "---\ndate: 2026-08-11\ntags:\n  - type-note\n  - \(tag)\n---\n\n"
}

/// Seven notes covering words, a phrase, a `regex:` line, tags, a star, a link and an orphan.
@MainActor
private func openMixedVault(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(tagged("client-acme") + "La curva di trasmissibilità, vedi [[Beta]].\n", to: "Alfa.md")
    try vault.write(tagged("client-acme-industriale") + "## Sezione\n\nUna frase esatta qui.\n", to: "Beta.md")
    try vault.write(front + "Sola, con la sua curva.\n", to: "Gamma.md")
    try vault.write(front + "Cita [[Beta]] e la frase esatta.\n", to: "Delta.md")
    try vault.write(tagged("status-a") + "Niente di che.\n", to: "Epsilon.md")
    try vault.write(front + "## Titolo\n\nCurva ancora.\n", to: "Zeta.md")
    try vault.write(front + "Prosa, e [[Alfa]].\n", to: "Eta.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    session.setStar(true, for: "Beta.md")
    return session
}

/// Seven notes, every one of them matching `curva`.
@MainActor
private func openMatchingVault(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    for index in 1...7 {
        try vault.write(front + "Nota \(index): la curva.\n", to: "Nota \(index).md")
    }
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

@MainActor
private final class PauseLog {
    var count = 0
}

private let queries = [
    "curva", "\"frase esatta\"", "-curva", "tag:client-*", "regex:^##\\s", "regex:[aperta",
    "is:starred", "linked:Beta", "orphan:", "zzz", "",
]

@MainActor
@Test(arguments: queries, [200, 1, 0])
func theCooperativeDoorAnswersExactlyAsTheSynchronousOne(raw: String, limit: Int) async throws {
    let vault = try TemporaryVault()
    let session = try await openMixedVault(vault)
    let query = SearchQuery(raw)
    let expected = session.search(query, limit: limit)

    for chunkSize in [1, 3, 1000] {
        let answer = try await session.searchCooperatively(query, limit: limit, chunkSize: chunkSize) {}
        #expect(answer == expected, "chunkSize \(chunkSize)")
    }
}

@MainActor
@Test func theCooperativeDoorsDefaultsAnswerAsTheSynchronousOne() async throws {
    // The positive control for the table above: the fixture really yields hits.
    let vault = try TemporaryVault()
    let session = try await openMixedVault(vault)
    let expected = session.search(SearchQuery("curva"))
    #expect(expected.count == 3)
    #expect(try await session.searchCooperatively(SearchQuery("curva")) == expected)
}

@MainActor
@Test func itPausesBetweenChunks() async throws {
    let vault = try TemporaryVault()
    let session = try await openMatchingVault(vault)
    let log = PauseLog()

    let answer = try await session.searchCooperatively(SearchQuery("curva"), chunkSize: 3) { log.count += 1 }

    #expect(answer.count == 7)
    // After the third and the sixth candidate, and none after the last chunk.
    #expect(log.count == 2)
}

@MainActor
@Test func itStopsAtThePauseWhenCancelled() async throws {
    let vault = try TemporaryVault()
    let session = try await openMatchingVault(vault)
    let log = PauseLog()
    let parked = Gate()
    let release = Gate()

    let search = Task { @MainActor in
        try await session.searchCooperatively(SearchQuery("curva"), chunkSize: 3) {
            log.count += 1
            parked.open()
            await release.wait()
        }
    }
    await parked.wait()
    search.cancel()
    release.open()

    await #expect(throws: CancellationError.self) { try await search.value }
    #expect(log.count == 1)
}

@MainActor
@Test func aSearchCancelledBeforeItStartsReadsNothing() async throws {
    let vault = try TemporaryVault()
    let session = try await openMatchingVault(vault)
    let log = PauseLog()

    // Both on the main actor: the body cannot start before the test suspends, so the
    // cancellation lands before the first chunk.
    let search = Task { @MainActor in
        try await session.searchCooperatively(SearchQuery("curva"), chunkSize: 1) { log.count += 1 }
    }
    search.cancel()

    await #expect(throws: CancellationError.self) { try await search.value }
    #expect(log.count == 0)
}

@MainActor
@Test func reachingTheLimitStopsWithoutAnotherPause() async throws {
    let vault = try TemporaryVault()
    let session = try await openMatchingVault(vault)
    let log = PauseLog()

    let answer = try await session.searchCooperatively(SearchQuery("curva"), limit: 2, chunkSize: 1) {
        log.count += 1
    }

    #expect(answer.count == 2)
    #expect(log.count <= 1)
}
