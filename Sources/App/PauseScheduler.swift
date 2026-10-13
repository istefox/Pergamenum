import Foundation

/// A restartable pause on the main actor (ADR-0095 §D4, PG-406): the editor's "typing stopped"
/// signal, injected so no test waits on a timer.
///
/// `restart(_:)` replaces the pending action and starts the interval again; `cancel()` drops it.
@MainActor
protocol PauseScheduler: AnyObject {
    func restart(_ action: @escaping @MainActor () -> Void)
    func cancel()
}

/// The production pause: a main-actor `Task` that sleeps for `interval` and then runs the last
/// action given to `restart(_:)`, once. 500 ms by default: at five keys a second keys arrive every
/// 200 ms, so half a second without one is "typing stopped" (ADR-0095 §D4).
@MainActor
final class TaskPauseScheduler: PauseScheduler {
    private let interval: Duration
    private var pending: Task<Void, Never>?

    init(interval: Duration = .milliseconds(500)) {
        self.interval = interval
    }

    func restart(_ action: @escaping @MainActor () -> Void) {
        pending?.cancel()
        let interval = interval
        pending = Task { @MainActor in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
