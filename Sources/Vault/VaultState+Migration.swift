import Foundation

/// `VaultState.migrateIfNeeded`, `vault.json`'s shape, and the duplicated-vault report,
/// split out of `VaultState.swift` on the same convention as `VaultSession+Identity.swift`
/// - kept under SwiftLint's file and type length limits, not a different concern from
/// the resolver itself. The move-with-fallback machinery `history/` and `ai-journal/`
/// need lives one file further out, in `VaultState+DirectoryMove.swift` (ADR-0017 §D3).
extension VaultState {
    // MARK: Migration

    /// What `vault.json` records: the root this state directory was last opened
    /// against, and which derived stores have already been moved out of the vault.
    ///
    /// Decoded key by key like `VaultSettings`, for the same reason: an older
    /// `vault.json` written before a field existed must still decode, one unrecognised
    /// key costing nothing rather than the whole record.
    struct Descriptor: Codable, Equatable, Sendable {
        /// The vault root last opened against this state directory, as a path.
        /// Compared against the root currently resolving here on every
        /// `migrateIfNeeded` call (ADR-0017 §D2/§D3): a mismatch whose recorded folder
        /// is gone is a rename, silently repointed; a mismatch whose recorded folder
        /// still exists is a duplicated vault, reported through `problems` instead.
        var root: String?
        /// One name per store already migrated out of the vault: `"cache"`,
        /// `"thumbnails"`, `"history"`, `"ai-journal"`. A store's migration step runs
        /// whenever its name is absent here, appended only on success or on nothing to
        /// do - which is what lets a vault an earlier build already touched still pick
        /// up a later store's move on its next open instead of being skipped forever,
        /// and lets a failed step retry rather than being silently abandoned.
        var migrated: [String]

        static let empty = Descriptor(root: nil, migrated: [])

        init(root: String?, migrated: [String]) {
            self.root = root
            self.migrated = migrated
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            root = try container.decodeIfPresent(String.self, forKey: .root)
            migrated = try container.decodeIfPresent([String].self, forKey: .migrated) ?? []
        }
    }

    /// Ensures this vault's state directory exists and runs each derived store's
    /// migration step exactly once, tracked in `vault.json`'s `migrated` array rather
    /// than by whether the directory itself is new.
    ///
    /// Keying on the directory's own existence would be consumed the moment slice 1
    /// shipped: by the time slice 2's steps existed, the directory slice 1 created was
    /// already there, so `history/` and `ai-journal/` would never have been picked up
    /// on any vault opened before that point - silently, forever, which is exactly the
    /// loss ADR-0017 D3's move-not-delete rule exists to prevent. Tracking per store
    /// instead means a vault an earlier build already touched still runs a later
    /// store's step the first time it sees it.
    ///
    /// `cache.db` and `thumbnails/` are removed at the old location and rebuilt at the
    /// new one: neither is anything but a rebuildable cache, so removing the old copy
    /// loses nothing. `history/` and `ai-journal/` are moved instead, because they are
    /// not rebuildable - `moveDerivedDirectory` never deletes the source until the
    /// destination is known-good (ADR-0017 D3).
    func migrateIfNeeded(from privateDirectory: URL, root: URL) -> [String] {
        var problems: [String] = []
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            problems.append("\(directory.lastPathComponent): \(error.localizedDescription)")
            return problems
        }

        var record = Self.readDescriptor(at: descriptor) ?? .empty
        var done = Set(record.migrated)

        if !done.contains(Self.cacheStoreName) {
            problems.append(contentsOf: Self.removeDerivedFile(
                named: Self.cacheFileName, sidecars: ["-journal", "-wal", "-shm"], in: privateDirectory
            ))
            done.insert(Self.cacheStoreName)
        }
        if !done.contains(Self.thumbnailsStoreName) {
            problems.append(contentsOf: Self.removeDerivedDirectory(
                named: Self.thumbnailsDirectoryName, in: privateDirectory
            ))
            done.insert(Self.thumbnailsStoreName)
        }
        if !done.contains(Self.historyStoreName) {
            let outcome = Self.moveDerivedDirectory(
                named: Self.historyDirectoryName, in: privateDirectory, to: history
            )
            problems.append(contentsOf: outcome.problems)
            if outcome.migrated { done.insert(Self.historyStoreName) }
        }
        if !done.contains(Self.journalStoreName) {
            let outcome = Self.moveDerivedDirectory(
                named: Self.journalDirectoryName, in: privateDirectory, to: journal
            )
            problems.append(contentsOf: outcome.problems)
            if outcome.migrated { done.insert(Self.journalStoreName) }
        }

        problems.append(contentsOf: Self.reportDuplicate(recordedRoot: record.root, resolvingRoot: root))

        record.migrated = done.sorted()
        record.root = root.path(percentEncoded: false)
        Self.writeDescriptor(record, to: descriptor, reporting: &problems)

        return problems
    }

    /// ADR-0017 §D2/§D3's mitigation for the known flaw of an id kept in a file: copy
    /// the vault folder and both copies carry the same id, so both resolve to one state
    /// directory. Run on every call, not only once, because the copy could appear at
    /// any later open, not only the first.
    ///
    /// Two situations share the same symptom - `vault.json`'s recorded root no longer
    /// matches the root resolving here - and must not be answered the same way. If the
    /// recorded folder is simply gone, this is a Finder rename: the pointer is stale
    /// and `migrateIfNeeded`'s caller overwrites it below regardless, silently. If the
    /// recorded folder is still there, two different, both-real folders are sharing one
    /// identity, and their histories could interleave from here on - worth a person's
    /// attention, not a guess this code should resolve on its own.
    private static func reportDuplicate(recordedRoot: String?, resolvingRoot root: URL) -> [String] {
        guard let recordedRoot, recordedRoot != root.path(percentEncoded: false) else { return [] }
        guard FileManager.default.fileExists(atPath: recordedRoot) else { return [] }
        return [
            """
            «\(root.path(percentEncoded: false))» e «\(recordedRoot)» condividono lo stesso \
            identificativo di stato: probabilmente una è una copia dell'altra, e le due \
            cronologie potrebbero mescolarsi
            """
        ]
    }

    private static func removeDerivedFile(
        named name: String, sidecars: [String], in privateDirectory: URL
    ) -> [String] {
        var problems: [String] = []
        removeIfPresent(privateDirectory.appending(path: name, directoryHint: .notDirectory), reporting: &problems)
        for suffix in sidecars {
            removeIfPresent(
                privateDirectory.appending(path: name + suffix, directoryHint: .notDirectory),
                reporting: &problems
            )
        }
        problems.append(contentsOf: conflictCopies(of: name, in: privateDirectory))
        return problems
    }

    private static func removeDerivedDirectory(named name: String, in privateDirectory: URL) -> [String] {
        var problems: [String] = []
        removeIfPresent(privateDirectory.appending(path: name, directoryHint: .isDirectory), reporting: &problems)
        problems.append(contentsOf: conflictCopies(of: name, in: privateDirectory))
        return problems
    }

    private static func removeIfPresent(_ url: URL, reporting problems: inout [String]) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Names in `privateDirectory` that look like an iCloud conflict copy of
    /// `baseName` - `"cache 2.db"` beside `"cache.db"`, `"thumbnails 2"` beside
    /// `"thumbnails"`. Named rather than deleted: an upgrade that removes a file it
    /// did not itself write is not a thing this app does (ADR-0017 D3).
    ///
    /// Not `private`: `VaultState+DirectoryMove.swift`'s `moveDerivedDirectory` reuses
    /// it for `history/` and `ai-journal/` rather than a second copy of the same scan.
    static func conflictCopies(of baseName: String, in directory: URL) -> [String] {
        let stem = (baseName as NSString).deletingPathExtension
        let ext = (baseName as NSString).pathExtension
        guard let entries = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path(percentEncoded: false)
        ) else { return [] }

        return entries
            .filter { entry in
                guard entry != baseName else { return false }
                let entryStem = (entry as NSString).deletingPathExtension
                return (entry as NSString).pathExtension == ext && entryStem.hasPrefix("\(stem) ")
            }
            .sorted()
            .map { "\($0): conflict copy left in \(VaultLayout.privateDirectory)/, not removed" }
    }

    private static func readDescriptor(at url: URL) -> Descriptor? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Descriptor.self, from: data)
    }

    private static func writeDescriptor(_ record: Descriptor, to url: URL, reporting problems: inout [String]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(record).write(to: url, options: .atomic)
        } catch {
            problems.append("\(Self.descriptorFileName): \(error.localizedDescription)")
        }
    }
}
