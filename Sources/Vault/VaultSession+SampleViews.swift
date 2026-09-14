import Foundation

/// Putting the shipped views into a vault, when somebody asks (ADR-0009, ADR-0011 §D5).
///
/// **Nothing is overwritten and nothing is written unasked.** A template with the same name
/// already there is left exactly as it is and named in the outcome: these are examples, and an
/// example that quietly replaced a file somebody had edited would be the worst thing in this
/// app to discover.
///
/// Through `write` like everything else, so the watcher recognises it and the history records
/// it. No journal: this creates files rather than changing them, and `undo` on a creation is
/// the one case `WriteJournal` cannot answer (it has no text to put back).
extension VaultSession {
    struct SampleViewsOutcome: Sendable, Equatable {
        var created: [String] = []
        var alreadyThere: [String] = []
        var failures: [String] = []
    }

    @discardableResult
    func installSampleViews() async -> SampleViewsOutcome {
        var outcome = SampleViewsOutcome()
        for sample in SampleViews.all {
            if (try? read(sample.relativePath)) != nil {
                outcome.alreadyThere.append(sample.relativePath)
                continue
            }
            do {
                try await write(sample.text, to: sample.relativePath)
                outcome.created.append(sample.relativePath)
            } catch {
                outcome.failures.append("\(sample.relativePath): \(error.localizedDescription)")
            }
        }
        return outcome
    }
}
