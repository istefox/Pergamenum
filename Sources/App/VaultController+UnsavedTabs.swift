import Foundation

/// Quit and vault switch with unsaved note tabs (PG-326, #693, ADR-0073).
///
/// ADR-0012 §D3's question, Salva / Non salvare / Annulla, guards every gesture that drops a
/// dirty note tab, not only a tab close. Nothing is autosaved on quit or on a switch, on
/// purpose: saving stays explicit (§D1).
extension VaultController {
    /// Asks once when at least one tab is dirty, in any column; nil when nothing is, and then
    /// `ask` is never called (ADR-0073 §D2). Quit and switch both decide here, so they cannot
    /// drift in what they ask or when. Asking writes nothing and changes no buffer.
    func unsavedTabsDecision(
        asking ask: (UnsavedNotesPrompt) -> UnsavedNotesChoice
    ) -> UnsavedNotesChoice? {
        UnsavedNotesPrompt(tabs: unsavedTabs).map(ask)
    }

    /// «Salva tutto»: writes every dirty tab through Cmd+S's own door, one path at a time
    /// (ADR-0073 §D3). True only when nothing failed or was refused **and** no tab is dirty at
    /// the end - the verdict is about the state the gesture is about to act on.
    ///
    /// - The paths are taken once, at the start; the dirty tabs of each are read **again after
    ///   every `await`** (ADR-0043 §D7), since a write's catch-up or a watcher reconcile can
    ///   change them in between.
    /// - Two dirty copies of one path with different texts are refused: writing either would
    ///   silently discard the other (ADR-0001 §D3.4). Identical copies are written once, and
    ///   `catchUp(to:)` adopts the second (§D4).
    /// - No `expecting:`, the same as Cmd+S: a pending external change is written over, because
    ///   the person saw the banner and asked to save.
    /// - A throw is recorded and the loop goes on (ADR-0046 §D3: best effort, one verdict).
    /// - Nothing here catches a tab up after its write: `landed(_:)` does (ADR-0067 §D5), and
    ///   `origin` names the writer so it keeps anything typed during its own suspension.
    func saveAllUnsavedTabs() async -> Bool {
        var seen = Set<String>()
        let paths = unsavedTabs.map(\.note.relativePath).filter { seen.insert($0).inserted }
        var failed = Set<String>()
        for path in paths {
            let dirty = unsavedTabs.filter { $0.note.relativePath == path }
            guard let writer = dirty.first else { continue }
            guard dirty.allSatisfy({ $0.note.text == writer.note.text }) else {
                recordProblem("\(path): aperta in più tab con testi diversi, non salvata")
                failed.insert(path)
                continue
            }
            guard let session else {
                failed.insert(path)
                continue
            }
            do {
                try await session.write(writer.note.text, to: path, origin: writer.id)
            } catch {
                recordProblem("\(path): \(error)")
                failed.insert(path)
            }
        }
        var leftover = Set<String>()
        for tab in unsavedTabs where !failed.contains(tab.note.relativePath) {
            guard leftover.insert(tab.note.relativePath).inserted else { continue }
            recordProblem("\(tab.note.relativePath): modificata durante il salvataggio, non salvata")
        }
        return failed.isEmpty && unsavedTabs.isEmpty
    }

    /// The vault switch the UI uses: «Apri cartella note…» and «Cartelle recenti» (ADR-0073
    /// §D6). False when the switch did not happen.
    ///
    /// «Annulla» leaves the vault and every buffer as they are. «Salva tutto» writes first, and
    /// a save that leaves anything unsaved aborts the switch and says so. «Non salvare», or
    /// nothing dirty, goes ahead: `open(_:)` closes the outgoing tabs. It asks whatever the
    /// target is, the open vault included - re-picking it has always rebuilt the session.
    func switchVault(to url: URL, presenter: UnsavedNotesPresenter) async -> Bool {
        switch unsavedTabsDecision(asking: presenter.ask) {
        case .cancel:
            return false
        case .saveAll:
            guard await saveAllUnsavedTabs() else {
                presenter.reportUnsaved(UnsavedNotesPrompt(tabs: unsavedTabs))
                return false
            }
        case .discard, nil:
            break
        }
        await open(url)
        return true
    }
}
