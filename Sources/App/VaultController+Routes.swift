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
        Self.routeLog.notice("route ricevuta: \(String(describing: route), privacy: .public)")
        let outcome = await perform(route)
        Self.routeLog.notice("route esito: \(outcome, privacy: .public)")
        return outcome
    }

    private func perform(_ route: PergamenumRoute) async -> Bool {
        // A link can arrive before the vault has finished opening - the app may have
        // been launched *by* the link. Holding the route and replaying it is the
        // difference between a link that works from cold and one that only works when
        // the app happened to be running.
        guard let store else {
            routeState.pending = route
            return false
        }

        switch route {
        case .note(let path):
            guard let url = try? store.url(for: path),
                  FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
            else {
                recordProblem("il link punta a una nota che non esiste: \(path)")
                return false
            }
            openNote(at: path)
            return true

        case .noteID(let id):
            // IDs live in the index, not in the frontmatter (SPEC §9), so an unknown
            // one means the note was renamed outside the app.
            guard let path = routeState.noteIDs[id] else {
                recordProblem("nessuna nota con id \(id)")
                return false
            }
            openNote(at: path)
            return true

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

    /// Opens the daily note for a route, reporting why when it cannot.
    ///
    /// `try?` here swallowed the reason and left a link that did nothing with no way
    /// to find out why.
    private func openDaily(_ date: CalendarDate) async -> Bool {
        do {
            _ = try await openDailyNote(for: date)
            return true
        } catch {
            Self.routeLog.error("daily note fallita: \(String(describing: error), privacy: .public)")
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
/// rather than four properties on the controller, so this extension owns its own state
/// instead of reaching into it.
extension VaultController {
    struct RouteState {
        /// A route that arrived before the vault was open, replayed once it is.
        var pending: PergamenumRoute?
        /// A canvas the Workspace should open when it next appears.
        var pendingCanvas: (path: String, nodeID: String?)?
        /// A query the quick switcher should start from.
        var pendingSearch: String?
        /// Stable ids for `pergamenum://note?id=`, held here rather than in the files.
        var noteIDs: [String: String] = [:]
    }
}
