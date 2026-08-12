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
    func handle(_ route: PergamenumRoute) -> Bool {
        Self.routeLog.notice("route ricevuta: \(String(describing: route), privacy: .public)")
        let outcome = perform(route)
        Self.routeLog.notice("route esito: \(outcome, privacy: .public)")
        return outcome
    }

    private func perform(_ route: PergamenumRoute) -> Bool {
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
            guard FileManager.default.fileExists(
                atPath: store.url(for: path).path(percentEncoded: false)
            ) else {
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
            return openDaily(date)

        case .today:
            return openDaily(.today)

        case .search(let query):
            routeState.pendingSearch = query
            isShowingQuickSwitcher = true
            return true

        case .capture(let text, let notePath):
            return append(text: text, to: notePath)

        case .addTask(let text):
            return captureTask(text)
        }
    }

    /// Opens the daily note for a route, reporting why when it cannot.
    ///
    /// `try?` here swallowed the reason and left a link that did nothing with no way
    /// to find out why.
    private func openDaily(_ date: CalendarDate) -> Bool {
        do {
            _ = try openDailyNote(for: date)
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

    /// Appends text to a note without opening it, for the capture route.
    private func append(text: String, to notePath: String?) -> Bool {
        guard let store else { return false }
        let path = notePath ?? {
            settings.dailyFolder.isEmpty
                ? NoteName.dailyFileName(for: .today)
                : "\(settings.dailyFolder)/\(NoteName.dailyFileName(for: .today))"
        }()

        do {
            if !FileManager.default.fileExists(atPath: store.url(for: path).path(percentEncoded: false)) {
                _ = try openDailyNote(for: .today)
            }
            let existing = try store.read(path).text
            let separator = existing.hasSuffix("\n") ? "" : "\n"
            let hash = try store.write(existing + separator + text + "\n", to: path)
            selfWrittenHashes[path] = hash
            index.update(try store.read(path).record, at: path)
            return true
        } catch {
            recordProblem("capture: \(error)")
            return false
        }
    }
}
