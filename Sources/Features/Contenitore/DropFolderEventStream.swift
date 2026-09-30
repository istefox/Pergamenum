import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D4, plan
// docs/plans/contenitore.md, Task 6 - R-01, R-04.
//
// App-only (§D14): the drop folder is the app's business, never a connector's.

/// FSEvents on the drop folder: one callback per coalesced burst, nothing else.
///
/// `MailStoreEventStream`'s shape, sink included, and for its reason: the stream is handed a
/// context pointer, and a callback arriving after teardown must find a retained, cancelled
/// sink rather than freed memory (the `VaultWatcher` use-after-free). What an event means is
/// `ContenitoreController`'s business: it observes the folder, and a file still changing
/// gets its second observation from the controller's own follow-up, not from here.
final class DropFolderEventStream: @unchecked Sendable {
    /// Short: a dropped file should start its stability wait promptly, and the wait itself
    /// (two observations with the same size and date) is what absorbs a long copy.
    private static let latency: CFTimeInterval = 0.5

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

    private let folder: URL
    private let queue = DispatchQueue(label: "it.stefer.pergamenum.contenitore-drop-folder")
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    /// The `+1` on the live `Sink`, given up in `stop()` from `queue`.
    private var sinkInfo: UnsafeMutableRawPointer?

    init(folder: URL, onChange: @escaping @Sendable () -> Void) {
        self.folder = folder
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil else { return }

        let info = Unmanaged.passRetained(Sink(onChange: onChange)).toOpaque()
        var context = FSEventStreamContext(
            version: 0, info: info, retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().fire()
        }
        let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [folder.path(percentEncoded: false)] as CFArray,
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
        let sink = Unmanaged<Sink>.fromOpaque(info)
        sink.takeUnretainedValue().cancel()
        // Serial queue, FIFO: every callback already running or enqueued has returned
        // before this gives up the last reference.
        queue.async { sink.release() }
    }
}
