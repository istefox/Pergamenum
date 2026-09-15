import Foundation

/// FSEvents under the Mail store, the third automatic trigger (R-17).
///
/// `VaultWatcher`'s shape without its `.md` filter - what changes here is `.emlx`
/// files and the Envelope Index's WAL, never a note. One callback per coalesced burst;
/// the debounce that turns a burst into one sync is `PraticaWatcher`'s, not this
/// object's.
///
/// Not `private`: `PraticheController+Triggers.swift` is an extension of
/// `PraticheController` in a separate file, and is this type's only construction site.
final class MailStoreEventStream: @unchecked Sendable {
    /// Longer than `VaultWatcher`'s 0.2 s: nothing here is waiting for a keystroke to
    /// appear on screen, and Mail writes in long bursts while it fetches.
    private static let latency: CFTimeInterval = 2

    /// `VaultWatcher.Sink`'s counterpart, and for the same reason: this stream was handed
    /// `self` as a bare, non-owning pointer, which ties the callback's context to nothing
    /// and leaves a callback arriving after teardown reading freed memory. That is the
    /// use-after-free the vault watcher was crashing on, copied here when this type was
    /// written in its shape. Same fix: an explicit `+1` on a separate context object,
    /// given up from `queue` after invalidation. See `VaultWatcher.Sink` for the evidence.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var onChange: (@Sendable () -> Void)?

        init(onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }

        func cancel() {
            lock.lock()
            onChange = nil
            lock.unlock()
        }

        func fire() {
            lock.lock()
            let deliver = onChange
            lock.unlock()
            deliver?()
        }
    }

    private let root: URL
    private let queue = DispatchQueue(label: "it.stefer.pergamenum.pratiche-mailstore")
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    /// The `+1` on the live `Sink`, given up in `stop()` from `queue`.
    private var sinkInfo: UnsafeMutableRawPointer?

    init(root: URL, onChange: @escaping @Sendable () -> Void) {
        self.root = root
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil else { return }

        let info = Unmanaged.passRetained(Sink(onChange: onChange)).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().fire()
        }

        let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [root.path(percentEncoded: false)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        )
        guard let created else {
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
        Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().cancel()
        // Serial queue, FIFO: every callback already running or enqueued has returned
        // before this gives up the last reference.
        queue.async { Unmanaged<Sink>.fromOpaque(info).release() }
    }
}
