import Foundation

/// How one task view groups, sorts and draws its list (ADR-0013 §D6).
///
/// Three controls rather than a filter: the five views of SPEC §7.4 decide *which* tasks are
/// in front of you and stay exactly as they were, and these decide how that list reads. The
/// distinction matters because it is what keeps §7.4 a closed list - a sixth view would be a
/// new place in the app, a new grouping is a menu item.
///
/// **Kept per view, never shared.** *Oggi* wants a flat list in hour order and *Tutti* wants
/// grouping by note; one setting behind both would turn every switch between them into a
/// re-setting, which is the reason §D6 exists as a decision at all.
enum TaskGrouping: String, CaseIterable, Codable, Sendable, Identifiable {
    /// One list, no headings. What *Oggi* opens as.
    case none
    case note
    case project
    case schedule
    case deadline
    /// One group per project task's `^id`, its `^parent` children indented beneath it
    /// (ADR-0021 D6). Not a sixth `TaskView` - ADR-0013 §D6 closed that list and named
    /// this the open axis.
    case subtasks
    /// One group per assigned Workspace board (ADR-0021 D9), unrelated to `.project` -
    /// that groups by the `^id`/`^parent` sub-task relation, this by the `^[[board.canvas]]`
    /// marker. The seventh grouping, same open axis `.subtasks` already opened.
    case workspace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Nessun raggruppamento"
        case .note: "Per nota"
        case .project: "Per progetto"
        case .schedule: "Per data"
        case .deadline: "Per scadenza"
        case .subtasks: "Progetti"
        case .workspace: "Per Workspace"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "list.bullet"
        case .note: "rectangle.3.group"
        case .project: "folder"
        case .schedule: "calendar"
        case .deadline: "exclamationmark.triangle"
        case .subtasks: "list.bullet.indent"
        case .workspace: "rectangle.3.group"
        }
    }
}

/// The order inside each group, or inside the single list when there is no grouping.
enum TaskSorting: String, CaseIterable, Codable, Sendable, Identifiable {
    /// By `>date` and then by the hour written after it, which is what a day reads as.
    case schedule
    /// By `!date`: what is late first, and what has no deadline last.
    case deadline
    case text
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: "Data pianificata"
        case .deadline: "Scadenza"
        case .text: "Testo"
        case .note: "Nota di origine"
        }
    }
}

/// How much of a row is drawn.
///
/// Compact is one line: the checkbox, the text and the marker. Expanded adds the second line
/// the list has always had - the source note, the wikilinks and the project - which is the
/// difference between reading a list and working through one.
enum TaskDensity: String, CaseIterable, Codable, Sendable, Identifiable {
    case compact
    case expanded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compatta"
        case .expanded: "Estesa"
        }
    }

    var systemImage: String {
        switch self {
        case .compact: "arrow.up.and.down.text.horizontal"
        case .expanded: "text.alignleft"
        }
    }
}

/// The three controls of one view, together.
struct TaskListOptions: Codable, Equatable, Sendable {
    var grouping: TaskGrouping
    var sorting: TaskSorting
    var density: TaskDensity

    /// Decoded key by key like `VaultSettings`, and for the same reason: this is written by
    /// one version of the app and read by the next, and a control added later must not cost
    /// the two that were already set.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        grouping = try container.decodeIfPresent(TaskGrouping.self, forKey: .grouping) ?? .none
        sorting = try container.decodeIfPresent(TaskSorting.self, forKey: .sorting) ?? .schedule
        density = try container.decodeIfPresent(TaskDensity.self, forKey: .density) ?? .expanded
    }

    init(grouping: TaskGrouping, sorting: TaskSorting, density: TaskDensity = .expanded) {
        self.grouping = grouping
        self.sorting = sorting
        self.density = density
    }
}

/// One heading and the tasks under it.
struct TaskGroup: Equatable, Sendable, Identifiable {
    /// Empty when the list is not grouped, and the view draws no heading for it.
    var title: String
    var tasks: [TaskItem]
    /// The project task this group is the children of, set only by `.subtasks`
    /// (ADR-0021 D6). `nil` for every other grouping.
    var parent: TaskItem?
    /// How many of `parent`'s children are done, set only by `.subtasks`. `nil`
    /// wherever `parent` is `nil`.
    var progress: TaskProgress?

    /// Falls back to `title` so nothing that groups by project or by day changes;
    /// rises to the parent's own id when there is one, so two projects whose parent
    /// tasks read the same in two different notes are two rows rather than one
    /// (ADR-0021 D2, D6).
    var id: String { parent?.id ?? title }
}

/// Turns a view's tasks into the list the user asked for.
///
/// Pure and outside the view on purpose: this is the whole of §D6 that can be wrong in a way
/// a screenshot would not show - a sort that is not stable, a group that swallows the tasks
/// with no project - and none of it needs SwiftUI to be tested.
enum TaskArrangement {
    /// The heading a task with nothing to group by ends up under. One string, so the
    /// grouped-by-project and grouped-by-note cases cannot disagree about the wording.
    static let noneTitle = "Senza"

    /// The heading an unassigned task ends up under when grouping by Workspace - deliberately
    /// not `noneTitle`: "Senza" answers "senza cosa?" for the other five groupings alike, and
    /// this one is specific enough that the interview asked for its own wording (SPEC trade-offs).
    static let noWorkspaceTitle = "Nessun Workspace"

    /// - Parameter priorityPaths: source notes whose group floats to the top when grouping by
    ///   note. The starred notes of ADR-0012 §D6, which the roadmap asks to see first in
    ///   *Tutti*. Empty everywhere else, and ignored by every other grouping.
    /// - Parameter boards: every board's vault-relative path, for resolving `.workspace`
    ///   grouping (`WorkspaceBoardResolver`). Empty and ignored by every other grouping.
    static func groups(
        _ tasks: [TaskItem],
        options: TaskListOptions,
        priorityPaths: Set<String> = [],
        boards: [String] = []
    ) -> [TaskGroup] {
        guard !tasks.isEmpty else { return [] }
        let sorted = sort(tasks, by: options.sorting)

        switch options.grouping {
        case .none:
            return [TaskGroup(title: "", tasks: sorted)]
        case .note:
            return byNote(sorted, priorityPaths: priorityPaths)
        case .project:
            return grouped(sorted) { $0.project?.description ?? noneTitle }
        case .schedule:
            return grouped(sorted) { $0.scheduled.map(dayTitle) ?? noneTitle }
        case .deadline:
            return grouped(sorted) { $0.due.map(dayTitle) ?? noneTitle }
        case .subtasks:
            return bySubtasks(sorted)
        case .workspace:
            return byWorkspace(sorted, boards: boards)
        }
    }

    /// `lunedì 17/08/2026`, the form the day view already writes dates in.
    static func dayTitle(_ day: CalendarDate) -> String {
        "\(DateEntry.weekdayName(of: day)) \(day.italianForm)"
    }

    // MARK: Sorting

    /// Stable, and secondary on the text every time.
    ///
    /// `sorted(by:)` is not stable in the standard library, so two tasks with the same date
    /// could swap places between two redraws of the same list - a list that shuffles while
    /// nothing changed is the kind of defect nobody reports and everybody notices.
    private static func sort(_ tasks: [TaskItem], by sorting: TaskSorting) -> [TaskItem] {
        tasks.sorted { first, second in
            let left = key(first, sorting)
            let right = key(second, sorting)
            if left != right { return left < right }
            return first.id < second.id
        }
    }

    /// One comparable string per task, so every sort is one code path.
    ///
    /// A task with no date sorts last rather than first: an empty marker is "not scheduled",
    /// and a list that opened on everything undated would bury the day it is about.
    private static func key(_ task: TaskItem, _ sorting: TaskSorting) -> String {
        switch sorting {
        case .schedule:
            guard let scheduled = task.scheduled else { return "\u{10FFFF}" }
            return scheduled.description + " " + (task.scheduledTime?.text ?? "99:99")
        case .deadline:
            guard let due = task.due else { return "\u{10FFFF}" }
            return due.description + " " + (task.dueTime?.text ?? "99:99")
        case .text:
            return task.text.lowercased()
        case .note:
            return noteTitle(of: task).lowercased()
        }
    }

    // MARK: Grouping

    private static func grouped(
        _ tasks: [TaskItem], lastTitle: String = noneTitle, by heading: (TaskItem) -> String
    ) -> [TaskGroup] {
        var order: [String] = []
        var buckets: [String: [TaskItem]] = [:]
        for task in tasks {
            let title = heading(task)
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(task)
        }
        // Alphabetical, except that the empty-bucket title goes last wherever it appears: it is
        // the absence of the thing the list is grouped by, and it is never what somebody
        // scrolled to.
        return order
            .sorted { first, second in
                if (first == lastTitle) != (second == lastTitle) { return second == lastTitle }
                return first.localizedStandardCompare(second) == .orderedAscending
            }
            .map { TaskGroup(title: $0, tasks: buckets[$0] ?? []) }
    }

    /// One group per assigned board, resolved via `WorkspaceBoardResolver`: the full path when
    /// unambiguous, the bare file name when ambiguous or orphaned, `noWorkspaceTitle` when the
    /// task carries no `^[[board.canvas]]` marker at all.
    private static func byWorkspace(_ tasks: [TaskItem], boards: [String]) -> [TaskGroup] {
        grouped(tasks, lastTitle: noWorkspaceTitle) { task in
            guard let workspacePath = task.workspacePath else { return noWorkspaceTitle }
            switch WorkspaceBoardResolver.resolve(workspacePath, in: boards) {
            case .unique(let path): return path
            case .ambiguous, .notFound: return workspacePath
            }
        }
    }

    /// One group per project task, its `^parent` children beneath it (ADR-0021 D6).
    ///
    /// **The join is `(sourcePath, localID)`, never `localID` alone.** Ids are note-local
    /// (D2), so `^id(1)` in `A.md` and `^id(1)` in `B.md` are two different projects and a
    /// key without the path would silently merge them the first time two notes each reached
    /// one sub-task. The same scoping `IndexSnapshot.subtasks(of:)` applies, restated here
    /// because this side has no index: `TaskArrangement` is handed a flat list and the
    /// relationships have to be rebuilt from the tasks themselves.
    ///
    /// A project heading is a task carrying an `^id` that some other task actually names: an
    /// `^id` with no children is not a project, it is a task, and it goes to "Senza" with
    /// everything else that has nothing to group by - alongside an orphaned `^parent(N)` whose
    /// `^id(N)` exists in no task of that note, which must still appear rather than vanish.
    private static func bySubtasks(_ tasks: [TaskItem]) -> [TaskGroup] {
        struct ProjectKey: Hashable {
            let sourcePath: String
            let localID: Int
        }

        // First occurrence wins on a note that carries `^id(1)` twice, the same rule
        // `marker(in:prefix:)` already applies to a line with two `>` dates. `tasks` arrives
        // sorted, so "first" is a deterministic choice and not an accident of input order.
        var parents: [ProjectKey: TaskItem] = [:]
        var parentOrder: [ProjectKey] = []
        for task in tasks {
            guard let localID = task.localID else { continue }
            let key = ProjectKey(sourcePath: task.sourcePath, localID: localID)
            guard parents[key] == nil else { continue }
            parents[key] = task
            parentOrder.append(key)
        }

        var children: [ProjectKey: [TaskItem]] = [:]
        for task in tasks {
            guard let parentLocalID = task.parentLocalID else { continue }
            let key = ProjectKey(sourcePath: task.sourcePath, localID: parentLocalID)
            guard parents[key] != nil else { continue }
            children[key, default: []].append(task)
        }

        // A second walk of the same sorted list rather than an `else` in the one above: the
        // "is this a heading" question cannot be answered until every child has been bucketed,
        // and walking `tasks` again is what keeps "Senza" in the order the sort asked for.
        var ungrouped: [TaskItem] = []
        for task in tasks {
            if let parentLocalID = task.parentLocalID,
               parents[ProjectKey(sourcePath: task.sourcePath, localID: parentLocalID)] != nil {
                continue
            }
            if let localID = task.localID,
               children[ProjectKey(sourcePath: task.sourcePath, localID: localID)] != nil {
                continue
            }
            ungrouped.append(task)
        }

        var groups = parentOrder.compactMap { key -> TaskGroup? in
            guard let parent = parents[key], let kids = children[key] else { return nil }
            return TaskGroup(
                title: parent.text,
                tasks: kids,
                parent: parent,
                // The same count `IndexSnapshot.progress(ofProject:)` returns, over the
                // children this list actually holds: a view that filters its tasks reports
                // progress on what it is showing.
                progress: TaskProgress(
                    done: kids.filter { $0.state == .done }.count, total: kids.count
                )
            )
        }
        if !ungrouped.isEmpty {
            groups.append(TaskGroup(title: noneTitle, tasks: ungrouped))
        }
        return groups
    }

    private static func byNote(_ tasks: [TaskItem], priorityPaths: Set<String>) -> [TaskGroup] {
        let starred = Set(
            tasks.filter { priorityPaths.contains($0.sourcePath) }.map(noteTitle)
        )
        return grouped(tasks, by: noteTitle).stableByStarred(starred)
    }

    static func noteTitle(of task: TaskItem) -> String {
        NoteName.title(fromFileName: (task.sourcePath as NSString).lastPathComponent)
    }
}

private extension Array where Element == TaskGroup {
    /// Starred groups first, each half keeping the alphabetical order it arrived in.
    ///
    /// A partition rather than a comparator: `sorted(by:)` is not stable, and a predicate
    /// that answers `false` for two groups on the same side of the line lets it put them in
    /// any order it likes - which showed up as the note headings reshuffling on every redraw.
    func stableByStarred(_ starred: Set<String>) -> [TaskGroup] {
        filter { starred.contains($0.title) } + filter { !starred.contains($0.title) }
    }
}

// MARK: - Persistence

extension TaskListOptions {
    /// The whole set of views' options, as the one string `@AppStorage` keeps.
    ///
    /// One key holding a map rather than one key per view: `@AppStorage` takes a literal
    /// key, so a key per view would mean five properties in the view and a sixth the day a
    /// sixth view exists. Here rather than in the view because a round-trip that silently
    /// loses a setting is exactly what a test catches and a screenshot does not.
    ///
    /// **In `UserDefaults` and not under `.pergamenum/`**, on the reasoning ADR-0012 §D10
    /// applies to the open tabs: how a list is grouped on this Mac describes this window,
    /// not the vault, and a vault copied to another machine should not carry it.
    static func map(fromJSON json: String) -> [String: TaskListOptions] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: TaskListOptions].self, from: data)
        else { return [:] }
        return decoded
    }

    /// Empty on failure rather than a throw: the caller is a view writing a preference, and
    /// a grouping that could not be encoded is worth losing, not worth a crash.
    static func json(of map: [String: TaskListOptions]) -> String {
        guard let data = try? JSONEncoder().encode(map),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }
}
