# Pratica links on the task side, and a link summary atop the pratica inspector — implementation plan

- **SPEC:** `SPEC.md` at the repository root, Status Approved (2026-09-23). Its `## Decisions`,
  `## Constraints` and `## Test seams` are settled input and no task below reopens them: the
  task→pratica relation is computed at read time and never stored; the reverse lookup is built once
  per `TasksView` render, not per row and not cached; one badge per linking pratica, in the
  `workspaceSegment(_:)` shape; a badge click lands on the Pratiche pane with that pratica
  selected; one summary line above `pratica.md`'s body scrolls to the existing
  `praticaLinksSection`; no write path changes anywhere.
- **ADR outcome: no new ADR.** ADR-0049 governs this work unchanged — §D3 (a task is named by its
  note and its `^id`), §D4 (a link is read off the file that owns it, nothing is cached,
  `IndexCache.schemaVersion` stays 4) and §D5 (one resolver, candidates passed in). The feature is
  a new *reader* of those decisions, not a change to any of them. It fails the "hard to reverse"
  test: no on-disk format, schema, protected interface or dependency is touched, and swapping the
  per-render lookup for a cached one later is a local change. The one principled "no" in play
  (never store the reverse relation on the task's note) is already recorded by ADR-0049 §D4 and
  its Negative consequences. The SPEC's "no cache" is a proportionality call for this vault's
  scale, not a principle. Task 6 adds a short dated addendum to ADR-0049 pointing here. The
  body stays as it is, following the "Implementation notes" convention that ADR already uses.
- **Other governing ADRs, registered and not reopened:** ADR-0001 §D1 (`Sources/Core` is
  Foundation-only; the new pure type lives there), ADR-0036 §D5 (`pratica.md` has one editor, so a
  badge opens the pane, never the file as a note) and §D10 (nothing reads the Mail store until the
  Pratiche pane is opened; Task 3's `load(from:)` call reads no Mail store, see below), ADR-0045
  §D3 (an extension member widened past `private` carries a comment naming the file that reads it).
- **Baseline:** worktree `Pergamenum-feature-pg-link-activities-notes-to-practice-c08eafa6`,
  branch `kepler/feature/pg-link-activities-notes-to-practice`, HEAD `114c398a`, `SPEC.md`
  modified.
- **Requirement ids** are the SPEC's own, R-01 … R-08. Every one is cited by at least one task;
  the coverage table at the foot is the check. R-08 carries `(no-test:)` and is still cited
  (Task 6). The SPEC's Test seams item 2 (`no-test: visual-only`) means R-01's styling, R-02, R-04
  and R-05 are checked by hand in Task 6. They still get plan tasks.
- **External dependencies:** none added. SwiftUI's `ScrollViewReader`/`ScrollViewProxy.scrollTo(_:anchor:)`
  was checked against Apple's current documentation (Context7, `/websites/developer_apple_swiftui`,
  2026-09-23). It needs only an `.id(_:)` on a view inside the `ScrollView`, and the proxy must be
  called from an action, never from inside the content builder. `ScrollPosition.scrollTo(id:)`
  needs a `.scrollTargetLayout()` container plus an `@State` on `PratichePane`, and an extension
  cannot add stored properties. That is why Task 5 uses `ScrollViewReader`, the shape
  `CompletionPanelView.swift:55` already uses.

## Corrections to the SPEC's premises, found while reading the code

These are facts the SPEC did not have. Each task below builds on the correction, and the
orchestrator should confirm them with Stefano.

1. **`PraticheController.pratiche` is empty until something calls `load(from:)`**, and the
   Pratiche pane does that only in its own `.task` (`PratichePane.swift:83-87`). This is
   deliberate, because ADR-0036 §D10 keeps the Mail probe off launch. Other callers are Settings ›
   Pratiche, the pratica commands, the wizard and the Mail sheet. Read literally, the SPEC's
   source means a task shows no badge on a fresh launch until the Pratiche pane has been opened,
   which fails R-01. Task 3 closes this by calling `pratiche.load(from: vault)` on `TasksView`'s
   existing `.task(id: vault.scanGeneration)`. This follows `PraticheSettingsTab.swift:265`.
   `load(from:)` reads the ledger JSON, the index and the `pratica.md` files. It reads no Mail
   store (`PraticheController+Ledger.swift:159-188`, verified at the line), so §D10 holds.
2. **`PraticheController.pratiche` has no display order of its own.** It is `vault.index.allNotes`
   (a `Dictionary`'s values sorted by title, `IndexSnapshot.swift:96-98`) filtered to
   `pratica.md` files. Every one of those is titled `pratica`, so the ties fall back to dictionary
   order, which differs from launch to launch. The list column's visible order comes from
   `PraticheSidebarGrouping.grouped(_:order:)`. Task 3 therefore feeds the lookup
   `PraticheSidebarGrouping.grouped(pratiche.pratiche)` flattened (open groups, then «Chiuse»).
   That is the pane's default `.newestFirst` order and it is deterministic. Honouring a person's
   `@AppStorage("praticheListOrder")` instead would need `TasksView` to repeat that key literal.
   Left as a question for Stefano, not done here.
3. **The SPEC's Decision on badge styling ("muted/disabled styling when it does not" resolve
   uniquely) conflicts with R-06 and the Edge cases ("no badge at all").** R-06 is the success
   criterion, so the plan follows it: only a uniquely resolving reference ever draws a badge, and
   the muted state never appears on the task side.
4. **The SPEC's example summary starts with an emoji ("🔗").** CLAUDE.md's design system forbids
   emoji in the interface, so Task 5 draws the SF Symbol `link` instead.
5. **The inspector's "NOTE COLLEGATE" header counts `pratiche.aggregatedNoteLinks`**
   (`PratichePane+Links.swift:112`). That covers the general links *plus* notes reached only
   through a message (ADR-0049 R-06), not `links.notes`. A summary that reads `links.notes.count`
   would disagree with the section it scrolls to. Task 5 reads the same three expressions the
   three section headers read.
6. **"`pratiche.selection` set to it" goes through `pratiche.select(_:in:)`**, the one door every
   selector in the pane uses (`PraticheListColumn.swift:214`, `PraticaCommandActions.swift:68`,
   `AddToPraticaSheet.swift:200`, `NuovaPraticaWizard+Actions.swift:183`). It marks the pratica
   opened and reloads its timeline, details and links. A raw assignment would leave the previously
   selected pratica's timeline and links on screen under the new selection.

## Standing rules for every task

1. **Run the whole `PergamenumTests` target after every task** (the TEST-CMD below), never a
   per-file selection. Task 3 changes the signatures of `row`, `details` and `project`. No test
   calls them today (grepped), and the full suite is how that stays confirmed.
2. **Run `tuist generate --no-open` before building in any task that adds a file** (Tasks 1, 3
   and 5). The generated project lists files explicitly. Skip it and the build error names the
   compiler rather than the cause.
3. **Tasks 1 and 2 also build `perg` and `pergamenum-mcp`**, because the new file sits under
   `Sources/Core/**`, which `Project.swift:88`'s `sharedSources` glob compiles into both tools:
   `xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build`,
   and the same for `pergamenum-mcp`. An import of SwiftUI or AppKit there breaks both builds and
   fails `Tests/SharedSourcesPurityTests.swift`.
4. **SwiftLint clean on every touched file**, with no new warning. The ceilings are `.swiftlint.yml`'s:
   `line_length` 120 (comments count), `file_length` 400, `type_body_length` 250. New view code
   goes in new `Type+Aspect.swift` files so that `TasksView+Row.swift` (210 lines) and
   `TasksView+List.swift` (238) grow by a handful of lines, not by a feature.
5. **No token bypass.** Every color and font goes through `theme.color(_:)`/`themedText(_:color:)`,
   with no literal colors (CLAUDE.md design-system rule).

---

## Task 1 — Declare the reverse lookup and write its red suite (tester) (R-01, R-06, R-07)

The tester owns the signature and the coder owns the body. This task leaves the app and both tool
targets **building**, with the new suite red where it should be.

**Files created**

- `Sources/Core/Pratiche/TaskPraticaLookup.swift`: Foundation-only, beside
  `PraticaLinkResolver.swift`. Declarations:

  ```swift
  /// One pratica that links a given task (SPEC "Data model").
  struct TaskPraticaLink: Equatable, Sendable {
      let praticaID: String      // PraticaListItem.id, what the badge selects
      let praticaTitle: String   // PraticaListItem.title, what the badge reads
  }

  /// The task -> pratica reverse lookup, built once per `TasksView` render from every
  /// pratica's own `PraticaLinks.tasks` and never stored (SPEC Decisions, R-03).
  struct TaskPraticaLookup: Sendable {
      /// One pratica as the lookup reads it, in the order the caller wants badges drawn.
      struct Source: Equatable, Sendable {
          var praticaID: String
          var praticaTitle: String
          var links: PraticaLinks
      }

      static let empty: TaskPraticaLookup

      /// `noteCandidates`: `IndexSnapshot.resolve(title:)`'s answer for a title.
      /// `localIDsInNote`: every `^id` the note at a path carries.
      /// Both passed in, never fetched here (ADR-0049 §D5, `PraticaLinkResolver`'s own rule).
      init(
          pratiche: [Source],
          noteCandidates: (String) -> [String],
          localIDsInNote: (String) -> [Int]
      )

      /// The pratiche linking the task at `taskSourcePath` carrying `^id(taskLocalID)`,
      /// in `pratiche`' input order, one entry per pratica.
      func praticheLinking(taskSourcePath: String, taskLocalID: Int?) -> [TaskPraticaLink]
  }
  ```

  The stub is a wrong but safe constant and never `fatalError`: `init` stores nothing, `empty` is
  an instance with nothing in it, and `praticheLinking` returns `[]`. The name deliberately avoids
  "Index", because the SPEC rejects a reverse index in `IndexCache` and a future reader should not
  mistake this for one.
- `Tests/TaskPraticaLookupTests.swift`: `@Suite`/`@Test`/`#expect`, no mocks, in the shape of
  `Tests/PraticaLinksTests.swift`. The two closures are dictionary lookups
  (`{ titles[$0] ?? [] }`, `{ ids[$0] ?? [] }`). The five R-07 cases are:
  1. one matching pratica → exactly that `TaskPraticaLink`;
  2. two matching pratiche → both, **in input order**. Feed them in non-alphabetical order
     (`"Zeta"` before `"Alfa"`) so the test proves order is preserved rather than sorted;
  3. zero matches → `[]`;
  4. an ambiguous note title (two candidate paths) → `[]` when queried with either path (R-06);
  5. a `^id` that exists in the note but belongs to a different task: the reference is
     `[[Follow-up]] ^id(3)`, the note carries `[1, 3, 5]`, the query is `^id(5)` → `[]`.

  Four more cases, cheap and each guarding a real way the body can go wrong:
  6. a missing note (no candidates) → `[]` (R-06);
  7. a `^id` the note no longer carries (reference `^id(9)`, note `[1, 3]`, query `^id(9)`) →
     `[]`. This one pins the reuse of `PraticaLinkResolver.task`'s own `^id` check (R-03's
     "reusing"). A body that keyed on `(path, ref.localID)` without asking the resolver would
     answer `[A]`;
  8. one pratica listing the same task twice → one `TaskPraticaLink`, not two (one badge per
     pratica, R-01);
  9. `taskLocalID: nil` → `[]`, since a task with no `^id` cannot be referenced (ADR-0049 §D3).

  Against the stub, cases 3, 4, 5, 6, 7 and 9 pass and 1, 2 and 8 fail. That is expected: the
  red cases are the ones that require the body to produce something.

**Acceptance.** `tuist generate --no-open` has been run. `Pergamenum`, `perg` and `pergamenum-mcp`
build. `PergamenumTests` runs with exactly the three new failures above and no others.

---

## Task 2 — Implement the lookup (coder) (R-01, R-03, R-06, R-07)

**Files modified**

- `Sources/Core/Pratiche/TaskPraticaLookup.swift`: the bodies only. Signatures are the tester's.

**Algorithm, stated so review can hold the code to it**

- `init`: for each `Source` in order, and for each `ref` in `source.links.tasks`:
  - `candidates = noteCandidates(ref.noteTitle)`;
  - `localIDs = candidates.count == 1 ? localIDsInNote(candidates[0]) : []`;
  - `PraticaLinkResolver.task(localID: ref.localID, noteCandidates: candidates, localIDsInResolvedNote: localIDs)`.
    On `.ambiguous` or `.missing`, skip. The task side never draws a broken or ambiguous badge
    (R-06).
  - On `.unique(path)`, key `(path, ref.localID)`. Append
    `TaskPraticaLink(praticaID:praticaTitle:)` under that key **once per source**: keep a per-source
    seen-set so a pratica listing the same task twice contributes one link (case 8).
  - Store the result as `[Key: [TaskPraticaLink]]`, with `Key` a private `Hashable` struct of
    `sourcePath` + `localID`. Appending in source order is what preserves input order (case 2).
- `praticheLinking(taskSourcePath:taskLocalID:)`: `nil` → `[]`, otherwise `map[key] ?? []`.
  Use an explicit `?? []`, never a bare subscript (the "absent key" rule in `~/.claude/rules/swift.md`).
- `empty`: an instance with an empty map.

`PraticaLinks` and `PraticaLinkResolver` are called and not modified (R-08).

**Acceptance.** All nine cases pass. The full `PergamenumTests` suite is green. `perg` and
`pergamenum-mcp` build.

---

## Task 3 — TasksView's data path: the list is loaded, the lookup is built once per render and handed to every row (R-01, R-03)

**Files created**

- `Sources/Features/Tasks/TasksView+Pratiche.swift`: an extension of `TasksView` holding:
  - `func taskPraticaLookup() -> TaskPraticaLookup`:
    - with `vault.root == nil`, return `.empty`;
    - order the list with `PraticheSidebarGrouping.grouped(pratiche.pratiche)`, flattened as
      `open.flatMap(\.pratiche) + closed` (premise correction 2);
    - for each item, build a `Source` with `links: PraticaLinks.parse(praticaFileAt:
      root.appending(path: PraticaNaming.praticaNotePath(of: item.id), directoryHint: .notDirectory))`.
      Read the file and never `NoteRecord.frontmatter.foreignKeys`: ADR-0049 §D4's trap, where the
      links vanish from the second launch onward;
    - `noteCandidates: { vault.index.resolve(title: $0) }`;
    - `localIDsInNote: { vault.index.note(at: $0)?.tasks.compactMap(\.localID) ?? [] }`. This is
      one dictionary hit per resolved note, not the `allTasks.filter` scan
      `PratichePane+Links.swift:171` does per row.

    A doc comment mirrors `PratichePane+Links.swift:11-17`'s "per draw, costs less than a cached
    copy that could go stale" and names SPEC R-03. This is the one place a future reader will be
    tempted to add a cache.
  - Task 4's segment also goes in this file. Both members are `internal`, each with a one-line
    comment naming the file that reads it (ADR-0045 §D3).

**Files modified**

- `Sources/Features/Tasks/TasksView.swift`:
  - add `@Environment(PraticheController.self) var pratiche`. `RootView.swift:338` is the only
    `TasksView()` site and the environment is injected app-wide (`PergamenumApp.swift:203`). No
    test hosts `TasksView` (grepped), so no test needs the environment added;
  - in the existing `.task(id: vault.scanGeneration)`, after `boards = …`, add
    `if vault.session != nil { pratiche.load(from: vault) }`, with a comment giving premise
    correction 1's reason and naming `PraticheSettingsTab.swift:265` as precedent. The guard
    leaves the no-vault reset (redirects and tombstones cleared) to the Pratiche surfaces, which
    own it. `scanGeneration` bumps only on a full scan (`VaultController.swift:247`, `:347`), so
    this runs on appearance, on vault open and on a rescan. It never runs per file event.
- `Sources/Features/Tasks/TasksView+List.swift`:
  - `list`: `let praticaLookup = taskPraticaLookup()` as the first statement. This is the
    **once per render** of R-03, evaluated in `body` and never in `row`;
  - `taskViewList(_:)` → `taskViewList(_:praticaLookup:)`, `categoryList(_:)` →
    `categoryList(_:praticaLookup:)`, and `project(_:parent:rolledIDs:)` →
    `project(_:parent:rolledIDs:praticaLookup:)`, each passing it down.
- `Sources/Features/Tasks/TasksView+Row.swift`:
  - `row(_:isRolledOver:)` → `row(_:isRolledOver:praticaLookup:)` and `details(_:)` →
    `details(_:praticaLookup:)`. **No default value** on the new parameter, so the compiler finds
    every call site and none can silently draw a row without its badges.

**Update the call sites and comments that name the old signatures** (the staleness rule; grepped
over `Sources`, `Tests` and `UITests` at HEAD `114c398a`):

- Call sites, all in `TasksView+List.swift`: `:15` (`taskViewList`), `:17` (`categoryList`),
  `:41` (`project`), `:50`, `:84` (inside `CategoryView`'s row closure), `:202`, `:209` (`row`);
  plus `TasksView+Row.swift:30` (`details`).
- Doc comments naming `row(_:isRolledOver:)`: `CategoryView.swift:8`, `CategoryView.swift:39`,
  `TasksView+List.swift:132`. `CommandActions+TaskCommands.swift:45` names `workspaceSegment(_:)`,
  whose signature does not change, so it stays.
- Tests: none call `row`, `details` or `project`, and none host `TasksView`. UI tests find a row by
  `identifier == "task-row" AND label CONTAINS[c] <text>` (`TaskCategoriesUITests.swift:61`,
  `WorkspaceIntegrationUITests.swift:232`). The row is `.accessibilityElement(children: .combine)`,
  so a badge's title *adds* text to that label and `CONTAINS` still matches. Neither fixture vault
  has a pratica.

**Acceptance.** It builds and the full `PergamenumTests` suite is green. By reading the code:
the lookup is built in `list` only; nothing new sits in `@State` or on `PraticheController`
(R-03); and no call site of `row`/`details`/`project` omits the lookup.

---

## Task 4 — The pratica badge on the task row, and its click (R-01, R-02, R-06)

**Files modified**

- `Sources/Features/Tasks/TasksView+Pratiche.swift`: add
  `@ViewBuilder func praticaSegment(_ task: TaskItem, lookup: TaskPraticaLookup) -> some View`.
  `ForEach` over `lookup.praticheLinking(taskSourcePath: task.sourcePath, taskLocalID: task.localID)`,
  identified by `praticaID`, one `Button` each, in `workspaceSegment(_:)`'s `.unique` shape
  (`TasksView+Row.swift:120-125`):
  - label: `Text("\(Image(systemName: Navigation.Pane.pratiche.symbol)) \(link.praticaTitle)")
    .themedText(.caption, color: .accentPrimary)`. The symbol is read from the pane catalogue
    (`folder.badge.person.crop`, `Navigation.swift:73`) rather than repeated as a literal, so the
    badge shows the icon of the pane it leads to and cannot drift from it. This resolves the
    SPEC's "exact SF Symbol" question: folder family, not `checklist` or `doc.text`;
  - `.buttonStyle(.plain)`, `.help(link.praticaID)`. Two pratiche in different clients can share a
    folder name, and the tooltip's full path tells them apart;
  - action: `pratiche.select(link.praticaID, in: vault)` then `navigation.pane = .pratiche`
    (premise correction 6). This never opens `pratica.md` as a note (ADR-0036 §D5).
  - Nothing is drawn for an empty result: no empty-state text (SPEC Edge cases), and no muted
    badge (premise correction 3, R-06).
- `Sources/Features/Tasks/TasksView+Row.swift`: in `details(_:praticaLookup:)`, call
  `praticaSegment(task, lookup: praticaLookup)` **immediately after `workspaceSegment(task)`**,
  before the tags. The two "this task points at a container" segments sit side by side.

**Scope note, not implemented.** `details` is drawn only in `.expanded` density
(`TasksView+Row.swift:30`), so a compact row shows no pratica indication. The Workspace
assignment, by contrast, has a marker in both densities (`:16-22`). The SPEC names `details(_:)`
and nothing else. A compact-density marker would widen the SPEC, so it is reported as an open
question rather than added.

**Acceptance.** It builds and the full suite is green. The manual checks are in Task 6.

---

## Task 5 — The link summary above `pratica.md`'s body, and its scroll (R-04, R-05)

**Files created**

- `Sources/Features/Pratiche/PratichePane+LinksSummary.swift`: an extension of `PratichePane`:
  - `static let praticaLinksAnchor = "pratiche-links-anchor"`: the scroll target id;
  - `func praticaLinksSummary(onJump: @escaping () -> Void) -> some View`, where
    - counts are `pratiche.aggregatedNoteLinks.count`, `pratiche.links.tasks.count` and
      `pratiche.links.boards.count`. These are **exactly the three expressions the section headers
      count** (`PratichePane+Links.swift:112`, `:154`, `:196`), so the summary and the section it
      scrolls to cannot disagree (premise correction 5). A comment says so. Broken references
      count, as they do in the headers;
    - all three zero: a plain `Text("nessun collegamento").themedText(.caption, color: .textTertiary)`,
      with no button and no action (SPEC Edge cases);
    - otherwise a `.plain` `Button(action: onJump)` whose label is `Image(systemName: "link")` plus
      the counts, in `.caption` with the `.accentPrimary` color. The exact wording is the SPEC's
      own "Not yet specified" and is decided in `/build`. Recommended: omit a zero category ("3
      note · 1 board"), and get Italian number agreement right ("1 nota", "3 note"; "task" and
      "board" are invariant);
    - `.accessibilityIdentifier("pratiche-links-summary")` on the leaf, a spoken
      `.accessibilityLabel` for the counts, and `.help("Vai ai collegamenti")` when clickable.
  - Both members are `internal`, each with a comment naming `PratichePane+Inspector.swift` as the
    reader (ADR-0045 §D3).

**Files modified**

- `Sources/Features/Pratiche/PratichePane+Inspector.swift`, in `inspector`:
  - wrap the existing `ScrollView` in `ScrollViewReader { proxy in … }`. Every modifier currently
    on the `ScrollView` (`.background`, `.accessibilityElement(children: .contain)`,
    `.accessibilityIdentifier("pratiche-inspector")`) stays where it is;
  - immediately after the "Nota della pratica" heading `HStack` and before the body `if/else`,
    add `if pratiche.selection != nil { praticaLinksSummary { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.praticaLinksAnchor, anchor: .top) } } }`.
    The animation matches `MarkdownReadingView.swift:98`'s own scroll idiom. The proxy is used
    only inside the action, never in the builder (Apple's documented constraint);
  - at the existing call site `praticaLinksSection` (`:86-88`), add `.id(Self.praticaLinksAnchor)`
    **at the call site**.
- **`PratichePane+Links.swift` is not touched.** R-05 requires the three sections, their content,
  order and identifiers unchanged. Putting the `.id` at the call site keeps that file
  byte-identical, which Task 6's diff check confirms.

**Acceptance.** It builds and the full suite is green. `git diff` shows no change to
`PratichePane+Links.swift`.

---

## Task 6 — Verification, the R-08 diff check, the ADR-0049 addendum and the manual pass (R-08; manual: R-01, R-02, R-04, R-05, R-06)

**R-08 (no-test: diff review).** `git diff --stat main...HEAD -- <paths>` must be empty for:
`Sources/Core/Pratiche/PraticaLinks.swift`, `Sources/Core/Pratiche/PraticaLinkResolver.swift`,
`Sources/Core/Pratiche/PraticaLinkReference.swift`, `Sources/Features/Pratiche/PraticaLinksWriter.swift`,
`Sources/Features/Pratiche/PraticaCommand.swift`, `Sources/Features/Pratiche/PraticaLinkPicker.swift`,
`Sources/Features/Pratiche/PraticaCommandActions+Links.swift`, `Sources/Features/Pratiche/PratichePane+Links.swift`,
`Sources/Connector/VaultPraticheLinks.swift`, `Sources/MCPServer/`, `Sources/CLI/`,
`Sources/Index/IndexCache.swift`. No `pergamenum-dossier-links-*` string may appear in any added
line.

**Builds and suites.** `Pergamenum`, `perg` and `pergamenum-mcp` build, and the full
`PergamenumTests` suite is green (TEST-CMD). SwiftLint shows no new warning on the eight touched or
created source files. `scripts/uitests.sh --status` first, then `--affected` at merge per
CLAUDE.md's merge-gate rule. It is advisory. The likely-reached classes are
`TaskCategoriesUITests`, `WorkspaceIntegrationUITests` and `PraticheUITests`. A `contaminated`
verdict is rerun, never acted on.

**Documentation.** Append a dated section to `docs/adr/0049-pratiche-links-to-notes-tasks-and-boards.md`,
"Addendum (2026-09-23): the task side reads the relation back", and leave everything above it
untouched, as the existing "Implementation notes" section already does. It needs three or four
lines: the Negative consequence "a frontmatter wikilink produces no backlink" still holds for the
index and for notes; a *task* row now shows the pratiche that link it, computed per render from
`pratica.md` through `PraticaLinks.parse(praticaFileAt:)` + `PraticaLinkResolver.task` and never
stored (§D4 unchanged); and it points to this plan. No CLAUDE.md chain-index entry, since there is
no new ADR.

**Manual pass (Stefano, on a real vault, Debug build via `ls -dt …/Debug/Pergamenum.app | head -1`):**

- R-01: a task linked from one pratica shows one badge in expanded density, and a task linked from
  two pratiche shows two. An unlinked task shows nothing. Check this **on a fresh launch, before
  the Pratiche pane has been opened** (premise correction 1).
- R-06: a pratica task reference whose note title is duplicated in the vault draws no badge
  anywhere, and neither does one whose `^id` no longer exists.
- R-02: clicking a badge lands on the Pratiche pane with that pratica selected, showing its own
  timeline and inspector, not the previously selected pratica's.
- R-04: a pratica with links shows the summary above the body with counts equal to the three
  section headers' counts. A pratica with none shows a muted «nessun collegamento» that cannot be
  clicked.
- R-05: clicking the summary scrolls the inspector down to the three sections, which look exactly
  as before.
- Light and dark themes both.

---

## Requirement coverage

| Id | Tasks | Verified by |
|---|---|---|
| R-01 | 1, 2, 3, 4 | unit suite (cases 1, 2, 8), manual pass |
| R-02 | 4 | manual pass (SPEC Test seams 2, `no-test`) |
| R-03 | 2, 3 | unit case 7 (resolver reuse), code review of Task 3's placement |
| R-04 | 5 | manual pass |
| R-05 | 5 | manual pass, `PratichePane+Links.swift` diff empty |
| R-06 | 1, 2, 4 | unit suite (cases 4, 6, 7), manual pass |
| R-07 | 1, 2 | `Tests/TaskPraticaLookupTests.swift` |
| R-08 | 6 | diff review (`no-test`) |

## Order and dependencies

Task 1 → Task 2 → Task 3 → Task 4 run in strict order: each needs the previous one's types or
signatures. Task 5 depends on nothing above and can run at any point after Task 1. Task 6 comes
last. One sequential coder, then the tester and the reviewer (lean model).

## Risks, dependencies and HITL gates

- **HITL before every commit, before push and before the merge to `main`** (CLAUDE.md). No task
  commits on its own authority. No schema change, no deletion and no protected-interface change
  is involved.
- **Synchronous file reads in `TasksView`'s body.** Every render opens every pratica's
  `pratica.md`: tens of small files, a fraction of a millisecond each from the page cache. The
  body re-evaluates on every row click, options change and index change. This is the SPEC's
  deliberate choice (R-03) and the pratica inspector's own precedent. If a vault ever reaches
  hundreds of pratiche, the fix is the cache the SPEC rejected, which means reopening a SPEC
  decision, not tuning this code.
- **`load(from:)` from the Tasks pane has side effects** beyond filling the list. It re-reads
  `ledger.json` (an in-memory change whose save failed is replaced, which is what every existing
  caller already does) and reloads the selected pratica's timeline, reading its `email/*.md`. It
  runs once per appearance and per full scan, never per file event. It reads no Mail store.
- **Badge order** follows the pane's default `.newestFirst` grouping, not a person's chosen list
  order (premise correction 2). This is cheap to change later.
- **Pratica list staleness during a session.** A pratica created or renamed in-app refreshes the
  list through the existing flows (`followFolderRelocations`, the commands, the wizard). One
  created or renamed from Finder, `perg` or MCP appears after the next full scan or the next
  Tasks-pane appearance. Link *contents* are always fresh, because they are read per render.
- **A board-sourced task (`.canvas`) never shows a badge.** That is correct by construction: a
  pratica task reference names a note title (ADR-0049 §D3), and `resolve(title:)` answers notes
  only.
- **Do not add `.id` or anything else inside `PratichePane+Links.swift`.** R-05 and R-08 are
  checked by that file's diff being empty.
- **`tuist generate --no-open`** after Tasks 1, 3 and 5, and after any git operation that adds or
  removes a file.
- **No externally provisioned resource is required**: no network, no third-party service, no
  consent flow, no environment variable or port. Everything read is a file this app already owns
  in the open vault.

---

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
TEST-CMD MODE: brownfield
