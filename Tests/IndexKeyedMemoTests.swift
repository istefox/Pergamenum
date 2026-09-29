import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D4, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 2 - R-05.
//
// The memo behind the inspector's lists and the linked-tasks panel: the same (generation, input)
// computes once, and a new generation or a new input computes again.

@MainActor
@Test func theSameKeyComputesOnce() {
    let memo = IndexKeyedMemo<String, Int>()
    var calls = 0

    let first = memo.value(generation: 3, input: "Nota") { calls += 1; return 7 }
    let second = memo.value(generation: 3, input: "Nota") { calls += 1; return 99 }

    #expect(first == 7)
    #expect(second == 7)
    #expect(calls == 1)
}

@MainActor
@Test func aNewGenerationRecomputes() {
    let memo = IndexKeyedMemo<String, Int>()
    var calls = 0

    _ = memo.value(generation: 3, input: "Nota") { calls += 1; return 7 }
    let next = memo.value(generation: 4, input: "Nota") { calls += 1; return 8 }

    #expect(next == 8)
    #expect(calls == 2)
}

@MainActor
@Test func aNewInputRecomputes() {
    let memo = IndexKeyedMemo<String, Int>()
    var calls = 0

    _ = memo.value(generation: 3, input: "Nota") { calls += 1; return 7 }
    let other = memo.value(generation: 3, input: "Altra") { calls += 1; return 8 }
    let back = memo.value(generation: 3, input: "Nota") { calls += 1; return 9 }

    #expect(other == 8)
    #expect(back == 9, "one slot: going back to the first input computes again")
    #expect(calls == 3)
}
