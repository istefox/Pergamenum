import Foundation

/// «Chiudi la colonna» (ADR-0012 D4), which asks before dropping unsaved work (PG-335).
///
/// Its own file because `VaultController+Tabs.swift` sits at SwiftLint's `file_length`.
extension VaultController {
    /// Closes a column and hands the focus to the one left, asking first when the column holds
    /// tabs with unsaved changes.
    ///
    /// Never the last one: an editor with no columns is a window with nothing in it, and the
    /// no-tabs state already says "nessuna nota aperta" without needing a second way to reach
    /// it. The tabs it held are not offered back by Cmd+Shift+T - closing a column is closing
    /// a place, not a note.
    ///
    /// A column whose tabs are all clean closes at once and asks nothing. Otherwise that
    /// column's dirty tabs, and only those, are reviewed with the quit's own machinery
    /// (ADR-0073: `QuitReview`, `saveForQuit`) and one question, `ask`, the close-tab dialog's
    /// answers (ADR-0012 §D3) for a whole column:
    ///
    /// - «Annulla» leaves the column open and untouched.
    /// - «Non salvare» closes it, dropping what the question showed.
    /// - «Salva» / «Salva tutto» writes each tab through `saveTab(_:)`, the one save door, one
    ///   after the other, re-reading the tab before every write; a conflicted tab, or one of a
    ///   previous vault, is never written.
    ///
    /// What happens next is `QuitReview.closeDecision(after:now:)`, decided on the column as it
    /// is after the answer ran, found again by id (ADR-0043 §D7: what was read before the
    /// saves' `await` is a filter, not a guard). The column closes only when the answer covered
    /// every dirty tab in it; anything left - a failed save, a conflicted tab, text typed during
    /// the saves - keeps it open, records a problem and brings the first such tab to the front.
    ///
    /// A second request for a column whose close is still asking or saving does nothing and
    /// returns false, whoever makes it (the menu wraps this door in a `Task`, so a second click
    /// during the saves would otherwise raise the question again). The column is named by id in
    /// `closingColumns`, and released on every exit.
    ///
    /// - Parameter ask: the question; the app's alert by default, injected by the tests.
    /// - Parameter saveAll: the bulk save; `nil` means `saveForQuit(_:)`. A seam for the tests,
    ///   which suspend the close after its saves to change the editor under it (ADR-0043 §D9),
    ///   the shape of `QuitCoordinator`'s own `saveAll`.
    /// - Returns: true when the column was closed.
    @discardableResult
    func closeColumn(
        _ index: Int,
        ask: @MainActor (QuitReview) -> QuitReview.Answer = QuitReviewAlert.askBeforeColumnClose,
        saveAll: (@MainActor (QuitReview) async -> QuitSaveReport)? = nil
    ) async -> Bool {
        guard columns.count > 1, columns.indices.contains(index) else { return false }
        let columnID = columns[index].id
        guard !closingColumns.contains(columnID) else { return false }
        closingColumns.insert(columnID)
        defer { closingColumns.remove(columnID) }
        let review = QuitReview(columns: [columns[index]])
        if !review.isEmpty {
            let answer = ask(review)
            if answer == .save {
                if let saveAll { _ = await saveAll(review) } else { _ = await saveForQuit(review) }
            }
            guard columns.count > 1, let now = columns.firstIndex(where: { $0.id == columnID }) else { return false }
            let decision = review.closeDecision(after: answer, now: QuitReview(columns: [columns[now]]))
            if case .keepOpen(let unresolved) = decision {
                if let first = unresolved.first {
                    var paths: [String] = []
                    for entry in unresolved where !paths.contains(entry.relativePath) {
                        paths.append(entry.relativePath)
                    }
                    recordProblem(
                        "Chiusura della colonna annullata: note non salvate: "
                            + paths.map { "«\($0)»" }.joined(separator: ", ")
                    )
                    revealTab(first.tabID)
                }
                return false
            }
        }
        guard let closing = columns.firstIndex(where: { $0.id == columnID }) else { return false }
        columns.remove(at: closing)
        focusedColumnIndex = 0
        rememberTabs()
        return true
    }
}
