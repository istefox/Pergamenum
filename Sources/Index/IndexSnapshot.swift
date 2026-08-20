import Foundation

/// The rebuildable index as a value: titles, links, backlinks and tags derived from
/// the files, with no framework underneath it.
///
/// Never the source of truth (SPEC §3, principle 3). Deleting it loses nothing,
/// because everything in it comes from a vault scan.
///
/// A value rather than an observable object, so a process without SwiftUI can hold
/// one: the CLI and the MCP server of ADR-0007 need every query below and none of the
/// observation. `VaultSession` owns the one the app reads, and observation reaches it
/// through the session, so the views and the connector get the same answers from the
/// same code.
struct IndexSnapshot: Sendable {
    private(set) var notes: [String: NoteRecord] = [:]
    /// Files that failed to read during the last scan, surfaced in the UI.
    private(set) var failures: [String] = []
    private(set) var lastScanDuration: Duration = .zero
    /// How many notes the last scan took from `.pergamenum/cache.db` rather than
    /// reading again (SPEC §12).
    private(set) var reusedFromCache = 0

    /// Lowercased title to the paths that carry it. A vault can legitimately hold two
    /// notes with the same title in different folders; a wikilink to that title is
    /// ambiguous and the UI has to say so rather than silently picking one.
    private var titleIndex: [String: [String]] = [:]
    /// Lowercased link target to the paths of the notes that link to it.
    private var backlinkIndex: [String: [String]] = [:]
    /// Lowercased target to the spelling it was first written with, so the unresolved
    /// links panel shows what the user typed rather than the lookup key.
    private var backlinkDisplayForm: [String: String] = [:]

    init() {}

    // MARK: Population

    mutating func replaceAll(with outcome: VaultScanner.Outcome, duration: Duration) {
        notes = Dictionary(uniqueKeysWithValues: outcome.records.map { ($0.relativePath, $0) })
        failures = outcome.failures.map { "\($0.path): \($0.reason)" }
        lastScanDuration = duration
        reusedFromCache = outcome.reusedFromCache
        rebuildDerivedIndexes()
    }

    /// Applies a single file's change. Passing nil removes the note, which is what a
    /// deletion or a move out of the vault looks like from the watcher.
    mutating func update(_ record: NoteRecord?, at relativePath: String) {
        if let record {
            notes[relativePath] = record
        } else {
            notes.removeValue(forKey: relativePath)
        }
        rebuildDerivedIndexes()
    }

    /// Rebuilds both derived maps from scratch.
    ///
    /// Incremental maintenance would need the note's *previous* link set to know what
    /// to unlink, and getting that wrong leaves phantom backlinks that nothing ever
    /// clears. At vault scale a full rebuild is cheap and cannot drift.
    private mutating func rebuildDerivedIndexes() {
        titleIndex.removeAll(keepingCapacity: true)
        backlinkIndex.removeAll(keepingCapacity: true)
        backlinkDisplayForm.removeAll(keepingCapacity: true)

        func addBacklink(to target: String, from path: String) {
            let key = target.lowercased()
            backlinkIndex[key, default: []].append(path)
            if backlinkDisplayForm[key] == nil { backlinkDisplayForm[key] = target }
        }

        for record in notes.values {
            titleIndex[record.title.lowercased(), default: []].append(record.relativePath)
            for target in record.linkTargets {
                addBacklink(to: target, from: record.relativePath)
            }
            // Structural links live in `related`, not in the body, and must appear in
            // the backlink panel too (W-03 distinguishes the two, the panel shows both).
            for related in record.frontmatter.related {
                for link in WikilinkParser.links(in: related) {
                    addBacklink(to: link.target, from: record.relativePath)
                }
            }
        }
        for key in titleIndex.keys { titleIndex[key]?.sort() }
        for key in backlinkIndex.keys { backlinkIndex[key] = Array(Set(backlinkIndex[key] ?? [])).sorted() }
    }

    // MARK: Queries

    var allNotes: [NoteRecord] {
        notes.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var count: Int { notes.count }

    func note(at relativePath: String) -> NoteRecord? { notes[relativePath] }

    /// Resolves a wikilink target to note paths. More than one result means the link
    /// is ambiguous; none means it is unresolved (W-07).
    func resolve(title: String) -> [String] {
        titleIndex[title.lowercased()] ?? []
    }

    func backlinks(toTitle title: String) -> [NoteRecord] {
        (backlinkIndex[title.lowercased()] ?? []).compactMap { notes[$0] }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Every link target that no note in the vault answers to, with the notes that
    /// point at it. Feeds the "Link non risolti" panel.
    func unresolvedLinks() -> [(target: String, sources: [NoteRecord])] {
        backlinkIndex.compactMap { key, sources in
            guard titleIndex[key] == nil else { return nil }
            let records = sources.compactMap { notes[$0] }
            return records.isEmpty ? nil : (backlinkDisplayForm[key] ?? key, records)
        }
        .sorted { $0.target.localizedStandardCompare($1.target) == .orderedAscending }
    }

    /// The notes in the link neighbourhood of a title, in **both** directions: the ones
    /// that link to it and the ones it links to (ADR-0012 D8, `linked:`).
    ///
    /// Both directions because the question `linked:` answers is "what is next to this
    /// note in the graph", and an edge is not directional to the person following it. The
    /// note itself is never in its own neighbourhood.
    func neighbourhood(ofTitle title: String) -> Set<String> {
        let own = Set(resolve(title: title))
        var paths = Set(backlinks(toTitle: title).map(\.relativePath))
        for path in own {
            guard let record = notes[path] else { continue }
            for target in record.linkTargets {
                paths.formUnion(resolve(title: target))
            }
            for related in record.frontmatter.related {
                for link in WikilinkParser.links(in: related) {
                    paths.formUnion(resolve(title: link.target))
                }
            }
        }
        return paths.subtracting(own)
    }

    /// Notes with no link in and no link out (ADR-0012 D8, `orphan:`).
    ///
    /// A note carrying a wikilink is not an orphan even when the target does not exist:
    /// it is a note that reaches out and misses, which is what `unresolvedLinks()` is
    /// for. Isolation is about having no edges at all.
    var orphans: Set<String> {
        var paths: Set<String> = []
        for record in notes.values {
            guard record.linkTargets.isEmpty,
                  backlinkIndex[record.title.lowercased()] == nil,
                  record.frontmatter.related.allSatisfy({ WikilinkParser.links(in: $0).isEmpty })
            else { continue }
            paths.insert(record.relativePath)
        }
        return paths
    }

    // MARK: Tasks

    /// Every task in the vault, in note order.
    var allTasks: [TaskItem] {
        notes.values
            .sorted { $0.relativePath < $1.relativePath }
            .flatMap(\.tasks)
    }

    /// Tasks whose text links to a title, for the "Task collegati" panel of a note or
    /// a canvas (SPEC §7.2). The link is an ordinary wikilink, so this is the reverse
    /// of the same relation the backlink panel shows.
    func tasks(linkingTo title: String) -> [TaskItem] {
        let needle = title.lowercased()
        return allTasks.filter { task in
            task.links.contains { $0.lowercased() == needle }
        }
    }

    /// The five views of SPEC §7.4.
    enum TaskView: String, CaseIterable, Identifiable, Sendable {
        case inbox, today, upcoming, byProject, all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inbox: "Inbox"
            case .today: "Oggi"
            case .upcoming: "Prossimi"
            case .byProject: "Per progetto"
            case .all: "Tutti"
            }
        }
    }

    /// Tasks for one view on a given day.
    ///
    /// `today` includes overdue tasks, because a task that slipped is exactly what the
    /// day view has to surface; SPEC §7.3 rules out moving it silently.
    /// `includingCompleted` widens every view to the tasks already done, which is what
    /// the "mostra completati" filter turns on: what got finished today is part of the
    /// day, and a list that hides it reads as a day where nothing happened.
    func tasks(
        for view: TaskView, on day: CalendarDate, includingCompleted: Bool = false
    ) -> [TaskItem] {
        let open = includingCompleted ? allTasks : allTasks.filter(\.state.isOpen)
        switch view {
        case .inbox:
            return open.filter { $0.scheduled == nil && $0.due == nil && $0.project == nil }
        case .today:
            return open.filter {
                $0.isScheduled(on: day) || $0.isOverdue(on: day) || $0.completed == day
            }
        case .upcoming:
            return open
                .filter { task in
                    guard let scheduled = task.scheduled else { return false }
                    return scheduled > day && daysBetween(day, scheduled) <= 7
                }
                .sorted { ($0.scheduled ?? day) < ($1.scheduled ?? day) }
        case .byProject:
            return open.filter { $0.project != nil }
        case .all:
            return open
        }
    }

    /// Open tasks carrying a `!` date on or after a day, soonest first.
    ///
    /// The day view's bell shows these: a deadline is the one date that matters before
    /// it arrives, and until now the only way to see the next one was to page the
    /// calendar until it turned up.
    func dueTasks(from day: CalendarDate, within days: Int = 30) -> [TaskItem] {
        allTasks
            .filter(\.state.isOpen)
            .filter { task in
                guard let due = task.due else { return false }
                return due >= day && daysBetween(day, due) <= days
            }
            .sorted { lhs, rhs in
                let left = (lhs.due ?? day, lhs.dueTime?.minutes ?? -1)
                let right = (rhs.due ?? day, rhs.dueTime?.minutes ?? -1)
                return left.0 == right.0 ? left.1 < right.1 : left.0 < right.0
            }
    }

    /// Every day an open task is due on, for the marks on the month grid.
    var dueDays: Set<CalendarDate> {
        Set(allTasks.filter(\.state.isOpen).compactMap(\.due))
    }

    /// Open task counts per view, for the sidebar badges.
    func taskCounts(on day: CalendarDate) -> [TaskView: Int] {
        Dictionary(uniqueKeysWithValues: TaskView.allCases.map { ($0, tasks(for: $0, on: day).count) })
    }

    /// Whole days from one date to another, both at midnight.
    private func daysBetween(_ from: CalendarDate, _ to: CalendarDate) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let start = DateComponents(calendar: calendar, year: from.year, month: from.month, day: from.day).date
        let end = DateComponents(calendar: calendar, year: to.year, month: to.month, day: to.day).date
        guard let start, let end else { return .max }
        return calendar.dateComponents([.day], from: start, to: end).day ?? .max
    }

    // MARK: Tags and fuzzy search

    /// Tag usage counts, for autocomplete to offer values already in the vault first
    /// (SPEC §4.4, open families).
    func tagUsage() -> [(tag: Tag, count: Int)] {
        var counts: [Tag: Int] = [:]
        for record in notes.values {
            for tag in record.frontmatter.tags { counts[tag, default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
    }

    /// The notes carrying **every** one of these tags, title-sorted (ADR-0012, slice 3).
    ///
    /// Here rather than in the tag browser, which is where it was first written: a filter over
    /// the index belongs beside the index, and a view is not a place a test can reach. An empty
    /// set answers nothing at all rather than everything - the browser with no tag chosen is
    /// asking a question, not selecting the vault.
    func notes(carryingAll tags: Set<Tag>) -> [NoteRecord] {
        guard !tags.isEmpty else { return [] }
        return notes.values
            .filter { tags.isSubset(of: Set($0.frontmatter.tags)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Titles matching a fuzzy query, best first, for the quick switcher.
    func search(_ query: String, limit: Int = 20) -> [NoteRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(allNotes.prefix(limit)) }

        return notes.values
            .compactMap { record -> (NoteRecord, Int)? in
                // Aliases (F-07) serve search but never the link target, so they are
                // searched here and ignored by `resolve(title:)`.
                let candidates = [record.title] + record.frontmatter.aliases
                let best = candidates.compactMap { FuzzyMatch.score(query: trimmed, candidate: $0) }.max()
                return best.map { (record, $0) }
            }
            .sorted { $0.1 == $1.1 ? $0.0.title.count < $1.0.title.count : $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
