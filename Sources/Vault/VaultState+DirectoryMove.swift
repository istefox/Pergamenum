import Foundation

/// The move-with-fallback machinery `VaultState.migrateIfNeeded` (in
/// `VaultState+Migration.swift`) uses for `history/` and `ai-journal/` - not
/// rebuildable, so the source is never touched until the destination is known-good
/// (ADR-0017 §D3). Its own file for the same reason the migration itself is: kept
/// under SwiftLint's file and type length limits, not a different concern.
extension VaultState {
    /// Moves a derived directory out of the vault, falling back to
    /// copy-then-verify-then-remove when a plain move fails.
    ///
    /// - Returns: the problems found along the way, and whether the store may be
    ///   recorded as migrated. `migrated` is `false` on any failure that leaves work
    ///   still to do, which is what keeps the caller from writing the store's name into
    ///   `vault.json` and losing the retry.
    static func moveDerivedDirectory(
        named name: String, in privateDirectory: URL, to destination: URL
    ) -> (problems: [String], migrated: Bool) {
        var problems = conflictCopies(of: name, in: privateDirectory)
        let source = privateDirectory.appending(path: name, directoryHint: .isDirectory)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            // Nothing to migrate: no directory is created at the destination where none
            // existed - both stores create their own lazily, on first write.
            return (problems, true)
        }

        guard fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
            do {
                try fileManager.moveItem(at: source, to: destination)
                return (problems, true)
            } catch {
                // A plain move can fail across volumes; copy-then-verify-then-remove
                // below is the fallback, not yet a problem worth reporting.
            }
            if copyThenVerifyThenRemove(source: source, to: destination, reporting: &problems) {
                return (problems, true)
            }
            problems.append("\(name): impossibile spostare fuori dal vault; riproverò al prossimo avvio")
            return (problems, false)
        }

        // The destination already exists: an interrupted previous run, or a duplicated
        // vault. Merged item by item rather than overwritten wholesale.
        let migrated = mergeDirectory(from: source, into: destination, reporting: &problems)
        return (problems, migrated)
    }

    /// `moveItem` failed - most likely a cross-volume move. Copies the tree, verifies
    /// every file the source has is present and identical under the destination, and
    /// only then removes the source. The removal is always last, so an interrupted
    /// migration leaves the only copy of a snapshot somewhere rather than nowhere.
    private static func copyThenVerifyThenRemove(
        source: URL, to destination: URL, reporting problems: inout [String]
    ) -> Bool {
        let fileManager = FileManager.default
        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            problems.append("\(source.lastPathComponent): \(error.localizedDescription)")
            try? fileManager.removeItem(at: destination)
            return false
        }
        guard verifyTreeCopied(from: source, to: destination) else {
            problems.append("\(source.lastPathComponent): copia incompleta, non tocco l'originale")
            return false
        }
        do {
            try fileManager.removeItem(at: source)
            return true
        } catch {
            problems.append(
                "\(source.lastPathComponent): copiato ma non rimosso dalla vecchia posizione: "
                    + error.localizedDescription
            )
            return false
        }
    }

    /// Walks `source` and confirms every file under it exists, byte for byte, under
    /// `destination` - the check `copyThenVerifyThenRemove` runs before it lets a
    /// single byte of what could be the only copy be deleted.
    private static func verifyTreeCopied(from source: URL, to destination: URL) -> Bool {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: source.path(percentEncoded: false)) else {
            return false
        }
        for case let relativePath as String in enumerator {
            let sourceItem = source.appending(path: relativePath)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: sourceItem.path(percentEncoded: false), isDirectory: &isDirectory
            ) else { continue }
            guard !isDirectory.boolValue else { continue }

            let destinationItem = destination.appending(path: relativePath)
            guard let sourceData = try? Data(contentsOf: sourceItem),
                  let destinationData = try? Data(contentsOf: destinationItem),
                  sourceData == destinationData
            else { return false }
        }
        return true
    }

    /// Merges `source` into an already-existing `destination`, moving what does not
    /// conflict and leaving what does: the interrupted-previous-run and
    /// duplicated-vault cases, where overwriting either copy would be a guess rather
    /// than a decision. `source` is removed only once it has been merged empty;
    /// anything left behind - a name that collided - means both copies are kept and
    /// reported, not resolved by picking one.
    private static func mergeDirectory(
        from source: URL, into destination: URL, reporting problems: inout [String]
    ) -> Bool {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            atPath: source.path(percentEncoded: false)
        ) else {
            problems.append("\(source.lastPathComponent): impossibile leggere la cartella da unire")
            return false
        }

        var leftBehind = false
        for entry in entries.sorted() {
            let sourceItem = source.appending(path: entry)
            let destinationItem = destination.appending(path: entry)
            var destinationIsDirectory: ObjCBool = false
            let existsAtDestination = fileManager.fileExists(
                atPath: destinationItem.path(percentEncoded: false), isDirectory: &destinationIsDirectory
            )

            guard existsAtDestination else {
                do {
                    try fileManager.moveItem(at: sourceItem, to: destinationItem)
                } catch {
                    problems.append("\(entry): \(error.localizedDescription)")
                    leftBehind = true
                }
                continue
            }

            var sourceIsDirectory: ObjCBool = false
            fileManager.fileExists(atPath: sourceItem.path(percentEncoded: false), isDirectory: &sourceIsDirectory)
            if destinationIsDirectory.boolValue && sourceIsDirectory.boolValue {
                // Both sides have a directory by this name - a note's own history
                // directory, most likely - and the snapshots underneath deserve the
                // same item-by-item treatment rather than being skipped as a conflict.
                if !mergeDirectory(from: sourceItem, into: destinationItem, reporting: &problems) {
                    leftBehind = true
                }
            } else {
                problems.append(
                    "\(entry): stesso nome già presente nella nuova posizione, lasciato in "
                        + source.lastPathComponent
                )
                leftBehind = true
            }
        }

        guard !leftBehind else { return false }
        do {
            try fileManager.removeItem(at: source)
            return true
        } catch {
            problems.append("\(source.lastPathComponent): unito ma non rimosso: \(error.localizedDescription)")
            return false
        }
    }
}
