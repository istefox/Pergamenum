import Foundation

/// One place for the chunk size and the pause every cooperative main-actor loop uses
/// (PG-260): global search's `searchCooperatively` and the «Viste» pane's scan.
///
/// Those loops read files on the main actor, where ADR-0041 §D12 keeps `VaultSession`'s
/// reads. Chunking with a pause between chunks is what lets the run loop draw a spinner and
/// take a keystroke meanwhile, and a cancellation check after each pause is what makes a
/// superseded search stop early instead of finishing a vault nobody is waiting for.
enum CooperativeLoop {
    /// How many candidates a loop handles between two pauses. A sensible constant, not a
    /// measured one (SPEC: no chunk-size tuning without a measured need).
    static let chunkSize = 32

    /// Hands the main run loop a turn.
    ///
    /// Timer-backed rather than `Task.yield()`: the stdlib documents that a yielding task
    /// that is still the highest-priority one is resumed at once, which promises the run
    /// loop nothing. A pending timer with an empty main queue lets it reach its drawing
    /// phase. If the GUI measurement (R-17) says otherwise, this one line is the change.
    @MainActor
    static func pause() async {
        try? await Task.sleep(for: .milliseconds(1))
    }
}
