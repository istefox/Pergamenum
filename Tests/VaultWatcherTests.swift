import Foundation
import Testing
@testable import Pergamenum

/// The watcher's lifetime contract, which is what an intermittent `EXC_BAD_ACCESS` on
/// `it.stefer.pergamenum.watcher` turned out to be about.
///
/// The crash itself is a race and does not reproduce on demand - three occurrences in
/// five days of heavy UI-test runs, and none of six deliberate constructions of the
/// interleaving triggered it. What the crash registers proved instead is *what* was
/// read: `URL.standardizedFileURL` faulted on a `URL` whose two words came back as
/// `0x0,0x0` twice and as a Swift `_StringObject` bit pattern once, read out of a live
/// heap address. That is `VaultWatcher.root` being read out of the watcher's own
/// storage after that storage had been freed and handed to something else - a
/// use-after-free, because FSEvents was given a non-owning pointer to the watcher.
///
/// So these tests do not try to race anything. They pin the two observable halves of
/// the ownership discipline that replaced it, and neither can fail spuriously: both
/// assert that something does *not* happen, so a run where the file system is quiet
/// passes rather than flaking.
@Suite("VaultWatcher lifetime")
struct VaultWatcherTests {
    /// Thread-safe collector: `onChange` is called on the watcher's own queue.
    private final class Deliveries: @unchecked Sendable {
        private let lock = NSLock()
        private var batches: [[String]] = []
        private var sealed = false
        private var sealedCount = 0

        func record(_ paths: [String]) {
            lock.lock()
            defer { lock.unlock() }
            if sealed { sealedCount += 1 }
            batches.append(paths)
        }
        /// Marks the moment `stop()` returned. Anything recorded after it is a delivery
        /// the caller had already asked not to receive.
        func seal() { lock.lock(); sealed = true; lock.unlock() }

        var afterSeal: Int { lock.lock(); defer { lock.unlock() }; return sealedCount }
        var all: [[String]] { lock.lock(); defer { lock.unlock() }; return batches }
    }

    private static func makeVault() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func touch(_ count: Int, in vault: URL, prefix: String) throws {
        for i in 0..<count {
            try "# \(prefix) \(i)\n".write(
                to: vault.appendingPathComponent("\(prefix)\(i).md"),
                atomically: false,
                encoding: .utf8
            )
        }
    }

    /// A stopped watcher is silent.
    ///
    /// Before the fix nothing said so: an event already in flight when the vault closed
    /// still reached `onChange`, carrying paths relative to a root the caller had moved
    /// on from. `reconcile` would then apply them against the newly-opened vault.
    @Test("no event is delivered after stop()")
    func silentAfterStop() async throws {
        let vault = try Self.makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let deliveries = Deliveries()
        let watcher = VaultWatcher(root: vault) { paths in deliveries.record(paths) }
        watcher.start()

        // Let the stream come up and deliver at least one batch, so the test is
        // exercising a live watcher rather than one that never started.
        try Self.touch(8, in: vault, prefix: "before")
        try await Task.sleep(for: .milliseconds(700))

        watcher.stop()
        deliveries.seal()

        // Everything from here on must be dropped.
        try Self.touch(8, in: vault, prefix: "after")
        try await Task.sleep(for: .milliseconds(700))

        #expect(
            deliveries.afterSeal == 0,
            "a stopped watcher delivered \(deliveries.afterSeal) batch(es): \(deliveries.all)"
        )
    }

    /// Starting and dropping watchers while the vault churns must not fault.
    ///
    /// This is the crashing shape - `VaultController.open(_:)` replaces the watcher on
    /// every vault switch, and a controller going away drops one through `deinit`
    /// without an explicit `stop()`. It cannot *prove* the race is gone, and it is not
    /// pretending to: what it does is run the teardown path against a busy stream often
    /// enough that a reintroduced use-after-free has somewhere to show up, and it costs
    /// about a second.
    @Test("a watcher dropped without stop() while the vault churns does not fault")
    func droppedWhileBusy() async throws {
        let vault = try Self.makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        for round in 0..<12 {
            let deliveries = Deliveries()
            // Deliberately no `stop()`: the only teardown is `deinit`, which is the path
            // a second `open(_:)` and a discarded controller both take.
            do {
                let watcher = VaultWatcher(root: vault) { paths in deliveries.record(paths) }
                watcher.start()
                try Self.touch(10, in: vault, prefix: "r\(round)n")
                try await Task.sleep(for: .milliseconds(40))
            }
            try Self.touch(10, in: vault, prefix: "r\(round)m")
        }
        try await Task.sleep(for: .milliseconds(400))
    }

    /// The filtering `handle` does, which had no coverage at all and which the ownership
    /// fix moved into `Sink`. A move is exactly when a silent behaviour change slips in.
    @Test("only markdown outside excluded directories is reported, deduped and sorted")
    func reportsMarkdownOnly() async throws {
        let vault = try Self.makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".pergamenum"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("Note"), withIntermediateDirectories: true
        )

        let deliveries = Deliveries()
        let watcher = VaultWatcher(root: vault) { paths in deliveries.record(paths) }
        watcher.start()
        defer { watcher.stop() }

        // Two notes, plus things that must never be reported: a cache write under the
        // app's own dot-folder, and a non-markdown file.
        try "# b\n".write(to: vault.appendingPathComponent("Note/Beta.md"), atomically: false, encoding: .utf8)
        try "# a\n".write(to: vault.appendingPathComponent("Alfa.md"), atomically: false, encoding: .utf8)
        try "x".write(to: vault.appendingPathComponent(".pergamenum/cache.db"), atomically: false, encoding: .utf8)
        try "{}".write(to: vault.appendingPathComponent("Board.canvas"), atomically: false, encoding: .utf8)

        try await Task.sleep(for: .milliseconds(900))

        let reported = Set(deliveries.all.flatMap { $0 })
        // FSEvents coalescing decides how these arrive, so the assertion is on the set,
        // never on the batching.
        #expect(reported.contains("Alfa.md"))
        #expect(reported.contains("Note/Beta.md"))
        #expect(!reported.contains(where: { $0.hasPrefix(".pergamenum/") }))
        #expect(!reported.contains(where: { $0.hasSuffix(".canvas") }))
        for batch in deliveries.all {
            #expect(batch == batch.sorted(), "a batch arrived unsorted: \(batch)")
            #expect(batch.count == Set(batch).count, "a batch arrived with duplicates: \(batch)")
        }
    }
}
