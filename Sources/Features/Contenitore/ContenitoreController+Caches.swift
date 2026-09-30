import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D8 and §D11, plan
// docs/plans/contenitore.md, Task 7 - R-09, R-13, R-15, R-19.
//
// Its own file because `ContenitoreController`'s body sits at SwiftLint's `type_body_length`.

/// What the pane would otherwise read from the disk on every `body` pass: each document's
/// extraction record (a JSON decode per row, twice with a search query) and the sub-container
/// tree (a walk of the folders under the root). Read once, kept until an event changes it.
struct ContenitoreCaches {
    /// What a cached tree was read for: a change to any part is a reason to read it again.
    struct TreeKey: Equatable {
        let session: ObjectIdentifier
        let root: String
        /// `VaultController.indexGeneration`: a landed change, a folder verb carrying notes.
        let index: Int
        /// `VaultController.scanGeneration`: every completed `rescan()`.
        let scan: Int
        /// `ContenitoreController.containerRevision`: a pane verb on an empty folder, which
        /// moves neither generation.
        let revision: Int
    }

    /// The session and scan generation the extraction entries were read at. «Svuota cache»
    /// empties the store on disk and ends with a scan, so a new scan generation drops them.
    var extractionSession: ObjectIdentifier?
    var extractionScan: Int?
    /// Lowercased SHA-256 to the status and method read, without the text: what every row's
    /// label and the queue's catch-up at `start()` need. A missing key means «not read yet»; a
    /// key holding `.some(nil)` means «read, and the store has none». Kept apart on purpose.
    var summaries: [String: ExtractionSummary?] = [:]
    /// Lowercased SHA-256 to the full record, text included, read only when a search query
    /// reaches the text or a caller asks for the record. Same two-level key meaning.
    var extractions: [String: ExtractedText?] = [:]
    var tree: (key: TreeKey, nodes: [ContainerNode])?
}

extension ContenitoreController {
    // MARK: - Extractions

    /// Where the extraction for `sha256` stands, read from the store without its text the first
    /// time it is asked for and from memory after that. Every row's label goes through here, so
    /// listing the archive never decodes an extracted text. Reading it makes the caller observe
    /// `extractionRevision`, so a label redraws when the queue records a new result.
    func extractionStatus(sha256: String) -> ExtractionSummary? {
        guard let session = extractionCacheSession() else { return nil }
        let key = sha256.lowercased()
        if let cached = caches.summaries[key] { return cached }
        if let full = caches.extractions[key] {
            let summary = full.map(ExtractionSummary.init)
            caches.summaries[key] = .some(summary)
            return summary
        }
        let read = session.extractedTexts.readSummary(sha256: key)
        caches.summaries[key] = .some(read)
        return read
    }

    /// The full extraction record for `sha256`, text included, read from the store the first
    /// time it is asked for and from memory after that: the search reads the text through here,
    /// only for a row the query did not already match by name or tag. Observes
    /// `extractionRevision` like `extractionStatus(sha256:)`.
    func extraction(sha256: String) -> ExtractedText? {
        guard let session = extractionCacheSession() else { return nil }
        let key = sha256.lowercased()
        if let cached = caches.extractions[key] { return cached }
        let read = session.extractedTexts.read(sha256: key)
        caches.extractions[key] = .some(read)
        caches.summaries[key] = .some(read.map(ExtractionSummary.init))
        return read
    }

    /// The queue wrote `record` for `sha256`: `pending` as a job starts, `done` or `failed` as
    /// it ends. The caches take it as written, without reading the file back.
    func recordExtraction(_ record: ExtractedText, sha256: String) {
        let key = sha256.lowercased()
        caches.extractions[key] = .some(record)
        caches.summaries[key] = .some(ExtractionSummary(record))
        extractionRevision += 1
    }

    /// Drops the cached record for `sha256`, so the next read goes to the store: an import
    /// whose hash may already have a record.
    func forgetExtraction(sha256: String) {
        let key = sha256.lowercased()
        caches.extractions.removeValue(forKey: key)
        caches.summaries.removeValue(forKey: key)
        extractionRevision += 1
    }

    /// The open session, with both extraction caches emptied first when they were read for
    /// another session or before the latest scan («Svuota cache» empties the store and ends with
    /// one). Registers `extractionRevision` for the caller.
    private func extractionCacheSession() -> VaultSession? {
        guard let session = vault.session else { return nil }
        _ = extractionRevision
        let owner = ObjectIdentifier(session)
        let scan = vault.scanGeneration
        if caches.extractionSession != owner || caches.extractionScan != scan {
            caches.extractions = [:]
            caches.summaries = [:]
            caches.extractionSession = owner
            caches.extractionScan = scan
        }
        return session
    }

    // MARK: - Containers

    /// The sub-container tree, read from the disk rather than the index: an empty container
    /// holds no note, so the index does not know it exists. Year folders are not descended into.
    ///
    /// Read once per `ContenitoreCaches.TreeKey`: after a landed change or a folder verb (the
    /// index generation), after a `rescan()` (the scan generation), after a pane verb on an
    /// empty folder (`containersChanged()`), or for another vault or root. Any other `body`
    /// pass is answered from memory.
    func containers() -> [ContainerNode] {
        guard let session = vault.session else { return [] }
        let root = self.root
        let key = ContenitoreCaches.TreeKey(
            session: ObjectIdentifier(session), root: root,
            index: vault.indexGeneration, scan: vault.scanGeneration, revision: containerRevision
        )
        if let tree = caches.tree, tree.key == key { return tree.nodes }
        let nodes = Self.readContainerTree(root: root, in: session)
        caches.tree = (key, nodes)
        return nodes
    }

    /// A pane verb created, renamed, moved or trashed a container: the next `containers()`
    /// reads the tree again.
    func containersChanged() {
        containerRevision += 1
    }

    private static func readContainerTree(root: String, in session: VaultSession) -> [ContainerNode] {
        guard let rootURL = try? session.store.url(for: root) else { return [] }
        var folders: [String] = []
        var pending: [(url: URL, path: String)] = [(rootURL, root)]
        let keys: [URLResourceKey] = [.isDirectoryKey]
        while let next = pending.popLast() {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: next.url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            )) ?? []
            for child in children where (try? child.resourceValues(forKeys: Set(keys)))?.isDirectory == true {
                let name = child.lastPathComponent
                guard !ContenitoreNaming.isYearFolderName(name) else { continue }
                let path = "\(next.path)/\(name)"
                folders.append(path)
                pending.append((child, path))
            }
        }
        return ContenitoreListModel.containerTree(root: root, folders: folders)
    }
}
