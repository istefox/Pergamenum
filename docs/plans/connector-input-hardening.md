# Plan: PG-256 / #570 (Audit Fable chain 3) and PG-151 / #280, connector input hardening

- **SPEC:** `SPEC.md` (Approved 2026-09-26), success criteria R-01…R-21. Its Decisions and
  Constraints are treated as settled. In four places this plan goes past the SPEC's letter. Each
  one waits on gate G1 below, and none is decided on Stefano's behalf.
- **ADR:** new, ADR-0063, at `docs/adr/0063-connector-input-hardening.md` (status: proposed).
  - `ROADMAP.md:410` sized this chain «S, no ADR».
  - An ADR is written anyway because the chain meets the override conditions, even though it
    fails the ordinary three-part test. The reasons:
    - it moves a security boundary: the dry-run lock and the vault boundary each reach a site they
      missed;
    - it writes the protected-interface line ADR-0041 proposed and left for later;
    - it makes two deliberate deviations that a later reader would be tempted to "fix": the app's
      board creations stay on the store, and the new door creates a missing folder where the store
      refuses;
    - it adds a precondition to a shared write door that the SPEC assumed already existed;
    - it records explicit no's: the journal never deletes, `limit` gets no upper bound, and 31
      residual sites are left for a follow-up.
- **Baseline:** written against `a6ce602`, which is both `HEAD` and `origin/main`. The tree is
  clean apart from `SPEC.md` and the new ADR. Every file:line below was read from that tree on
  2026-09-26.
- **UI budget:** zero GUI tests.
  - MCP acceptance goes through `scripts/mcp-smoke.py`.
  - Everything else is asserted in-process in `PergamenumTests`.

## Before `/build` (orchestrator; each item is a HITL point)

1. Run `tuist install` (once per fresh worktree), then `tuist generate --no-open`. Task 1 adds a
   test file, so run `tuist generate --no-open` again after it.
2. **Gate G1: approve ADR-0063.** Four points go past the SPEC and each needs its own answer.

   1. **§D4.5: a creation precondition on the `.canvas` write door.**
      - The SPEC says the session's existing `.canvas` door is enough. It is not.
        `VaultSession.writeFile` (`VaultSession+Journal.swift:199`) and
        `VaultDisk.writeFile(…journalDescriptor:journal:)` (`VaultDisk.swift:349`) have
        `expecting:` and nothing else, and `expecting:` cannot express "must not exist".
      - Without it, the SPEC constraint cannot be met: the check for a taken name must run on the
        same side of the suspension as the write.
      - Recommendation: approve. The change is one defaulted `expectingAbsent: Bool = false` on two
        functions, using ADR-0057 §D3's existence test. No existing caller changes: there are three
        in `Sources` and thirteen in `Tests`, and all keep the default.
   2. **§D4.7: the new door creates a missing parent folder.**
      - `createNote` does the same. `CanvasStore.createBoard` does not (ADR-0025 §D1).
      - Recommendation: approve. A connector's folder is typed text, and `create_note` into a new
        folder already works. The alternative needs `requiringExistingFolder:` on the `.canvas`
        door plus a second rehearsal check.
   3. **§D1.5: `ToolArguments.int` stops trapping on a JSON number outside `Int`'s range.**
      - Today `Int(number)` (`ToolArguments.swift:45`) kills the server on `1e300`, for `minutes`
        and `ordinal` too.
      - This fix is outside the R-ids.
      - Recommendation: approve. It is the same one-line conversion the new `limit` reader needs,
        in a function the task already edits, and the SPEC's objective is that no process dies.
   4. **§D1.6: `VaultSession.search` answers empty for `limit <= 0`.**
      - Today the loop appends a hit before it tests the limit (`VaultSession+Search.swift:30-35`),
        so `limit: 0` answers one hit. R-05 cannot pass without this fix.
      - Recommendation: approve. The fix goes in the session rather than in `VaultAPI`, because the
        bug is the session's. No app caller passes `0`; `VaultController+Search.swift:10-11`
        defaults to 200.

   If G1 refuses §D4.5, Task 4 loses its guard and R-13 is met by the filter alone. The plan would
   then record that as a named gap, rather than claim the constraint holds.
3. **Gate G2: the registry line (R-20).**
   - `.claude/protected-interfaces` is outside the architect's write scope, and `TODO.md:38`
     (`PG-151`) says the entry is an operator action.
   - The exact line is in ADR-0063 §D8.
   - In Task 7, either Stefano writes it, or the coder writes it once Stefano says so in the session.
   - If a hook refuses the write, the orchestrator hands the line to Stefano verbatim.
4. Commit, push and merge stay HITL at the end of `/build`. The pre-push guard (ADR-0061/0062) runs
   on push, if it is installed on this machine.

## Ownership and order

This is a compiled target. In each task the **tester** owns every signature the tests name, and the
**coder** owns the bodies.

**Within a task**, the tester's half lands first and must leave `Pergamenum`, `perg` and
`pergamenum-mcp` building. The new tests are then red on their assertions, except the ones marked
«green today», which are guards.

**Across tasks**, the order below is binding where one task depends on another:

- Task 3 needs Task 2's text rule.
- Task 5 needs Task 4's door.
- Task 6 comes after Task 4, because both edit `VaultSession+Notes.swift` and `CanvasStore.swift`.
- Tasks 1 and 2 are independent of the rest.

The tester may do several tasks' halves in one batch before the coder starts, as long as both rules
below hold.

**Rule 1: no test may trap the test host on today's code.**

- The `Stop` hook runs the whole `PergamenumTests` bundle every turn. A trap kills the bundle and
  hides every other result, which is worse than a red test.
- Only one such path exists in-process: `VaultAPI.journalLog(limit: -1)` on a vault whose state
  exists. It reaches `.suffix(-1)` (`VaultWrites.swift:340`).
- That single test is written in **Task 2's coder half, in the same commit as the guard**. Task 2's
  tester half still proves R-01 red, without trapping, by using a vault that was never opened.

**Rule 2: placeholder bodies never trap.** No `fatalError`, no `preconditionFailure`, no force
unwrap. A placeholder throws an ordinary error or returns an inert value.

---

### Task 1 — The flag parser refuses three shapes (R-08, R-09, R-10)

**Files:** `Sources/Connector/Arguments.swift`, new `Tests/ArgumentsTests.swift`.

#### Tester

1. Add `case flagTakesNoValue(String)` to `Arguments.ParseError`, with its description line (ADR-0063
   §D3 wording: `l'opzione --\(name) non vuole un valore`) and an `Equatable` conformance. Nothing
   produces the case yet.
2. Run `tuist generate --no-open`.
3. Write the new `Tests/ArgumentsTests.swift`. These are pure tests, with no vault.

| Test | Asserts | Today |
|---|---|---|
| `anOptionFollowedByAFlagIsAMissingValue` | `["note","new","T","--folder","--dry-run"]` throws `.missingValue("folder")` (R-08) | red |
| `anOptionFollowedByAnotherOptionIsAMissingValue` | `["--folder","--title","x"]` throws `.missingValue("folder")` | red |
| `aFlagSpelledWithAValueIsRefused` | `--dry-run=true` throws `.flagTakesNoValue("dry-run")` and `--json=1` throws `.flagTakesNoValue("json")` (R-09) | red |
| `aBareDoubleDashIsRefused` | `["note","--","x"]` throws `.unknownFlagSyntax("--")` (R-09) | red |
| `anEqualsValueMayStartWithDoubleDash` | `--title=--strange` gives `["title"] == "--strange"` (R-10) | green, pins |
| `aNegativeNumberIsAnOrdinaryValue` | `--limit -1` gives `["limit"] == "-1"` (R-10) | green, pins |
| `aTrailingOptionIsAMissingValue` | `["--folder"]` throws `.missingValue("folder")` | green, pins |
| `flagsAndOptionsStillParse` | `["note","new","T","--folder","A","--dry-run","--json"]` gives the words, `["folder"] == "A"` and both flags | green, positive control |

R-08's «performs no write» follows from the throw. Both entry points parse before any dispatch, and
the reviewer checks both:

- `Sources/CLI/main.swift:123-127` returns `.usage`;
- `Sources/MCPServer/main.swift:59-65` exits with 1.

#### Coder

`Arguments.init` implements ADR-0063 §D3 in this order:

1. a bare `--`;
2. `name=value`, checked against `flagNames`;
3. flags;
4. the value token, which must not begin with `--`.

Nothing else in the grammar changes. The single-dash rule for *words* (`:47-50`) stays.

**Done when:** the eight tests pass, all three schemes build, and the whole unit bundle is green.

### Task 2 — One `limit` rule in the shared layer, and `perg` (R-01, R-02, R-04, R-05)

**Files:**

- `Sources/Connector/VaultReads.swift`
- `Sources/Connector/VaultWrites.swift`
- `Sources/Vault/VaultSession+Search.swift`
- `Sources/CLI/Commands/JournalCommands.swift`
- `Sources/CLI/Commands/SearchCommands.swift`
- `Tests/ConnectorTests.swift`

#### Tester

Add two signatures in `VaultReads.swift`, inside `extension VaultAPI`, with no new source file:

- `static func checkedLimit(_ limit: Int?, named name: String = "limit") throws -> Int?`.
  Placeholder: returns `limit`.
- `static func limit(parsing text: String?, named name: String = "limit") throws -> Int?`.
  Placeholder: `text.flatMap(Int.init)`, which is today's lenient behaviour.

Both refusals must produce **one** sentence, built by one private builder, as a
`ConnectorError(…, usage: true)`.

The new tests go in `Tests/ConnectorTests.swift`. They use the file's existing fixtures, and the
journal tests mirror the one at `:223`.

| Test | Asserts | Today |
|---|---|---|
| `aNegativeLimitIsOneUsageSentence` | `checkedLimit(-1)` throws with `usage == true`, and the description names `limit` and `-1` | red |
| `unreadableLimitTextIsTheSameSentence` | `limit(parsing: "abc")` and `limit(parsing: "")` throw with `usage == true`; `limit(parsing: "-1")` reads `-1`; `limit(parsing: nil)` is `nil` | red |
| `journalLogRefusesANegativeLimitBeforeAnyDiskWork` | on a vault that was **never opened**, `journalLog(at:base:limit: -1)` throws the usage sentence, not «vault mai aperto» (R-01). It cannot trap today, because the state lookup throws first. | red on assertion |
| `searchRefusesANegativeLimit` | `VaultAPI.search(session, "Uno", limit: -1)` throws the same sentence as `checkedLimit(-1)` rather than returning `[]` (R-02) | red |
| `searchWithLimitZeroAnswersEmpty` | a query that matches returns `[]` at `limit: 0` (R-05) | red: one hit today |
| `journalLogWithLimitZeroAnswersEmpty` | after an armed write, `journalLog(limit: 0)` is `[]` (R-05) | green today, guard |

#### Coder

1. `checkedLimit` refuses values below 0. `limit(parsing:)` refuses any text `Int.init` cannot
   read, including `""`.
2. `VaultAPI.search` and `VaultAPI.journalLog` call `checkedLimit` as their first statement.
3. `VaultSession.search` gains `guard limit > 0 else { return [] }` next to its query guard at `:20`
   (ADR-0063 §D1.6, gate G1).
4. `JournalCommands.swift:19` and `SearchCommands.swift:13` read `--limit` through
   `VaultAPI.limit(parsing: arguments["limit"])`. This is R-04, checked by review only, because
   `perg` has no harness.
5. **In the same commit as the guard**, add `journalLogRefusesANegativeLimitOnAnOpenedVault`: after
   an armed write, `journalLog(limit: -1)` throws the sentence. This is the Rule 1 test.

**Done when:** the seven tests pass, the whole unit bundle is green, and all three schemes build.

### Task 3 — The MCP reader, the cursor, and a smoke stage (R-01, R-02, R-03, R-05, R-06, R-07, R-11)

**Files:**

- `Sources/MCPServer/ToolArguments.swift`
- `Sources/MCPServer/VaultHost.swift`
- `Sources/MCPServer/main.swift`
- `scripts/mcp-smoke.py`

`Sources/MCPServer` has no unit seam: it is excluded from the app target, and the MCP SDK is not
linked into it. The seam the SPEC names is `scripts/mcp-smoke.py`.

#### Tester

1. Add `func checkedInt(_ name: String) throws -> Int?` to `ToolArguments`. Placeholder: forwards
   to `int(name)`.
2. Make `VaultHost.resources(after:)` `throws`. The placeholder body is unchanged.
3. Change `main.swift:51` to `try await host.resources(after: parameters.cursor)`.
4. Add a new function `hardening(binary, vault, check)` to `scripts/mcp-smoke.py`, and append it
   **last** to the stage tuple in `main` (`:485`).
   - Placed last, a crash before the fix stops the run only after every other stage has reported.
   - `send()`'s own `sys.exit` is the crash assertion.
5. The stage builds the same pratica fixture as `pratiche_links` (`:361-369`), with the
   `PRATICA_NOTE` constant. It then runs these checks, in order:

| Check | Asserts | R |
|---|---|---|
| `journal_log` with `{"limit": -1}` | `isError`, and the text is the usage sentence | R-01 |
| `search_vault` with `{"query": "Nota", "limit": -1}` | `isError`, same sentence | R-02 |
| `search_vault` and `journal_log` with `"limit": "abc"` and with `"limit": ""` | `isError`, same sentence | R-03 |
| `search_vault` with `"limit": 1e300` | `isError`, and the next request answers | §D1 |
| `run_view` with `{"path": "Nota.md", "ordinal": 1e300}` | any answer, and the next request answers (no trap) | §D1.5 |
| `search_vault` and `journal_log` with `"limit": 0` | `[]` | R-05 |
| `resources/list` with `{"cursor": "-1"}`, then with `{"cursor": "abc"}` | `error.code == -32602` both times, and the `resources/list {}` that follows each has a `result` | R-06 |
| `resources/list` with `{"cursor": "100000"}` and with `{"cursor": "9223372036854775807"}` | `result.resources == []`, and no `nextCursor` | R-07, §D2 |
| `pratica_create_board` with `{"pratica": "Offerta", "name": "Preventivo"}` and no `dryRun` | `applied` is false, `note` contains `Preventivo.canvas`, and no `Preventivo.canvas` exists on disk | R-11 |
| the same call with `"dryRun": false`, then `journal_log` | the file exists, and the log has a row with that path, `created` true, and command `pratica_create_board` | R-12 |

#### Coder

1. `checkedInt` implements ADR-0063 §D1.4:
   - absent or `.null` returns `nil`;
   - `.int` returns the value;
   - `.double` is truncated by `Int(exactly: d.rounded(.towardZero))`, and refused when that is
     `nil`;
   - `.string` goes to `VaultAPI.limit(parsing:named:)`;
   - anything else is refused with the same sentence.
2. The `.double` case of `ToolArguments.int` uses the same non-trapping conversion, and returns
   `nil` when out of range (§D1.5, gate G1).
3. `search_vault` (`VaultHost.swift:82`) and `journal_log` (`:125`) read `limit` through
   `checkedInt`. `run_view` and `add_time_block` stay on `int`.
4. `resources(after:)` implements §D2:
   - a cursor that does not read as a non-negative integer throws `MCPError.invalidParams(…)`, with
     one sentence;
   - when `start >= notes.count`, it answers an empty page with no cursor, before any arithmetic;
   - `end = start + min(Self.pageSize, notes.count - start)`.

**Done when:** `scripts/mcp-smoke.py` passes every stage, `pergamenum-mcp` and `perg` build, and the
unit bundle is green.

### Task 4 — A creation precondition on the `.canvas` door, and `VaultSession.createBoard` (R-11, R-12, R-13)

**Files:**

- `Sources/Vault/VaultSession+Journal.swift`
- `Sources/Vault/VaultDisk.swift`
- `Sources/Vault/VaultSession+Notes.swift`
- `Sources/Vault/CanvasStore.swift`
- `Sources/Core/Vault/FolderIdentity.swift`
- `Sources/Vault/FolderFileOperations.swift`
- `Tests/VaultWriteAbsentPreconditionTests.swift`
- `Tests/VaultSessionJournalTests.swift`
- `Tests/VaultBoundaryCallSiteTests.swift`

`VaultSession+Notes.swift`, `VaultDisk.swift`, `CanvasStore.swift` and everything under
`Sources/Core/**` are in `sharedSources`, so `Project.swift` needs no edit.
`FolderFileOperations.swift` is app-only.

#### Tester

Signatures:

- **`VaultSession.writeFile(_:to:expecting:expectingAbsent: Bool = false)`** forwards the new
  argument.
- **`VaultDisk.writeFile(_:to:expecting:expectingAbsent: Bool = false, journalDescriptor:journal:)`**
  accepts the argument and ignores it (placeholder). The journal-less test overload at
  `VaultDisk.swift:322` is left alone.
- **`static func validate(_ name: String) -> [NoteName.Violation]` on `FolderName`**
  (`FolderIdentity.swift`).
  - Its body is moved **verbatim** from `FolderFileOperations.validate` (`:42-46`), and the old
    function becomes a one-line forwarder.
  - This is a pure move with no behaviour change, so the tester does all of it.
  - The callers, `WorkspaceFolderSheets.swift:28` and `FolderFileOperations.swift:66,179`, are
    untouched.
- **`CanvasStore.boardFilePath(named:in:)`** goes from `private` to `internal`, with no other
  change.
- **`VaultSession.createBoard(named: String, in parent: String) async throws -> String`**, in
  `VaultSession+Notes.swift`. Placeholder: `throw FileOperationError.failed("createBoard: non
  ancora")`.

Tests:

| File | Test | Asserts | Today |
|---|---|---|---|
| `VaultWriteAbsentPreconditionTests.swift` | `writeFileExpectingAbsentOverAnExistingFileRefuses` | armed session with `B.canvas` seeded: throws `VaultWriteRefusal.movedOn("B.canvas")`, bytes unchanged, no journal entry | red |
| `VaultWriteAbsentPreconditionTests.swift` | `writeFileExpectingAbsentOnAFreePathWrites` | the file is written and journalled with `textBefore == nil` | green today, guard |
| `VaultSessionJournalTests.swift` | `createBoardWritesTheStoresBytesAndJournalsACreation` | armed, with `journalCommand = "t"`: returns `"Preventivo.canvas"`; bytes equal `CanvasDocument.empty.encoded()`; one entry with `textBefore == nil` and command `t` (R-12) | red |
| `VaultSessionJournalTests.swift` | `createBoardOnARehearsalWritesNothing` | with `isDryRun = true`: returns the path, writes no file, adds no journal entry (R-11) | red |
| `VaultSessionJournalTests.swift` | `createBoardRefusesATakenNameOnARehearsalAndARealRun` | with `Preventivo.canvas` seeded: throws `CreationError.alreadyExists` in both modes, bytes unchanged, no entry (R-13) | red |
| `VaultSessionJournalTests.swift` | `createBoardRefusesAnInvalidName` | `"a/b"`, `"."`, `".."` and `""` each throw `CreationError.invalidTitle` | red |
| `VaultSessionJournalTests.swift` | `createBoardCreatesAMissingParentFolder` | `in: "Nuova/Sotto"` writes `Nuova/Sotto/X.canvas` (§D4.7, gate G1) | red |
| `VaultBoundaryCallSiteTests.swift` | `createBoardRefusesAParentEscapingTheVault` | `in: "../../fuori"` throws `VaultBoundary.Violation`, on a rehearsal and on a real run; nothing appears under `container/fuori` | red |

#### Coder

1. In `VaultDisk.writeFile(…journalDescriptor:journal:)`, add
   `if expectingAbsent, try fileExists(relativePath) { throw VaultWriteRefusal.movedOn(relativePath) }`.
   - It goes immediately before the byte write, and after the `expecting` check.
   - It reuses the actor's private `fileExists` (`:288`), per ADR-0057 §D3.
2. `createBoard` implements ADR-0063 §D4 steps 1 to 6, in this order:
   1. validate the name;
   2. spell the path through `CanvasStore.boardFilePath`;
   3. resolve it with `store.url(for:)`;
   4. check `exists` as a filter;
   5. call `writeFile(String(decoding: CanvasDocument.empty.encoded(), as: UTF8.self), to:,
      expectingAbsent: true)`;
   6. return the path.

   It does not rescan; the connector does that in Task 5.
3. The door's doc comment names the two deliberate differences from `CanvasStore.createBoard`
   (§D4.7 and §D5).

**Done when:** the eight tests pass, the unit bundle is green, and all three schemes build.

### Task 5 — The connector's «create and link» verbs adopt the door and name what they create (R-11, R-12, R-13, R-14)

**Files:** `Sources/Connector/VaultPraticheLinks.swift`, `Tests/PraticheLinksConnectorTests.swift`.

#### Tester

No new signature. The new tests go in the existing `VaultAPIPraticheLinksTests` suite and reuse
`openVaultWithOnePratica`.

- The journal is read back with `VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit:
  nil)`.
- Undo goes through `VaultAPI.undo(_:id:)` (`VaultWrites.swift:277`).

| Test | Asserts | Today |
|---|---|---|
| `aBoardRehearsalLeavesNoCanvasAndNoJournalEntry` | with `dryRun: true`: `applied` is false; `note` contains `Preventivo.canvas`; no file is written; `pratica.md` bytes are unchanged; the journal rows are unchanged (R-11) | red: the file is created |
| `aRealBoardCreationIsJournalledAndItsUndoIsDeclined` | with `dryRun: false` and command `pratica_create_board`: the file and the link are present; there is one row for `Preventivo.canvas` with `created` true and that command; `undo` on it throws a `ConnectorError` containing «ha creato»; the file still exists (R-12) | red: no row |
| `aTakenBoardNameIsRefusedBeforeAnyWrite` | with `Preventivo.canvas` seeded, on a rehearsal and on a real run: throws; `pratica.md` and the canvas bytes are unchanged (R-13) | green today, guard: the store refuses too |
| `eachCreateAndLinkSummaryNamesTheCreatedFile` | for each of the three verbs, as a rehearsal and then as a real run: `note` contains the created path (`Preventivo 2026.md` or `Preventivo.canvas`); encoding the `WriteSummary` yields no key outside `{path, applied, diff, note}` (R-14) | red: `note` is nil |

The three existing tests at `:182-229` stay as they are and must stay green.

#### Coder

1. `createAndLinkPraticaBoard` calls `session.createBoard(named:in: folder ?? "")`. It then calls
   `await session.rescan()` **only when `!session.isDryRun`** (checked by review, R-11), and then
   links.
2. Map the errors:
   - `VaultSession.CreationError` and `VaultBoundary.Violation` become `ConnectorError("\(error)")`;
   - `VaultWriteRefusal` becomes `«…» non è stato creato: \(refusal.description)`;
   - the `CanvasStore.StoreError` catch is removed.
3. All three verbs return the link's `WriteSummary`, with `note` set as ADR-0063 §D6 describes:
   - `creerebbe «path»` on a rehearsal, or `creato «path»` on a real run;
   - followed by `"; " + linkNote` when the link carried a note of its own.

   The two note verbs take the path from `createNote`'s `WriteResult.path`.

Call-sites of the three verbs (grep, 2026-09-26):

- `Sources/MCPServer/VaultHost+PraticheLinks.swift:49,60,81`
- `Sources/CLI/Commands/WriteCommands.swift:208,230,261`
- `Tests/PraticheLinksConnectorTests.swift:187,202,220`

None of them reads `note`. `perg` prints it as a line (`Sources/CLI/Writing.swift:23`). Nothing else
changes.

**Done when:** the four new tests and the three existing ones pass, the unit bundle is green, and
the smoke run's R-11 and R-12 checks pass.

### Task 6 — Five sites resolve through the boundary (R-15, R-16, R-17, R-18, R-19)

**Files:**

- `Sources/Vault/VaultSession+Notes.swift` (`importFile`, `:96-113`)
- `Sources/Vault/CanvasStore.swift` (`createFolder`, `:293-301`)
- `Sources/Vault/FolderFileOperations.swift` (`:387`, `:392`, `:440`)
- `Sources/Connector/VaultPratiche.swift` (`:187`)
- `Sources/Core/Conventions/Attachment.swift`
- `Sources/Features/Editor/NoteTextView+Embeds.swift` (`EmbedTable`)
- `Tests/VaultBoundaryCallSiteTests.swift`

#### Tester

One signature on `Attachment`: `static func resolve(_ target: String, nearNoteAt notePath: String,
within boundary: VaultBoundary) -> String?`. Placeholder: forwards to the existing form with
`inVaultAt: boundary.root`.

The new tests go in `Tests/VaultBoundaryCallSiteTests.swift`. Its private `CallSiteFixture` already
owns a directory outside the vault: `../../x` names `container/x`, and `../x` names
`container/level/x`.

| Test | Asserts | Today |
|---|---|---|
| `importFileRefusesANoteFolderEscapingTheVault` | `importFile(source, near: "../../fuori/n.md")` returns `nil`; `session.problems` gains one entry; nothing appears under `container/fuori` (R-15) | red: the copy lands outside |
| `canvasStoreCreateFolderRefusesANameEscapingTheVault` | `createFolder(named: "../../fuori", in: "")` and `createFolder(named: "x", in: "../..")` both throw `VaultBoundary.Violation`; neither directory exists (R-16) | red |
| `renameFolderRefusesADirectoryEscapingTheVault` | with `container/level/fuori/n.md` seeded, `renameFolder(at: "../fuori", to: "y", knownPaths: [])` throws; the directory and its file are still there; no `y` exists anywhere (R-17) | green today, guard: `isDirectory` refuses upstream (`:190`) |
| `trashFolderRefusesADirectoryEscapingTheVault` | same fixture: `trashFolder(at: "../fuori")` throws; the directory is still there (R-17) | green today, guard (`:432`) |
| `attachmentResolutionRefusesANoteFolderEscapingTheVault` | with `container/fuori/x.png` seeded, `resolve("x.png", nearNoteAt: "../../fuori/n.md", inVaultAt: root)` returns `nil` (R-18) | red: it answers `../../fuori/x.png` |
| `attachmentResolutionFromAnEscapingNoteProbesNothing` | with `vault/x.png` also seeded, both the `inVaultAt:` and `within:` forms still return `nil`. The escaping folder must short-circuit before any probe, including the root probe and the by-name search (R-18, «probes nothing outside») | red: it answers `x.png` |
| `attachmentResolutionWithinABoundaryMatchesTheRootForm` | for an ordinary note, both forms return the same path in the beside, root and by-name cases | green today, guard |

The eleven existing calls in `Tests/AttachmentTests.swift` must stay green, unchanged.

#### Coder

1. **`importFile`.**
   - An empty folder means `store.root`. Otherwise, call `try store.url(for: folder)` **before**
     `ImportNaming.uniqueFileName` probes the directory.
   - A violation records a problem and returns `nil`.
   - `importPastedImage` inherits the fix, because it calls `importFile`.
2. **`CanvasStore.createFolder`:** `let directory = try boundary.url(for: relativePath)`.
3. **`FolderFileOperations`.**
   - Both ends of the move, and the trash target, go through `try store.url(for:)`.
   - This is defence in depth: the ADR-0063 Context section explains why these paths are already
     gated upstream.
   - The existing error mapping in the `do` block stays.
4. **`VaultAPI.timeline(ofPraticaFolder:)`:** `guard let directory = try? session.store.url(for:
   folder) else { return [] }`. This is R-19, checked by review only.
5. **`Attachment`,** as in ADR-0063 §D7:
   - the implementation moves into the `within:` form;
   - when the note's folder is not empty it must resolve, otherwise return `nil` without probing
     anything;
   - `exists` probes only through `boundary.url(for:)`;
   - `byName` walks `boundary.root` and drops its own `resolvingSymlinksInPath`;
   - `inVaultAt:` becomes a one-line wrapper that builds one `VaultBoundary`.
6. **`EmbedTable`.**
   - It holds one `VaultBoundary`, memoised by root, and calls the `within:` form from
     `resolvedPath(for:notePath:root:)`.
   - `apply(runs:…)` gets **no** new parameter: it is already at SwiftLint's parameter-count cap
     (see its own comment).
   - Checked by review only: no symlink resolution is added on the keystroke path.

**Done when:** the seven tests pass, `AttachmentTests` is unchanged and green, the unit bundle is
green, and all three schemes build.

### Task 7 — Records and verification (R-04, R-19, R-20, R-21)

**Files:** `.claude/protected-interfaces` (gate G2), `CLAUDE.md`, `TODO.md`,
`docs/adr/0063-connector-input-hardening.md`.

1. **R-20.** After gate G2, add the line from ADR-0063 §D8 to `.claude/protected-interfaces`,
   verbatim.
2. **`CLAUDE.md`.** Add ADR-0063's chain-index entry, using the text proposed in the ADR, after the
   ADR-0062 line. Set ADR-0063's status to accepted, and add implementation notes for any departure
   `/build` made.
3. **At ship, after merging `origin/main` into the branch:**
   - close `PG-256` (`TODO.md:9`) and `PG-151` (`TODO.md:38`), naming this PR on both;
   - **R-21:** file one follow-up under the next free `PG-` id. It must contain:
     - the residual count, re-measured with `rg -n "root\.appending\(path:" Sources | wc -l`, and
       the files it spans. Expect 31 lines in 21 files;
     - the three heaviest `FileManager.default` concentrations, re-counted with
       `rg -c "FileManager\.default" Sources`. Expect `PraticaFileOperations.swift` (11),
       `VaultDisk.swift` (10) and `CanvasStore.swift` (7);
     - the other items named in ADR-0063 §D9.
4. **Review checklist.** Nothing tests these, so the reviewer checks each by reading the code:
   - R-04: `perg`'s two `--limit` reads;
   - R-19: the timeline site;
   - R-11: a rehearsal skips the rescan;
   - the `EmbedTable` memo;
   - R-08: both entry points parse before they dispatch;
   - `Sources/Core` and `Sources/Connector` still import no SwiftUI.
5. **Verification.**
   - Build `Pergamenum`, `perg` and `pergamenum-mcp`.
   - Run the **whole** `PergamenumTests` bundle, not only the touched files. The limit rule, the
     parser and the write door are shared contracts.
   - Run `scripts/mcp-smoke.py` against the freshly built `pergamenum-mcp`.
   - Run SwiftLint on the touched files. `VaultDisk.swift` is already past the 400-line warning; do
     not split it in this chain, and report any new error instead.
   - Run `scripts/uitests.sh --affected` at merge, as `CLAUDE.md` requires. This chain touches no
     view, so it should select nothing.

**Done when:** every item above is done, or handed to Stefano with its exact text.

---

## Requirement coverage

| R | Task(s) | Verified by |
|---|---|---|
| R-01 | 2, 3 | `ConnectorTests` (a vault never opened, and an opened one); smoke `journal_log -1` |
| R-02 | 2, 3 | `ConnectorTests.searchRefusesANegativeLimit`; smoke |
| R-03 | 2, 3 | `ConnectorTests.unreadableLimitTextIsTheSameSentence` (the text rule); smoke `"abc"` and `""` |
| R-04 | 2, 7 | review (no test: no CLI harness) |
| R-05 | 2, 3 | `ConnectorTests` (both reads at `0`); smoke |
| R-06 | 3 | smoke (`-32602`, then the next request answers) |
| R-07 | 3 | smoke (past the end, and `Int.max`) |
| R-08 | 1 | `ArgumentsTests`, plus review of the two entry points |
| R-09 | 1 | `ArgumentsTests` |
| R-10 | 1 | `ArgumentsTests` |
| R-11 | 3, 4, 5 | `VaultSessionJournalTests`, `PraticheLinksConnectorTests`, smoke with the default `dryRun`; the no-rescan part by review |
| R-12 | 3, 4, 5 | `VaultSessionJournalTests`, `PraticheLinksConnectorTests` (entry and declined undo), smoke |
| R-13 | 4, 5 | `VaultSessionJournalTests`, `PraticheLinksConnectorTests` |
| R-14 | 5 | `PraticheLinksConnectorTests.eachCreateAndLinkSummaryNamesTheCreatedFile` |
| R-15 | 6 | `VaultBoundaryCallSiteTests` |
| R-16 | 6 | `VaultBoundaryCallSiteTests` |
| R-17 | 6 | `VaultBoundaryCallSiteTests` (already green; see Departures) |
| R-18 | 6 | `VaultBoundaryCallSiteTests` |
| R-19 | 6, 7 | review (no test: its folder comes from the index) |
| R-20 | 7 | review of the registry line and of `TODO.md` (no test) |
| R-21 | 7 | review of the ledger entry (no test) |

## Departures / open points

Each item says how it is handled: in this plan, at a gate, or named and left unfixed.

1. **The `.canvas` door had no creation precondition.** The SPEC's «the existing door suffices»
   does not hold (ADR-0063 Context). Task 4 adds `expectingAbsent:`. Decided at **gate G1**.
2. **The new door creates a missing parent folder.** `CanvasStore.createBoard` does not, but the
   SPEC's own note precedent does (ADR-0063 §D4.7). Decided at **gate G1**.
3. **Search with `limit: 0` answers one hit today**, not none (`VaultSession+Search.swift:30-35`).
   R-05 depends on the §D1.6 fix. Decided at **gate G1**.
4. **`ToolArguments.int` traps on `1e300`**, for `minutes` and `ordinal` too. This is outside the
   R-ids. The plan fixes it in Task 3 (§D1.5). Decided at **gate G1**.
5. **An `Int.max` cursor overflows** at `start + pageSize` (`VaultHost.swift:279`). The SPEC names
   only negative and non-numeric cursors. The fix is in the same site and the same task (§D2), so it
   adds no scope.
6. **R-17 is already refused upstream.**
   - `renamePlan` and `trashFolder` call `isDirectory` first (`FolderFileOperations.swift:190,432`),
     and `isDirectory` resolves through `store.url(for:)`.
   - So the SPEC's edge case «today the path reaches the move» does not hold.
   - The site change is defence in depth. Its tests are green before and after, and the reviewer
     verifies the three lines.
7. **The SPEC's «thirty-eight residual sites» include the five sites this chain fixes.** Today
   `rg -n "root\.appending\(path:" Sources` gives 38 lines in 25 files; afterwards, about 31 in 21.
   R-21 records the count re-measured at ship, not the SPEC's number.
8. **The folder-name rule moves to `Sources/Core`** (`FolderName.validate`). The connector door
   needs it, and `FolderFileOperations.swift` is not a shared source. It is a pure move with a
   forwarder, and no caller changes.
9. **Seam file.** SPEC seam 5 names the canvas-store and folder-operation test files. Tasks 4 and 6
   use `Tests/VaultBoundaryCallSiteTests.swift` instead, as «the nearest existing sibling» the SPEC
   allows: its private fixture already owns a directory outside the vault, and the other two files
   do not have one.
10. **`ROADMAP.md:410` sized the chain «S, no ADR».** An ADR is written anyway, for the reasons in
    the header.
11. **ADR number collision.** `ROADMAP.md:947` (Chain 14, item 2) plans to renumber one of the two
    `0061` ADRs to `0063`. This chain takes `0063`, so Chain 14 must pick the next free number when
    it runs. Recommendation: note this on Chain 14's ledger entry at ship.
12. **`TODO.md:9` gives the reproduction as `perg journal list --limit -1`.** The command is
    actually `perg journal log`; `journal list` is refused as an unknown subcommand
    (`JournalCommands.swift:8-11`). Harmless, no action needed.
13. **A behaviour change worth a line in the PR description.** `pergamenum-mcp --vault
    --allow-write` used to open a vault named `--allow-write`, read-only. It now refuses to start
    (§D3).
14. **Named in ADR-0063 §D9, and not fixed here:**
    - `createNote`'s check for a taken name has no in-actor guard;
    - `perg --ordinal` and `--minutes` still fall back to a default on unreadable text;
    - `--=value` still parses;
    - `unlinkedMentions(limit: 0)` returns one result;
    - a board or folder name starting with a dot becomes a hidden file;
    - the connector's own `praticaLinks` and `praticaNotes` root appends
      (`VaultPraticheLinks.swift:43`, `VaultPratiche.swift:110`), which are part of the 31.

## Risks and HITL gates

- **HITL gates.**
  - **G1:** ADR-0063, the four points above.
  - **G2:** the registry line.
  - **Commit, push and merge.**
  - **R-21's ledger entry**, written at ship with a re-measured count.
- **A trap in the test host.** See Rule 1 above. If a batch ever lands `journalLog(limit: -1)` on an
  opened vault before the guard, the run started by the `Stop` hook dies and hides every other
  result. Read the `.xcresult` rather than rerunning.
- **Shared sources.**
  - `VaultSession+Notes.swift`, `VaultDisk.swift`, `CanvasStore.swift`, `FolderIdentity.swift`,
    `Attachment.swift` and everything in `Sources/Connector` compile into `perg` and
    `pergamenum-mcp`.
  - A SwiftUI import in any of them breaks both tool builds (ADR-0001 §D1).
  - All three schemes are built as part of every task's «done».
- **The editor path.**
  - `Attachment` sits on the keystroke path. The `within:` form and the memoised boundary exist so
    the change adds no `resolvingSymlinksInPath` there.
  - If `/build` finds the memo awkward, it must not fall back to building a boundary per call from
    `EmbedTable`. It reports instead.
- **A smoke side effect, which exists already.** The `journal_log` and write stages resolve state
  for the throwaway vault under the real
  `~/Library/Application Support/it.stefer.pergamenum/vaults/<id>/`. The `writing` stage already
  does this; this chain adds nothing new there.
- **Contract changes and their call-sites** (grep run 2026-09-26):

| Contract | Call-sites | Effect |
|---|---|---|
| `Arguments(` | `Sources/CLI/main.swift:124`, `Sources/MCPServer/main.swift:61` | parse errors now cover three more shapes |
| `resources(after:` | `Sources/MCPServer/main.swift:51` | becomes `try` |
| the three create-and-link verbs | listed under Task 5 | none reads `note` |
| `journalLog(` | `VaultHost.swift:124`, `JournalCommands.swift:16`, `ConnectorTests.swift:223,236,256,271`, `CaptureTests.swift:203,232` | all pass `limit: nil`; none changes |
| `writeFile(` | `VaultSession.swift:674`, `VaultSession+Journal.swift:218,335`, and 13 test call-sites | all use the default; none changes |
| `CanvasStore.createFolder` | `FolderFileOperations.swift:68`, `CanvasTests.swift:156,170,185`, `FolderFileOperationTests.swift:115,153` | none passes an escaping path, so each keeps its current outcome |

  Run the **full** unit bundle after the change, not only the touched files.
- **No external service or provisioned resource is needed.** The MCP SDK stays at 0.12.1
  (`Tuist/Package.resolved`). `MCPError.invalidParams` was checked in the installed checkout.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

This is `.claude/test-cmd`, unchanged. The `Stop` hook runs the test command every turn, so it must
stay on `PergamenumTests`. The smoke run, the two tool builds and `scripts/uitests.sh --affected`
are acceptance steps in Task 7, not part of it.
