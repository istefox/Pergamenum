import Foundation
import OSLog

/// Handling a `pergamenum://` link (SPEC §9).
///
/// A link that silently does nothing is indistinguishable from a broken scheme
/// registration, and that ambiguity cost real time to diagnose; every route says what
/// it did, and one that names something missing returns false so the caller can say so.
extension VaultController {
    /// Handles a `pergamenum://` link (SPEC §9).
    ///
    /// Returns false when the route names something that is not there, so the caller
    /// can say so rather than silently doing nothing: a link from DEVONthink that
    /// quietly fails is worse than one that reports the note has moved.
    /// Traces URL handling.
    ///
    /// A link that silently does nothing is indistinguishable from a broken scheme
    /// registration, and that ambiguity cost real time to diagnose; every route now
    /// says what it did.
    private static let routeLog = Logger(subsystem: AppInfo.bundleIdentifier, category: "url-scheme")

    @discardableResult
    func handle(_ route: PergamenumRoute) async -> Bool {
        Self.routeLog.notice("route ricevuta: \(route.kind, privacy: .public) \(String(describing: route))")
        let outcome = await perform(route)
        Self.routeLog.notice("route esito: \(outcome, privacy: .public)")
        return outcome
    }

    private func perform(_ route: PergamenumRoute) async -> Bool {
        // A link can arrive before the vault has finished opening - the app may have
        // been launched *by* the link. Holding the route and replaying it is the
        // difference between a link that works from cold and one that only works when
        // the app happened to be running. "Not open" includes "still opening": a route
        // acted on during the rescan would open a tab, `rememberTabs()` would overwrite
        // the saved tab session, and `restoreTabs()` would then find tabs and bail out.
        guard let store, !routeState.isOpeningVault else {
            routeState.pending = route
            return false
        }

        switch route {
        case .note(let path):
            guard noteExists(at: path, in: store) else {
                recordProblem("il link punta a una nota che non esiste: \(path)")
                return false
            }
            openNote(at: path)
            return true

        case .noteID(let id):
            return openNote(id: id, in: store)

        case .canvas(let path, let nodeID):
            routeState.pendingCanvas = (path, nodeID)
            return true

        case .day(let date):
            return await openDaily(date)

        case .today:
            return await openDaily(.today)

        case .search(let query):
            routeState.pendingSearch = query
            isShowingQuickSwitcher = true
            return true

        case .capture(let text, let destination, let scheduled, let due):
            return await capture(text: text, to: destination, scheduled: scheduled, due: due)

        case .addTask(let text):
            return await captureTask(text)
        }
    }

    /// The `.noteID` route. Ids live in `.pergamenum/note-ids.json`, read through the
    /// session on every route rather than copied onto the controller (ADR-0059 §D1/§D7).
    /// They follow every rename the app makes, so a miss means an id nobody minted, an
    /// unreadable registry, or a note moved or deleted outside the app - each said in its
    /// own words, and each returning false.
    private func openNote(id: String, in store: NoteStore) -> Bool {
        switch session?.lookUpNote(id: id) ?? .unknown {
        case .unknown:
            recordProblem("nessuna nota con id \(id)")
            return false
        case .unreadable:
            recordProblem(
                "il registro degli id delle note (\(VaultLayout.noteIDsFile)) non è leggibile: "
                    + "impossibile aprire la nota con id \(id)"
            )
            return false
        case .found(let path):
            guard noteExists(at: path, in: store) else {
                recordProblem(
                    "la nota con id \(id) era in \(path), che non esiste più: "
                        + "è stata spostata o eliminata fuori dall'app"
                )
                return false
            }
            openNote(at: path)
            return true
        }
    }

    /// Whether a route's path names a file inside the vault. One check for `.note` and
    /// `.noteID` alike (ADR-0059 §D7): a registry path is hand-editable, so it goes
    /// through `store.url(for:)` - `VaultBoundary`, ADR-0041 §D1 - exactly as a `file=`
    /// argument does, and an id never opens a tab on a missing file.
    private func noteExists(at path: String, in store: NoteStore) -> Bool {
        guard let url = try? store.url(for: path) else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// The link «Copia link Pergamenum» copies for `path` (ADR-0059 §D8): the id form,
    /// minted through the session the first time (§D2), so it survives every rename and
    /// move the app makes. When no id can be minted, the path form - a link that still
    /// works today - with one problem saying it will not survive a rename. Lives here,
    /// not in `CommandActions`, so that file stays under the `file_length` warning.
    func pergamenumLink(toNoteAt path: String) -> URL? {
        if let id = session?.mintNoteID(for: path), let url = PergamenumLink.note(id: id) {
            return url
        }
        recordProblem(
            "il link copiato per \(path) è nella forma a percorso e non sopravvive a una rinomina: "
                + "non è stato possibile assegnare un id alla nota"
        )
        return PergamenumLink.note(path: path)
    }

    /// Opens the daily note for a route, reporting why when it cannot.
    ///
    /// `try?` here swallowed the reason and left a link that did nothing with no way
    /// to find out why.
    private func openDaily(_ date: CalendarDate) async -> Bool {
        do {
            _ = try await openDailyNote(for: date)
            return true
        } catch {
            Self.routeLog.error("daily note fallita: \(String(describing: error))")
            recordProblem("nota giornaliera: \(error)")
            return false
        }
    }


    func consumePendingCanvasRoute() -> (path: String, nodeID: String?)? {
        defer { routeState.pendingCanvas = nil }
        return routeState.pendingCanvas
    }

    func consumePendingSearch() -> String? {
        defer { routeState.pendingSearch = nil }
        return routeState.pendingSearch
    }

    /// The capture route, through the same door the panel and the connectors use
    /// (ADR-0008 §D4, §D5).
    ///
    /// The default is `today` and not the connector's `note`: `?text=…` alone has meant
    /// "append to today's note" since SPEC §9 published the route, and a link already
    /// sitting in a Shortcut must not start creating notes instead.
    ///
    /// The app arms no guardrails (ADR-0007 §D6): a person editing their own notes does
    /// not need an undo log, and the session's `isDryRun` stays false.
    private func capture(
        text: String, to destination: String?, scheduled: String?, due: String?
    ) async -> Bool {
        guard let session else { return false }
        do {
            let target = try VaultAPI.CaptureDestination.named(
                destination ?? "today", folder: nil
            )
            let summary = try await VaultAPI.capture(
                session, to: target, text: text, scheduled: scheduled, due: due
            )
            // The editor may be holding the note that just grew: re-read it, or the
            // next keystroke saves the version without the capture in it.
            if let result = try? session.read(summary.path) {
                syncOpenNote(with: VaultSession.WriteResult(path: summary.path, text: result.text))
            }
            return true
        } catch {
            recordProblem("capture: \(error)")
            return false
        }
    }
}

/// Everything the routes hold between arriving and being acted on (SPEC §9). One value
/// rather than three properties on the controller, so this extension owns its own state
/// instead of reaching into it.
extension VaultController {
    struct RouteState {
        /// A route that arrived before the vault was open, replayed once it is.
        var pending: PergamenumRoute?
        /// A canvas the Workspace should open when it next appears.
        var pendingCanvas: (path: String, nodeID: String?)?
        /// A query the quick switcher should start from.
        var pendingSearch: String?
        /// True while `open(_:)` is between installing the session and restoring the tabs.
        var isOpeningVault = false
    }
}
