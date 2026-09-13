import Foundation

/// Watches the vault for changes made outside the app - Obsidian, Finder, a script -
/// and reports the affected paths.
///
/// The app does not suppress events while it writes. It records the hash of what it
/// wrote and lets the resulting event arrive; the reconciler sees a matching hash and
/// does nothing. A suppression window would be timing-dependent and would drop a
/// genuine external edit that landed inside it (ADR-0001 §D3).
final class VaultWatcher: @unchecked Sendable {
    /// Coalescing window. Long enough that a save which rewrites a file in several
    /// steps arrives as one batch, short enough to feel immediate.
    private static let latency: CFTimeInterval = 0.2

    /// Everything the FSEvents callback touches, owned separately from the watcher.
    ///
    /// This exists because of an intermittent `EXC_BAD_ACCESS` on this queue, always in
    /// `URL.standardizedFileURL` under `VaultScanner.relativePath`. The pure function
    /// named in the stack had nothing wrong with it; what the three crash reports show,
    /// read out of their registers, is the `URL` it was handed. The getter loads the two
    /// words of the struct and asks `swift_getObjectType` about the first, and those two
    /// words came back `0x0,0x0` twice and, once, `0x20` beside a Swift `_StringObject`
    /// bit pattern - read from a perfectly live heap address. That block had been freed
    /// and handed to something else. The `URL` was `root`, so the storage that had been
    /// freed was the watcher's own.
    ///
    /// The cause is that FSEvents was given a bare, non-owning pointer to the watcher
    /// (`passUnretained` with no `retain`/`release` on the context), which ties the
    /// callback's context to nothing at all. Teardown does not close that: measured on
    /// this machine, `FSEventStreamStop` + `Invalidate` + `Release` return in 0.0 ms
    /// while a callback is still running and has not returned. A callback that has
    /// already started is in fact safe, because `takeUnretainedValue()` hands back a
    /// managed reference and so retains - the exposure is a callback that has not yet
    /// reached that line when the watcher goes away.
    ///
    /// So the sink is what the callback resurrects, and its lifetime is explicit: a `+1`
    /// taken in `start()` and given up in `stop()` from `queue` itself, so anything the
    /// stream has already handed to that serial queue has run before the last reference
    /// goes. The watcher may be freed whenever it likes; nothing reads it from a callback.
    ///
    /// Not reproduced on demand - six deliberate constructions of the interleaving all
    /// came back clean, which is ordinary for a window this narrow (three crashes in five
    /// days of heavy UI-test runs). The evidence is the crash registers, not a repro.
    private final class Sink: @unchecked Sendable {
        let root: URL
        private let lock = NSLock()
        private var onChange: (@Sendable ([String]) -> Void)?

        init(root: URL, onChange: @escaping @Sendable ([String]) -> Void) {
            self.root = root
            self.onChange = onChange
        }

        /// Stops delivery without freeing anything. An event still in flight when the
        /// vault closed describes a vault the caller has already moved on from - before
        /// this, such an event reached `reconcile` with paths relative to the old root.
        func cancel() {
            lock.lock()
            onChange = nil
            lock.unlock()
        }

        func handle(absolutePaths: [String]) {
            let relative = absolutePaths.compactMap { path -> String? in
                let url = URL(fileURLWithPath: path)
                let relativePath = VaultScanner.relativePath(of: url, under: root)

                // Our own cache writes must not feed the watcher that would then re-read
                // them, and no directory under a dot-folder holds notes.
                guard !relativePath.split(separator: "/").contains(where: { VaultLayout.isExcludedDirectory(String($0)) })
                else { return nil }
                guard url.pathExtension.lowercased() == "md" else { return nil }
                return relativePath
            }
            guard !relative.isEmpty else { return }

            lock.lock()
            let deliver = onChange
            lock.unlock()
            deliver?(Array(Set(relative)).sorted())
        }
    }

    private let root: URL
    private let queue = DispatchQueue(label: "it.stefer.pergamenum.watcher")
    private let onChange: @Sendable ([String]) -> Void
    private var stream: FSEventStreamRef?
    /// The `+1` on the live `Sink`, held on the stream's behalf rather than as a strong
    /// property: a strong one would be destroyed with the rest of the watcher, which is
    /// exactly the moment it has to survive.
    private var sinkInfo: UnsafeMutableRawPointer?

    /// - Parameter onChange: called on a background queue with vault-relative paths.
    init(root: URL, onChange: @escaping @Sendable ([String]) -> Void) {
        self.root = root
        self.onChange = onChange
    }

    deinit {
        // Torn down without touching any isolated state: `stop()` only handles the
        // stream and the sink's `+1`, both of which this object owns exclusively, and
        // captures nothing of `self` in the block it leaves behind. This is the path
        // that used to crash - a watcher dropped without an explicit `stop()`, which is
        // what a second `open(_:)` racing the first produces.
        stop()
    }

    func start() {
        guard stream == nil else { return }

        // Retained, not unretained: this `+1` is what keeps the callback's context alive
        // for the whole of a callback. It is balanced in `stop()`.
        let info = Unmanaged.passRetained(Sink(root: root, onChange: onChange)).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let sink = Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue()
            // With kFSEventStreamCreateFlagUseCFTypes absent, FSEvents hands back a
            // C array of C strings, which is what this rebinds to.
            let cPaths = paths.assumingMemoryBound(to: UnsafeMutablePointer<CChar>.self)
            let changed = (0..<count).map { String(cString: cPaths[$0]) }
            sink.handle(absolutePaths: changed)
        }

        let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [root.path(percentEncoded: false)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            // FileEvents reports individual files rather than only directories;
            // WatchRoot keeps the stream valid if the vault folder itself is moved.
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        )
        guard let created else {
            // No stream, so nothing will ever call back through `info`: balance the `+1`
            // here or the sink leaks.
            Unmanaged<Sink>.fromOpaque(info).release()
            return
        }

        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
        sinkInfo = info
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil

        guard let info = sinkInfo else { return }
        sinkInfo = nil
        // Safe to read: this call still holds the `+1` taken in `start()`.
        Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().cancel()
        // `queue` is serial and FSEvents delivers the callback on it, so every callback
        // already running or already enqueued has returned by the time this block runs.
        // Only then is the last reference given up. Nothing of `self` is captured -
        // `stop()` is reached from `deinit`, where capturing `self` is not allowed.
        queue.async { Unmanaged<Sink>.fromOpaque(info).release() }
    }
}
