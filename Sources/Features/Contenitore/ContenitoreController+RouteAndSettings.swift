import AppKit
import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D10 and §D11 and
// ADR-0059 §D2, plan docs/plans/contenitore.md, Tasks 6 and 7 - R-23, R-24, R-26.
//
// Its own file because `ContenitoreController`'s body sits at SwiftLint's `type_body_length`.

extension ContenitoreController {
    // MARK: - Route and link (R-23, R-24)

    /// Applies a pending `pergamenum://contenitore` target: selects the document, widening the
    /// scope and clearing the filter so the row is on screen, or clears the selection.
    func consumeRoute() {
        guard let target = vault.consumePendingContenitoreRoute() else { return }
        switch target {
        case .select(let path):
            scope = .all
            filter = ContenitoreFilter()
            selection = path
        case .none:
            selection = nil
        }
    }

    /// Puts `pergamenum://contenitore?id=<id>` for the scheda at `schedaPath` on the pasteboard,
    /// minting the id on first use and reusing it after (ADR-0059 §D2). False, with a recorded
    /// problem, when no id can be had.
    @discardableResult
    func copyLink(for schedaPath: String) -> Bool {
        guard let session = vault.session,
              let id = session.mintNoteID(for: schedaPath),
              let url = PergamenumLink.contenitore(id: id)
        else {
            vault.recordProblem("impossibile creare un link Pergamenum per \(schedaPath)")
            return false
        }
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        return true
    }

    // MARK: - Settings › Contenitore (R-26)

    /// Stores `folder` as the drop folder, `~`-relative when it sits under the home folder, or
    /// returns why it cannot be. `RootView`'s `.task(id:)` restarts the watcher on the change.
    func setDropFolder(_ folder: URL) -> ContenitoreSettings.DropFolderRefusal? {
        guard let session = vault.session else { return .empty }
        let stored = ContenitoreSettings.storedDropFolder(for: folder, home: home)
        if let refusal = ContenitoreSettings.validateDropFolder(stored, vaultRoot: session.root, home: home) {
            return refusal
        }
        vault.updateSettings { $0.contenitore.dropFolder = stored }
        return nil
    }

    /// Stores `root` as the Contenitore root, or returns why it cannot be. Nothing already in
    /// the old root moves: the setting says where new documents go and what the pane lists.
    func setRoot(_ root: String) -> ContenitoreSettings.RootRefusal? {
        guard let session = vault.session else { return .empty }
        if let refusal = ContenitoreSettings.validateRoot(root, praticheFolder: session.settings.pratiche.rootFolder) {
            return refusal
        }
        let trimmed = root.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespaces))
        vault.updateSettings { $0.contenitore.root = trimmed }
        return nil
    }

    /// The drop folder the open vault's settings resolve to, for the settings tab and the
    /// pane's footer.
    var resolvedDropFolder: URL? {
        vault.session.map { $0.settings.contenitore.resolvedDropFolder(home: home) }
    }

    /// The drop folder as the settings store it: `~/Pergamenum Drop`.
    var dropFolderDisplay: String {
        vault.settings.contenitore.dropFolder
    }

    /// The open vault's Contenitore root, as the settings store it.
    var root: String {
        vault.settings.contenitore.root.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
