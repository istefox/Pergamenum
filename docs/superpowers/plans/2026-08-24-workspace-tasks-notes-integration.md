# Plan — Workspace browser, Task↔Workspace/Note relations, project sub-tasks

- **SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-16)
- **UX blueprint:** `/Users/stefer/Developer/Pergamenum/UX-BLUEPRINT.md` — binding for the
  window inventory (no new Scene), the Vista and Task menu entries, `Cmd+Shift+Return`, and the
  accessibility checklist.
- **ADR:** `ADR-0021: A task carries its Workspace and its place in a project as caret markers in
  its own line, and nothing new is stored anywhere else`, currently at
  `/Users/stefer/Developer/Pergamenum/docs/architecture/ADR-0021-workspace-tasks-notes-integration.md`,
  **to be moved by the operator to
  `/Users/stefer/Developer/Pergamenum/docs/adr/0021-workspace-tasks-notes-integration.md`**
  before Task 1 (this project's ADRs all live under `docs/adr/`; the architect agent's write
  scope forbade that directory). Every reference below is to **ADR-0021** by name, not by path,
  so the move breaks nothing.
- **Branch:** `feature/adr-0021-workspace-tasks-notes-integration`
- **Base:** `main` at `c5cde2a`. Every line number quoted below was read at that commit.
- **Style:** TDD. Every task writes its failing test first, then the code that makes it pass.
  Swift Testing (`#expect`, `#require`), never XCTest, for everything new in `Tests/`.
- **Swift is compiled, so "red" has a precondition.** A task's test step must add the new type
  and signature declarations *together with* the failing tests — a placeholder body returning
  `nil` / `[]` / the unchanged input — so the target **builds** and the tests fail on their
  assertions. A batch that leaves `Pergamenum` unable to compile produces no red tests at all,
  only a build error. Never `fatalError()` and never a force-unwrap as a placeholder
  (`~/.claude/rules/swift.md`).
- **Harness:** this plan creates **no new harness script.** Verification is the two commands this
  project already trusts: `.claude/test-cmd` after every task, and `scripts/uitests.sh` once, at
  Task 10, before the merge to `main` (`CLAUDE.md`, working agreements — the UI suite is outside
  `test-cmd` on purpose and its state is unknown between deliberate runs, `PG-033`).
  **Every new or extended test file's header comment must name `ADR-0021` and this plan's
  basename `2026-08-24-workspace-tasks-notes-integration`**, the way every embed test file names
  `ADR-0018`/`ADR-0019` — that citation is the only link this repository keeps between a test and
  the decision that asked for it.
- **After any task that adds a file:** `tuist generate --no-open`. The generated project lists
  files and does not regenerate itself; a build that fails naming the compiler rather than the
  missing file is the documented failure mode.
- **`Sources/Core/**` must not import SwiftUI or AppKit.** Enforced by the `perg` and
  `pergamenum-mcp` builds, which compile those files (ADR-0001 §D1). If a Core file in this plan
  needs a UI type, the design is wrong, not the rule.
- **`Project.swift` needs no edit.** `Sources/Core/**` and `Sources/Connector/**` are globbed
  into `sharedSources`; the app target is `Sources/**` minus `Sources/CLI/**` and
  `Sources/MCPServer/**`. Every file this plan adds falls under an existing glob. Only add a
  `sharedSources` entry if a **new** file under `Sources/Vault/` is needed by a connector — this
  plan adds none.
- **Known false positive, ignore it:** the pre-commit `weakening-scan.sh` reports every Swift
  Testing test as `zero-assertion-test` because its body scanner treats a line starting with `#`
  as a comment and `#expect(...)` starts with one. Documented in `CLAUDE.md`. Do not restructure
  a test to appease it; do still read the diff for a genuinely assertion-free test.

## Three things the SPEC says about this repository that are false

Read at the line before this plan was written. Do not rediscover them, and do not follow the
SPEC's wording where it contradicts these.

| SPEC says | Truth | Consequence for this plan |
|---|---|---|
| index is "via GRDB" | No GRDB anywhere. `grep -rn GRDB Sources/ Project.swift` is empty; `Tuist/Package.swift` calls MCP *"the only third-party dependency in the project"*. `IndexCache` is `import SQLite3`. | **Add no dependency.** Nothing in this plan touches `Tuist/Package.swift`. |
| "extend the task table with `workspace_path`, `local_id`, `parent_local_id`" | There is no task table. `IndexCache` has one table, `notes(path, payload BLOB)`. `StoredTask` stores `rawLine`/`sourcePath`/`lineIndex` and **re-parses** via `TaskParser.parse` (`IndexCache.swift:266-269`). | **Add no columns and no fields to `StoredTask`.** The three fields ride the re-parse for free. `IndexCache.schemaVersion` stays **3** (ADR-0021 D4). |
| cache is at `.pergamenum/cache.db` | Since ADR-0017 (`PG-004`) it is at `~/Library/Application Support/it.stefer.pergamenum/vaults/<id>/`. | Only matters if someone goes looking. Unit tests must pass a temporary state base, never resolve the real directory (`CLAUDE.md` principle 3). |

## Contract changes, and the call sites already grepped

Do not rediscover these either. Greped across `Sources/`, `Tests/` and `UITests/` at `c5cde2a`.

| Change | Call sites found | Action |
|---|---|---|
| `TaskItem` gains `workspacePath`, `localID`, `parentLocalID` | Memberwise init is called at `TaskParser.swift:51-59` only; everywhere else `TaskItem` is produced by the parser. Defaulted properties keep it compiling. | Task 1 |
| `TaskItem.links` stops containing the caret-prefixed canvas target | `IndexSnapshot.tasks(linkingTo:)` (`IndexSnapshot.swift:173-178`), `TasksView.details` (`:285`), `TaskTests.swift:37-40` (asserts `links == ["Progetto X.canvas"]` for a **plain** link — must stay green, that line has no caret). | Task 1 — verify `TaskTests` stays green, do not edit it |
| `TaskParser.displayText(from:)` strips three more markers | `TaskParser.swift:70-73` (self), `TaskTests.swift` display assertions. | Task 1 |
| `TaskGroup` gains `parent`, `progress`; `id` becomes `parent?.id ?? title` | Built at `TaskListOptions.swift:146,151-154,217` and `TasksView.swift:214`. All use `(title:tasks:)`; defaulted properties keep them compiling. Read at `TasksView.swift:142-154`, `Tests/TaskArrangementTests.swift` (11 tests). | Task 8 |
| `TaskGrouping` gains `.subtasks` | `allCases` drives the picker in `TaskListControls.swift`; `TaskArrangement.groups` switch at `TaskListOptions.swift:144-155` **must** grow a case or it stops compiling (good — that is the compiler doing the work). `TaskListOptions.init(from:)` decodes `TaskGrouping` with a `?? .none` fallback, so an old stored preference is safe. | Task 8 |
| `NoteViolations` gains `taskMarkers: [TaskMarkerViolation] = []`; `isEmpty`/`count` include it | Declared `NoteViolations.swift:9`. **Constructed at six sites, all passing the same five labelled arguments** — `VaultSession+Search.swift:124`, `VaultController+Conformance.swift:17`, `DayController+TaskDrop.swift:32`, `ViewBoardRenderer.swift:131`, `NoteRowMenu.swift:74`, `VaultBrowser.swift:320`. A defaulted trailing property keeps all six compiling. Consumed at `ConformanceText.lines` (`VaultBrowser.swift:244-313`), `ConformanceView.swift:125,129`, `VaultBrowser.swift:201`. | Task 5 |
| `VaultAPI.LintFinding` JSON gains `taskMarkers`, `count` grows | `Sources/Connector/VaultPayloads.swift:129-147` (decl + init), `Sources/Connector/VaultReads.swift:105-108` (only producer). `Tests/ConnectorTests.swift` — grep for `LintFinding`/`lint` before editing. | Task 5 |
| `VaultSession.TaskChange` gains `.workspace(String?)` | `enum` at `VaultSession+Tasks.swift:6-16`, switched at `:86-97` (must grow a case), forwarded by `VaultController.apply` (`VaultController+Tasks.swift:16`). Callers pass specific cases, so none break. | Task 3 |
| `WorkspaceView.isShowingTray` moves from `@State` to `Navigation` | `WorkspaceView.swift:17` (decl), `:42` (read), `:160-164` (toolbar Toggle). `Navigation.isShowingInspector` (`Navigation.swift:94`) is the pattern to copy. | Task 7 |
| `NoteTree` gains `build(fromPaths:)` | `NoteTree.build(from:)` called at `NoteListPane.swift:239`; `Tests/NoteTreeTests.swift` covers it. The private `Builder` is refactored to hold `(path, name)` — **the existing entry point's behaviour must not change**, which `NoteTreeTests` is the guard for. | Task 6 |
| new `ShortcutCommand.taskAddSubtask` | `ShortcutCommand.allCases` drives the settings list; `section` (`:117-138`), `title` (`:142-195`) and `defaultBinding` (`:203-289`) are exhaustive switches and **will fail to compile** until the case is handled — again, the compiler doing the work. `Tests/ShortcutTests.swift` may assert a count or a no-collision property; grep before editing. **The raw value is identity: never rename it afterwards.** | Task 9 |

**A contract change is checked by the full unit suite, never by that table.** Run `.claude/test-cmd`
in full after every task. The task parser feeds the index, the day view, the timeline, the saved
views, the CLI and the MCP server; a change to what `displayText` strips can turn a test red in
`ViewRenderingTests`, `DayControllerTests` or `CaptureTests`, which are named in no row above.

---

### Task 1 — The three caret markers in `TaskParser`, pure (R-02, R-04, R-15)

ADR-0021 D1, D2. Nothing else in this plan can start before this is green.

- **Test first.** New `Tests/TaskMarkerTests.swift`. Header names ADR-0021 and this plan's
  basename. Assertions, at minimum:
  - `^[[vibrofer-emea.canvas]]` → `workspacePath == "vibrofer-emea.canvas"`, and that target is
    **absent** from `task.links`.
  - `^[[Nota]]` (no `.canvas`) → `workspacePath == nil` and `links == ["Nota"]` — today's
    behaviour, unchanged. This is the backward-compatibility assertion and it is the important one.
  - `[[Progetto X.canvas]]` **without** a caret → `workspacePath == nil`, `links` contains it.
    Guards `Tests/TaskTests.swift:37-40`, which must stay green.
  - `^id(3)` → `localID == 3`; `^parent(1)` → `parentLocalID == 1`; both nil when absent.
  - A line carrying all three plus `>2026-09-01 !2026-09-10 [[Nota A]] [[Nota B]] #project-x`
    parses every field correctly **in three different marker orders** (R-04 and the
    order-independence claim in one test).
  - Two `^[[…]].canvas` markers → the **first** wins.
  - `task.text` contains none of `^`, `id(`, `parent(`, `[[`, and has no double spaces and no
    stranded caret.
  - A `^id(3)` inside a fenced code block is not a task at all (the existing `codeRanges` skip
    still holds).
  - `TaskParser.nextLocalID(in:)` → 1 for a note with no ids, `max+1` otherwise, and it counts
    ids on **every** task line in the note, not only open ones.
- **Then the code.** `Sources/Core/Tasks/TaskItem.swift`: three defaulted properties with the
  doc-comment style of the file. `Sources/Core/Tasks/TaskParser.swift`: a `caretAnnotation(in:
  name:)` sibling of `annotationValue(in:name:)`; workspace detection by walking
  `WikilinkParser.links(in: body)` and checking the character before `link.range.lowerBound` is
  `^` **and** `link.target` has a case-insensitive `.canvas` extension; the `links` filter; the
  three removals in `displayText`, with the caret removed together with its link.
- **Foundation only.** No `import SwiftUI`, no `import AppKit`. Verified by Task 10's connector
  builds and, cheaply, by reading the import block.
- Budget: `Sources/Core/Tasks/TaskItem.swift`, `Sources/Core/Tasks/TaskParser.swift`,
  `Tests/TaskMarkerTests.swift` (~260 lines)

### Task 2 — The three index queries, and the cache round-trip that proves R-14 (R-14, R-04)

ADR-0021 D4, D5.

- **Test first.** Extend `Tests/TaskMarkerTests.swift` (queries) and `Tests/IndexCacheTests.swift`
  (round-trip).
  - `tasks(assignedToWorkspace:)` finds tasks across several notes, matches case-insensitively,
    and does **not** match a task that merely carries a plain `[[X.canvas]]` wikilink (R-04's
    other half: the two mechanisms are independent).
  - `subtasks(of:)` returns only same-note children; **a `^parent(1)` in a different note whose
    own `^id(1)` exists there is not a child** — this is the D2 assertion and it is the one that
    catches a global-id mistake.
  - `progress(ofProject:)` counts `state == .done` over the children, returns nil for a task with
    none, and never touches a file.
  - **Round-trip:** build records, `IndexCache.save`, `load`, and assert the three fields survive
    identically, plus `IndexCache.schemaVersion == 3` — a literal assertion, so a coder who bumps
    it turns a test red. Then a second test that discards the cache entirely and re-derives from
    text, asserting the same relationships (R-14, "delete cache.db and rescan").
- **Then the code.** `Sources/Index/IndexSnapshot.swift`, in the `// MARK: Tasks` section beside
  `tasks(linkingTo:)`. `TaskProgress` (`Equatable, Sendable`, `done`/`total`) goes in
  `Sources/Core/Tasks/TaskItem.swift` — a struct, not a tuple, because `TaskGroup` carries it and
  is `Equatable` (ADR-0021 D5).
- **Do not touch `StoredTask`.** Adding the fields there is the one way to make this task fail its
  own point (ADR-0021 D4, closing paragraph).
- Budget: `Sources/Index/IndexSnapshot.swift`, `Sources/Core/Tasks/TaskItem.swift`,
  `Tests/TaskMarkerTests.swift`, `Tests/IndexCacheTests.swift` (~200 lines)

### Task 3 — The two writes: assign a Workspace, insert a sub-task (R-03, R-07, R-09)

ADR-0021 D9 and A9. Both go through the existing `read` → rewrite → atomic `write` path; neither
invents a second one.

- **Test first.** New `Tests/TaskMarkerWriteTests.swift`.
  - `TaskParser.line(for:assigningWorkspace:)`: adds the marker to a line with none; **replaces**
    the existing one rather than appending a second (R-03, "exactly one"); passing nil clears it
    and leaves no double space; the rest of the line — indentation, bullet, `>`/`!`/`@` markers,
    plain wikilinks — is byte-identical.
  - `TaskParser.insertingSubtask(in:below:draft:)`:
    - parent had no `^id` → parent line gains `^id(N)`, child line carries `^parent(N)` and
      `^id(N+1)`, both allocated from one `nextLocalID` scan;
    - parent already had `^id(2)` → parent line is **unchanged** and the child gets `^parent(2)`;
    - the child is inserted **immediately below** the parent, indented at parent-indent + 2
      spaces (cosmetic only, never read back — the hierarchy is `^parent`);
    - the child carries the draft's own `>date`/`!due`/`@remind`/`@repeat`, independent of the
      parent's (R-07's last clause);
    - **staleness:** when the line at `lineIndex` is not `expecting`, it returns nil and the text
      is untouched — same guard as `TaskParser.rewrite` (`TaskParser.swift:247`);
    - every other line of the note, including its frontmatter and its trailing newline, is
      byte-identical.
  - **R-09, explicitly:** completing every child through `VaultSession.apply(.state(.done), to:)`
    leaves the parent's line byte-identical, with no `@done`. Assert the parent's `rawLine`
    before and after. There is no code to write for this — the test is what makes the absence
    verifiable.
- **Then the code.** `TaskParser`: the two new builders, reusing `withPrecedingSpace` for the
  removal. `VaultSession+Tasks.swift`: `.workspace(String?)` in `TaskChange` and its arm in the
  `apply` switch; `TaskDraft` gains `var parent: TaskItem? = nil`; `captureTask` branches on it —
  with a parent it goes through `insertingSubtask`, without one it appends exactly as today.
- Budget: `Sources/Core/Tasks/TaskParser.swift`, `Sources/Vault/VaultSession+Tasks.swift`,
  `Tests/TaskMarkerWriteTests.swift` (~300 lines)

### Task 4 — The rename mechanism is caret-safe (R-13)

ADR-0021 D3. Small, and it earns its own task because it is the one requirement whose honest
answer is narrower than its wording.

- **Test first.** Extend `Tests/ConventionsTests.swift` (where `NoteRename` is exercised today —
  grep it first; if it is elsewhere, follow the existing home).
  - `NoteRename.rewritingLinks(in:from:to:)` given `"- [ ] Testo ^[[Vecchio.canvas]] >2026-09-01"`,
    `from: "Vecchio.canvas"`, `to: "Nuovo.canvas"` → `^[[Nuovo.canvas]]`, **caret intact**, rest
    of the line byte-identical.
  - The same for a line carrying both a plain `[[Nota]]` and a `^[[Vecchio.canvas]]`: only the
    canvas target moves.
  - Re-parsing the rewritten line yields `workspacePath == "Nuovo.canvas"` — the round trip, not
    just the string.
- **Then the code:** most likely **none**. `NoteRename` replaces `link.range`, which for a
  non-embed link starts at `[[`, so the caret is outside it. If the test is green on the first
  run, that is the result: record it in the test's own comment and move on. If it is red, the
  cause is in `WikilinkParser.links` range computation and the fix belongs there, not in a
  caret special case.
- **Write into the report, do not silently absorb:** the app has **no UI that renames a `.canvas`
  file** (`renameNote` validates a note title via `NoteName.validate`; a board is named after its
  folder by `CanvasStore.boardPath(forFolder:)`). R-13 is therefore satisfied at the level of the
  mechanism. Say so in the PR description.
- Budget: `Tests/ConventionsTests.swift` (~60 lines)

### Task 5 — Two advisory linter rules (R-11, R-12)

ADR-0021 D11. Carries a JSON contract change; see the table above before starting.

- **Test first.** Extend `Tests/ConventionsTests.swift` or add
  `Tests/TaskMarkerLintTests.swift` — one file, named for the rules.
  - A note with a task line carrying two `^[[…]].canvas` markers → exactly one
    `.duplicateWorkspace` finding, naming the line index, the kept target and the ignored one.
  - A note with `^parent(9)` and no `^id(9)` → exactly one `.orphanedParent`.
  - `^parent(2)` **with** a matching `^id(2)` in the same note → **no** finding. The false-positive
    guard, and the one that matters.
  - A `^parent(1)` whose matching `^id(1)` lives in a *different* note → a finding, because ids
    are note-local (D2).
  - A conformant note → `taskMarkers.isEmpty`, and its `NoteViolations.isEmpty` is unchanged.
  - `count` grows by exactly the number of findings.
  - **Nothing blocks:** a note with both findings still writes through
    `VaultSession.apply(...)`/`write` and still scans. Assert the write succeeds.
- **Then the code.** `NoteViolations.swift`: the defaulted `taskMarkers` property and the
  `TaskMarkerViolation` enum; `isEmpty` and `count` extended.
  `VaultSession+Search.swift:106-131` (`violations(path:title:text:)`): compute the findings from
  `TaskParser.tasks(in: text, sourcePath: path)` — pure, no index.
  `ConformanceText.lines` (`VaultBrowser.swift:244`): two Italian strings, in the register the
  neighbouring lines already use.
  `Sources/Connector/VaultPayloads.swift`: `LintFinding` gains `taskMarkers: [String]`.
- **Then run the full suite.** `ConnectorTests` asserts the connector's JSON; a new key or a
  changed `count` may turn it red, and that is the point of running everything rather than the
  new file.
- Budget: `Sources/Core/Conventions/NoteViolations.swift`,
  `Sources/Vault/VaultSession+Search.swift`, `Sources/Features/Editor/VaultBrowser.swift`,
  `Sources/Connector/VaultPayloads.swift`, `Tests/TaskMarkerLintTests.swift` (~220 lines)

### Task 6 — The Workspace folder browser (R-01)

ADR-0021 D10. UX blueprint: reuse the existing folder-tree component, not a parallel tree.

- **Test first.** Extend `Tests/NoteTreeTests.swift` and `Tests/CanvasTests.swift`.
  - `CanvasStore.allBoards()` over a temporary vault: finds nested `.canvas` files, returns
    vault-relative paths sorted, skips `.obsidian`/`.git`/`.pergamenum` via
    `VaultLayout.isExcludedDirectory`, ignores `.md` and everything else, and returns `[]` for a
    vault with no boards.
  - `NoteTree.build(fromPaths:)` produces the same folder shape `build(from:)` does for the same
    layout — assert against a hand-written expected tree, and assert **`build(from:)`'s own
    existing tests still pass unchanged** (the private `Builder` refactor is the risk here, and
    `NoteTreeTests` is its guard).
- **Then the code.** `Sources/Vault/CanvasStore.swift`: `allBoards()`, Foundation only — it is in
  `sharedSources`, so a UI import breaks both connector builds. `Sources/Vault/NoteTree.swift`:
  the second entry point over the same `Builder`, refactored to hold `(path, name)`.
  `Sources/Features/Workspace/WorkspaceBrowser.swift` (new): the tree view inside the existing
  Workspace pane, modelled on `NoteListPane`'s `folderTree` — `DisclosureGroup` rows, the same
  filter field, the same expand/collapse behaviour. Leaves draw a board icon
  (`rectangle.3.group`); **`NoteTree.Node.Kind` is not extended** (D10).
- **UX blueprint, binding:** VoiceOver labels on the section header and on each row, mirroring the
  note tree's pattern with "Nota" → "Workspace". Every row gets an `accessibilityIdentifier` —
  `CLAUDE.md` is explicit that a UI test must never find a control by the words on it.
- **Tokens only.** No hardcoded colour or font in the new view; `CLAUDE.md` says a view that uses
  one without a token does not pass review.
- Budget: `Sources/Vault/CanvasStore.swift`, `Sources/Vault/NoteTree.swift`,
  `Sources/Features/Workspace/WorkspaceBrowser.swift`, `Tests/NoteTreeTests.swift`,
  `Tests/CanvasTests.swift` (~330 lines)

### Task 7 — The board's dashboard: Task assegnati and Note referenziate (R-05, R-06)

ADR-0021 D7, D8.

- **Test first.** New `Tests/WorkspaceReferenceTests.swift`, plus the query test from Task 2
  reused for the task half.
  - `WorkspaceReferences.notes(in:)` over an in-memory `CanvasDocument`: picks up `.file` nodes
    whose path ends `.md`, picks up wikilinks inside `.text` nodes, ignores `.link`, `.group` and
    non-`.md` files, de-duplicates, and returns a stable order.
  - A board with no notes returns `[]` (so the section can decide to draw nothing).
- **Then the code.** `Sources/Core/Canvas/WorkspaceReferences.swift` (new, Foundation only).
  `Sources/Features/Workspace/BoardChrome.swift`: `BoardTray` gains **TASK ASSEGNATI**
  (`index.tasks(assignedToWorkspace: boardFileName)`) and **NOTE REFERENZIATE**, beneath the
  sections it has. Factor the row out of `LinkedTasksPanel` into a shared `TaskPanelRow` so the
  two sections cannot drift — that file's own header already makes this argument about itself.
  Completion in place goes through `vault.toggle(task)`, which writes the source note (R-05).
  Wrap the tray's content in a `ScrollView`: four sections on a 200-point column will overflow.
- **The toggle moves.** `WorkspaceView.isShowingTray` (`@State`, `:17`) → `Navigation`, beside
  `isShowingInspector` (`Navigation.swift:94`). The Vista menu gains **"Pannello Workspace"** as
  a `Toggle` with **no shortcut** and **no `ShortcutCommand` case** — the blueprint asks for none,
  and "Dividi l'editor" (`MenuCommands.swift:39`) is the precedent for a keyless Vista entry. The
  existing toolbar Toggle keeps working and drives the same state.
- **UX blueprint, binding:** VoiceOver labels on both new section headers and on each row,
  consistent with the existing panel labels. `accessibilityIdentifier` on each row.
- Budget: `Sources/Core/Canvas/WorkspaceReferences.swift`,
  `Sources/Features/Workspace/BoardChrome.swift`, `Sources/Features/Tasks/LinkedTasksPanel.swift`,
  `Sources/App/Navigation.swift`, `Sources/App/MenuCommands.swift`,
  `Sources/Features/Workspace/WorkspaceView.swift`, `Tests/WorkspaceReferenceTests.swift`
  (~340 lines)

### Task 8 — The "Progetti" grouping in Attività (R-08, R-10)

ADR-0021 D6. A grouping, **not** a sixth `TaskView` — ADR-0013 §D6 closed that list and named this
as the open axis.

- **Test first.** Extend `Tests/TaskArrangementTests.swift`.
  - `.subtasks` emits one group per parent task, children indented beneath it in the group's
    `tasks`, with `group.parent` set and `group.progress == TaskProgress(done:total:)`.
  - Tasks with neither `^id` nor `^parent` land in the trailing `"Senza"` group, and `"Senza"`
    goes last — the existing rule of `grouped(_:by:)`.
  - Two notes each with `^id(1)` produce **two** groups, not one. The D2 assertion at the
    arrangement level.
  - An orphaned `^parent(9)` still appears — in `"Senza"` — rather than vanishing (SPEC edge case:
    *"the sub-task still appears ungrouped in the flat Attività views"*).
  - Ordering is **stable**: the same input twice gives the same output, groups and rows. The file
    already has this test shape for the other groupings and the reason is recorded there.
  - **R-10, explicitly:** `.none`, `.note`, `.project`, `.schedule`, `.deadline` produce
    byte-identical output before and after this change, and each of the five `TaskView`s still
    returns every task including sub-tasks. Assert it; do not assume it.
- **Then the code.** `TaskListOptions.swift`: `TaskGrouping.subtasks` (title `"Progetti"`, symbol
  `list.bullet.indent`); `TaskGroup` gains the two defaulted properties and the new `id`;
  `TaskArrangement.groups` grows the `.subtasks` arm, bucketing on `(sourcePath, parentLocalID)`.
  `Sources/Features/Tasks/TasksView.swift`: a group with `parent != nil` draws as a
  `DisclosureGroup` — parent row on the header (completable, same row view as any other task),
  children indented, progress drawn beside the header. `IndexSnapshot.TaskView` is **not** touched.
- **The progress indicator writes nothing** (R-09, again). It is a read of `progress(ofProject:)`.
- **UX blueprint, binding:** the disclosure control and the indicator get a VoiceOver label in the
  spoken form **"3 di 5 completati"**, not a bare `3/5`. Semantic fonts, no fixed point sizes.
- Budget: `Sources/Core/Tasks/TaskListOptions.swift`, `Sources/Features/Tasks/TasksView.swift`,
  `Tests/TaskArrangementTests.swift` (~280 lines)

### Task 9 — Menu, shortcut and the two pickers (R-03, R-07)

UX blueprint's menu bar map and keyboard table, made real.

- **Test first.** Extend `Tests/ShortcutTests.swift` and `Tests/CommandActionTests.swift`.
  - `ShortcutCommand.taskAddSubtask` exists, `section == .task`, `defaultBinding ==
    KeyBinding("return", [.command, .shift])`, and **no two commands share a binding** — if that
    property test does not exist yet, write it; it is the assertion that keeps this safe as
    commands accumulate.
  - `CommandActions.canRun(.taskAddSubtask)` is false with no task selected and true with one.
  - Running it with a task selected opens the composer with `draft.parent` set to that task
    (assert the state, not the pixels).
- **Then the code.** `ShortcutCommand.swift`: the case plus its three exhaustive switch arms — the
  compiler names every place. `PergamenumApp.swift:243` `CommandMenu("Task")`: **"Aggiungi
  sotto-task"**, bound through `shortcuts.shortcut(for:)`, never a literal — `CLAUDE.md` and
  ADR-0002 both make the store the single source, and the reschedule defaults have already moved
  once. `CommandActions.swift`: the arm. `TaskComposer`: prefilled from `draft.parent`, showing
  which task it is a child of.
  New `Sources/Features/Tasks/WorkspacePicker.swift`: a sheet over `CanvasStore.allBoards()` with
  a filter field, reached from the Attività toolbar group beside "Collega nota o board" and from
  the task row's context menu, confirming into `vault.apply(.workspace(name), to: task)`.
- **`Cmd+Shift+Return` was checked, not assumed:** `taskToggle` is `Cmd+Return`, `newBoard` is
  `Cmd+Shift+B`, `quickTask` is `Cmd+Shift+N`, and the board's bare `Return`
  (`WorkspaceView.swift:198`) is scoped to an open crop. **Still press it in the running app**
  before calling this done — `~/.claude/rules/swift.md` records a shortcut that built, shipped and
  never fired because another app held the key globally.
- **UX blueprint, binding:** the command is reachable from the Task menu with no mouse, satisfying
  full keyboard access. `accessibilityIdentifier` on the picker's field and rows.
- Budget: `Sources/Core/Shortcuts/ShortcutCommand.swift`, `Sources/App/PergamenumApp.swift`,
  `Sources/App/CommandActions.swift`, `Sources/Features/Tasks/TaskComposer.swift`,
  `Sources/Features/Tasks/TasksView.swift`, `Sources/Features/Tasks/WorkspacePicker.swift`,
  `Tests/ShortcutTests.swift`, `Tests/CommandActionTests.swift` (~380 lines)

### Task 10 — End to end, the UI suite, and the record (R-16, R-15)

- **New `UITests/WorkspaceIntegrationUITests.swift`**, walking R-16 in one pass: open the
  Workspace browser, select a board, read its two panel sections, create a project task with two
  sub-tasks on different due dates, assign the board and two notes, switch Attività to
  **Progetti**, see the group expand with its indicator; then quit, relaunch, and see all of it
  again.
  - **Pass `-disableCalendar YES`.** Every one of the thirteen existing UI-test files does, and
    `CLAUDE.md` records the afternoon a real 16:30 meeting turned a hours-window test red.
  - **Find every control by `accessibilityIdentifier`, never by its words.** Same file, same
    rule, and it cost two days once.
  - Drive a throwaway vault with `-recentVaults '("/path")'` — the **plist array form**; a bare
    path leaves `stringArray(forKey:)` nil and no vault opens.
- **R-15, mechanically.** A test that scans every file this branch touched for a new frontmatter
  key or a tag prefix outside the eight of §4.4 is not worth writing — the change adds neither, by
  construction (ADR-0021 D12). Instead: assert in `Tests/TaskMarkerTests.swift` that a note whose
  tasks carry all three markers still parses to the **same `Frontmatter`** and the **same tag set**
  as the identical note without them. That is R-15 as a property of the parser rather than as a
  promise.
- **Run `scripts/uitests.sh` with no arguments**, before the merge to `main`. Not a convenience
  wrapper: it kills stale instances, refuses to run while a copy from `/Applications` is open, and
  prints the seconds beside each failure so a launch timeout is not read as a defect. An argument
  **replaces** the selection rather than adding to it. Expect ~12 minutes.
- **Then `ps -Ao pid,command | grep Pergamenum.app/Contents/MacOS`** and clean up: a UI-test
  instance outlives its run and holds the global hot key, and the next launch is refused.
- **The record.** Add ADR-0021 to the "Chain decision index" in `CLAUDE.md` in the form the two
  entries there already use, and add a "Decisions from …" section if the operator wants the same
  treatment ADR-0019 got. Update `PROJECT_BRIEF.md`'s Status section if this closes a milestone
  criterion. **Do not** edit `CLAUDE.md`'s stack line about GRDB in this PR — it is wrong (see the
  table at the top) but correcting it is a separate, one-line decision for the operator.

---

## Risks, dependencies and HITL gates

**Risks.**

- **The SPEC's storage section is wrong in three places** (GRDB, the task table, the cache path).
  A coder who follows it literally will try to add a dependency, bump a schema and edit
  `StoredTask` — the three things ADR-0021 D4 exists to prevent. The table at the top of this plan
  is the mitigation; it is the first thing to read.
- **`TaskParser` is upstream of almost everything.** Index, cache, day view, week and month
  scales, timeline, saved views, quick capture, `perg`, `pergamenum-mcp`. A `displayText` change
  that strips one character too many surfaces as a red test in a file nobody expected. Run the
  **full** unit suite after every task, not the new file's tests.
- **The two-line sub-task write is the first of its kind in this app.** Its staleness guard covers
  the parent line only. Task 3's byte-identity assertions on every other line are what stands
  between it and a note quietly reformatted.
- **`NoteTree`'s `Builder` refactor** (Task 6) touches the component the note sidebar depends on
  daily. `NoteTreeTests` must stay green **unedited** — if a test there needs changing to pass, the
  refactor is wrong.
- **R-13 cannot be exercised end to end**: no UI renames a `.canvas` file. Verified at the
  mechanism level (Task 4). Say so in the PR rather than letting the checkbox imply more.
- **The UI suite has been red before without anyone knowing** — three of sixty-seven tests, for a
  whole milestone, because a suite outside `test-cmd` has an unknown state between deliberate runs
  (`PG-033`). Budget the twelve minutes at Task 10 and read the result.
- **`Cmd+Shift+Return` may be held by a global-hotkey utility** (Paste, Raycast). It builds and
  ships either way and simply never fires. Press it in the running app.
- **Scope creep towards the editor.** The markers will look bad in the TextKit 2 editor and
  someone will want to hide them. That is ADR-0018 territory and a separate ADR (D12). Do not do
  it in this branch.

**Dependencies.**

- Task ordering is real: 1 → 2 → 3 gate everything; 4 and 5 depend on 1; 6 is independent of 1–5
  and could run in parallel in a worktree; 7 needs 2 and 6; 8 needs 2; 9 needs 3 and 6; 10 needs
  everything.
- No external service, no network, no account. The feature is fully offline, as the whole app is
  (principle 2).
- `tuist generate --no-open` after Tasks 6, 7, 9 and 10 (each adds a file).

**HITL gates.**

- **Before the first commit** on `feature/adr-0021-workspace-tasks-notes-integration` — and never
  a commit on `main`, which is never committed to directly and never force-pushed.
- **Before `git push` and before opening the PR.**
- **Before merging to `main`**, and only after `scripts/uitests.sh` has run green with no
  arguments.
- **Before moving the ADR** from `docs/architecture/` to `docs/adr/` — a file move the operator
  performs, not the coder.
- **No permanent deletion** anywhere in this plan. `NoteTree`'s `Builder` is refactored, not
  replaced; no test is disabled or deleted to make a suite pass (`CLAUDE.md`, and it is
  non-negotiable).
- **Before installing any build over `/Applications/Pergamenum.app`** — move the previous copy
  aside, never delete it.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: opus
