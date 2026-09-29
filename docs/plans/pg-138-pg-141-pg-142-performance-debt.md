# Plan: performance debt in index and view queries, the mail pipeline and board gestures (PG-138, PG-141, PG-142)

- **SPEC:** repo-root `SPEC.md`, approved 2026-09-29. It declares R-01 to R-22. The PR closes #238,
  #241 and #242.
- **ADR:** new, `docs/adr/0072-index-generation-keys-index-derived-caches.md` (`proposed`). Its
  number must be rechecked before the merge (gate G5).
- **Baseline:** `kepler/fix-fable-chain-debt` at `3cdc97fb`. Every line number below was read
  there. `origin/main` at `e653cbdc` touches none of the files this plan changes: it adds PG-274's
  CRLF line walk (`Sources/Core/Markdown`, `Sources/Core/Conventions`, `ListNesting.swift`,
  `MarkdownStyler.swift`) and #677's doc-comment move in `Sources/Core/Email/MIMEParameter.swift`.
- **Test command:** `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
  (`.claude/test-cmd`, unchanged).
- **One PR.** The seven tasks are ordered by dependency. Task 1 pins today's behaviour before any
  production file changes.

## Before `/build`

- **G1, index generation placement (confirm at review).** The SPEC says the generation is "owned by
  the session's observable facade". ADR-0072 §D1/§D2 counts it inside `IndexSnapshot`'s two
  mutating doors and exposes it through `VaultController.indexGeneration` as base plus count,
  monotonic across vault switches. The facade is still the only reader API. If the reviewer reads
  the SPEC as requiring the increments themselves on the facade, stop and ask; do not move them
  silently.
- **G2, the reading of R-12.** A mailbox's store directory is remembered per reader once found. A
  mailbox with no UUID store directory is listed again on every call, exactly as today. "At most
  once" therefore applies to a mailbox that has one.
- **G3, stop rule.** Task 1's order characterization must be green on `3cdc97fb`. It checks that
  equal-`date_sent` messages come out in `ROWID` order and that recipients come out in row order. If
  either is red on today's code, the `ORDER BY` that ADR-0072 §D8 adds would change behaviour, so
  stop Task 5 and report.
- **G4, a scope question for Stefano, not in this plan.**
  `MailStorePreparation.resolveFollowedConversations` (`MailStorePreparation.swift:150-176`) still
  reads followed conversations one at a time. Task 5's batch primitive would batch it in about ten
  lines, and the existing Pratiche sync tests would pin it. R-11 scopes the SPEC to the counterpart
  read, so it is out unless he widens the SPEC. **Decided 2026-09-29: yes.** R-11 is widened in
  SPEC.md; Task 5 batches `resolveFollowedConversations` with the same primitive and the same order
  guarantees, and the "followed-conversations loop" follow-up below is dropped.
- **G5, the ADR number.** `0070` is the highest on `origin/main`, and a parallel chain claims
  `0071`. Recheck immediately before the merge (`docs/adr/README.md` §1).
- **Setup.**
  - Merge `origin/main` into the branch first. It does not overlap these files.
  - Run `tuist install` once if this is a fresh worktree.
  - Run `tuist generate --no-open` after every task that adds a file (Tasks 1, 2, 5, 6 and 7) and
    after Task 2's `Project.swift` edit.

## Ownership rule (Swift is compiled)

The tester's step in each task declares every new signature the tests need, with a body that
compiles and keeps today's behaviour or answers a neutral value. Equivalence tests are green from
the start. Tests of a behaviour or work-count change are red until the coder's step. The coder owns
the bodies, never the signatures. A batch that leaves the target unable to build proves nothing,
so the tester's step ends with the unit suite building and running.

## Tasks

### Task 1 — Pin today's behaviour before touching it (R-01, R-02, R-07, R-08, R-09, R-10, R-11, R-13, R-14, R-17, R-18)

Only new test files. Every one is green on `3cdc97fb` and must stay green, unchanged, through
Task 7. No production file changes.

- `Tests/MailByteIdentityTests.swift`: the byte-identity run the SPEC requires before and after
  every reducer or decoder change.
  - One recorded SHA-256 hex digest per case, using CryptoKit in the test target only, over:
    - `HTMLTextReducer` output for every HTML fixture of `EmailFixtureCorpus` and every `.html` case
      of `FormatEdgeCorpus.mail`;
    - `MIMEDecoder` parts (each part's headers and payload bytes) for every RFC 822 message of
      `EmailFixtureCorpus` and every `.part` case;
    - the `.encodedWord` and `.parameter` cases.
  - Added variants that exercise exactly what Task 4 changes:
    - a CRLF that reaches `breakLine`/`breakParagraph`, e.g. `<p>a\r\n</p><p>b</p>` and
      `<div>x\r\n<br></div>`;
    - upper- and mixed-case closers (`</STYLE>`, `</ScRiPt>`, `-->` after mixed case);
    - non-ASCII characters adjacent to and inside a near-match closer: the Kelvin sign U+212A, `ſ`
      U+017F, and a combining-mark grapheme;
    - whitespace-only paragraphs made of U+00A0, U+2028 and U+3000;
    - boundary lines with trailing space, tab and CR;
    - a nested boundary that extends the outer one (`----=_X` and `----=_X-alt`);
    - a multipart with no closing delimiter.
  - Digests are recorded from one run on the baseline. A failure prints the actual output, not only
    the digest.
- `Tests/GlobPatternEquivalenceTests.swift`: a literal table of (pattern, candidate, expected) for
  `Glob.matchesTag`, `Glob.matchesPath` and `Glob.matches`. Rows cover:
  - no wildcard (exact tag, path prefix), `*`, `?`, `*` alone, the empty pattern;
  - the backtracking case `a*a*a*` against a long path;
  - accents (`équipe/*` against `Equipe/x`) and capitals.

  It also holds `SearchQuery` `tag:`/`-tag:` cases (exact and wildcard, over frontmatter and task
  tags) and `ViewEvaluator` `.text` needles with accents and case.
- `Tests/ViewEvaluatorGraphPinTests.swift`: `linksTo`/`linkedFrom` over an alias, a different
  capitalisation, an ambiguous title (two paths), a self-link, an unresolved title and a title no
  record links to. Results and totals are asserted literally.
- `Tests/MessageDocumentFrontmatterPinTests.swift`. A new file, because `MessageDocumentTests.swift`
  is already 430 lines. Cases:
  - a duplicated key, where the first occurrence wins;
  - an indented line, which is skipped even when it carries a known key;
  - whitespace before the colon, and a value that contains colons;
  - `pergamenum-mail-date` with an offset and with `Z`;
  - `pergamenum-mail-received` with fractional seconds, then a second message without them, parsed
    in that order;
  - render → parse → render byte identity for each.
- `Tests/PraticheConnectorTimelineDatePinTests.swift`: `VaultAPI`'s pratica timeline dates for a
  message and a manual entry. Each is checked against a reference `ISO8601DateFormatter` built in
  the test with `[.withInternetDateTime]` and `.current`, which is the production recipe and keeps
  the pin independent of the machine's zone.
- `Tests/IndexTaskListPinTests.swift`: snapshots built with `replaceAll` from scanner outcomes that
  hold notes and boards, then a sequence of `update` calls:
  - add a note's first task;
  - remove a note's last task;
  - remove a note;
  - add a note whose path sorts first, and one whose path sorts last.

  After each step, `snapshot.allTasks` must equal the reference formula
  `notes.values.sorted(by path).flatMap(\.tasks) + boardTasks.values.sorted(by path).flatMap(\.tasks)`,
  read from the `private(set)` stores. For a grid of days and `rolloverDays` of 0 and 7,
  `taskCounts(on:rolloverDays:)[view]` must equal `tasks(for: view, on:).count`, plus
  `rolledOverTasks(...).count` for `.today`.
- `Tests/MailStoreReaderOrderPinTests.swift`: a `MailStoreFixture` counterpart across four
  conversations.
  - One conversation holds two messages with equal `date_sent` whose ROWIDs are inserted out of
    array order.
  - One holds a deleted message.
  - Several messages carry two or three recipients.
  - The test asserts the exact ordered result of `conversations(counterpart:within:)`: ids, then
    ROWIDs per conversation, then recipients per message. It asserts the same for
    `messages(inConversation:)` and `row(rowID:)`. **This is gate G3.**
- `Tests/BoardFolderAfterLoadPinTests.swift`: load a board whose `.file` node names a folder that
  does not exist; `subfolder(for:)` is `nil`. Create the folder on disk with no reload;
  `subfolder(for:)` now returns the path.
- `Tests/DragSnapEquivalencePinTests.swift`: drive `beginDrag`, `updateDrag` and `endDrag` on a
  `WorkspaceController`. The board holds several nodes and a group (expanded by
  `BoardGeometry.expandingGroups`). Vary grid on and off, zoom 0.5, 1 and 2, an explicit anchor, a
  defaulted anchor, and an anchor id absent from the document. For each translation in a sequence,
  `dragTranslation` and `activeGuides` must equal a reference computed in the test with
  `BoardGeometry.snapped` over `document.nodes`, which is today's formula. The committed move is
  asserted after `endDrag`.

Verification: `tuist generate --no-open`, then the test command. All green on the baseline tree.

### Task 2 — Index: stored task list, index generation, index-keyed caches (R-01, R-02, R-03, R-04, R-05)

**Tester.**

Signatures, each with a body that keeps today's behaviour:

- `IndexSnapshot.generation: Int`, as `private(set) var generation = 0`, never incremented yet;
- `VaultController.indexGeneration: Int`, returning `index.generation`, with no base yet;
- `IndexSnapshot.unresolvedLinks(limit: Int? = nil)`: today's body plus a prefix;
- `IndexKeyedMemo<Input: Equatable, Value>` (new `Sources/App/IndexKeyedMemo.swift`,
  `@MainActor final class`) with `value(generation:input:compute:)`, which always computes for now;
- `BoardTray.refreshKey(for: VaultController, board: String) -> AssignedKey`, with `AssignedKey`
  widened from `private` to `internal` and an ADR-0045 comment naming the test file, returning
  today's `AssignedKey(generation: vault.taskGeneration, board:)`.

Tests:

- `Tests/IndexGenerationTests.swift`, red until the coder's step:
  - `replaceAll` and `update` each move `generation`;
  - through `VaultController`, each of these strictly increases `indexGeneration`: an editor save
    (`saveOpenNote()`), an external edit through the watcher's reconcile path, a move, a trash, a
    `rescan()` and `clearCache()`;
  - a buffer edit with no save leaves it unchanged;
  - opening vault A, then B, then A again gives a strictly increasing sequence.
- `Tests/IndexKeyedMemoTests.swift`, red: the same key computes once; a new generation or a new
  input recomputes.
- `Tests/BoardTrayRefreshTests.swift`, red today (R-04):
  - an editor save that adds `- [ ] X ^[[Board.canvas]]` changes `BoardTray.refreshKey`, and the
    task is in `index.tasks(assignedToWorkspace:)`. The same holds for an external edit.
  - an editor save that adds a task linking `[[T]]` moves `indexGeneration`, and the task is in
    `index.tasks(linkingTo: "T")`.
- `Tests/UnresolvedLinksLimitTests.swift`, green: `unresolvedLinks(limit: n)` equals
  `Array(unresolvedLinks().prefix(n))`, targets and source paths, for n = 0, 1, 10, count and
  count + 5. The snapshot holds more than ten unresolved targets, including numeric (`Nota 2`,
  `Nota 10`), accented and case-variant ones.

**Coder.**

- `Sources/Index/IndexSnapshot.swift`:
  - `allTasks` (`:171-179`) becomes `private(set) var allTasks: [TaskItem] = []`, rebuilt by a
    private `rebuildTaskList()` at the end of `replaceAll` (`:41`) and `update` (`:52`), with the
    same formula and order;
  - `generation += 1` as the last statement of both;
  - `unresolvedLinks(limit:)` (`:117`) keeps today's membership filter, applied before sorting. It
    sorts the kept keys by the same `localizedStandardCompare` over the display form, in the same
    iteration order, takes the prefix, and only then builds `sources`. No partial-selection
    algorithm: the prefix property must hold for ties too (ADR-0072 §D4).
- `Sources/Index/IndexSnapshot+TaskView.swift` (new):
  - `TaskView`, `tasks(for:on:includingCompleted:)`, `rolledOverTasks(on:daysBack:)` and
    `taskCounts(on:rolloverDays:)` move here verbatim (`:225-376`);
  - `taskCounts` becomes one pass over `allTasks`, with one membership predicate per view shared by
    `tasks(for:)` (the list filters on it, the count counts on it) and the rollover predicate
    counted in the same pass;
  - `daysBetween`/`dayCalendar` widen from `private` to `internal` only if the split requires it,
    one ADR-0045 comment each naming the file that reads it.
- `Project.swift`: add `"Sources/Index/IndexSnapshot+TaskView.swift"` to `sharedSources` beside
  `IndexSnapshot+Categories.swift` (`:97`) and `IndexSnapshot+Search.swift` (`:102`). Then run
  `tuist generate --no-open`.
- `Sources/App/VaultController.swift`:
  - add `private(set) var indexGenerationBase = 0`;
  - `indexGeneration` returns `indexGenerationBase + index.generation`;
  - `open(_:)` raises the base to `indexGeneration + 1` before `session = newSession` (`:226`);
    `close()` does the same before `session = nil` (`:257`).
- `Sources/App/IndexKeyedMemo.swift`: a single `(generation, input, value)` slot. A hit returns the
  stored value; a miss computes and stores. It is not `@Observable`.
- `Sources/Features/Tasks/LinkedTasksPanel.swift:23`: add
  `@State private var memo = IndexKeyedMemo<String, [TaskItem]>()` and read
  `memo.value(generation: vault.indexGeneration, input: title) { vault.index.tasks(linkingTo: title) }`.
- `Sources/Features/Workspace/BoardTray.swift`:
  - `refreshKey` reads `vault.indexGeneration`;
  - `.task(id:)` (`:138`) calls `Self.refreshKey(for: vault, board: boardFileName)`;
  - the doc comment at `:20-26`, which names `taskGeneration`, is corrected.
- `Sources/Features/Editor/VaultBrowser.swift`: `backlinks(_:)` (`:282-296`) and `unresolved`
  (`:298-313`) read through two `IndexKeyedMemo`s, keyed on the title and on the constant 10.
  `unresolved` calls `unresolvedLinks(limit: 10)`.

**Update tests and call sites asserting the old behaviour.** Grepped at `3cdc97fb`:

- **`taskGeneration`.** `rg -n "taskGeneration" Sources Tests` finds:
  - its three increments (`VaultController.swift:279`, `:288`, `:383`) and its readers
    `PergamenumApp.swift:297`, `TasksView.swift:69` and `TodayView.swift:62`, all unchanged
    (ADR-0072 §D3);
  - `Tests/TaskComposerTests.swift:109,120`, which asserts that a capture moves `taskGeneration`;
    it stays true and unchanged;
  - `BoardTray.swift:24,138`, changed here.

  No unit test asserts BoardTray's key: `rg -n "BoardTray" Tests` is empty.
  `UITests/WorkspaceIntegrationUITests.swift` (`assertAssignedTasksHeaderCount`, doc comment at
  `:165`) waits for the tray's «Task assegnati» count after a capture. A capture writes through the
  session, so it moves `indexGeneration` as well as `taskGeneration`, and the tray refreshes at
  least as early as today. The class runs in Task 7's `--affected` run.
- **`allTasks`.** It keeps its name, type and order, and every reader compiles and behaves
  unchanged. `rg -n "allTasks" Sources` finds these production readers:
  - `Index/IndexSnapshot+Categories.swift:41,53`;
  - `Connector/VaultLookup.swift:56` and `Connector/VaultReads.swift:108,109,157,158`;
  - `Features/Today/DayController.swift:136` and `Features/Tasks/TasksView.swift:154`;
  - `App/VaultController+Tasks.swift:45,94` and `App/VaultController+TaskDrop.swift:43`;
  - `App/PergamenumApp.swift:299` and `Features/Settings/SettingsView.swift:182`;
  - `Features/Pratiche/PratichePane+Links.swift:171` and `Features/Pratiche/PraticaLinkPicker.swift:87`.

  `rg -ln "\.allTasks" Tests` finds sixteen test files: `FrontmatterDamageLintTests`,
  `TaskMarkerLintTests`, `WorkspaceIntegrationWalkTests`, `TaskMarkerWriteTests`,
  `VaultControllerWriteCatchUpTests`, `BoardSubtaskTests`, `TaskViewTests`, `CategoryLintTests`,
  `VaultSessionTests`, `TaskMarkerTests`, `TaskComposerTests`, `GuardrailTests`, `VaultTests`,
  `CategoryRegistryTests`, `TaskDropTests` and `VaultAsyncCascadeTests`. Several read `allTasks`
  right after a session write, so they now also pin the rebuild in `update`.
- **`unresolvedLinks`.** `rg -n "unresolvedLinks" Sources Tests` finds `VaultBrowser.swift:299`,
  `Connector/VaultReads.swift:48,159`, `MCPServer/VaultHost.swift:93` (through `VaultAPI`),
  `CLI/Commands/NoteCommands.swift:73`, `Tests/VaultTests.swift:236,262` and
  `Tests/ConnectorTests.swift:141`. The defaulted parameter keeps them compiling and their output
  identical.

**Verification:**

- the test command;
- `xcodebuild … -scheme perg … build` and `-scheme pergamenum-mcp … build`, because the new
  `Sources/Index` file must be in `sharedSources` or both fail;
- `swiftlint lint` on the touched files, compared with the baseline: `IndexSnapshot.swift` must end
  under 400 lines.

### Task 3 — View queries: parse once, read records once, fold once (R-06, R-07, R-08)

**Tester.**

- Signature: `Glob.Pattern: Sendable`, with `init(_ pattern: String)`,
  `matchesTag(_:) -> Bool` and `matchesPath(_:) -> Bool`. The stub bodies delegate to the static
  functions.
- `Tests/GlobPatternEquivalenceTests.swift` gains the same table run through `Glob.Pattern`
  (green).
- `Tests/ViewEvaluatorWorkCountTests.swift`, red today, uses a counting `ViewCorpus` test double: a
  lock-protected counter in the test target, no production counter. For one `evaluate` it asserts:
  - `records` is read exactly once (today: three times, `ViewEvaluator.swift:67,176,178`);
  - `paths(forTitle:)` is called at most once per distinct title string, for a corpus in which one
    title is a link target of many records and a filter holds `linksTo` and `linkedFrom` on it.

**Coder.**

- `Sources/Core/Query/Glob.swift`:
  - `Pattern` stores `isPattern` (computed on the raw pattern, as today), the folded characters and
    the folded string, once;
  - the static `matches`, `matchesTag` and `matchesPath` keep their signatures and become
    `Pattern(pattern)…(candidate)`, so there is one implementation.
- `Sources/Core/Query/ViewEvaluator.swift`:
  - `let records = corpus.records` once in `evaluate`, passed into `Context.init`;
  - `Context` resolves each distinct title once, through a local dictionary built in `init` over
    every record's link targets and every filter title;
  - `Context` keeps, per record path, the set of paths its targets resolve to, with self-links
    included, unlike `graph.incoming`;
  - a private prepared filter is built once per evaluation from `block.filter`:
    - `.linksTo(title)` becomes the resolved target set, and a record matches when that set meets
      the record's resolved-target set;
    - `.linkedFrom(title)` becomes the resolved source paths present in the corpus, and a record
      matches when some source's resolved-target set contains the record's path;
    - `.text` becomes the folded needle;
    - `.path` and `.tag` become a `Glob.Pattern`;
  - the scope patterns and the grouping's `.tag` pattern are prepared once per evaluation.
- `Sources/Core/Search/SearchQuery+Matching.swift`: `Matcher.init` builds `tagPatterns` and
  `negatedTagPatterns: [Glob.Pattern]`, and `carries` (`:80`) uses them.
- `Sources/Features/Views/RenderedViewBlock.swift`:
  - `body` reads `block` once into a local;
  - the `.task(id:)` action calls `evaluate(parsed)` with that captured parse;
  - `evaluate()` (`:88-90`) takes the parse as a parameter;
  - `taskID` is unchanged, so the first frame is unchanged (nil result until the task runs).

  This is R-06, marked `(no-test:)` in the SPEC. It is proven by construction, and results stay
  pinned by `ViewEvaluatorTests`, `ViewQueryTests`, `ViewBlockOutOfScopeTests` and the `taskID`
  tests.

**Verification:** the test command, the `perg` and `pergamenum-mcp` builds (`Sources/Core` is
shared), and `swiftlint` on the touched files.

### Task 4 — Mail decoding without per-character or per-line allocations (R-09, R-10)

No new signature: both changes are to private functions, and the pins are Task 1's digests.

1. **Before.** Run `MailByteIdentityTests`, `HTMLTextReducerTests`, `MIMEDecoderTests`,
   `EmailTests` and `FormatEdgeCorpusTests` on the tree as it stands. All must be green. Record the
   run.
2. **`Sources/Core/Email/HTMLTextReducer.swift`.**
   - `end(of:from:in:)` (`:165-172`) computes the needle's characters once per call.
   - `matches` (`:147-152`) compares per character. When both characters are a single ASCII scalar
     it lowercases in ASCII. For any other character it uses today's
     `$0.lowercased() == $1.lowercased()` unchanged, which keeps the Kelvin sign and combining
     sequences exact.
   - `breakLine`/`breakParagraph` (`:361-372`) hold no local copy of the buffer across the append.
     The blank test becomes "every unicode scalar is in `CharacterSet.whitespacesAndNewlines`", the
     exact meaning of `trimmingCharacters(in:).isEmpty`. `hasSuffix("\n")` and `hasSuffix("\n\n")`
     stay on the `String`, with Character semantics: a trailing CRLF is one Character and is not
     `"\n"`. Do not replace them with a byte or scalar test.
   - Re-run step 1's tests.
3. **`Sources/Core/Email/MIMEDecoder.swift`.**
   - `bodies(of:boundary:)` (`:127-162`) passes the line as an index range or `ArraySlice` of
     `bytes`, not `Array(bytes[offset..<lineEnd])`.
   - `delimiter` (`:166-173`) compares the prefix in place, trims trailing CR, SP and HT by moving an
     end index, and tests `--` with two byte comparisons, allocating nothing.
   - Re-run step 1's tests.
4. **After.** Every digest is identical. `HTMLTextReducer.swift` is already over the 400-line
   warning at 501 lines, so keep its net line count flat or lower.

### Task 5 — Mail store reads in batches; one formatter per call (R-11, R-12, R-13, R-14)

**Tester.**

Signatures:

- `MailStoreReader.init(connection:batchSize:)` and `init(storeURL:batchSize:)`, with
  `batchSize: Int = 500` stored as `let batchSize`. The stub ignores it.
- `MailStoreConnection.handle` (`MailStoreConnection.swift:51`) becomes `private(set) var`, with an
  ADR-0045 comment naming the test file that reads it.

`Tests/MailStoreReaderBatchTests.swift`:

- **Statement count, red today.** The test attaches `sqlite3_trace_v2` with `SQLITE_TRACE_STMT` to
  `connection.handle` (the fixture has no triggers, so one event is one statement). Tests may
  import `SQLite3`, as `IndexCacheTests.swift` does. For a counterpart with n conversations and
  `batchSize: 2`:
  - n = 0 gives exactly 1 statement;
  - n = 1 gives 3;
  - n = 3 and n = 4 both give 5, which shows the count is independent of n within a batch count;
  - n = 5 gives 7.

  Today the count is `1 + 2n`.
- **Order across a batch boundary, green.** With `batchSize: 2` and five conversations, the result
  equals the default reader's result and Task 1's pinned order.
- **Deleted message, green.** A deleted message stays out in a batch.
- **R-12, red on the first case.** A mailbox with UUID store directory A:
  - `emlxPath` for two rows resolves under A;
  - replace A on disk with B; the same reader still answers A, which proves the listing ran once; a
    fresh reader answers B;
  - a mailbox with no UUID directory answers the mailbox path, and a UUID directory created
    afterwards is found by the same reader (gate G2: misses are not cached).

**Coder.**

- `Sources/Core/Email/MailStoreReader+Batches.swift` (new, Foundation only, shared by glob): add
  `messages(inConversations ids: [Int]) -> [Int: [MailMessageRow]]`, chunked by `batchSize`, with
  no statement for an empty input. Per chunk:
  - rows use `rowSelect` with `WHERE m.conversation_id IN (?1…?k) AND m.deleted = 0 ORDER BY m.date_sent, m.ROWID`;
  - recipients use `SELECT r.message, a.address FROM recipients r JOIN addresses a ON a.ROWID = r.address JOIN messages m ON m.ROWID = r.message WHERE m.conversation_id IN (…) ORDER BY r.ROWID`,
    lowercased, folded onto the rows as today;
  - an unpreparable recipients statement answers "no recipients", fail-closed as ADR-0036 §D24.4
    requires.
- `Sources/Core/Email/MailStoreReader.swift`:
  - `messages(inConversation:)` (`:102-114`) returns `messages(inConversations: [id])[id] ?? []`;
  - `conversations(counterpart:within:)` (`:123-154`) keeps its id query and SQL, then maps the
    identifiers, in order, through one `messages(inConversations:)` call;
  - `recipients(forConversation:)` (`:207-229`) is deleted: its only caller is `:109`;
  - `recipients(forMessage:)` (`:233-245`) gains `ORDER BY r.ROWID`;
  - `connection`, `rows`, `collect`, `rowSelect` and `date` widen from `private` to `internal`
    only as far as the new file needs, one ADR-0045 comment each naming
    `MailStoreReader+Batches.swift`.
- `Sources/Core/Email/MailStoreReader+Paths.swift`: `storeDirectory(in:)` (`:74`) consults a
  per-reader `final class` cache (`[URL: URL]`, found directories only), held as a `let` on the
  reader and set by both inits. A miss lists the directory as today.
- `Sources/Core/Pratiche/MessageDocument+Reading.swift`:
  - `parse` (`:10-48`) builds one first-occurrence `[String: String]` over non-indented lines that
    hold a colon, with keys trimmed by `.whitespaces`, and every `scalar`/`list` read becomes a
    lookup;
  - `storeReferences(in:)` (`:94-124`) keeps its own scan and predicate (ADR-0072 §D9);
  - one `ISO8601DateFormatter` per `parse` is passed into `isoDate`, which sets `formatOptions` to
    `[.withInternetDateTime]` at the start of every call, before the fractional fallback.
- `Sources/Core/Pratiche/MessageDocument.swift`: `render` builds one formatter, and
  `isoString(_:offset:)` (`:252-257`) takes it and sets `timeZone` before every string (the offset
  zone for the date, UTC for received). `MessageDocument.isPendingAttachmentEntry` is protected and
  untouched.
- `Sources/Connector/VaultPratiche.swift`: the timeline (`:186-195`, used at `:217` and `:258`)
  builds one formatter per call and passes it down. `isoString(_:)` (`:314-319`) stays for the
  pratica list's `lastActivity` (`:51`), which feeds the protected `VaultAPI.PraticaSummary` and is
  not part of R-14.

**Verification:**

- the test command, including `MailByteIdentityTests`, `MessageDocumentTests`,
  `MailStoreReaderTests`, `PraticaSyncTests` and `PraticheConnectorTests`;
- the `perg` and `pergamenum-mcp` builds;
- `swiftlint` on the touched files. `MailStoreReader.swift` must not grow past its current size
  class.

### Task 6 — Views over disk state: attachment chip, timeline, board card, drag (R-15, R-16, R-17, R-18)

**Tester.**

Signatures:

- `PraticaTimelineModel.nextRows(in: [PraticaTimelineEntry]) -> [PraticaTimelineEntry.ID: PraticaTimelineEntry]`
  in `Sources/Features/Pratiche/PraticaTimelineModel.swift`. The stub returns `[:]`.
- `BoardDragSnap` (new `Sources/Features/Workspace/BoardDragSnap.swift`), with
  `init(anchorID:anchor:others:)` and
  `snapped(translation:zoom:gridStep:) -> (translation: CGSize, guides: [BoardGeometry.Guide])`.
  The stub returns the translation unchanged and no guides.

Tests:

- `Tests/PraticaTimelineNextRowsTests.swift`, red: for empty, one, and many entries, filtered and
  unfiltered, the map equals a reference written in the test ("firstIndex + 1", today's
  `following(_:)`). The last entry has no successor.
- `Tests/BoardDragSnapTests.swift`, red: for anchor and candidate frames, zooms 0.5, 1 and 2, and
  grid on and off, the result equals `BoardGeometry.snapped(anchor.offsetBy(t), to: others, threshold: 6 / max(zoom, 0.01), gridStep:)`
  translated back to `snapped.minX - anchor.x` and `snapped.minY - anchor.y`, which is today's
  formula (`WorkspaceController+Gestures.swift:32-44`).

**Coder.**

- `Sources/Features/Pratiche/AttachmentChip.swift`:
  - `body` resolves the file state at most once per URL per body evaluation. Use a local per-body
    memo created at the top of `body`, or compute the state once and pass it. Either way, `symbol`,
    `label`, `isMissing`, `helpText`, `accessibilityText` and `.accessibilityActions` become
    functions of the resolved state.
  - No `@State` cache: it would outlive one body.
  - Action-time reads keep calling the live `state(_:)`: `preview`, the double-click
    `openWithDefaultApp`, `run`, and the `AttachmentChipMenuHost` `entries` closure (`:90`),
    evaluated when the menu opens.

  This is R-15, marked `(no-test:)` in the SPEC. The model stays pinned by `AttachmentChipTests`.
- `Sources/Features/Pratiche/PraticaTimelineView.swift`:
  - `body` reads `entries` (`:43`) once and passes the array to `list` (`:61`), `sections` (`:294`)
    and `empty` (`:218`);
  - `nextRows(in:)` is computed once per body and passed to `menu(for:)` (`:167`) and
    `insertHere(after:)` (`:183`);
  - `following(_:)` (`:195-200`) is deleted;
  - `toggle(_:expandsAll:)` (`:277`) runs at action time and keeps reading `entries` live.
- `Sources/Features/Pratiche/PraticaTimelineModel.swift`: `nextRows(in:)` body.
- `Sources/Features/Workspace/BoardContentLayer.swift`: per node,
  `let subfolder = workspace.subfolder(for: node)` once, passed to the accessibility summary (`:79`)
  and to `cardBody(_:subfolder:)` (`:230`). `WorkspaceController+Files.swift:99` `subfolder(for:)`
  is unchanged (PG-054).
- `Sources/Features/Workspace/BoardDragSnap.swift`: the `snapped` body, calling
  `BoardGeometry.snapped`.
- `Sources/Features/Workspace/WorkspaceController.swift:542`: `var dragAnchorID: String?` becomes
  `var dragSnap: BoardDragSnap?`, **one line for one line**. The class body is at 349 of the
  350-line `type_body_length` error.
- `Sources/Features/Workspace/WorkspaceController+Gestures.swift`:
  - `beginDrag` (`:13-20`) builds the snap once from `document.node(id:)` and the non-dragged
    frames, or `nil` when the anchor is absent;
  - `updateDrag` (`:24-45`) uses the snap, reads `zoom` and `snapsToGrid` live, and falls back to
    the raw translation when the snap is `nil`;
  - `endDrag` (`:48-58`) clears it.
- `Sources/Features/Workspace/WorkspaceController+Lifecycle.swift:49`: `dragAnchorID = nil` becomes
  `dragSnap = nil`, inside ADR-0066's reset door.

**Update tests and call sites asserting the old behaviour.** `rg -n "dragAnchorID" Sources Tests UITests`
at `3cdc97fb` finds `WorkspaceController.swift:542`, `WorkspaceController+Gestures.swift:17,26,52`
and `WorkspaceController+Lifecycle.swift:49`, and no test. `following(` and the chip's computed
properties are `private`, with no external caller.

**Verification:** the test command, including Task 1's drag, folder-after-load, `BoardInteractionTests`,
`WorkspaceEnterFolderTests`, `WorkspaceLifecycleTests`, `PraticaTimelineTests` and
`AttachmentChipTests`, and `swiftlint` on the touched files, with the `WorkspaceController` class
body at or under 350.

### Task 7 — Test-only items, then the whole-suite gate (R-19, R-20, R-21, R-22)

- **`Tests/SourceTreeSnapshot.swift` (new).**
  - One walk of `Sources/` per test process: a `static let` initialised once, built on
    `resolvedRepoRoot()` (`Tests/RepoRootSupport.swift`), holding a `Sendable` list of path and
    contents for each `.swift` file.
  - `SharedSourcesPurityTests`, `PlaudIsolationTests` and `PraticheIsolationTests` select their
    directories from it by path prefix instead of each running `FileManager.enumerator`.
  - Each keeps its own verdict logic unchanged, and `PraticheIsolationTests` keeps its
    `scannedAnyFile` expectation.
  - A small `SourceTreeSnapshotTests` asserts that the snapshot is non-empty.
  - Adding a positive count to the two guards that lack one is `PG-128`'s job and is not done here.
  - Run the three suites before and after: same verdicts (R-19).
- **`UITests/WorkspaceOpenStateUITests.swift`.**
  - `tree` (`:90-92`) is resolved once per assertion and passed to the selected-rows query
    (`:100-104`) and to `assertExactlyOneRowSelected` (`:116-124`).
  - `rootBoardRow` (`:81-84`) and `row(identifier:)` (`:86-88`) query inside the tree instead of
    `app.descendants(matching: .any)`.
  - For each identifier those helpers are called with, the coder first confirms, in
    `WorkspaceBrowser` and its row views, that the identifier is set on a row inside
    `workspace-tree`. An identifier that is not stays app-scoped.
  - No assertion changes. This is R-20, marked `(no-test:)`: it is itself a test.
- **`scripts/mcp-smoke.py:141`.** The list-building lambda becomes a named drain function that reads
  and discards each stderr line (`for _ in stream: pass`), still on a daemon thread. This is R-21,
  marked `(no-test:)`.
- **Whole-suite gate (R-22).**
  - The test command: the whole unit suite, not the new files alone.
  - Build `perg` and `pergamenum-mcp`.
  - `swiftlint lint`, compared with the baseline: no new `file_length` or `type_body_length`
    finding.
  - `scripts/uitests.sh --status`, then `scripts/uitests.sh --affected`. `classes_for_path` maps
    `Sources/Index`, `Sources/Vault` and `Sources/App` to ALL, so this runs the whole GUI bundle,
    about 25 minutes. `WorkspaceOpenStateUITests` and `WorkspaceIntegrationUITests` must be green.
    A red is diagnosed from the `.xcresult` before any rerun, and a `contaminated` verdict is rerun,
    not acted on.
  - `scripts/mcp-smoke.py` against a fresh `pergamenum-mcp` build.
  - `git fetch origin && scripts/check-adr-references.py`.
  - `git diff 3cdc97fb -- Tests UITests` shows no deleted test, no `.disabled`, no `XCTSkip` and no
    weakened expectation.

## Requirement coverage

| R-id | Tasks |
| --- | --- |
| R-01 | Task 1, Task 2 |
| R-02 | Task 1, Task 2 |
| R-03 | Task 2 |
| R-04 | Task 2 |
| R-05 | Task 2 |
| R-06 | Task 3 (no-test) |
| R-07 | Task 1, Task 3 |
| R-08 | Task 1, Task 3 |
| R-09 | Task 1, Task 4 |
| R-10 | Task 1, Task 4 |
| R-11 | Task 1, Task 5 |
| R-12 | Task 5 |
| R-13 | Task 1, Task 5 |
| R-14 | Task 1, Task 5 |
| R-15 | Task 6 (no-test) |
| R-16 | Task 6 |
| R-17 | Task 1, Task 6 |
| R-18 | Task 1, Task 6 |
| R-19 | Task 7 |
| R-20 | Task 7 (no-test) |
| R-21 | Task 7 (no-test) |
| R-22 | Task 7 |

## Risks

- **Equal-date message order (G3).** The whole of R-11's "same order as today" rests on today's
  ties coming out in `ROWID` order. Task 1 measures this before Task 5 writes the `ORDER BY`.
- **CRLF and Character semantics in the reducer.** The audit measured one CRLF divergence. The
  digests plus the CRLF, non-ASCII and whitespace variants are the guard, run before and after each
  of Task 4's two changes.
- **The `sharedSources` omission.** Forgetting `IndexSnapshot+TaskView.swift` breaks both tool
  builds, not the app. That is why Task 2's verification builds them, not only Task 7's.
- **SwiftLint budgets.**
  - The `WorkspaceController` class body is at 349/350: the drag swap must be one line for one
    line.
  - `IndexSnapshot.swift` is at 395/400: the task-view move lands in the same task as the stored
    list.
  - `HTMLTextReducer.swift` (501) and `MessageDocumentTests.swift` (430) are already over the
    warning: no growth.
- **Per-body memo in SwiftUI.** A local memo created inside `body` is correct only while it is not
  stored in `@State`. The reviewer checks that no disk-derived value moved into `@State` (ADR-0072
  §D7).
- **BoardTray now refreshes on every save.** This is the intended behaviour change. The cost is one
  filter per index change while a board is on screen.
- **The GUI run takes the machine for about 25 minutes** and launches the app repeatedly. The
  script refuses to run while a copy from `/Applications` is open. Tell Stefano before starting it.
- **Dependencies.** None external. SQLite is the system library. The bound-parameter limit (999
  before 3.32.0, 32766 after) and `sqlite3_trace_v2`'s event semantics were read on sqlite.org on
  2026-09-29. No provisioned resource, env var or port is needed.

## HITL gates

- Commit, push and merge. Every commit needs Stefano's approval. Merge only after Task 7's gate is
  green and G5 is rechecked.
- The ADR-0072 status flip to `accepted`, the first docs change after the merge, citing the PR and
  the merge commit.
- G1 and G2 are confirmed at review, G3 stops the chain if red, and G4 needs Stefano's decision.
- Named follow-ups (ADR-0072 §D11) are filed only with Stefano's OK:
  - TodayView on `taskGeneration`;
  - editor view blocks on `scanGeneration`;
  - the followed-conversations loop (if G4 is declined);
  - `PG-128`'s missing positive counts.
- No schema change, no data migration, and no file deletion. Only functions are deleted:
  `recipients(forConversation:)`, `following(_:)` and `dragAnchorID`.
