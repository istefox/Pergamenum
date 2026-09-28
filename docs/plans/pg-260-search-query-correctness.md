# Plan: PG-260 / #574 (Audit Fable chain 7), search and query correctness

- **SPEC:** `SPEC.md` (Approved 2026-09-28), success criteria R-01…R-18. Its Decisions and
  Constraints are treated as settled and are not reopened here: one PR and no ADR; search `tag:`
  uses the views' exact-or-glob rule through the one shared predicate; quote state tracked
  explicitly; search and the views scan stay on the main actor and cooperative (ADR-0041); two
  search doors over one loop; spinner and validation ordered by generation; board parents read
  their children from their own board; the legend shows `tag:client-*`; exactly one GUI test.
- **ADR:** none. See "ADR outcome" at the end.
- **Baseline:** written against `HEAD` `f0fdc0df` (branch `fix/pg-260-search-query-correctness`).
  `origin/main` is `a65ef42a`, four commits ahead, touching only `TODO.md` and
  `scripts/uitests.sh` (the `--status` inheritance fix). None of the files below overlap. Every
  file:line below was read from `f0fdc0df` on 2026-09-28.
- **UI budget:** one GUI test (R-17), in a new class. Everything else is asserted in-process in
  `PergamenumTests`.
- **ROADMAP deviation, registered, not reopened:** ROADMAP §Chain 7 item 3 proposes "move the read
  off the main actor". The SPEC decides against it under ADR-0041 §D12 (`read` stays synchronous and
  main-actor bound). This plan follows the SPEC. Task 8 records the difference in the roadmap.

## Before `/build` (orchestrator; each item is a HITL point)

1. **Merge `origin/main` into the branch** (a merge, never a force). It carries the
   `scripts/uitests.sh --status` fix that Task 7's run relies on. There are no conflicting paths.
2. Run `tuist install` (once per fresh worktree), then `tuist generate --no-open`. Tasks 1, 3, 4,
   5, 6 and 7 add files, so run `tuist generate --no-open` again after each tester half that adds
   one.
3. **Gate G1: two existing tests change.** CLAUDE.md requires the explanation in chat before the
   edit:
   - `Tests/SearchTests.swift:105-110`, `filtersByTag`. Line 108-109 asserts the defect itself:
     "A prefix matches, so `tag:topic-` finds every topic." Under R-01 `tag:topic-` matches
     nothing, because no tag is literally `topic-`. The assertion is rewritten to `tag:topic-*`
     (R-03), and the old spelling becomes a negative assertion. No assertion is dropped.
   - `Tests/ViewBlockOutOfScopeTests.swift:229-258`. The test replicates the private
     `ViewsPane.entry(...)`, on the stated premise that `ViewsPane.swift` is unchanged. Task 6 moves
     that function into `ViewCatalogue`, which makes the premise false. The replica is replaced by a
     call to the real function, and every assertion stays identical.
   - Recommendation: approve both. The first asserts the behaviour the SPEC removes. The second
     gets stronger, because it now calls production code instead of a copy of it.
4. **Gate G2: one accessibility identifier beyond the SPEC's list.** The SPEC names identifiers for
   the search progress indicator and the results list. The GUI test also needs a signal that the
   first vault scan has finished on a large vault. Without one it would search a half-built index
   and measure nothing. The plan adds `vault-note-count` to the count label in the note list's
   status bar (`Sources/Features/Editor/NoteListPane+Footer.swift:44`). That label is drawn only
   when no scan is running, and its text carries a number the test wrote itself. Recommendation:
   approve. It is one modifier, and it has no behaviour. The alternative, a warm-up search, doubles
   the test's run time and leaves a results list on screen that confuses the assertion.
5. Commit, push and merge stay HITL at the end of `/build`. The pre-push guard (ADR-0061/0062) runs
   on push, if it is installed on this machine.

## Ownership and order

This is a compiled target. In each task the **tester** owns every signature the tests name, and the
**coder** owns the bodies.

- Within a task, the tester's half lands first and must leave `Pergamenum`, `perg` and
  `pergamenum-mcp` building. The new tests are then red on their assertions, except the ones marked
  «green today», which are guards.
- **Placeholder bodies never trap:** no `fatalError`, no force unwrap. A placeholder returns an
  inert value (`[]`, an entry with an error string) or does nothing.
- Across tasks:
  - Tasks 1, 2, 3 and 6 are independent of each other.
  - Task 4 comes before Task 5, because Task 5 wires the async door.
  - Task 6 needs Task 4's `CooperativeLoop`.
  - Task 7 comes after Task 5.
  - Task 8 comes last.
  - Tasks 1 and 2 both edit `Tests/SearchTests.swift`, so run them in order, not in parallel
    worktrees.

---

### Task 1 — Search `tag:` shares the views' rule (R-01, R-02, R-03, R-04, R-05, R-12)

**Files:** `Sources/Core/Search/SearchQuery+Matching.swift` (the two lines at 78-79 and the
comment above them at 74-76), `Sources/Core/Search/SearchQuery.swift:19` (doc comment of `tags`),
`Sources/Core/Query/Glob.swift` (the type header and the `isPattern`/`matchesTag` doc, which now
names search as a second caller), `Tests/SearchTests.swift:105-110`, new
`Tests/SearchTagRuleTests.swift`, `Tests/ConnectorTests.swift` (one new test).

**Contract change:** the meaning of `tag:` and `-tag:` in every search. The call-sites below were
found with `rg -n "\.search\(|func search\b" Sources Tests`:

- Production reaches the one `Matcher` through `VaultSession.search`
  (`Sources/Vault/VaultSession+Search.swift:19`), which is called by:
  - `VaultController.search` (`Sources/App/VaultController+Search.swift:11`), reached from
    `GlobalSearchView.swift:114`;
  - `VaultAPI.search` (`Sources/Connector/VaultReads.swift:87`), reached from `perg search`
    (`Sources/CLI/Commands/SearchCommands.swift:15`) and the MCP `search_vault` tool
    (`Sources/MCPServer/VaultHost.swift:81`).
- Tests that assert the old behaviour: `Tests/SearchTests.swift:108-109` only (gate G1).
- Tests that stay valid because their tags are exact: `SearchTests.swift:106-107, 114, 151-155,
  175-185` and `VaultSessionTests.swift:308`. `ConnectorTests.swift` and `scripts/mcp-smoke.py`
  never use `tag:`.

#### Tester

No new production signature. Write `Tests/SearchTagRuleTests.swift`, pure tests using a local
`record(tags:tasks:)` helper in the shape of `SearchTests.swift:5-25`:

| Test | Asserts | Today |
|---|---|---|
| `anExactTagDoesNotTakeALongerOne` | `tag:client-acme` matches `["client-acme"]` and not `["client-acme-industriale"]` (R-01) | red |
| `aNegatedTagExcludesOnlyThatTag` | `-tag:status-a` excludes `["status-a"]` and keeps `["status-attivo"]` and `["status-archiviato"]` (R-02) | red |
| `aStarMatchesAFamily` | `tag:client-*` matches `client-acme` and `client-acme-industriale`, not `project-client` (R-03) | red |
| `aQuestionMarkMatchesOneCharacter` | `tag:client-acm?` matches `client-acme`, not `client-acme-industriale` or `client-acm` (R-03) | red |
| `searchAndViewsAgreeOnEveryTagPair` | parameterized over one shared table of `(pattern, tag)` pairs: exact, prefix only, suffix only, `*` leading, trailing and inner, `?`, an uppercase pattern, `status-a`/`status-attivo`. For each pair, `SearchQuery("tag:\(p)").matches(...)` equals `Glob.matchesTag(p, t)` and equals the `ViewEvaluator` total (0 or 1) of `where: tag("p")` over a one-record corpus; `-tag:` equals the negation (R-04) | red on the prefix rows |
| `aTaskTagIsStillSearched` | a note with no frontmatter `client-` tag whose task carries `#client-acme-industriale`: `tag:client-acme-industriale` matches (green today), `tag:client-acme` does not, `tag:client-*` does (R-05) | red |

Edit `Tests/SearchTests.swift` `filtersByTag` (after G1): replace the prefix assertion with
`#expect(SearchQuery("tag:topic-*").matches(...))` and `#expect(!SearchQuery("tag:topic-").matches(...))`,
and fix the comment.

Add to `Tests/ConnectorTests.swift` `aConnectorSearchMatchesATagExactly` (R-12). On a temporary vault
holding `client-acme` and `client-acme-industriale` notes, `VaultAPI.search(session, "tag:client-acme",
limit: nil)` returns only the exact one. The `SearchHit` shape is unchanged. Red today.

#### Coder

- Replace the two `hasPrefix(tag)` predicates with `Glob.matchesTag(tag, $0)`. How `noteTags` is
  built (frontmatter plus task tags) does not change, and neither does the `#` stripping in
  `SearchQuery.parse`.
- Correct the three doc comments listed under **Files**.

---

### Task 2 — Quote state tracked explicitly (R-06, R-07)

**Files:** `Sources/Core/Search/SearchQuery.swift:212-269` (`tokenise`), `Tests/SearchTests.swift`
(a new `// MARK: - Quote state` section).

**Contract change:** `tokenise` is `private`. Its observable surface is `SearchQuery.init`. Only the
case of a phrase ending in `:` changes.

#### Tester

| Test | Asserts | Today |
|---|---|---|
| `aPhraseEndingInAColonClosesItself` | `"nota:" progetto forno` → `phrases == ["nota:"]`, `words == ["progetto", "forno"]` (R-06) | red |
| `aNegatedPhraseEndingInAColonClosesItself` | `-"nota:" forno` → `negatedPhrases == ["nota:"]`, `words == ["forno"]` | red |
| `anOperatorQuoteStillHoldsItsValue` | `path:"01 Progetti"` → `paths == ["01 progetti"]`, no words; `-path:"03 Risorse" x` → `negatedPaths == ["03 risorse"]`, `words == ["x"]`; `tag:"type-note"` → `tags == ["type-note"]` (R-07) | green today |
| `aPhraseThenAnOperatorQuote` | `"frase" path:"01 Progetti"` → `phrases == ["frase"]`, `paths == ["01 progetti"]` | green today |
| `anUnclosedOperatorQuoteBehavesAsToday` | `path:"01 Pro` → `phrases == ["path:01 pro"]`, `paths == []`, pinning the SPEC edge case "an unbalanced quote at the end behaves as today" | green today |

`treatsAnUnclosedQuoteAsPlainText` (`SearchTests.swift:59`) stays as it is.

#### Coder

Replace `inQuotes` and `quotedOperator` with one `enum QuoteState { case none, phrase, operatorValue }`:

| State when `"` arrives | Condition | Action | New state |
|---|---|---|---|
| `.none` | `current` ends in `:` | continue, do not flush | `.operatorValue` |
| `.none` | anything else | today's negation carry-over and flush | `.phrase` |
| `.phrase` | — | flush as a phrase | `.none` |
| `.operatorValue` | — | continue, do not flush | `.none` |

- A space splits only in `.none`.
- The final flush is `flush(asPhrase: state != .none)`. This keeps both unbalanced cases exactly as
  they are today.
- Update the doc comments of the two removed variables into the enum's doc.

---

### Task 3 — A board parent reads its sub-tasks from its board (R-15)

**Files:** `Sources/Index/IndexSnapshot.swift:201-219` (`subtasks(of:)` and its doc comment;
`progress(ofProject:)` follows automatically), new `Tests/BoardSubtaskTests.swift`.

**Contract change:** `subtasks(of:)` and `progress(ofProject:)` answer for a parent whose
`sourcePath` is a `.canvas`. `rg -n "subtasks\(of|progress\(ofProject" Sources Tests` finds:

- **No production caller** outside `IndexSnapshot.swift` itself.
- Tests: `TaskMarkerTests.swift:224, 243, 253` (note parents, unaffected) and
  `WorkspaceIntegrationWalkTests.swift:110` (a note parent, unaffected).
- `TaskListOptions.swift:277`'s comment ("the same scoping `IndexSnapshot.subtasks(of:)` applies")
  stays true.

#### Tester

Build the snapshot with `IndexSnapshot.replaceAll(with: .init(records:failures:boardTaskRecords:))`,
the shape of `Tests/VaultTests.swift:203`. Build the board tasks with
`TaskParser.tasks(in:sourcePath: "01 Progetti/Lavagna.canvas")`, giving the children distinct
`nodeID`s so that two cards of one board are covered.

| Test | Asserts | Today |
|---|---|---|
| `aBoardParentListsItsChildrenFromItsBoard` | parent `^id(1)` on `Lavagna.canvas`, two children `^parent(1)` on the same board. The distractors carry `^parent(1)` in `Altro.md` and in a second board. The result is exactly the two board children (R-15) | red |
| `aBoardParentsProgressCountsItsChildren` | one of the two children is done: `progress(ofProject:) == TaskProgress(done: 1, total: 2)` (R-15) | red |
| `aBoardParentWithNoChildrenHasNone` | `subtasks == []`, `progress == nil` | green today |
| `aParentWhoseBoardIsNotIndexedHasNone` | a parent `TaskItem` whose `.canvas` is absent from `boardTasks`: `[]` and `nil` | green today |
| `theIndexAndTheProgettiGroupingAgreeOnABoardParent` | `TaskArrangement.groups(index.allTasks, options:)` with `.subtasks` grouping gives the board parent's group the same child set and progress as `subtasks(of:)`/`progress(ofProject:)`. This guards against the two restated rules drifting apart | red (index side) |

#### Coder

- The lookup becomes `notes[task.sourcePath]?.tasks ?? boardTasks[task.sourcePath]?.tasks ?? []`,
  filtered on `parentLocalID == id`, scoped by source path exactly as today.
- The doc comment changes from "same-note children" to "same-source children (the note or board the
  parent lives on)".

---

### Task 4 — A cooperative search door over the same loop (R-10, R-11, R-12)

**Files:** new `Sources/Core/CooperativeLoop.swift` (covered by the `Sources/Core/**` glob, so it
compiles into both connectors with no `Project.swift` edit), `Sources/Vault/VaultSession+Search.swift`
(already in `sharedSources`), `Sources/App/VaultController+Search.swift`, new
`Tests/SearchCooperativeTests.swift`.

**Contract change:** additive only.

- A new async door is added beside the synchronous one, whose signature does not change.
  `VaultAPI.search`, `perg` and `pergamenum-mcp` keep calling the synchronous door (Constraint:
  the connectors' signature and JSON stay as they are).
- `SearchResult` gains `Equatable`.
- Naming: the new door must not be an `async` overload named `search`. Inside an `async` test,
  Swift prefers the async overload, so the existing un-awaited calls at
  `VaultSessionTests.swift:307-347` (all `async` tests) would stop compiling. Hence the distinct
  name `searchCooperatively`.

#### Tester

Declare these, with inert bodies:

```swift
/// One place for the chunk size and the pause every cooperative main-actor loop uses.
enum CooperativeLoop {
    static let chunkSize = 32
    @MainActor static func pause() async {}              // placeholder
}

extension VaultSession {
    func searchCooperatively(
        _ query: SearchQuery, limit: Int = 200,
        chunkSize: Int = CooperativeLoop.chunkSize,
        pause: @MainActor () async -> Void = CooperativeLoop.pause
    ) async throws -> [SearchResult] { [] }                // placeholder
}

extension VaultController {
    func searchCooperatively(_ query: SearchQuery, limit: Int = 200) async throws -> [SearchResult] { [] }
}
```

Also add `Equatable` to `VaultSession.SearchResult`.

Write the tests on a `TemporaryVault` opened as in `VaultSessionTests.swift:13-21`. One fixture of
about seven notes covers words, a phrase, a `regex:` line, tags, a star, a link and an orphan.

| Test | Asserts | Today |
|---|---|---|
| `theCooperativeDoorAnswersExactlyAsTheSynchronousOne` | parameterized: queries `curva`, `"frase esatta"`, `-curva`, `tag:client-*`, `regex:^##\s`, `regex:[aperta`, `is:starred`, `linked:Beta`, `orphan:`, `zzz` and the empty query, crossed with `limit` 200, 1 and 0, crossed with `chunkSize` 1, 3 and 1000. `try await searchCooperatively` equals `search`, element for element and in order (R-10) | red |
| `itPausesBetweenChunks` | seven matching notes, `chunkSize: 3`, a counting `pause`: exactly 2 pauses (after 3 and after 6, none after the last chunk) (R-11) | red |
| `itStopsAtThePauseWhenCancelled` | the `pause` closure records a call and awaits a `Gate` (`Tests/GateSupport.swift`). The test cancels the search's `Task` while it is parked there, then opens the gate. The search throws `CancellationError` and returns no array. This is ADR-0043 §D9's gate-forced interleaving, not a timing race (R-11) | red |
| `aSearchCancelledBeforeItStartsReadsNothing` | cancelled before the first chunk: throws `CancellationError`, and the counting `pause` was never called | red |
| `reachingTheLimitStopsWithoutAnotherPause` | `limit: 2`, `chunkSize: 1`: two results and at most one pause | red |

#### Coder

- Both doors share **one per-candidate step and one plan**:
  - a private `searchPlan(_:limit:)` holds the empty-query and `limit <= 0` guards, the `Matcher`
    and `candidates(for:)`, and returns `nil` or the plan;
  - a private `hit(for:matcher:) -> SearchResult?` holds the read, the match and the excerpt;
  - the limit test (`results.count >= limit`) is the same line in both loops.
- The synchronous door becomes a thin loop over those two pieces.
- The async door runs the same loop. It does `try Task.checkCancellation()` before the first
  candidate. After every `chunkSize` candidates, when more remain, it does `await pause()` and then
  `try Task.checkCancellation()`.
- The candidate list is captured once, as the synchronous door already does, so a watcher update
  mid-search cannot change which notes are considered.
- **`CooperativeLoop.pause()` is timer-backed:** `try? await Task.sleep(for: .milliseconds(1))`,
  not `Task.yield()`.
  - Reason: the stdlib's own doc for `Task.yield()` (`stdlib/public/Concurrency/Task.swift`, read
    through Context7 on 2026-09-28) says that when the task is the highest-priority one, "the
    executor immediately resumes execution of the same task". Nothing there promises the main run
    loop a turn to draw or take a keystroke.
  - A pending timer with an empty main queue lets the run loop reach its drawing phase.
  - The repo's own precedents (`UnlinkedMentionsSection.swift:105-113`,
    `PraticaSyncEngine+Folder.swift:140`) use `Task.yield()` but never measured drawing. R-17 is
    that measurement.
  - If R-17 shows the 1 ms pause is not needed, or not enough, the change is this one line.
- `VaultController.searchCooperatively` forwards to the session. With no session it answers `[]`.
- Update the file header of `VaultSession+Search.swift`: two doors, one loop, and why the
  connectors keep the synchronous one.
- **Verification (R-12):**
  - `xcodebuild … -scheme perg … build` and `… -scheme pergamenum-mcp … build`;
  - `scripts/install-cli.sh` into a scratch directory, then `scripts/mcp-smoke.py <that binary>`;
  - `ConnectorTests` stays green.

---

### Task 5 — The search state is ordered by generation; legend and identifiers (R-08, R-09, R-16)

**Files:** new `Sources/Features/Search/GlobalSearchState.swift`,
`Sources/Features/Search/GlobalSearchView.swift`, `Sources/App/VaultController+Search.swift`
(delete the synchronous `search(_:limit:)`), new `Tests/GlobalSearchStateTests.swift`.

**Contract change:** `VaultController.search(_:limit:)` is deleted. `rg -n "vault\.search\(|controller\.search\("
Sources Tests` finds exactly one caller, `GlobalSearchView.swift:114`, which moves to the async
door in this task. No test calls it. The private `Hit` mirror of `SearchResult` goes with it.

#### Tester

Declare these, with inert bodies:

```swift
@MainActor @Observable
final class GlobalSearchState {
    typealias Sleep = @MainActor (Duration) async -> Void
    typealias Search = @MainActor (SearchQuery) async throws -> [VaultSession.SearchResult]
    static let debounce: Duration = .milliseconds(180)

    private(set) var results: [VaultSession.SearchResult] = []
    private(set) var isSearching = false
    private(set) var invalidPatterns: [String] = []
    /// The raw text whose answer `results` is. Nil until one has been published.
    private(set) var answeredRaw: String?

    func run(_ raw: String, sleep: Sleep, search: Search) async {}   // placeholder
}

extension GlobalSearchView {
    /// The legend, one string per line.
    static let legendLines: [String] = [ /* today's two lines, verbatim */ ]
}
```

`legend` then renders `legendLines`. The text does not change in this half.

Tests are gate-driven (`Tests/GateSupport.swift`). The injected `sleep` awaits one gate and the
injected `search` awaits another. Each `run` is wrapped in a `Task` so the test can cancel it:

| Test | Asserts | Today |
|---|---|---|
| `validationWaitsForTheDebounce` | `run("regex:[a")`: while parked in `sleep`, `invalidPatterns == []` and `isSearching == false`; after the gate, `invalidPatterns == ["[a"]` (R-08) | red |
| `theSpinnerStartsAfterTheDebounceAndStopsWithTheAnswer` | parked in `sleep`: `isSearching == false`. Parked in `search`: `true`. After it: `false`, `results` equal to the stub, `answeredRaw == raw` (R-08) | red |
| `anEmptyQueryClearsAtOnce` | `run("   ")` never calls `sleep` or `search`; `results == []`, `isSearching == false`, `invalidPatterns == []` | red |
| `aSupersededSearchLeavesTheNewSpinnerAlone` | A parks in `search`. The test cancels A. B passes the debounce and parks in `search` (`isSearching == true`). A's `search` is released and throws `CancellationError`. `isSearching` is still `true`. Then B is released: B's results arrive and `isSearching == false` (R-09) | red |
| `aSupersededSearchNeverOverwritesTheNewResults` | A parks in `search` and is cancelled. B completes with `["B.md"]`. A's `search` then returns `["A.md"]`, a search that finished its last chunk as it was cancelled. `results` is still `["B.md"]`, `answeredRaw` is B's text and `isSearching == false` (R-09) | red |
| `aSearchCancelledDuringTheDebounceTouchesNothing` | earlier results stay published, no spinner, `search` never called | red |
| `theLegendShowsATagGlob` | `legendLines.joined(separator: " ").contains("tag:client-*")` (R-16) | red |

#### Coder

- **`run` in order:**
  1. Parse.
  2. An empty query bumps the generation and clears everything at once, with no debounce.
  3. Otherwise `await sleep(Self.debounce)`, then `guard !Task.isCancelled`.
  4. `begin`: bump the generation, set `invalidPatterns` from the query and `isSearching = true`.
  5. `try await search(query)`.
  6. On return, publish `results`, set `answeredRaw` and `isSearching = false`, but only if the
     captured generation is still current.
  7. On a throw, `isSearching = false` under the same condition. Nothing is ever published by a
     stale generation.
- **View:**
  - `@State private var search = GlobalSearchState()` and
    `.task(id: raw) { await search.run(raw, sleep: { try? await Task.sleep(for: $0) }, search: { try await vault.searchCooperatively($0) }) }`.
  - `content` shows «Nessun risultato.» only when `search.answeredRaw == raw` and no search is
    running. Without that check the placeholder would flash during every debounce, now that the
    spinner starts after it.
  - The `List` is drawn only when `results` is non-empty, with
    `.accessibilityIdentifier("search-results")`. Otherwise it is an empty area.
  - `ProgressView` gets `search-progress` and the `TextField` gets `search-field`.
- **Legend (R-16):** add `tag:client-*` to `legendLines`. Check by hand that the sheet (720 pt) does
  not truncate the line. If it does, move `regex:^##` to the second line.
- Delete `VaultController.search(_:limit:)` and `Hit`. Correct the file header of
  `GlobalSearchView.swift`: the reads are cooperative, on the main actor, per ADR-0041 §D12.

---

### Task 6 — The views scan is cooperative (R-13, R-14)

**Files:** `Sources/Features/Views/ViewCatalogue.swift` (gains `scan` and `entry`),
`Sources/Features/Views/ViewsPane.swift` (the trigger, an async `scan()`, and the doc comments at
15-18 and 160-165), new `Tests/ViewsScanTests.swift`, `Tests/ViewBlockOutOfScopeTests.swift:229-258`
(gate G1).

**Contract change:** `ViewsPane.scan()`/`entry(...)` were `private`. The only outside reference is
`ViewBlockOutOfScopeTests.swift`'s replica and its comment (`rg -n "ViewsPane" Tests`). The
connector's `VaultAPI.views` (`Sources/Connector/VaultViews.swift:16`) is not touched.

#### Tester

Declare these, with inert bodies:

```swift
extension ViewCatalogue {
    @MainActor
    static func scan(
        _ session: VaultSession, today: CalendarDate = .today,
        chunkSize: Int = CooperativeLoop.chunkSize,
        pause: @MainActor () async -> Void = CooperativeLoop.pause
    ) async throws -> [ViewEntry] { [] }                                   // placeholder

    static func entry(
        _ record: NoteRecord, ordinal: Int, parsed: Result<ViewBlock, ViewBlockError>,
        location: Location?, corpus: some ViewCorpus, today: CalendarDate = .today,
        text: (NoteRecord) -> String?
    ) -> ViewEntry                                                        // placeholder: block nil, error "non implementato"
}
```

The fixture is a `TemporaryVault` with:

- `B.md`: a valid view under a heading and a broken view;
- `A.md`: one valid `tag("client-*")` view;
- `C.md`: no view;
- a few tagged notes, so the counts are non-trivial.

`today` is fixed.

| Test | Asserts | Today |
|---|---|---|
| `theScanListsEveryViewInPathOrder` | the exact `[ViewEntry]`: path, ordinal, `lineIndex`, heading, renderer, `matches`, `error`. Its `(path, ordinal)` list equals `VaultAPI.views(session)`'s (R-13, "same entries as before") | red |
| `theScanPausesBetweenChunks` | `chunkSize: 1` over the fixture's N notes gives exactly N − 1 pauses. A chunk unit is one note: read, parsed and its views evaluated (R-13) | red |
| `aCancelledScanPublishesNothing` | gate at the first pause, the scan is cancelled, `CancellationError` (R-13) | red |

In `ViewBlockOutOfScopeTests.swift` (after G1): replace the private replica with
`ViewCatalogue.entry(..., corpus: Self.corpus, text: { _ in nil })`. The assertions are untouched.
Rewrite the doc comment at 236-240 so it names the new home.

#### Coder

- `scan` moves the body of `ViewsPane.scan()` and `entry(...)` into `ViewCatalogue`, unchanged:
  sorted by `relativePath`, `locations` paired by ordinal, `ViewEvaluator.evaluate` with the session
  as corpus and `session.read(...).text` as the body.
- It does `try Task.checkCancellation()` before the first note, and `await pause()` plus a check
  after every `chunkSize` notes when more remain.
- **`ViewsPane`:**
  - `@State private var dayTick = 0`;
  - `.onDayChange { dayTick += 1 }`;
  - one `.task(id: ScanTrigger(generation: vault.scanGeneration, dayTick: dayTick)) { await scan() }`.
    A new generation or a day change cancels the running scan through the same `.task(id:)`
    mechanism;
  - `scan()`:
    - with no session: clear `entries`;
    - otherwise: `isScanning = true`, then `try await ViewCatalogue.scan(session)`, then
      `guard !Task.isCancelled` before publishing, then publish and set `isScanning = false`;
    - on a throw it publishes nothing.
- Rewrite both doc comments:
  - the scan is cooperative on the main actor (ADR-0041 §D12), not a thread;
  - one evaluation still reads the whole vault inside its chunk when the view has a `text()`
    filter (see Risks).
- **R-14 is no-test:** Stefano's hand check (open «Viste» on the Labs vault, then «Rigenera
  indice», and the spinner shows) goes in the PR body's verification list.

---

### Task 7 — One GUI test: the spinner draws and typing is accepted during a search (R-17)

**Files:** new `UITests/GlobalSearchUITests.swift`,
`Sources/Features/Editor/NoteListPane+Footer.swift:44` (`vault-note-count` identifier, gate G2).
No `scripts/uitests.sh` mapping change: every path this chain touches outside `UITests/` and `Tests/`
is unmapped, so it maps to `ALL`, and `ALL` includes the new class.

#### Tester

- **The class doc comment carries the GUI-test justification.** The SPEC gives it, and `SPEC.md` is
  rewritten by the next chain, so the justification must live somewhere that lasts. CLAUDE.md
  requires every GUI test to be justified. With no ADR in this chain, that means this comment and
  the PR body.
- **Setup** follows `UITests/TaskCategoriesUITests.swift:13-42`:
  - a temporary vault, `-stateBase` and `-mailStoreRoot` directories;
  - `-recentVaults '("<path>")'`;
  - `-disableCalendar YES`, `-disableUpdater YES`, `-disablePlaud YES`.
- **Fixture:**
  - N filler notes, deterministic prose with no needle. N and note size are constants, sized so a
    search takes at least 3 s on this machine;
  - one `Bersaglio.md` containing `quadrifoglio`.
- **Walk:**
  1. Wait until `vault-note-count`'s label contains `"\(N + 1) note"` (generous timeout; the first
     scan of a fresh state is not cached).
  2. Press Cmd+Shift+F and wait for `search-field`.
  3. Type `quadri`, then wait for `search-progress` to exist (R-17a).
  4. While it exists, type `foglio`. Assert that `search-field`'s value is `quadrifoglio` while
     `search-results` does not exist yet (R-17b).
  5. Wait for `search-results`. Assert that it contains a row whose label carries `Bersaglio`, which
     is text the test itself wrote, and that `search-progress` is gone.

#### Coder

Add `.accessibilityIdentifier("vault-note-count")` to the count `Text`. Then run:

```bash
scripts/uitests.sh --status
scripts/uitests.sh -only-testing:PergamenumUITests/GlobalSearchUITests
```

Diagnose any red from the `.xcresult` (`xcrun xcresulttool get test-results summary --path <bundle>`)
before rerunning. Record the measured search duration on the fixture in the class doc comment.

**Feasibility stop:** XCUITest waits for the app to be idle before it synthesises a keystroke. If the
run shows that `typeText` was held until the search finished, then step 4's field read happens only
after the spinner is gone, and R-17b cannot be observed as written. In that case, stop and report to
Stefano. Do not weaken the assertion and do not add sleeps. R-17 was his choice, and changing what it
proves is his decision.

---

### Task 8 — Close the chain (R-18)

**Files:** `ROADMAP.md` (§Chain 7 at 656-683, and §Chain 15's bullet at 993), `TODO.md` through
`/project-tasks`.

- Under the §Chain 7 heading add a **Shipped** paragraph in the form of §Chain 1 (`ROADMAP.md:30`):
  - the branch, the PR number and "closes all 5 items, no ADR";
  - one sentence on item 3: the SPEC kept the reads on the main actor and made them cooperative
    (ADR-0041 §D12) instead of the "off the main actor" fix proposed there;
  - the residuals below.
- Mark §Chain 15's "`GlobalSearchView` and `ViewsPane` synchronous reads" bullet as absorbed by
  chain 7.
- **The PR body:**
  - `Closes #574`;
  - the GUI-test justification;
  - the R-14 and R-16 hand checks;
  - one line for connector users: `tag:x` is now exact, and `tag:x-*` gives the old family search.
    Scripts that relied on a prefix need the `*`.
- No CLAUDE.md chain-index entry, since there is no ADR.
- **Final verification before the HITL commit gate:**
  - `.claude/test-cmd` (the whole `PergamenumTests` bundle, not only this chain's files). The tag
    rule and the `SearchResult` conformance are shared contracts, so an unrelated module's test can
    break;
  - the `perg` and `pergamenum-mcp` builds and `scripts/mcp-smoke.py`;
  - SwiftLint on the changed files;
  - `scripts/uitests.sh --affected`.

---

## Requirement coverage

| R-id | Task |
|---|---|
| R-01, R-02, R-03, R-04, R-05 | 1 |
| R-06, R-07 | 2 |
| R-08, R-09 | 5 |
| R-10, R-11 | 4 |
| R-12 | 1 (tag rule through the connector door), 4 (builds, smoke, unchanged signature) |
| R-13 | 6 |
| R-14 (no-test) | 6 |
| R-15 | 3 |
| R-16 | 5 |
| R-17 | 7 |
| R-18 (no-test) | 8 |

## Risks and residuals

- **Whether a pause really draws.** The stdlib does not promise that `Task.yield()` gives the main
  run loop a turn. The plan uses a 1 ms timer-backed pause in one function
  (`CooperativeLoop.pause`), and R-17 is the measurement. The in-process tests only prove that the
  pause is called and that cancellation stops the loop.
- **XCUITest idle-waiting** can serialise typing behind the search. See Task 7's feasibility stop.
- **One chunk can still be long.** `ViewEvaluator.evaluate` is synchronous (`Sources/Core`, shared
  with the connectors). A view with a `text()` filter reads the whole vault inside one chunk step.
  It is not chunked here, because making the evaluator async would reach the connectors. It is
  named in the ROADMAP shipped note, not fixed.
- **Sibling left synchronous:** `VaultSession.unlinkedMentions` (`VaultSession+Search.swift:77`) is
  the same full-vault read shape and stays synchronous. It is out of the SPEC's scope and is named,
  not fixed.
- **R-15 has no user-visible surface today.** `IndexSnapshot.subtasks(of:)`/`progress(ofProject:)`
  have no production caller. The «Progetti» grouping uses `TaskArrangement.bySubtasks`
  (`TaskListOptions.swift:285`), which already scopes board parents correctly. The fix still
  closes a trap for the next caller, and Task 3's agreement test ties the two rules together.
- **Local ids on a board** are scoped per `.canvas` file, not per card. `^id(1)` on two cards of one
  board are one project, which is the same rule `TaskArrangement` applies. This is recorded as a
  fact, not changed.
- **A behaviour change for the connectors** (R-12, accepted by the SPEC): `perg search 'tag:client-'`
  used to return every client and now returns nothing. The PR body says so.
