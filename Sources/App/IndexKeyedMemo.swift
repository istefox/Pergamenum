import Foundation

/// One remembered answer to an index-derived question, keyed on the index generation and the
/// question's own input (ADR-0072 §D4).
///
/// Held in a view's `@State` and deliberately not observable: filling it must never schedule a
/// render. Synchronous on purpose, so the first frame draws the same entries it drew before this
/// type existed. Correctness comes from the key alone - SwiftUI may drop the `@State` storage
/// whenever it likes, and that costs one recomputation, never a stale answer.
@MainActor
final class IndexKeyedMemo<Input: Equatable, Value> {
    private struct Slot {
        let generation: Int
        let input: Input
        let value: Value
    }

    private var slot: Slot?

    func value(generation: Int, input: Input, compute: () -> Value) -> Value {
        if let slot, slot.generation == generation, slot.input == input { return slot.value }
        let value = compute()
        slot = Slot(generation: generation, input: input, value: value)
        return value
    }
}
