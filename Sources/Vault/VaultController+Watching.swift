import Foundation

/// Keeping up with changes made outside the app (SPEC §12, watcher FSEvents).
extension VaultController {
    func startWatching(_ url: URL) {
        let watcher = VaultWatcher(root: url) { [weak self] paths in
            Task { @MainActor [weak self] in
                self?.reconcile(paths)
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    /// Applies external changes, one path at a time.
    func reconcile(_ paths: [String]) {
        guard let store else { return }

        for path in paths {
            let fileURL = store.url(for: path)
            guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
                index.update(nil, at: path)
                continue
            }
            guard let (record, text) = try? store.read(path) else { continue }

            // The app's own write coming back. Compared by content hash rather than
            // by a time window, so a real external edit is never mistaken for it.
            if selfWrittenHashes[path] == record.contentHash {
                selfWrittenHashes.removeValue(forKey: path)
                continue
            }

            index.update(record, at: path)

            guard var note = openNote, note.relativePath == path else { continue }
            if note.hasUnsavedChanges {
                // Never merge, never discard: ask.
                note.externalChangePending = text
                replaceOpenNote(note)
            } else {
                note.text = text
                note.savedText = text
                replaceOpenNote(note)
            }
        }
    }
}
