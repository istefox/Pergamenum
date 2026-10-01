import Foundation

/// Opening another notes folder while one is open (PG-334).
extension VaultController {
    /// The one door every "open this notes folder" goes through: the open panel, «Cartelle
    /// recenti» and the launch's reopen. `open(_:)` is the mechanism under it and never asks.
    ///
    /// `open(_:)` alone keeps `columns`, so a tab of the folder being left used to survive the
    /// switch and name, by its relative path, a file of the new one. Here, before a *different*
    /// folder (compared by `URL.vaultKey`) replaces the session, every dirty tab of every column
    /// is reviewed with the quit's own machinery (ADR-0073: `QuitReview`, `saveForQuit`) and
    /// one question, `ask`:
    ///
    /// - «Annulla» cancels: the open folder stays open, nothing is written, no tab is closed.
    /// - «Non salvare» covers the snapshot the question showed.
    /// - «Salva» / «Salva tutto» saves through `saveForQuit`, into the folder the tabs belong
    ///   to, before the session changes.
    ///
    /// Anything the answer did not cover - a failed save, a conflicted tab the bulk save never
    /// writes, text typed during the saves - cancels the switch, records a problem and brings
    /// the first such tab to the front. Otherwise the arrangement is remembered for the folder
    /// being left, so its tabs come back when it is opened again, `columns` starts empty (the
    /// one writer of `columns` beside `close()` outside the tab doors), and `open(_:)` restores
    /// the new folder's own tabs.
    ///
    /// Reopening the folder already open, or opening one with none open, asks nothing and
    /// resets nothing: it is `open(_:)`.
    ///
    /// A switch asked for while another one's `open(_:)` is still scanning does nothing and
    /// returns false: its `columns` are already empty and its folder not yet restored, so
    /// leaving "it" would remember an empty arrangement over the real one. The flag is read at
    /// the start of the door, before anything is asked.
    ///
    /// Before anything is asked, a different folder's state base is resolved once
    /// (`resolveStateBase`, the seam `open(_:)` reads): when it cannot be, the switch is refused
    /// with a recorded problem and nothing is touched - no question, no saved or discarded tab,
    /// no draft, recents or close request cleared.
    ///
    /// The session is compared again after the saves' `await` (ADR-0043 §D7): a switch that
    /// landed meanwhile has done its own review, and this one stops rather than empty that
    /// folder's tabs.
    ///
    /// - Parameter ask: the question; the app's alert by default, injected by the tests.
    /// - Returns: true when `url` is the open folder afterwards.
    @discardableResult
    func switchVault(
        to url: URL,
        ask: @MainActor (QuitReview) -> QuitReview.Answer = QuitReviewAlert.askBeforeVaultSwitch
    ) async -> Bool {
        guard !routeState.isOpeningVault else { return false }
        guard let leaving = session, leaving.root.vaultKey != url.vaultKey else {
            await open(url)
            return root?.vaultKey == url.vaultKey
        }
        // Preflight: `open(_:)` bails when the state base cannot be resolved, and by then the
        // review, the draft, the recents and a «Non salvare» buffer would be gone for a switch
        // that never happens. Nothing is asked or touched unless the switch can proceed.
        guard (try? resolveStateBase()) != nil else {
            recordProblem(
                "Apertura di un'altra cartella note annullata: impossibile risolvere la cartella di Application Support"
            )
            return false
        }
        let review = QuitReview(columns: columns)
        if !review.isEmpty {
            let answer = ask(review)
            if answer == .cancel { return false }
            if answer == .save { _ = await saveForQuit(review) }
            guard session === leaving else { return false }
            // «Salva» covers nothing it did not save; «Non salvare» covers what it showed.
            let now = QuitReview(columns: columns)
            let left = answer == .save ? now.entries : review.uncovered(in: now)
            if let first = left.first {
                var paths: [String] = []
                for entry in left where !paths.contains(entry.relativePath) { paths.append(entry.relativePath) }
                recordProblem(
                    "Apertura di un'altra cartella note annullata: note non salvate: "
                        + paths.map { "«\($0)»" }.joined(separator: ", ")
                )
                revealTab(first.tabID)
                return false
            }
        }
        rememberTabs()
        columns = [EditorColumn()]
        focusedColumnIndex = 0
        // What belongs to the folder being left and names its files: the composer's draft
        // (as `close()` does), the tabs reopenable with «riapri ultima tab», the quick
        // switcher's in-memory recents and a pending close question about a tab now gone.
        endNewNote()
        closedTabPaths = []
        recentNotePaths = []
        closeRequest = nil
        await open(url)
        // Defence: the preflight above makes this unreachable for an unresolvable state base,
        // but should `open(_:)` still give up before touching the session or the watcher, the
        // folder being left is still open and watched, so its arrangement comes back.
        if session === leaving {
            restoreTabs()
            return false
        }
        return root?.vaultKey == url.vaultKey
    }
}
