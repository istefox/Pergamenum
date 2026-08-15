import Foundation

/// Turning what a caller wrote into what the vault understands.
///
/// A date arrives as a string, a task arrives as a phrase, a view arrives as a name -
/// from a shell or from a model, it makes no difference. Reading them is the same job
/// both times, and so are the sentences said when they cannot be read.
extension VaultAPI {
    /// An ISO date, or today when none was given.
    ///
    /// `CalendarDate.today` is `Calendar.current`, so this agrees with what the app
    /// would show at the same moment on the same machine.
    static func day(_ raw: String?) throws -> CalendarDate {
        guard let raw, !raw.isEmpty else { return .today }
        guard let date = CalendarDate(iso: raw) ?? CalendarDate(compact: raw) else {
            throw ConnectorError("«\(raw)» non è una data (YYYY-MM-DD o YYYYMMDD)", usage: true)
        }
        return date
    }

    /// The five views of SPEC §7.4, named as the sidebar names them - and in Italian
    /// too, because a person typing at a shell types the word they see on screen.
    static func taskView(_ raw: String?) throws -> IndexSnapshot.TaskView {
        switch raw ?? "all" {
        case "inbox": return .inbox
        case "today", "oggi": return .today
        case "upcoming", "prossimi": return .upcoming
        case "by-project", "progetto": return .byProject
        case "all", "tutti": return .all
        case let other:
            throw ConnectorError(
                "«\(other)» non è una vista; ci sono inbox, today, upcoming, by-project, all",
                usage: true
            )
        }
    }

    /// `HH:MM` as minutes from midnight.
    static func minutesFromMidnight(_ text: String) throws -> Int {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute)
        else {
            throw ConnectorError("«\(text)» non è un orario (HH:MM)", usage: true)
        }
        return hour * 60 + minute
    }

    /// Finds the one task a phrase names, and refuses when it names several.
    ///
    /// `percorso:riga` is exact; anything else is matched against the task's text.
    /// Ambiguity is an error rather than a first match: completing the wrong task is
    /// silent, and whoever asked would find out much later.
    @MainActor
    static func task(_ session: VaultSession, matching needle: String) throws -> TaskItem {
        let tasks = session.index.allTasks

        if let colon = needle.lastIndex(of: ":"), let line = Int(needle[needle.index(after: colon)...]) {
            let path = String(needle[needle.startIndex..<colon])
            guard let task = tasks.first(where: { $0.sourcePath == path && $0.lineIndex + 1 == line }) else {
                throw ConnectorError("nessun task a \(path):\(line)")
            }
            return task
        }

        let matches = tasks.filter { $0.text.localizedCaseInsensitiveContains(needle) }
        switch matches.count {
        case 0: throw ConnectorError("nessun task contiene «\(needle)»")
        case 1: return matches[0]
        default:
            let list = matches.prefix(5)
                .map { "  \($0.sourcePath):\($0.lineIndex + 1)  \($0.text)" }
                .joined(separator: "\n")
            throw ConnectorError(
                "«\(needle)» corrisponde a \(matches.count) task; indica percorso:riga\n\(list)",
                usage: true
            )
        }
    }
}
