# ADR-0021: A task carries its Workspace and its place in a project as caret markers in its own line, and nothing new is stored anywhere else

- Status: accepted
- Date: 2026-08-24. Written from a reading of the code at `c5cde2a`, not from the SPEC alone.
  Three claims the SPEC makes about this repository turned out to be false when read at the
  line, and each one is corrected below with the file and line number that disproves it. Where
  the SPEC and the code disagree, the code is the fact and the SPEC's *intent* is what this ADR
  preserves.
- Supersedes: nothing.
- Depends on: **SPEC §7.1** (the task line grammar), **§7.2** (a wikilink is the only link
  between a task and a note or a board), **§7.4** (the five task views are a closed list),
  **§4.3/§4.4** (the frontmatter and tag schemas are closed and must not be extended),
  **§4.7** (the linter reports and never corrects), **§6.1** (a board is the spatial view of a
  real folder), and principles **1** (file over app) and **3** (rebuildable index) of
  `CLAUDE.md`. It leans on **ADR-0013 §D6** for the view/grouping distinction and on
  **ADR-0007 §D2** for what a connector may and may not see.

## Context

Pergamenum already holds all three halves of what this feature asks for, and holds them apart.

A task is a markdown line and nothing else (`Sources/Core/Tasks/TaskParser.swift`). It carries
`>YYYY-MM-DD`, `!YYYY-MM-DD`, `@done(…)`, `@remind(…)`, `@repeat(n/N)`, flat namespaced tags and
any number of wikilinks. `TaskItem.links` is documented as *"SPEC §7.2 makes these the link
between a task and a note or a canvas - there is no separate syntax"*, and `Tests/TaskTests.swift`
already asserts that `- [ ] Task con canvas collegato, vedi [[Progetto X.canvas]]` parses to
`links == ["Progetto X.canvas"]`. So a task can already mention a board. What it cannot do is
say *which* board it belongs to: a list of links has no distinguished member, and a second link
to a second board is as valid as the first.

A board is `CanvasStore`'s view of one folder: the board for `01 Progetti/vibrofer-emea` is
`01 Progetti/vibrofer-emea/vibrofer-emea.canvas`, and `boardPath(forFolder:)` is the whole of
that mapping (`Sources/Vault/CanvasStore.swift:21-28`). The board's right-hand column,
`BoardTray` (`Sources/Features/Workspace/BoardChrome.swift:177-207`), already shows the folder's
unplaced files and, beneath them, a `LinkedTasksPanel` keyed on the board's own file name — the
same view the note editor's inspector uses, *"because §7.2 asks for the same panel in both and
two implementations would drift"*. So the board can already ask "who links here". What it cannot
do is ask "who is assigned here", because assignment does not exist, and it cannot say which
notes it carries, because nothing enumerates its own cards for the reader.

A project is a `#project-*` tag today: `TaskItem.project` is *"at most one is meaningful"* and
`TaskGrouping.project` buckets a list by it. A tag is a flat label. It cannot express that
task B is part of task A, and it cannot be made to without extending the closed tag schema of
SPEC §4.4 — which `CLAUDE.md` forbids outright, because `harness-system` owns that vocabulary
and the app is downstream of it.

So three additions are needed, and the whole question is where they are allowed to live.

**Three facts about this repository decide most of what follows, and the SPEC gets all three
wrong.** They were read at the line rather than assumed, and each one made the design smaller
rather than larger.

**Fact 1 — there is no GRDB in this project.** `Tuist/Package.swift` declares exactly one
third-party dependency, the MCP SDK, and calls it *"the only third-party dependency in the
project (ADR-0007 §D2)"*. `grep -rn GRDB Sources/ Project.swift` returns nothing. `IndexCache`
is `import SQLite3` against the system library, and its own header says why: *"SQLite through
the system library rather than a package: it is already on every Mac, the schema is four
columns, and a dependency added for that would have to be carried for the life of the app."*
The SPEC's *"Index (`.pergamenum/cache.db` via GRDB)"* describes a project that does not exist.
`CLAUDE.md`'s own stack list still says *"GRDB (SQLite cache only)"* and `Tuist/Package.swift`
still says *"GRDB to be added at indexing milestone"* — the milestone came and the dependency
was declined.

**Fact 2 — there is no task table to extend.** `IndexCache` has one table, `notes(path TEXT
PRIMARY KEY, payload BLOB)`. A task is not a row; it is an element of `StoredTask` inside the
JSON blob of its note, and `StoredTask` stores three things — `rawLine`, `sourcePath`,
`lineIndex` — and reconstructs the task by **re-parsing the line**:

```swift
/// Re-parsed from the line rather than stored field by field, so a cached task can
/// never disagree with what the parser would say about the same line today.
var task: TaskItem? {
    TaskParser.parse(line: rawLine, sourcePath: sourcePath, lineIndex: lineIndex)
}
```
`Sources/Index/IndexCache.swift:266-269`.

That comment is the single most useful sentence in this repository for this feature. A field
added to `TaskItem` and read by `TaskParser.parse` appears in every cached task the moment the
new binary loads an old cache, with no schema change, no version bump and no migration. The
SPEC asks for three new columns; the code makes three new columns unnecessary.

**Fact 3 — the cache is not in `.pergamenum/`.** ADR-0017 (`PG-004`) moved every derived store
to `~/Library/Application Support/it.stefer.pergamenum/vaults/<id>/`, and `CLAUDE.md` records
that *"delete `.pergamenum/` to reset the app" is no longer true*. The SPEC's path is stale by
one ADR. Nothing in this feature depends on the path, but a plan that told a coder to look in
`.pergamenum/` would send them to an empty directory.

Two further facts, less load-bearing but decisive for two of the sixteen requirements:

**`.canvas` files are not in the index at all.** `VaultScanner.scan()` drops every file whose
extension is not `md` (`Sources/Vault/VaultScanner.swift:66`). `IndexSnapshot.notes` therefore
contains no boards, `NoteTree.build(from:)` takes `[NoteRecord]`, and a folder tree of `.canvas`
files cannot be built from the index without putting boards into it.

**Nothing in the app renames a `.canvas` file.** `renameNote` validates its new title through
`NoteName.validate` and is reached from exactly one place, the note tree's rename sheet
(`Sources/Features/Editor/NoteListPane.swift:52`). A board is named after its folder by
`boardPath(forFolder:)` and has no rename path of its own. R-13 therefore cannot be satisfied
by exercising a UI that does not exist; it can only be satisfied at the level of the mechanism,
which is stated plainly in D3 rather than dressed up.

## Decision

**D1. The three new relations are caret markers in the task line, read by `TaskParser` and by
nothing else.**

The grammar addition, in full:

| Marker | Cardinality | Meaning | Field on `TaskItem` |
|---|---|---|---|
| `^[[<name>.canvas]]` | 0 or 1 | the one Workspace this task is assigned to | `workspacePath: String?` |
| `^id(<N>)` | 0 or 1 | this task's identifier **within its own note** | `localID: Int?` |
| `^parent(<N>)` | 0 or 1 | the `^id` of this task's parent, in the same note | `parentLocalID: Int?` |

Order-independent relative to each other and to `>`/`!`/`@`, matching the tolerance the existing
grammar already has. A second occurrence of any of the three is ignored and the first wins, which
is the same rule `marker(in:prefix:)` already applies to a line carrying two `>` dates.

Three properties of the recognition rule, each chosen to make the change unable to regress an
existing vault:

- **`^[[…]]` is a Workspace marker only when the target ends in `.canvas`** (case-insensitively).
  Anything else — `^[[Nota]]`, a caret that happens to precede a link in prose — keeps today's
  behaviour exactly: an ordinary wikilink with a literal caret in front of it. This is the whole
  of the backward-compatibility argument, and it costs one `hasSuffix`. A malformed caret-link is
  deliberately **not** a new linter rule: SPEC declares two new advisory rules and adding a third
  would be scope nobody asked for.
- **The Workspace marker is removed from `TaskItem.links`.** The plain-wikilink mechanism of
  §7.2 keeps meaning "notes referenced by this task" (R-04), and the assignment is a different
  fact with a different field. A consequence worth naming: `BoardTray`'s existing "TASK
  COLLEGATI" section, which is keyed on `IndexSnapshot.tasks(linkingTo:)`, will **not** list a
  task assigned with `^[[…]]`. That is correct — the new "Task assegnati" section lists those —
  and it is invisible in practice because the syntax is new and no vault contains it.
- **All three markers are stripped from `TaskItem.text`.** `displayText(from:)` already removes
  every wikilink by `link.rendered`, which for `^[[X.canvas]]` would remove `[[X.canvas]]` and
  strand the caret mid-sentence. The caret goes with it, and `^id(N)`/`^parent(N)` are removed
  by the same mechanism `@done`/`@remind`/`@repeat` already use.

`TaskParser` lives in `Sources/Core/Tasks/` and stays free of SwiftUI and AppKit, which is
ADR-0001 §D1 enforcing itself through the two connector builds. This is not a preference: a
`import SwiftUI` added there breaks `perg` and `pergamenum-mcp` loudly, and it should.

**D2. `^id` is note-local, allocated by scanning the note, and there is no registry.**

`^id(3)` in `Vibrofer.md` and `^id(3)` in `Cliente B.md` are two different tasks and neither
knows about the other. Every join is therefore `sourcePath`-scoped, and that scoping is
load-bearing rather than defensive: without it, the "Progetti" grouping would silently merge two
unrelated projects the first time two notes both reached three sub-tasks.

Allocation is a scan of the note's own text: `TaskParser.nextLocalID(in: String) -> Int` returns
one past the highest `^id` present, or 1 for a note with none. No counter is persisted anywhere,
which is principle 3 applied to identity — an id is read out of the file, so deleting every
derived store loses nothing, and a note edited in Obsidian or by hand keeps working.

Ids are never rewritten on a move or a rename, because they name nothing outside their own file.
That is the entire reason to prefer note-local ids over vault-wide ones, and it is what makes the
"task copied to another note" edge case a non-event: the copy's `^parent` finds no `^id` in its
new home, the linter says so (R-12), and the task still appears, ungrouped, in every flat view.

**D3. The Workspace marker stays a wikilink at note level, and that is what makes the rename
requirement free.**

`NoteStore.linkTargets(in:)` reads the whole note body and will keep counting `X.canvas` among
the note's link targets, exactly as it does for a plain `[[X.canvas]]` today. Not changed, and
two things follow:

- the board keeps getting a backlink from a note whose task is assigned to it, which is the
  behaviour anyone would expect and which nobody has to build;
- `NoteRename.rewritingLinks` replaces `link.range`, and for a non-embed link that range starts
  at `[[`. **The caret sits outside the replaced range and survives untouched.** A rename of
  `Vecchio.canvas` to `Nuovo.canvas` rewrites `^[[Vecchio.canvas]]` into `^[[Nuovo.canvas]]`
  with no new code at all.

R-13 asks for exactly that, and this ADR grants it at the level of the mechanism while stating
the caveat rather than hiding it: **the app has no path that renames a `.canvas` file today.**
`renameNote` is note-only and boards are named after their folders. So R-13 is verified by a unit
test on the pure function, proving caret-safety, and a canvas-rename UI is named here as a
follow-up somebody may or may not want. Claiming R-13 was exercised end to end would be a claim
about a screen that does not exist.

**D4. There is no schema change, no version bump, and R-14 is true by construction.**

Because `StoredTask` re-parses `rawLine` (Fact 2), the three new fields require nothing of
`IndexCache`. `IndexCache.schemaVersion` stays **3**. That constant's own comment says it is
bumped when `StoredRecord` changes *shape* **or its meaning**, and neither changes here: the same
bytes are written, and the same bytes now decode to a task that also knows its Workspace and its
parent, because the parser that reads them got better.

This is the strongest form R-14 can take. "Delete `cache.db`, rescan, get identical relationships"
is not a property to be tested into existence; it is the only possible outcome when the cache
stores the line and the line is the truth. The test still gets written — round-trip through a
real `IndexCache` in a temporary directory, the way `Tests/IndexCacheTests.swift` already does —
but it confirms an argument rather than propping one up.

The corollary is a rule for the coder: **do not add the three fields to `StoredTask`.** Doing so
would create exactly the disagreement between cache and file that the existing comment was
written to prevent, and it would then require the version bump that this decision avoids.

**D5. The relations are three queries on `IndexSnapshot`, and none of them is a new store.**

```
func tasks(assignedToWorkspace canvasFileName: String) -> [TaskItem]
func subtasks(of task: TaskItem) -> [TaskItem]
func progress(ofProject task: TaskItem) -> TaskProgress?
```

`IndexSnapshot` is a value with no framework under it — *"a process without SwiftUI can hold
one: the CLI and the MCP server of ADR-0007 need every query below and none of the observation"*
— so putting these here rather than in a view is what makes them reachable from `perg`, testable
without a vault, and impossible to duplicate. `tasks(assignedToWorkspace:)` matches
case-insensitively on the file name, mirroring `tasks(linkingTo:)` beside it.

`TaskProgress` is a small `Equatable, Sendable` struct with `done` and `total`, not a tuple: it is
carried on `TaskGroup`, which is `Equatable`, and a tuple would break the synthesis.

**Nothing here writes.** The progress indicator is computed on read and never reaches a file:
R-09 is not a behaviour that has to be suppressed, it is a behaviour that is never written in the
first place. There is no code path from "every sub-task is done" to `@done` on the parent, and
this decision is why.

**D6. "Progetti" is a sixth `TaskGrouping`, never a sixth `TaskView`.**

ADR-0013 §D6 closed the five views on purpose and said what the escape hatch is: *"a sixth view
would be a new place in the app, a new grouping is a menu item."* `IndexSnapshot.TaskView` is
therefore untouched, and `TaskGrouping` gains `.subtasks`, titled **"Progetti"**, symbol
`list.bullet.indent`.

`TaskGroup` gains two properties, both defaulted:

```swift
var parent: TaskItem? = nil
var progress: TaskProgress? = nil
var id: String { parent?.id ?? title }
```

Defaulted because the memberwise initialiser is called with `(title:tasks:)` in
`TaskArrangement` and in `TasksView.rolledOverGroup`, and a defaulted trailing property keeps
every one of those compiling untouched. `id` falls back to `title` so nothing that groups by
project or by day changes, and rises to the parent's id when there is one, so two projects whose
parent tasks read the same in two different notes are two rows rather than one.

`TaskArrangement.groups` handles `.subtasks` by bucketing on `(sourcePath, parentLocalID)`,
emitting one group per parent task and one trailing "Senza" group for everything with neither an
`^id` nor a `^parent`. Being in `TaskArrangement` rather than in the view is the existing rule of
that file — *"a sort that is not stable and a group that swallows the tasks with nothing to group
by are defects a test can hold and a screenshot cannot"* — and it is what lets R-08 and R-10 be
asserted without a window.

R-10 needs no work: `.none`, `.note`, `.project`, `.schedule` and `.deadline` are not read by the
new branch and the five views are not touched. It is verified, not implemented.

**D7. The Workspace dashboard goes into the tray the board already has, and does not become a
second trailing column.**

The UX blueprint asks for a *"trailing inspector column ... the same structural slot the existing
Backlink / Task collegati panels already occupy"*, and says the architect should *"reuse whatever
view/container abstraction already backs [them], rather than introducing a second inspector
mechanism for the canvas"*. Read against the code, those two sentences point at the same thing:
the board's trailing column already exists, it is `BoardTray`, it is 200 points wide, and it
already hosts `LinkedTasksPanel` for precisely the §7.2 reason. Building a second trailing column
beside it would give one board two inspectors and would be the second mechanism the blueprint
asks us not to introduce.

So `BoardTray` gains two sections beneath the ones it has:

- **TASK ASSEGNATI** — `index.tasks(assignedToWorkspace: boardFileName)`, drawn with the same row
  `LinkedTasksPanel` uses (checkbox that calls `vault.toggle`, source-note button, `!`/`>` chip)
  and therefore completable in place, writing to the task's own note. The row is factored out of
  `LinkedTasksPanel` into a shared `TaskPanelRow` so there is one row and not two that drift —
  the same argument that file's own header already makes about itself.
- **NOTE REFERENZIATE** — the notes this board carries.

The tray's visibility moves from `@State private var isShowingTray` in `WorkspaceView` onto
`Navigation`, beside `isShowingInspector`, because a menu item cannot reach a view's `@State`.
The Vista menu gains **"Pannello Workspace"** as a `Toggle`, with no shortcut — the blueprint asks
for none, and "Dividi l'editor" is the precedent for a Vista entry that carries no key and no row
in the remappable catalogue. The existing toolbar toggle keeps working and drives the same state.

**D8. "Note referenziate" is read from the open board document, never from the index.**

`WorkspaceReferences.notes(in: CanvasDocument) -> [String]`, a pure function in
`Sources/Core/Canvas/`:

- every `.file(path:_)` node whose path ends in `.md` — the Document cards;
- every wikilink found by `WikilinkParser.links` inside a `.text(String)` node, resolved through
  the index for display and left as written when it resolves to nothing.

The board is already loaded and already in memory; asking the index would answer a different
question ("which notes mention this board") and would be wrong on a board whose cards were placed
and never linked. Pure and in `Core` so it is tested against a `CanvasDocument` built in memory,
with no window, no vault and no SwiftUI — the same reason `TaskArrangement` is where it is.

**D9. Assigning a Workspace replaces, and it is a `TaskChange` like every other write.**

`VaultSession.TaskChange` gains `.workspace(String?)`, and `TaskParser` gains
`line(for:assigningWorkspace:)`, which removes any existing `^[[….canvas]]` marker together with
its preceding space — through the same `withPrecedingSpace` helper the `>`/`!` removals already
use — and then appends the new one, or nothing when passed nil.

Replace rather than append, and that is R-03's *"exactly one"* made structural: a user who
assigns a board twice gets one marker, so the duplicate the linter watches for (R-11) can only
ever arrive by hand or by paste. Every guarantee the existing write path gives comes along
unchanged, because it is the same path: the `expecting: task.rawLine` staleness guard in
`TaskParser.rewrite`, the atomic `NoteStore.write`, and `WriteJournal` on the connector side.

The picker is a new small sheet listing the vault's boards, reached from the two places the note
picker is already reached from — the Attività toolbar's "Collega nota o board" group and the task
row's context menu. SPEC §UI-flow-2 calls this a "Task detail panel"; there is no such panel in
this app, and inventing one to satisfy the wording would be a larger change than the feature.

**D10. `.canvas` files get their own enumeration, and the index stays a note index.**

Two ways to build a folder tree of boards:

Put `.canvas` files into `IndexSnapshot`. Rejected. It changes what `StoredRecord` means (a
version bump to 4, and the whole of D4 with it), and it changes `allNotes`, `resolve(title:)`,
`orphans`, `search`, the quick switcher and the `ViewCorpus` conformance the saved-view engine
of ADR-0009 is built on — every one of which would have to learn that some of its "notes" are not
notes. A board is a spatial view of a folder, not a document; the index is right to exclude it.

Enumerate on demand. Chosen. `CanvasStore.allBoards() -> [String]` walks the vault for
`*.canvas`, skipping the same excluded directories `VaultScanner` skips through
`VaultLayout.isExcludedDirectory`, and returns vault-relative paths sorted. It is called when the
Workspace browser appears and on `scanGeneration`, which is when the note tree rebuilds itself
today; a board list is tens of entries and this is cheaper than the rebuild beside it.

The tree itself is the existing one. `NoteTree` gains a second entry point,
`build(fromPaths:)`, over the same private `Builder`, so there is one tree implementation and the
blueprint's *"not a parallel tree implementation"* is true at the level of the code rather than at
the level of the intention. `NoteTree.Node.Kind` is **not** extended: a board row is a `.note`
leaf, and the Workspace browser — whose leaves are all boards — draws its own icon. Extending the
enum would force every `switch` over `Kind` in `NoteListPane` to grow a case for something that
can never appear there.

**D11. Two advisory linter rules, added without breaking the six places `NoteViolations` is
built.**

`NoteViolations` gains one property:

```swift
var taskMarkers: [TaskMarkerViolation] = []

enum TaskMarkerViolation: Equatable, Sendable {
    case duplicateWorkspace(line: Int, kept: String, ignored: String)
    case orphanedParent(line: Int, parent: Int)
}
```

Defaulted, and that default is the whole compatibility story: all six construction sites pass the
same five labelled arguments (`VaultSession+Search.swift:124`,
`VaultController+Conformance.swift:17`, `DayController+TaskDrop.swift:32`,
`ViewBoardRenderer.swift:131`, `NoteRowMenu.swift:74`, `VaultBrowser.swift:320`) and every one of
them keeps compiling untouched.

The findings are produced inside `VaultSession.violations(path:title:text:)`, from
`TaskParser.tasks(in: text, sourcePath: path)` — the note's own text, no index, no vault, so the
rule is a pure function of a string and testable as one.

Both count towards `isEmpty` and `count`, which is what "the linter flags it" means and what puts
the note in the Conformità list. **Nothing blocks.** SPEC §4.7 already says the linter reports and
does not correct, `ConformanceView`'s own subtitle on screen says *"Il linter segnala, non
corregge"*, and no write path consults `violations` before writing. Advisory here means the same
thing it already means everywhere else in this app, which is why it needs no new machinery.

The connector surface changes with it: `VaultAPI.LintFinding` gains a `taskMarkers` array and
`count` grows. That is an observable contract for anything reading `perg lint --json` or the MCP
`lint` tool, and it is called out here so the plan can carry it as a task rather than let it
surface as a broken assertion.

**D12. What this feature deliberately does not do.**

- **The editor does not draw the new markers as anything.** A task line in the TextKit 2 editor
  shows `^id(3)` and `^parent(1)` literally, and `^[[X.canvas]]` as a styled wikilink with a bare
  caret in front of it. Hiding or decorating them is ADR-0018's territory and a separate decision;
  SPEC requires parsing, not styling. Named as a known consequence so nobody files it as a defect.
- **Obsidian shows the markers as literal text.** Accepted in the SPEC on 2026-08-24, consistent
  with ADR-0020's same-day deprioritisation of round-trip fidelity. The file stays valid Markdown
  and nothing else about the note breaks.
- **No completion cascade, in either direction** (R-09), and no cross-file cascade on deletion.
- **No cross-note hierarchy.** A `^parent` never reaches outside its own note. D2 is why.
- **No `#task-NNN` tag.** Rejected in the SPEC and again here: `task` is not one of the eight
  closed prefixes of §4.4, and `CLAUDE.md` makes `harness-system` the source of truth for that
  vocabulary. R-15 is satisfied by never touching either closed schema, which is a property of the
  design and not a test that has to pass.

## Alternatives considered

**A1. Store the Workspace assignment in the note's frontmatter.** Rejected outright. SPEC §4.3
closes the frontmatter to exactly `date`, `tags`, `related`, `aliases`, and `CLAUDE.md` repeats
that `title`, `status`, `type`, `draft`, `version` and `author` are forbidden. Beyond the rule,
frontmatter is a fact about the *note* and this is a fact about one *line* in it: a note holding
nine tasks assigned to four boards has nowhere to put four values in one header.

**A2. Use the `#project-*` tag for the hierarchy, or add a `#task-NNN` tag.** Rejected. A flat
tag has no parent, so `#project-x` can group tasks but cannot say that one of them contains the
others. `#task-NNN` would express it, at the price of inventing a ninth prefix in a schema whose
owner is another repository — the exact change `CLAUDE.md` principle 5 forbids doing locally.

**A3. Store the relations in the index only, as three real columns on a task table.** This is
what the SPEC literally asks for, and it is rejected on two grounds. It violates principle 1: the
index is explicitly never the source of truth, and a relation that existed only in `cache.db`
would vanish when the cache is cleared from Impostazioni — which is a supported action with a
button. And it cannot be built as described: there is no task table and no GRDB (Facts 1 and 2).
The SPEC's *intent* — that the relations are queryable and rebuildable — is fully honoured by D4,
which achieves it with no schema at all.

**A4. Express the hierarchy with GFM indentation, the way Obsidian Tasks and Things do.**
Genuinely attractive: it is what a markdown reader already understands, it needs no new syntax,
and Obsidian would render it correctly. Rejected for two reasons. `TaskParser` deliberately
preserves indentation and refuses to interpret it — *"Deliberately not a blanket collapse of
double spaces: that also ate the leading indentation of a nested task, silently reformatting the
user's note"* — so indentation is currently the user's, not the app's, and claiming it would be a
breaking reinterpretation of every existing indented task in the Labs vault. And it is fragile
under exactly the operation this feature invites: moving a sub-task to a different day in the
Attività list would have to move a *line* to keep its meaning, whereas `^parent(N)` survives the
line being anywhere in the note.

**A5. Vault-wide unique ids (a UUID, or a monotonic counter in a registry file).** Rejected. A
registry is a second source of truth that has to be kept in step with the notes, which is the
thing principle 3 exists to prevent; and a UUID in a task line is nine characters of signal
wrapped in twenty-seven of noise in a file a human reads. Note-local ids are readable, allocatable
by a scan, and need no rewriting on rename or move (D2) — the cost is that a task copied between
notes loses its meaning, which the SPEC already accepts as linter territory.

**A6. A new trailing inspector column on the canvas, separate from `BoardTray`.** Rejected in
D7: the board already has a trailing column doing this job, and two would be the second inspector
mechanism the UX blueprint explicitly asks not to introduce. Considered seriously, because the
blueprint's wording ("gains a trailing inspector column") reads as if there were none.

**A7. Put `.canvas` files into `IndexSnapshot` so the browser, the picker and the assignment all
resolve through one lookup.** Rejected in D10, and it was the closest call in this ADR — it would
have made board name resolution behave exactly like note title resolution, ambiguity reporting
included. The cost is a cache meaning-change (version 3 → 4), and a new obligation on every
existing consumer of `allNotes`, `orphans`, `search` and the ADR-0009 `ViewCorpus` to distinguish
a document from a spatial view. Too much blast radius for a folder tree.

**A8. A sixth `TaskView` ("Progetti") in the Attività sidebar rather than a sixth grouping.**
Rejected by ADR-0013 §D6, which closed that list and named the alternative in the same sentence.
Worth recording because both the SPEC and the UX blueprint call the new thing a "grouping" while
listing it beside Inbox/Oggi/Progetto/Tutti, which are views — the ambiguity is in the source
documents, and D6 resolves it towards the grouping, which is the axis the codebase left open.

**A9. Write the sub-task line directly on `Cmd+Shift+Return`, with placeholder text, and let the
user rename it in place.** Rejected: the Attività list has no inline text editing for a task, so
the placeholder would have to be edited in the note, which defeats the command. Reusing the
existing capture composer (D9's sibling decision, plan Task 3) gives the user somewhere to type
and gives the sub-task its own `>`/`!`/`@remind`/`@repeat` for free, which is half of R-07.

## Consequences

**Positive.**

- The whole feature is additive to one function. `TaskParser.parse` learns three markers and
  everything downstream — the index, the cache, the CLI, the MCP server, the day view, the
  timeline — inherits them without being touched. `EventKit` needs no special case because a
  sub-task with its own `>` date is a task with a `>` date (SPEC's own decision, and it is free
  here rather than implemented).
- **No dependency, no schema, no migration, no version bump.** `IndexCache.schemaVersion` stays 3
  and `Tuist/Package.swift` still has one third-party dependency.
- R-14 and R-15 are properties of the design rather than behaviours to be defended: the relations
  are in the file and nowhere else, and no closed schema is touched by any line of the change.
- R-13 costs nothing, because the caret sits outside the range `NoteRename` replaces (D3).
- R-09 and R-10 need no code: nothing writes a parent's completion, and no existing grouping is
  read by the new branch.
- Everything that can be wrong without a window is in `Sources/Core` or `Sources/Index` and is
  testable with Swift Testing against strings and in-memory values — the parser, the id allocator,
  the two-line insert, the three queries, the grouping, the two linter rules, the board
  enumeration and the canvas reference reader. The UI suite is needed for exactly one thing, the
  end-to-end pass of R-16.

**Negative.**

- **The markers are ugly in the editor and in Obsidian.** `- [ ] Rivedere il preventivo
  ^[[vibrofer-emea.canvas]] ^id(3) ^parent(1) >2026-09-01` is a lot of syntax on one line, and
  nothing hides any of it (D12). This is the price of principle 1 and it was accepted knowingly;
  the mitigation — teaching ADR-0018's markup hiding about the caret family — is a separate
  decision that this one leaves available.
- **`BoardTray` becomes a four-section column** and will want scrolling on a board with many
  assigned tasks. The tray is 200 points wide and was designed for one list.
- **`NoteViolations.count` grows**, so a note that was conformant can start appearing in the
  Conformità pane and in `perg lint` output on the strength of a marker mistake. Intended, and it
  is a JSON contract change for the connector (D11) that has to be carried deliberately.
- **A task assigned with `^[[…]]` no longer shows in the board's existing "TASK COLLEGATI"
  section** (D1). Correct, but it means two sections on the same column answer two similar
  questions, and a user who does not know the difference will read it as a bug once.
- **`^id` collides silently across notes** if anyone reads the markers as global. The design is
  right and the failure mode is a person's mental model, which no test catches.
- The sub-task write touches **two lines in one operation**, which is the first write in this app
  that does. The staleness guard covers the parent line only; a sub-task inserted while the note
  changed elsewhere is still an atomic whole-file write, but the guard is narrower than the change.

**Neutral.**

- The SPEC's three factual errors about this repository (GRDB, the task table, the cache path) are
  corrected here and not in the SPEC, because the SPEC is the record of what was agreed and this
  ADR is the record of what is true. `CLAUDE.md`'s stack line still names GRDB; whether to correct
  it is a separate, one-line decision for the operator.
- The Workspace pane already existed as `.pane(.workspace)` in a three-group sidebar. R-01's "new
  Workspace section" is a folder browser *inside* that pane, not a twelfth sidebar row — the
  blueprint's "third top-level section (Note / Workspace / Task)" describes the pane list that is
  already there.
- `Cmd+Shift+Return` is unused: `taskToggle` holds `Cmd+Return`, `newBoard` holds `Cmd+Shift+B`,
  `quickTask` holds `Cmd+Shift+N`, and the board's bare `Return` is scoped to an open crop
  (`WorkspaceView.swift:198`). Registered through `ShortcutStore` as a new `ShortcutCommand` in
  section `.task`, so it is remappable like everything else; the raw value is identity and must
  never be renamed afterwards.
- No file moves between targets. Every new file falls under an existing glob —
  `Sources/Core/**` and `Sources/Connector/**` are globbed into `sharedSources`, and
  `Sources/**` minus the two tool directories is the app target — so `Project.swift` needs no
  edit. `tuist generate --no-open` is still required after **any** file is added, because the
  generated project lists files and does not regenerate itself.

## References

- `SPEC.md` (this feature), R-01 … R-16, and its Decisions section of 2026-08-24.
- `UX-BLUEPRINT.md` (this feature): window inventory, Vista and Task menu entries,
  `Cmd+Shift+Return`, and the accessibility checklist.
- `docs/20260811_Pergamenum_SpecApp.md` §4.3, §4.4, §4.7, §6.1, §7.1, §7.2, §7.4, §7.5, §10, §12.
- ADR-0001 §D1 (`Sources/Core` imports no UI framework, enforced by the connector builds),
  §D2 (a cold scan rebuilds the index).
- ADR-0007 §D2 (the connectors compile the same files; the MCP SDK is the only dependency),
  §D6 (dry run, diff, journal).
- ADR-0009 §D4 (`ViewCorpus`, and what depends on `IndexSnapshot.allNotes`).
- ADR-0013 §D1 (rollover), §D6 (five closed views, and grouping as the open axis).
- ADR-0017 / `PG-004` (derived stores left `.pergamenum/`).
- ADR-0018 (markup hiding — named as the place a future decision about drawing these markers
  would live).
- ADR-0020 (prefixed-scalar keys on canvas nodes; the same-day Obsidian deprioritisation this
  ADR's D12 leans on). **This feature does not use that mechanism** — it extends the task-line
  text instead, per the SPEC.
- Code read at `c5cde2a`: `Sources/Core/Tasks/TaskParser.swift`, `TaskItem.swift`,
  `TaskListOptions.swift`, `Sources/Core/Conventions/Wikilink.swift`, `NoteRename.swift`,
  `NoteViolations.swift`, `Sources/Core/Canvas/JSONCanvas.swift`,
  `Sources/Index/IndexCache.swift`, `IndexSnapshot.swift`, `Sources/Vault/VaultScanner.swift`,
  `CanvasStore.swift`, `NoteStore.swift`, `NoteTree.swift`, `NoteFileOperations.swift`,
  `VaultSession+Tasks.swift`, `VaultSession+Search.swift`,
  `Sources/Features/Workspace/WorkspaceView.swift`, `BoardChrome.swift`,
  `Sources/Features/Tasks/LinkedTasksPanel.swift`, `TasksView.swift`, `TaskViewSidebar.swift`,
  `Sources/Features/Editor/VaultBrowser.swift`, `NoteListPane.swift`,
  `Sources/App/MenuCommands.swift`, `PergamenumApp.swift`, `SidebarItem.swift`,
  `Sources/Connector/VaultPayloads.swift`, `VaultReads.swift`, `Project.swift`,
  `Tuist/Package.swift`.
