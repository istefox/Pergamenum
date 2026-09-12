import Foundation

/// Starring a note, and keeping the star on it (ADR-0012 D6).
///
/// On the session and not on the controller, for the reason every other piece of vault state is:
/// a connector could offer `perg note star` tomorrow by calling these, and a facade that owned
/// the set would mean writing the feature twice. Whether either connector does is a separate
/// decision and is not taken here.
extension VaultSession {
    func isStarred(_ relativePath: String) -> Bool {
        starred.contains(relativePath)
    }

    /// Adds or removes the star, and writes the file. Returns what the note now is.
    @discardableResult
    func toggleStar(_ relativePath: String) -> Bool {
        setStar(!isStarred(relativePath), for: relativePath)
        return isStarred(relativePath)
    }

    func setStar(_ wanted: Bool, for relativePath: String) {
        let before = starred
        if wanted {
            starred.insert(relativePath)
        } else {
            starred.remove(relativePath)
        }
        guard starred != before else { return }
        testOnlyStarredSaveCount += 1
        if let problem = starredStore.save(starred) { recordProblem(problem) }
    }

    /// Follows a note that has been renamed or moved.
    ///
    /// **Called from `VaultSession+Files`, not left to the caller.** A star is a path, and a path
    /// the vault no longer has is a row in the sidebar pointing at nothing - the same class of
    /// follow-up a rename already performs for the links (wikilink.md W-08).
    ///
    /// Re-expressed as the one-pair form of `moveStars` below (ADR-0041 §D8, Task 7): the
    /// single-pair and batched shapes share one body now, so the two cannot drift apart.
    func moveStar(from oldPath: String, to newPath: String) {
        moveStars([(old: oldPath, new: newPath)])
    }

    /// Real batched form of `moveStar(from:to:)` above (ADR-0041 §D8, Task 7): every star a
    /// batch's items carried, applied to `starred` in memory and saved to `starred.json`
    /// **once** for the whole call - not once per pair, which is what made a batch of *n*
    /// starred notes write the file *n* times before this task
    /// (`perf-VaultSession+Starred.swift-4d9`). A pair whose `old` is not currently starred
    /// is skipped, the same guard the single-pair form always carried: moving a note that
    /// was never starred moves no star.
    func moveStars(_ pairs: [(old: String, new: String)]) {
        var changed = false
        for pair in pairs {
            guard starred.contains(pair.old) else { continue }
            starred.remove(pair.old)
            starred.insert(pair.new)
            changed = true
        }
        guard changed else { return }
        testOnlyStarredSaveCount += 1
        if let problem = starredStore.save(starred) { recordProblem(problem) }
    }

    /// Takes a star out of `starred` in memory only - no save, no count. The seam
    /// `VaultSession+Move.swift`'s batched `moveItems` uses to neutralize `moveNote`'s own
    /// per-note call to `moveStar(from:to:)` ahead of time: that call lives in
    /// `VaultSession+Files.swift`, outside this task's budget, and there is no flag to ask
    /// it to skip itself. With nothing left in `starred` for that call to find, its own
    /// guard above turns it into a no-op, and the batch does its single save afterwards
    /// instead of one per starred note.
    ///
    /// Returns whether there was a star to take - what the caller needs to know whether to
    /// carry the note's new path forward, once its move has actually succeeded, to
    /// `commitBatchedStarMoves(_:)` below.
    func extractStarForBatchedMove(_ relativePath: String) -> Bool {
        guard starred.contains(relativePath) else { return false }
        starred.remove(relativePath)
        return true
    }

    /// Puts a star back exactly where `extractStarForBatchedMove` took it from, in memory
    /// only - the undo for a batched move whose file-system operation failed *after* the
    /// star had already been provisionally taken. Nothing was ever saved to disk in
    /// between the two calls, so restoring it in memory is the whole story:
    /// `starred.json` never disagreed with what actually happened.
    func restoreExtractedStar(_ relativePath: String) {
        starred.insert(relativePath)
    }

    /// Inserts every new path a batch's moves actually finished moving into, for a note
    /// whose star `extractStarForBatchedMove` took earlier, and saves `starred.json`
    /// **once** for however many the whole batch collected - the closing half of the pair
    /// above, and the reason a batch of several starred notes writes the file once rather
    /// than once per note (R-05). A caller with nothing to insert saves nothing, the same
    /// as every other door on this file.
    func commitBatchedStarMoves(_ newPaths: [String]) {
        guard !newPaths.isEmpty else { return }
        starred.formUnion(newPaths)
        testOnlyStarredSaveCount += 1
        if let problem = starredStore.save(starred) { recordProblem(problem) }
    }

    /// Drops the star of a note that is no longer there.
    func forgetStar(_ relativePath: String) {
        setStar(false, for: relativePath)
    }

    /// The starred notes as records, title-sorted, skipping any whose file the index no longer
    /// knows: a vault edited outside the app can leave a star behind, and a row that opens
    /// nothing is worse than a row that is not there.
    var starredNotes: [NoteRecord] {
        index.allNotes
            .filter { starred.contains($0.relativePath) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
