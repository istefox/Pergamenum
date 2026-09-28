import Foundation
import Testing
@testable import Pergamenum

// PG-260 (Audit Fable chain 7), R-08, R-09, R-16: the search sheet's state is ordered by
// generation. The injected sleep and search each park on a `Gate`, so every interleaving
// below is forced (ADR-0043 §D9), never observed by timing.

/// One injected dependency that parks until the test releases it.
@MainActor
private final class Parking {
    let entered = Gate()
    let release = Gate()
    private(set) var calls = 0

    func park() async {
        calls += 1
        entered.open()
        await release.wait()
    }
}

private func hit(_ path: String) -> VaultSession.SearchResult {
    VaultSession.SearchResult(path: path, title: String(path.dropLast(3)), excerpt: "")
}

@MainActor
@Test func validationWaitsForTheDebounce() async {
    let state = GlobalSearchState()
    let sleep = Parking()

    let run = Task { @MainActor in
        await state.run("regex:[a", sleep: { _ in await sleep.park() }, search: { _ in [] })
    }
    await sleep.entered.wait()
    // Still typing: no error flashed and no spinner for a pattern not searched yet.
    #expect(state.invalidPatterns == [])
    #expect(!state.isSearching)

    sleep.release.open()
    await run.value
    #expect(state.invalidPatterns == ["[a"])
}

@MainActor
@Test func theSpinnerStartsAfterTheDebounceAndStopsWithTheAnswer() async {
    let state = GlobalSearchState()
    let sleep = Parking()
    let search = Parking()

    let run = Task { @MainActor in
        await state.run("curva", sleep: { _ in await sleep.park() }, search: { _ in
            await search.park()
            return [hit("Alfa.md")]
        })
    }
    await sleep.entered.wait()
    #expect(!state.isSearching)

    sleep.release.open()
    await search.entered.wait()
    #expect(state.isSearching)

    search.release.open()
    await run.value
    #expect(!state.isSearching)
    #expect(state.results == [hit("Alfa.md")])
    #expect(state.answeredRaw == "curva")
}

@MainActor
@Test func anEmptyQueryClearsAtOnce() async {
    let state = GlobalSearchState()
    // Something published first, so clearing is observable.
    await state.run("curva", sleep: { _ in }, search: { _ in [hit("Alfa.md")] })
    #expect(state.results == [hit("Alfa.md")])

    var sleeps = 0
    var searches = 0
    await state.run("   ", sleep: { _ in sleeps += 1 }, search: { _ in
        searches += 1
        return [hit("Beta.md")]
    })

    #expect(sleeps == 0)
    #expect(searches == 0)
    #expect(state.results == [])
    #expect(!state.isSearching)
    #expect(state.invalidPatterns == [])
}

@MainActor
@Test func aSupersededSearchLeavesTheNewSpinnerAlone() async {
    let state = GlobalSearchState()
    let searchA = Parking()
    let searchB = Parking()

    let runA = Task { @MainActor in
        await state.run("alfa", sleep: { _ in }, search: { _ in
            await searchA.park()
            // The real door checks after every pause, which is where a cancelled search stops.
            try Task.checkCancellation()
            return [hit("A.md")]
        })
    }
    await searchA.entered.wait()
    runA.cancel()

    let runB = Task { @MainActor in
        await state.run("beta", sleep: { _ in }, search: { _ in
            await searchB.park()
            return [hit("B.md")]
        })
    }
    await searchB.entered.wait()
    #expect(state.isSearching)

    searchA.release.open()
    await runA.value
    // A threw `CancellationError`; B is still searching and its spinner stays.
    #expect(state.isSearching)

    searchB.release.open()
    await runB.value
    #expect(state.results == [hit("B.md")])
    #expect(!state.isSearching)
}

@MainActor
@Test func aSupersededSearchNeverOverwritesTheNewResults() async {
    let state = GlobalSearchState()
    let searchA = Parking()

    let runA = Task { @MainActor in
        await state.run("alfa", sleep: { _ in }, search: { _ in
            await searchA.park()
            // Finished its last chunk as it was cancelled: it returns rather than throws.
            return [hit("A.md")]
        })
    }
    await searchA.entered.wait()
    runA.cancel()

    await state.run("beta", sleep: { _ in }, search: { _ in [hit("B.md")] })
    #expect(state.results == [hit("B.md")])

    searchA.release.open()
    await runA.value
    #expect(state.results == [hit("B.md")])
    #expect(state.answeredRaw == "beta")
    #expect(!state.isSearching)
}

@MainActor
@Test func aSearchCancelledDuringTheDebounceTouchesNothing() async {
    let state = GlobalSearchState()
    await state.run("gamma", sleep: { _ in }, search: { _ in [hit("C.md")] })
    #expect(state.results == [hit("C.md")])

    let sleep = Parking()
    let search = Parking()
    search.release.open()
    let run = Task { @MainActor in
        await state.run("regex:[a", sleep: { _ in await sleep.park() }, search: { _ in
            await search.park()
            return []
        })
    }
    await sleep.entered.wait()
    run.cancel()
    sleep.release.open()
    await run.value

    #expect(search.calls == 0)
    #expect(state.results == [hit("C.md")])
    #expect(state.answeredRaw == "gamma")
    #expect(!state.isSearching)
    #expect(state.invalidPatterns == [])
}

@MainActor
@Test func theLegendShowsATagGlob() {
    #expect(GlobalSearchView.legendLines.joined(separator: " ").contains("tag:client-*"))
}
