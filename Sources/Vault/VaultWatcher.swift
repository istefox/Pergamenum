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

    private let root: URL
    private let queue = DispatchQueue(label: "it.stefer.pergamenum.watcher")
    private let onChange: @Sendable ([String]) -> Void
    private var stream: FSEventStreamRef?

    /// - Parameter onChange: called on a background queue with vault-relative paths.
    init(root: URL, onChange: @escaping @Sendable ([String]) -> Void) {
        self.root = root
        self.onChange = onChange
    }

    deinit {
        // Torn down without touching any isolated state: `stop()` only handles the
        // stream, which this object owns exclusively.
        stop()
    }

    func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
            // With kFSEventStreamCreateFlagUseCFTypes absent, FSEvents hands back a
            // C array of C strings, which is what this rebinds to.
            let cPaths = paths.assumingMemoryBound(to: UnsafeMutablePointer<CChar>.self)
            let changed = (0..<count).map { String(cString: cPaths[$0]) }
            watcher.handle(absolutePaths: changed)
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
        guard let created else { return }

        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handle(absolutePaths: [String]) {
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
        onChange(Array(Set(relative)).sorted())
    }
}
