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
        if let problem = starredStore.save(starred) { recordProblem(problem) }
    }

    /// Follows a note that has been renamed or moved.
    ///
    /// **Called from `VaultSession+Files`, not left to the caller.** A star is a path, and a path
    /// the vault no longer has is a row in the sidebar pointing at nothing - the same class of
    /// follow-up a rename already performs for the links (wikilink.md W-08).
    func moveStar(from oldPath: String, to newPath: String) {
        guard starred.contains(oldPath) else { return }
        starred.remove(oldPath)
        starred.insert(newPath)
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
