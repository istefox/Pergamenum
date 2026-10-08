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
    /// Tasks from every scanned `.canvas` board's own To Do card(s), keyed by the board's
    /// relative path (PG-074, plan Section 4). A sibling of `notes`, never merged into it -
    /// `allTasks` is where the two collections meet.
    private(set) var boardTasks: [String: BoardTaskRecord] = [:]
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

    /// Moves once per `replaceAll` and once per `update`, the only two ways the index changes
    /// (ADR-0072 §D1). A UI refresh signal, never an ordering clock (§D3); views read it through
    /// `VaultController.indexGeneration`, which keeps it monotonic across vaults (§D2).
    private(set) var generation = 0

    init() {}

    // MARK: Population

    mutating func replaceAll(with outcome: VaultScanner.Outcome, duration: Duration) {
        notes = Dictionary(uniqueKeysWithValues: outcome.records.map { ($0.relativePath, $0) })
        boardTasks = Dictionary(uniqueKeysWithValues: outcome.boardTaskRecords.map { ($0.relativePath, $0) })
        failures = outcome.failures.map { "\($0.path): \($0.reason)" }
        lastScanDuration = duration
        reusedFromCache = outcome.reusedFromCache
        rebuildDerivedIndexes()
        rebuildTaskList()
        generation += 1
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
        rebuildTaskList()
        generation += 1
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

    /// The link targets of one note that name no note, in `linkTargets` order (ADR-0084 §D2):
    /// the inspector's list, through the derivation the query field and `VaultAPI.links` share.
    func unresolvedTargets(of path: String) -> [String] {
        UnresolvedTargets.of(notes[path]?.linkTargets ?? [], resolving: resolve(title:))
    }

    func backlinks(toTitle title: String) -> [NoteRecord] {
        (backlinkIndex[title.lowercased()] ?? []).compactMap { notes[$0] }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Every link target that no note in the vault answers to, with the notes that
    /// point at it. Feeds the "Link non risolti" panel.
    ///
    /// `limit` keeps the first entries of the same sort, and only those get their source list
    /// built (ADR-0072 §D4): every caller takes the one path, so a limited answer is the prefix
    /// of the full one by construction, ties included.
    func unresolvedLinks(limit: Int? = nil) -> [(target: String, sources: [NoteRecord])] {
        let members = backlinkIndex.compactMap { key, sources -> (target: String, key: String)? in
            guard titleIndex[key] == nil, sources.contains(where: { notes[$0] != nil }) else { return nil }
            return (backlinkDisplayForm[key] ?? key, key)
        }
        .sorted { $0.target.localizedStandardCompare($1.target) == .orderedAscending }
        let kept = limit.map { members.prefix($0) } ?? members[...]
        return kept.map { member in
            (member.target, (backlinkIndex[member.key] ?? []).compactMap { notes[$0] })
        }
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

    /// Every task in the vault, note-sourced and board-sourced alike, in path order. The
    /// single aggregation point every task query below reads - a board contributes here and
    /// nowhere else, so every one of them inherits board tasks for free.
    ///
    /// Stored, rebuilt by both mutating doors and never lazily (ADR-0072 §D6): every reader
    /// used to sort every note and flat-map every task on each read.
    private(set) var allTasks: [TaskItem] = []

    private mutating func rebuildTaskList() {
        let noteTasks = notes.values
            .sorted { $0.relativePath < $1.relativePath }
            .flatMap(\.tasks)
        let boardTaskItems = boardTasks.values
            .sorted { $0.relativePath < $1.relativePath }
            .flatMap(\.tasks)
        allTasks = noteTasks + boardTaskItems
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

    /// Tasks assigned to a Workspace via `^[[<canvas>.canvas]]` (ADR-0021 D1, D5), for
    /// the board's "Task assegnati" section. Matches the file name case-insensitively,
    /// mirroring `tasks(linkingTo:)` above. Independent of `tasks(linkingTo:)`: a plain
    /// `[[X.canvas]]` wikilink with no caret is a mention, not an assignment, and does
    /// not appear here (R-04).
    ///
    func tasks(assignedToWorkspace canvasFileName: String) -> [TaskItem] {
        allTasks.filter { WorkspaceBoardResolver.matches(canvasFileName, workspacePath: $0.workspacePath) }
    }

    /// The same-source children of a task (the note or board the parent lives on),
    /// bucketed on its `^id` (ADR-0021 D2, D5). A `^parent(N)` in a different file whose
    /// own `^id(N)` matches is **not** a child: ids are file-local, and the join is
    /// `sourcePath`-scoped. A board parent reads its board's tasks (PG-260), every card of
    /// that board alike - the same scoping `TaskArrangement`'s «Progetti» grouping applies.
    func subtasks(of task: TaskItem) -> [TaskItem] {
        guard let id = task.localID else { return [] }
        let siblings = notes[task.sourcePath]?.tasks ?? boardTasks[task.sourcePath]?.tasks ?? []
        return siblings.filter { $0.parentLocalID == id }
    }

    /// How many of a project's sub-tasks are done (ADR-0021 D5). `nil` for a task with
    /// no sub-tasks. Computed on read from what is already in the snapshot; nothing
    /// here reaches a file.
    func progress(ofProject task: TaskItem) -> TaskProgress? {
        let children = subtasks(of: task)
        guard !children.isEmpty else { return nil }
        return TaskProgress(
            done: children.filter { $0.state == .done }.count,
            total: children.count
        )
    }
}
