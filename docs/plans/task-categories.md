# Task categories and the end of the Obsidian round-trip — implementation plan

- **SPEC:** `SPEC.md` at the repository root, topic slug `task-categories`, Status Approved
  (2026-09-16). Its `## Decisions` and `## Constraints` are settled input and are not reopened by
  any task below. The `BRAINSTORM.md`/`UX-BLUEPRINT.md` in the root belong to older completed
  chains (editor WYSIWYG unification, Pratiche) and are disregarded.
- **ADR:** `docs/adr/0047-task-categories-and-the-end-of-the-obsid.md` (new, proposed). Read §D4,
  §D5, §D6, §D10 and §D12 before writing code — they are the five a task can silently violate by
  writing the «obvious» version.
- **Governing prior ADRs, registered and not reopened:** ADR-0007 §D2/§D3/§D6, ADR-0013 §D6,
  ADR-0020 and ADR-0032 (the `pergamenum-` key namespace), ADR-0021 §D6/§D11, ADR-0023, ADR-0024,
  ADR-0039 §D2/§D4, ADR-0041 §D9–§D11, ADR-0043 §D8, ADR-0046 §D1/§D5, ADR-0001 §D1 (`Sources/Core`
  imports no SwiftUI).
- **Baseline:** worktree `Pergamenum.worktrees/chore-question-activity`, branch
  `chore-question-activity`, HEAD `7cee42a`, `SPEC.md` modified. The branch name does not match
  CLAUDE.md's Conventional Branch rule (`feature/task-categories` would); renaming or re-branching
  is the orchestrator's call, not part of any task below.
- **Requirement ids** are the SPEC's own, R-01 … R-16. Every one is cited by at least one task; the
  coverage matrix at the foot of this file is the check. Four ids carry `(no-test: documentation)` —
  R-12, R-13, R-14, R-15 — which exempts them from the test axis and from nothing else: each still
  has a citing task.

## Standing rules for every task

1. **`TEST-CMD` before Task 1 to establish the baseline, and after every task.** Run the whole
   `PergamenumTests` target every time, never a per-file selection: this chain changes
   `NoteRecord`, `NoteViolations`, `IndexCache.schemaVersion` and a `LintFinding` shape, and a
   contract change reaches tests in modules that have nothing to do with categories.
2. **`tuist generate --no-open` before building in any task that adds or removes a file** (Tasks 1,
   2, 4, 5, 6, 7 add files). The generated project lists files explicitly; skipping this produces
   an error naming the compiler rather than the cause.
3. **Both connector targets build in Tasks 1, 2, 3, 6 and 7**, not only the app —
   `xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build`
   and the same for `pergamenum-mcp`. Every new file under `Sources/Core`, `Sources/Index`,
   `Sources/Vault` and `Sources/Connector` must be named in `sharedSources` (`Project.swift:86-140`)
   **by hand** unless it falls under `Sources/Core/**` or `Sources/Connector/**`; a new file there
   that imports SwiftUI breaks both tool builds by design (ADR-0001 §D1).
4. **The tester owns every new signature.** Swift is compiled: a task whose red tests reference a
   declaration that does not exist yet produces a build failure, not a red test. In each task the
   items under **Declare first** are added with their final signature and a compiling body (the
   existing behaviour, or a stub that returns the empty/none case) *before* the assertions are
   written; the behaviour that turns them green is the task's second half.
5. **`swiftlint --quiet` after every task**, no new violation on a touched file. `.swiftlint.yml`
   errors at 1000 lines per file and 350 lines per type body; a type that outgrows it splits into
   `Type+Aspect.swift` extensions (ADR-0045's shape), never into a new type invented for size.
6. **One commit per task**, Conventional Commits, English: `feat(tasks):`, `feat(vault):`,
   `feat(connector):`, `docs(adr):`, `test(...)` as appropriate.
7. **Never disable, skip or delete a test to make the suite pass** (CLAUDE.md). `CanvasTests
   .roundTripsAnObsidianCanvas` in particular is a *format* test and stays green: ADR-0047 §D11
   retires the manual probe, not the format.
8. **No colour literal in any view.** The category colour is a palette name in the registry resolved
   to a design token at render time (SPEC constraint, CLAUDE.md design-system rule).
9. **UI strings Italian, code/comments/commits English.**
10. **`scripts/uitests.sh` by hand before the merge to `main`**, not per task (Task 8).

---

## Task 1 — The registry: type, validation, store, session lifecycle (R-01, R-02, R-11)

The vault-side half of R-01: a category exists, is valid, and survives a relaunch, with no note and
no index involved.

**Files created**
- `Sources/Core/Categories/Category.swift` — the entry (`slug`, `name`, `color`, `symbol`,
  `description`, `deadline`, `parent`, `order`, `archived`), `Codable`, `Sendable`, no SwiftUI.
- `Sources/Core/Categories/CategoryRegistry.swift` — the ordered list plus `version`, and the one
  validation door (§D3): slug grammar via `Tag.isWellFormedValue`
  (`Sources/Core/Conventions/Tag.swift:37`), uniqueness across both levels, parent must be
  top-level, archive cascades to the subtree, unarchiving a child unarchives its parent.
- `Sources/Vault/CategoryRegistryStore.swift` — `StarredStore`'s shape
  (`Sources/Vault/StarredStore.swift`: atomic pretty-printed write, problem returned not thrown),
  plus §D2's divergence: a file that exists and does not decode loads as `.malformed`, is reported
  through `recordProblem`, and is **never** overwritten by a save.
- `Sources/Vault/VaultSession+Categories.swift` — create, update, reorder, reparent, archive,
  unarchive, delete, promote-implicit. Each validates through §D3's door, then saves once.
- `Tests/CategoryRegistryTests.swift` — the SPEC's «Unit — registry» seam.

**Files modified**
- `Sources/Core/Conventions/VaultLayout.swift` — `static let categoriesFile = "categories.json"`.
- `Sources/Vault/VaultSession.swift` — `@ObservationIgnored let categoryStore`, `private(set) var
  categories: CategoryRegistry`, loaded in `init` beside `starred`/`vocabulary` (`:48`, `:71-75`,
  `:166`).
- `Project.swift` — `sharedSources` gains `Sources/Vault/CategoryRegistryStore.swift` and
  `Sources/Vault/VaultSession+Categories.swift` (the two `Sources/Core` files are covered by the
  `Sources/Core/**` glob).

**Declare first:** `Category`, `CategoryRegistry`, `CategoryRegistry.RefusalReason`,
`CategoryRegistryStore.load()/save(_:)`, and the eight `VaultSession` mutations with their final
signatures.

**Tests:** decode/encode round-trip; unknown `version` refused as malformed; duplicate slug across
both levels refused *before* any write (assert the file's bytes are unchanged); a parent that is
itself a child refused; archive cascade; unarchive-child-unarchives-parent; a malformed file loads
empty, reports, and a subsequent mutation does not rewrite it.

---

## Task 2 — Index derivations and the cache field (R-04, R-08, R-11, and R-06's derivation half)

**Files created**
- `Sources/Index/IndexSnapshot+Categories.swift` — effective category per task (explicit tag → the
  note's `pergamenum-category` → none; a `.canvas` task inherits nothing, it has no frontmatter),
  implicit categories, rolled-up task set per slug, `TaskProgress` over the subtree.
- `Sources/Core/Categories/CategoryFrontmatter.swift` — the scalar reader for
  `pergamenum-category` over `Frontmatter.foreignKeys`, the shape
  `MessageDocument+Reading.swift:13` uses. One key, one line, no second YAML parser.
- `Tests/CategoryIndexTests.swift` — the SPEC's «Unit — index» seam.

**Files modified**
- `Sources/Vault/NoteStore.swift` — `NoteRecord.categorySlug: String?` (defaulted, so the 15
  `NoteRecord(` construction sites keep compiling) filled inside
  `makeRecord(from:text:document:attributes:at:)` (`:111-129`), the single seam `read` and
  `NoteStore+ReadSurface.record` both go through.
- `Sources/Index/IndexCache.swift` — `StoredRecord.categorySlug` (defaulted for the same reason
  `embedTargets` is, `:264-269`), carried both ways in `init(_:)`/`record`, and
  `schemaVersion` `3 → 4` at `:212` with its reason appended to the running comment.
- `Sources/Index/IndexSnapshot.swift` — nothing structural; the derivations live in the new file.
- `Project.swift` — `sharedSources` gains `Sources/Index/IndexSnapshot+Categories.swift`
  (`Sources/Index/**` is **not** a glob: three files are named individually at `:91-97`).
- `Tests/IndexCacheTests.swift:234` — `#expect(IndexCache.schemaVersion == 3)` becomes `== 4`.
  **This is the contract-staleness update; see the staleness section below.**

**Declare first:** `IndexSnapshot.effectiveCategory(of:)`, `implicitCategories`,
`tasks(inCategory:rolledUp:)`, `progress(ofCategory:)`, `NoteRecord.categorySlug`,
`StoredRecord.categorySlug`.

**Tests:** precedence (explicit tag beats the note key, note key beats nothing); a board task
inherits nothing; implicit categories are exactly the `#project-*` values absent from the registry;
rollup counts the subtree; progress counts `[x]` done, `[ ]`/`[>]` open, `[-]` in neither; **and one
test that writes a cache, reloads from it, and asserts `categorySlug` survives the round-trip** —
the defect §D5 exists to prevent, and the only way to catch it is to exercise the reuse path rather
than a fresh scan.

**Boundary, restated because it is the easy mistake:** `IndexSnapshot.tasks(for:on:)`'s `.byProject`
branch (`:280-281`) and `TaskGrouping.project` (`TaskListOptions.swift:181-182`) keep reading
`task.project` literally. They are not rewritten to use the effective category (ADR-0047 §D4).

---

## Task 3 — The line write: assign and remove a category (R-03's write half)

**Files modified**
- `Sources/Core/Tasks/TaskParser+Writes.swift` — `line(for:assigningCategory:)`, mirroring
  `line(for:assigningWorkspace:)` (`:142-157`): remove **every** existing `#project-*` through
  `withPrecedingSpace`, then append the new one; `nil` removes and appends nothing. Indentation,
  bullet, dates, `^id`/`^parent`/`^[[board]]` and any unmodelled syntax are preserved.
- `Sources/Vault/VaultSession+Tasks.swift` — a `TaskChange` case (`:60-105`) routed through the
  existing `apply(_:to:)` (`:106-140`), which already rewrites with
  `TaskParser.rewrite(_:at:expecting:with:)` and writes with `expecting:` (`:125`, `:139`). No new
  write door, no journal change, no batch.
- `Tests/TaskMarkerWriteTests.swift` — the SPEC's «Unit — parser writes» seam.

**Declare first:** `TaskParser.line(for:assigningCategory:)` and the `TaskChange` case.

**Tests:** append to a line with no project tag; replace one; replace **two** (the SPEC edge case:
all of them go, one comes back); remove; a line whose only tag is a `#type-*` is untouched apart
from the addition; no double space and no trailing space; a stale `rawLine` is refused by
`rewrite`'s existing guard.

---

## Task 4 — The command catalogue and the four assignment gestures (R-03)

**Files created**
- `Sources/Features/Tasks/CategoryPicker.swift` — registered, non-archived categories grouped
  parent → child; refuses a stale choice (a category deleted while the picker is open) rather than
  applying it, and refreshes from the registry.

**Files modified**
- `Sources/Features/Tasks/TaskCommand.swift` — `.assignCategory`, `.removeCategory`, their Italian
  titles, SF Symbols and `available(for:)` gating (`.removeCategory` only when the task carries a
  project tag, the shape `.goToBoard` already uses at `:52-58`).
- `Sources/App/CommandActions+TaskCommands.swift` — `run(_:on:)` and `canRun(_:on:)` gain the two
  cases.
- `Sources/App/Navigation.swift` — `var taskPickingCategory: TaskItem?` beside `taskPickingBoard`
  (`:219`).
- `Sources/App/RootView.swift` — the picker's `.sheet(item:)` beside the board picker's
  (`:147-148`), so assignment works from every surface (ADR-0039 §D4).
- `Sources/Features/Tasks/TaskComposer+Footer.swift` — the composer's category picker; the chosen
  slug is appended to the drafted line by Task 3's writer, never by string concatenation here.
- `Sources/Features/Today/TaskDrag.swift` + the category row's drop handler (Task 5's file) — the
  existing `TaskDragPayload` (path + line index, deliberately nothing else) is reused unchanged.
- `Sources/Vault/VaultSession+Notes.swift:144-152` — `tagSuggestions` gains the registered,
  non-archived slugs as `#project-<slug>`, de-duplicated by the existing `seen` filter, so the
  editor's `#` completion (`CompletingTextView.swift:361-363`) offers a category nobody has typed
  yet.
- `Tests/TaskCommandTests.swift` (catalogue seam), `Tests/TaskDropTests.swift` (drop seam).

**Declare first:** the two `TaskCommand` cases, `Navigation.taskPickingCategory`, the drop
handler's entry point.

**Tests:** both commands appear on every surface the catalogue feeds and carry a unique
`identifier`; `.removeCategory` is absent for a task with no project tag; the drop of a
`TaskDragPayload` onto a category row resolves to the same write Task 3 produces; a drop whose
payload no longer resolves to a task is refused; `tagSuggestions` contains a registered slug that
appears on no task.

---

## Task 5 — The sidebar section, the category editor and the category view (R-01, R-04, R-05, R-07, R-16)

**Files created**
- `Sources/Features/Tasks/TaskPaneSelection.swift` — `enum TaskPaneSelection { case
  view(IndexSnapshot.TaskView); case category(String) }` (ADR-0047 §D6).
- `Sources/Features/Tasks/CategorySidebarSection.swift` — flat recursive rows, chevron and depth
  drawn by hand, **never `DisclosureGroup`** (ADR-0024); colour dot from a token, symbol, name, open
  count, progress ring; implicit rows muted with a «Registra» affordance; archived ones inside a
  collapsed «Archiviate» group; a «+» in the section header. Every row and affordance carries an
  `accessibilityIdentifier` — a UI test must not find a control by the words on it (CLAUDE.md).
- `Sources/Features/Tasks/CategoryEditor.swift` — name, slug (proposed from the name, editable only
  at creation), colour, symbol, description, deadline, parent; a refusal from Task 1's validator is
  shown and nothing is written.
- `Sources/Features/Tasks/CategoryView.swift` — header (name, description, deadline, rolled-up
  progress), then direct tasks, then one group per child.
- `UITests/TaskCategoriesUITests.swift` — the SPEC's single UI test: the «Categorie» section shows a
  registered row and an implicit row, and clicking a row opens the category view. Launched with the
  five standard arguments the suite uses (`-recentVaults '("…")'`, `-disableCalendar YES`,
  `-mailStoreRoot <fixture>`, `-disablePlaud YES`, `-disableUpdater YES`, `-stateBase …` —
  `UITests/SectionToolbarsUITests.swift:22-31`). The sidebar drag is **not** UI-tested while PG-162
  is open; its drop logic is Task 4's unit test.

**Files modified**
- `Sources/Features/Tasks/TaskViewSidebar.swift` — the binding becomes
  `Binding<TaskPaneSelection>`; the five view rows are unchanged in content and order; the new
  section is appended under them.
- `Sources/Features/Tasks/TasksView.swift` — `@State var view: IndexSnapshot.TaskView` becomes
  `@State var selection: TaskPaneSelection` (`:11`); `followLastCapture()` sets `.view(…)`.
- `Sources/Features/Tasks/TasksView+List.swift` — the list branches on the selection; per-category
  options read from the same `@AppStorage("taskListOptions")` map under a `category:<slug>` key
  (`:62-70`), not a second store.

**Declare first:** `TaskPaneSelection`, `TaskViewSidebar`'s new binding type, the category view's
entry point.

**Tests:** the five `TaskView` cases and their `defaultListOptions` are unchanged (a regression
assert, cheap and load-bearing); options round-trip under a `category:` key without disturbing the
five view keys; the UI test above.

---

## Task 6 — The linked note: frontmatter key, inspector, navigation, lint (R-06, R-10)

**Files created**
- `Tests/CategoryLintTests.swift` — the two advisory findings, `TaskMarkerLintTests.swift`'s shape.

**Files modified**
- `Sources/Vault/VaultSession+Categories.swift` — link and unlink write `pergamenum-category:
  <slug>` into the note's frontmatter through the existing document render path, one key, through
  the write door with `expecting:` (ADR-0043 §D8). Nothing else in the note is touched.
- `Sources/Core/Conventions/NoteViolations.swift` — `var categories: [CategoryViolation] = []`
  (defaulted, ADR-0021 §D11's precedent, so the seven `NoteViolations(` construction sites keep
  compiling) plus its inclusion in `isEmpty` and `count`, and the `CategoryViolation` enum
  (`unknownSlug`, `duplicateHome`).
- `Sources/Vault/VaultSession+Search.swift:106-132` — populates it; this is the one place in the
  lint path that can see both the registry and the index (ADR-0047 §D10).
- `Sources/Connector/VaultPayloads.swift:129-150` — `LintFinding.categories`, additive, beside
  `taskMarkers`.
- `Sources/Features/Editor/VaultBrowser.swift` — `ConformanceText.lines(_:)` (`:275-281`) gains
  `categoryLines(_:)`, and the inspector (`:194-217`) gains the category row with «Vai alla
  categoria» and an unlink affordance, under the star and above the backlinks.
- `Sources/Features/Tasks/CategoryView.swift` — «Vai alla nota» in the header.

**Declare first:** `CategoryViolation`, `NoteViolations.categories`, `LintFinding.categories`,
`ConformanceText.categoryLines(_:)`, the link/unlink signatures.

**Tests:** a note carrying the key is the category's home and its untagged tasks count as the
category's, while a task with an explicit different tag does not; a second note naming the same slug
is a `duplicateHome` finding and the home is the first in vault order, deterministically; a key
naming an implicit slug still inherits and reports `unknownSlug` (the SPEC's edge case: the finding
says the slug is unregistered, not that the key is wrong); a deleted home note leaves the category
unlinked with no registry change.

---

## Task 7 — The two connector reads (R-09, R-11)

**Files created**
- `Sources/Connector/VaultCategories.swift` — `categories` (entries with `implicit`, `archived`,
  `parent`, `progress`) and `categoryTasks(slug:)` (rolled up, grouped as the view groups),
  both `@MainActor static func` on `VaultAPI`, covered by the `Sources/Connector/**` glob.
- `Sources/CLI/Commands/CategoryCommands.swift` — `perg categories` and `perg category-tasks
  <slug>`, printing for a person and `--json` for a machine, the shape `TaskCommands.swift` uses.

**Files modified**
- `Sources/Connector/VaultPayloads.swift` — the two payload structs beside the existing ones.
- `Sources/CLI/main.swift:13-19` — the two new groups in the dispatch switch.
- `Sources/CLI/Help.swift` — their help lines.
- `Sources/MCPServer/ToolCatalogue.swift` — two `Tool(...)` entries in `reading`, each
  `annotations: .init(readOnlyHint: true)`, Italian descriptions. The pinned SDK is 0.12.1
  (`Tuist/Package.resolved`); use the existing `Tool(name:description:inputSchema:annotations:)`
  shape and **do not** adopt `title`/`outputSchema`/`icons`, which the pinned version does not have.
- `Sources/MCPServer/VaultHost.swift:77+` — the two dispatch cases.
- `scripts/mcp-smoke.py` — both tools exercised over stdio (R-09 says so explicitly).
- `Tests/ConnectorTests.swift` — the payload seam.

**Declare first:** the two `VaultAPI` functions and their payload structs.

**Tests:** both payloads carry the implicit and archived flags, the parent and the progress; the
rollup in the payload equals the index's; the grouping matches the app view's; no write tool is
added to either front end (assert `ToolCatalogue.reading` grew by two and `writing` by none).

---

## Task 8 — The documentation amendment and the merge gate (R-12, R-13, R-14, R-15, R-16)

No code. Four documentation obligations the SPEC marks `no-test`, and the final verification.

**Files modified**
- `CLAUDE.md` — principle 4 rewritten per ADR-0047 §D11: the Labs vault still opens without
  conversion and the formats are still what they are; the round-trip is no longer a binding
  constraint; principle 5 (harness) explicitly untouched. Dated. The chain decision index gains its
  ADR-0047 line, and the «Decisions from later chains» section gains its compacted paragraph.
- `docs/20260811_Pergamenum_SpecApp.md` — the amendment at **line 16** (§1), **line 52** (§3's
  «Compatibilità Obsidian» row), **line 64** (the numbered principle 4), **line 484** (§13's M2
  acceptance criterion, annotated as satisfied on 2026-08-11 and retired as a gate, never deleted)
  and **§14 line 502** («Formato canvas»: the format stays, the interoperability *obligation*
  ends). Each as a dated `*Emendato 2026-09-16 (ADR-0047).*` note in the style §7.2, §7.3 and §7.4
  already use. **R-12 names «SPEC §2»; §2 (Identità) carries no compatibility line — the lines
  above are the real targets. Flagged rather than silently substituted.**
- `docs/20260811_Pergamenum_SpecApp.md` §7.1 and §7.4 — R-15: one line in §7.1 saying
  `#project-<slug>` is the category pointer and that the registry lives in
  `.pergamenum/categories.json`; an amendment note in §7.4 naming ADR-0013 §D6 and stating the five
  views are unchanged and the «Categorie» section is an addition.
- `docs/adr/0010, 0019, 0020, 0021, 0022, 0023, 0024, 0025, 0027` — the scope note at the head,
  verbatim from ADR-0047 §D12, **body untouched**. Re-run the classification
  (`grep -ril obsidian docs/adr/`, judged by §D12's rule) and record any correction in ADR-0047's
  own list, which is where R-13 requires the list to live.
- `docs/adr/0047-…md` — Status `proposed` → `accepted`, with the plan path.
- `TODO.md` / `PROJECT_BRIEF.md` Status — per the repo's own convention. `PROJECT_BRIEF.md`'s
  milestone history is **not** rewritten (ADR-0047 §D11).

**Verification (R-16), in this order:** full `PergamenumTests` green; `perg` and `pergamenum-mcp`
build; `scripts/mcp-smoke.py`; `swiftlint --quiet`; `scripts/uitests.sh` by hand with no stale
instance alive (a run started with stale instances produces 60.2 s launch timeouts that are not
defects — CLAUDE.md).

---

## Contract changes and their call-sites (staleness rule)

Grepped on the baseline tree, not left for the implementer to discover:

| Contract | Call-sites found | Action |
|---|---|---|
| `IndexCache.schemaVersion` 3 → 4 | `Tests/IndexCacheTests.swift:234` (`#expect(... == 3)`) — the only assertion on the value | Task 2 updates it. Every existing `cache.db` is discarded once on first launch; that is the documented behaviour of a bump, not a defect. |
| `NoteRecord` gains `categorySlug` | 15 `NoteRecord(` sites across `Sources/` and `Tests/` | Defaulted property, so all 15 keep compiling; only `NoteStore.makeRecord` and `IndexCache.StoredRecord.record` fill it. |
| `NoteViolations` gains `categories` | 7 construction sites: `VaultSession+Search.swift`, `VaultController+Conformance.swift`, `DayController+TaskDrop.swift`, `WorkspaceFolderSheets.swift`, `NoteRowMenu.swift`, `ViewBoardRenderer.swift`, `VaultBrowser.swift` | Defaulted, so all 7 keep compiling; `isEmpty`, `count` and `ConformanceText.lines` (`VaultBrowser.swift:275-281`) must each include it or the finding is invisible. |
| `VaultAPI.LintFinding` gains `categories` | Produced at `VaultReads.swift:104-108`, consumed by `perg lint` and the two MCP lint tools | Additive key; no consumer breaks. Protected interface — the addition is recorded in ADR-0047. |
| `TaskViewSidebar(selection:)` binding type | 1 site: `TasksView.swift:37`, plus the `@State` at `:11` | Task 5 changes both together. No test or UI test references `TaskViewSidebar` (checked). |
| `TaskCommand.allCases` grows by two | `TaskCommandTests.swift`, `CommandActions+TaskCommands.swift`, the four rendering surfaces | Any test asserting an exhaustive command list must be updated, not relaxed. |
| `tagSuggestions` contents | `VaultController+Notes.swift:65`, `EditorColumnView.swift:179`, `DiaryView.swift:104`, `EditorColumn+Text.swift:62`, `TodayView.swift:215` (passes `[]`) | Read-only consumers; a test asserting an exact suggestion list must be updated. |

**Run the full suite after Tasks 2, 5 and 6 in particular** — those are the three that change a
shape other modules share.

## Risks and HITL gates

- **The cache bump is the chain's one irreversible-ish step.** Every `cache.db` in every vault is
  discarded on first launch. Harmless by principle 3, but it is a protected interface spent: no
  second bump in this chain, and a later task discovering it needs one must stop and re-open
  ADR-0047 §D5 rather than bumping again.
- **Writing a frontmatter key into somebody's note (Task 6) is the only task that modifies notes the
  user wrote.** It goes through the write door with `expecting:`; a refusal is reported, never
  retried blind.
- **`categories.json` has no backup and no journal.** A malformed file is reported and never
  overwritten (§D2), which is the whole mitigation. Registry operations are deliberately not
  journalled — the same call ADR-0022 made for folder rename/delete.
- **Nine ADR files are edited at the head (Task 8).** Append-only history gaining a note is a diff a
  reviewer should read line by line; a body change anywhere in those nine is a defect, not a
  judgement call.
- **PG-162 (the macOS 27 UI-test drag regression) is open**, which is why the sidebar drag is unit-
  tested and not UI-tested. If PG-162 closes before this chain merges, that is a follow-up, not a
  reason to add a flaky UI test now.
- **`SPEC.md` is modified in the working tree at the baseline.** Confirm what that diff is before
  committing anything; it is not this plan's to carry.
- **HITL gates:** every commit; the push; the merge to `main`; the `scripts/uitests.sh` run and its
  verdict; the `CLAUDE.md` principle-4 rewrite (it changes a binding project principle and should be
  read by Stefano before it lands, not after); any deletion, of which this plan proposes none.
- **No externally provisioned resource is needed.** No API key, no OAuth flow, no cloud console, no
  new environment variable or port: everything this chain touches is local files, the existing
  targets and the already-pinned SDKs. Nothing new is added to `Tuist/Package.swift`.
- **Unresolved user decisions, for the parent session — not answered here:** the category colour
  palette and the restricted SF Symbol list (the SPEC defers both to the mockup step), and whether a
  category deadline surfaces in «Prossimi» (the SPEC's default for this chain is no, and the plan
  implements that default).

## Requirement coverage

| id | Task(s) | id | Task(s) |
|---|---|---|---|
| R-01 | 1, 5 | R-09 | 7 |
| R-02 | 1 | R-10 | 6 |
| R-03 | 3, 4 | R-11 | 1, 2, 7 |
| R-04 | 2, 5 | R-12 | 8 *(no-test: documentation)* |
| R-05 | 5 | R-13 | 8 *(no-test: documentation)* |
| R-06 | 2, 6 | R-14 | 8 *(no-test: documentation)* |
| R-07 | 5 | R-15 | 8 *(no-test: documentation)* |
| R-08 | 2 | R-16 | 5, 8 |

## Test command

```
TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield
```

`-only-testing:PergamenumTests` is load-bearing, not tidiness: `.claude/test-cmd` runs at the end of
every turn through the `Stop` hook, and with the UI suite in there every turn launches
`XCUIApplication()`, terminates the app the person at the keyboard is using, and leaves an instance
holding the global hot key so the next launch is refused (CLAUDE.md). The UI suite is run
deliberately, by hand, through `scripts/uitests.sh`, before the merge to `main` — Task 8.
