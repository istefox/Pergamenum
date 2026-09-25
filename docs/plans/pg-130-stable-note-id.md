# Feature: a stable note id that `pergamenum://note?id=` can answer (PG-130 / #230)

No `SPEC.md` governs this task. The `SPEC.md`, `BRAINSTORM.md` and `UX-BLUEPRINT.md` at the repo
root belong to an unrelated feature. They are **not** inputs to this chain. There are no R-ids.
Instead, each task names the scope item of the brief it answers (S1–S6, in the table below).

This plan was read from the worktree `Pergamenum-230-pg-130-fix-notestate-noteids-c08eafa6` at
`48ca1b5d`, with a clean tree. Every line number and call-site list below was grepped in that tree,
not taken from the ticket.

## Settled before this plan, registered and not reopened

- **Stefano's decision:** implement a real stable id, and keep the route.
- **Stefano's decision:** the id survives every rename and move the app performs, and may break only
  on a rename or move made outside the app.
- **SPEC §9 and §14, and ADR-0001 §D2:** the id is not in the frontmatter, because the closed
  4-key schema (F-02) forbids it. It is stable until the file is renamed outside the app.
- **CLAUDE.md principle 3, SPEC §12, and ADR-0001 §D2 rules 1-2:** the index can always be rebuilt,
  and deleting it loses nothing.
- **ADR-0017 §D1:** a fact about the vault lives in the vault, and a fact about one machine lives in
  that machine's state directory.
- **ADR-0012 §D6 and ADR-0047 §D2** set the shapes of `starred.json` and `categories.json`.
- **ADR-0052:** a store held in memory must know what it was read from.
- **ADR-0007 §D2:** a file in `sharedSources` is listed by hand.
- **ADR-0051:** one shared test helper per concern.
- **`IndexCache.schemaVersion` is a protected interface.**

## Before `/build`: three HITL gates, answered first

The ADR records the reasons for each gate. The plan below assumes the recommended answer to every
one. **A different answer to gate A or gate B means this plan is re-planned before Task 1.** Do not
improvise around it.

- **Gate A: accept the design's departure from the brief's steps 1, 2 and 4.**
  - The id lives in `.pergamenum/note-ids.json`, not in `StoredRecord`, and there is no
    `schemaVersion` bump.
  - It is minted when a link is copied, not at first indexing.
  - The route reads through to the session, rather than keeping a filled `RouteState.noteIDs`.

  ADR-0059's Context measures why an index field cannot meet the persistence decision: a rescan
  after every in-app rename, a cache dropped by «Svuota cache», by a bump and on every other Mac,
  and the fact that principle 3 would stop being true. **Recommended: accept.**
- **Gate B: what «Copia link Pergamenum» copies.**
  - Option 1 (recommended): it copies the id link from now on (ADR-0059 §D8). This changes the
    clipboard contract and the existing test `RowCommandTests.swift:94-105`.
  - Option 2: a second command copies the id link, and the current one stays as it is (Alternative
    10).

  This is a preference, not a fact. Option 1 is recommended because the links SPEC §9 exists for
  are exactly the ones an in-app rename breaks today.
- **Gate C: are the Pratiche follow calls (Task 4) in this chain or split into their own?**
  - Recommended: in this chain. The change is two call sites and one test, and a message note's id
    otherwise breaks the first time it is moved with «Sposta in…».
  - If split, test 25 and Task 4 move to a follow-up ticket, and ADR-0059 §D5's last table row is
    marked as deferred in that ticket.

**Branch state.** `git log HEAD..origin/main` is empty against the local ref, which was not fetched
while this plan was written. Check it again before `/build`. `Pergamenum.xcworkspace` was generated
in this worktree on 2026-09-25 (`tuist install && tuist generate --no-open`), after this plan was
first drafted; it now exists. Run `tuist generate --no-open` again after Task 1 regardless, since
Task 1 adds `sharedSources` entries and new test files.

## ADR outcome: new ADR, `docs/adr/0059-note-ids-live-in-a-vault-registry.md`

The ADR is written with status `proposed`. It is accepted when this branch merges.

**Path deviation, stated rather than taken silently.** The architect's write scope names
`docs/architecture/**`, but that directory does not exist in this repo. Every ADR lives at
`docs/adr/NNNN-<slug>.md`, and CLAUDE.md's chain index links them there. The plans for ADR-0054,
ADR-0055 and ADR-0058 recorded the same deviation.

**Why an ADR is needed.** All three significance criteria hold:

- **Hard to reverse.** The `note-ids.json` format and the `note?id=` links pasted into other apps
  outlive any refactor.
- **Surprising without context.** A reader of SPEC §9 ("registrato nell'indice") would expect an
  index column and "fix" it back into one.
- **A real trade-off.** There were ten real alternatives, including a frontmatter key that would
  also survive a rename outside the app.

Several overrides apply as well:

- It sits on a security boundary: a hand-editable path is fed to `VaultBoundary`.
- It deliberately departs from the ticket's framing.
- It records explicit "no"s: no minting at index time, no copy in memory, no guessing after a
  rename outside the app, and no id exposed through the connectors.
- It amends ADR-0001 §D2 and two SPEC rows.

## The scope items of the brief, and how this plan answers each

| Label | Brief scope item | Answered by |
|---|---|---|
| **S1** | "Add an id field to `StoredRecord`, bump `schemaVersion`." | **Changed at gate A.** The id is stored in `NoteIDRegistry`/`NoteIDStore` (`.pergamenum/note-ids.json`), with no index change and no bump (ADR-0059 §D1, §D3). Tasks 1-2. |
| **S2** | "Generate the id once, at first indexing." | **Once, when a link is first copied** (§D2): one door, never regenerated. Tasks 1-2. |
| **S3** | "Investigate rename/move and carry the id." | Investigated: ADR-0059 Context, "the inventory". Carried at every door (§D4, §D5, §D6). Tasks 3-4. |
| **S4** | "Populate `RouteState.noteIDs` from the snapshot." | **Changed at gate A.** `RouteState.noteIDs` is deleted and the route reads through the session (§D7). Task 5. |
| **S5** | "An id builder on `PergamenumLink`, wired to a copy-link command." | `PergamenumLink.note(id:)`, and «Copia link Pergamenum» goes through `VaultController.pergamenumLink(toNoteAt:)` (§D8, gate B). Task 6. |
| **S6** | "Regression tests: end to end through `handle(_:)`, and the id survives a rename." | ADR-0059 Acceptance 1-34, written red in Task 1. The end to end tests are 26-28 and 32, and the rename tests are 15, 21 and 27. Proven in Task 7. |

## How the work is split between tester and coder

Swift is compiled and type-checked, so **the tester owns every new signature and the coder owns
the bodies**. After Task 1, all three schemes **build**. The new tests are **red on their
assertions**, not red because the build failed. While Task 1 is red, `.claude/test-cmd`'s Stop hook
reports red at the end of each turn. That is expected and does not mean anything regressed.

---

### Task 1: Tester. Signatures, 34 tests, and the staleness sweep (S1-S6 acceptance)

**Files: declarations** (stub bodies unless stated otherwise)

- `Sources/Core/Conventions/VaultLayout.swift`: add `static let noteIDsFile = "note-ids.json"`.
  This is the real value, not a stub. Give it a doc comment in the form of `categoriesFile`'s:
  in the vault because an id names a note on every Mac, and it is not an index (ADR-0059 §D1).
- **New** `Sources/Core/Vault/NoteIDRegistry.swift`:

  ```swift
  struct NoteIDRegistry: Codable, Equatable, Sendable {
      static let currentVersion = 1
      static let empty = NoteIDRegistry(version: currentVersion, notes: [:])
      var version: Int
      var notes: [String: String]          // lowercase id -> vault-relative path
      static func makeID() -> String       // stub: ""
      func path(forID id: String) -> String?     // stub: nil
      func id(forPath path: String) -> String?   // stub: nil
      func assigning(_ id: String, to path: String) -> NoteIDRegistry   // stub: self
      func relocating(_ moves: [MovedNote]) -> NoteIDRegistry           // stub: self
      func removing(_ paths: [String]) -> NoteIDRegistry                // stub: self
  }
  ```

  The stored properties and the synthesized `Codable` are real. They **are** the version-1 format
  (§D1), which is what the tester owns.
- **New** `Sources/Vault/NoteIDStore.swift`, in the shape of `CategoryRegistryStore`:
  - `enum LoadedState: Equatable { case absent, loaded, malformed, evicted }`;
  - `let file: URL`;
  - `init(root: URL)`, which is real and builds `.pergamenum/note-ids.json`;
  - `func load() -> (registry: NoteIDRegistry, state: LoadedState)`, stubbed to `(.empty, .absent)`;
  - `@discardableResult func save(_ registry: NoteIDRegistry) -> String?`, stubbed to `nil`
    without writing.
- **New** `Sources/Vault/VaultSession+NoteIDs.swift`:
  - `enum NoteIDLookup: Equatable, Sendable { case found(String), unknown, unreadable }`, nested in
    `VaultSession`;
  - `var noteIDStore: NoteIDStore { NoteIDStore(root: root) }`, which is real;
  - `func lookUpNote(id: String) -> NoteIDLookup`, stubbed to `.unknown`;
  - `func mintNoteID(for relativePath: String) -> String?`, stubbed to `nil`;
  - `func relocateNoteIDs(_ moves: [MovedNote])` and `func forgetNoteIDs(_ paths: [String])`, both
    with empty bodies.

  All of these are synchronous and `@MainActor`, as the extension inherits.
- `Sources/Core/URLScheme/PergamenumURL.swift`: `static func note(id: String) -> URL?`, stubbed to
  `nil`, directly below `note(path:)` (`:116-118`).
- `Sources/App/VaultController+Routes.swift`: `func pergamenumLink(toNoteAt path: String) -> URL?`,
  stubbed to return `PergamenumLink.note(path: path)`, which is today's behaviour.
- `Project.swift`, in `sharedSources`: add `"Sources/Vault/NoteIDStore.swift"` and
  `"Sources/Vault/VaultSession+NoteIDs.swift"`, with one comment in the form of `:105-109` naming
  ADR-0059 §D9. Both are required: `VaultSession+Journal.swift` (`:134`) calls the doors from Task 3
  on. Then run `tuist generate --no-open`.
- **`Sources/Vault/VaultSession.swift` is not touched** (§D3). The store is a computed property in
  the new extension.

**Files: tests**

- **New** `Tests/NoteIDRegistryTests.swift`: tests 1-11.
- **New** `Tests/NoteIDFollowTests.swift`: tests 12-25. Test 25 moves out if gate C splits it.
- **New** `Tests/NoteIDRouteTests.swift`: tests 26-31.
- `Tests/RowCommandTests.swift`: update test 32 (`runningCopyLinkOnAClosedRowOpensItThenPutsItsLinkOnThePasteboard`,
  `:94-105`) and add test 33. They stay in this file because it owns the private
  `makeActions(vault:)` helper (`:22-40`). A second copy of that helper in a new file is what
  ADR-0051 forbids.
- `Tests/URLSchemeTests.swift`: add test 34 next to `buildsLinksThatParseBackToTheSameRoute` (`:79`).
- Run `tuist generate --no-open` again for the three new test files.

**How to write them.** Use the shapes already in use:

- A session opened directly: `VaultSession(root: vault.root, stateBase: vault.stateBase)`
  (`Tests/StarredTests.swift:28`).
- A controller:
  1. `VaultController(recents: .volatile(), openTabs: .volatile())`;
  2. `await controller.open(vault.root)`;
  3. `await controller.handle(…)`;
  4. `controller.close()`.

  See `Tests/URLSchemeTests.swift:116-140`.
- The connector: `VaultAPI.arm`, `VaultAPI.renameNote` and `VaultAPI.undo`, as in
  `Tests/ConnectorTests.swift`.
- Pratiche: `PraticheController(probe: { .granted }, performSync: { _, _ in })`
  (`Tests/PraticaLiveSyncRelocatedMidRunTests.swift:76`), and `PraticaRowDetail(notePath:…)`
  (`Tests/PraticaLinkAggregationTests.swift:22`).
- Registry fixtures are written as literal JSON with
  `vault.write(json, to: ".pergamenum/note-ids.json")`.

Test-specific notes, so that no test passes by accident against a stub:

- **Tests 8 and 9 split the format pin.**
  - Test 8 decodes the literal version-1 JSON and re-encodes it **inside the test** with the
    store's settings (`JSONEncoder`, `[.prettyPrinted, .sortedKeys]`), then compares bytes. It pins
    the `Codable` shape and is green at Task 1.
  - Test 9 checks that `NoteIDStore.save` writes exactly those bytes. It is red until Task 2.
- **Keeping-in-step tests (15-25) assert on the file itself.** Decode it with `JSONDecoder` into
  `NoteIDRegistry`, whose `Codable` is real at Task 1. **Do not** read it through
  `NoteIDStore.load()` or `lookUpNote`: those are stubs that answer "empty" and "unknown", and test
  17 ("the trash forgets") would then pass before any code exists.
- **Route tests 27-31 obtain their id without Task 6.** They use a seeded file or
  `controller.session?.mintNoteID(for:)`. Only test 26 goes through `pergamenumLink(toNoteAt:)`.
  Task 5 can then turn them green on its own.
- **Test 27** calls `await controller.renameNote(at:to:)` and then an explicit
  `await controller.rescan()`, before `handle`. The facade starts its own rescan in an unstructured
  `Task` (`VaultController+Files.swift:52-55`), and the test must not race it.
- **Test 18** seeds an entry for `P/gone.md` with no file behind it, which stands in for an evicted
  note. It asserts that the entry moves with the folder (§D4, last bullet).
- **Test 24** opens two `VaultSession`s on one root and the same `stateBase`, the way the app and a
  connector share a vault.
- Messages are asserted by outcome and by the id or path appearing in `problems`, never by exact
  wording (§D7).
- No test uses a timer, a sleep or a gate.

**Staleness sweep: update the tests and call sites that assert the old behaviour.** Three
observable contracts change:

1. what «Copia link Pergamenum» puts on the clipboard;
2. how the `.noteID` route resolves, and what it reports;
3. what `VaultSession.moveFile`/`trashFile` and the folder doors do besides moving, in shared code.

A whole-repo grep, done while writing this plan, found:

- **The clipboard contract:**
  - the handler is `CommandActions.swift:203-204,366-370`;
  - it is invoked from `VaultCommands.swift:121-123` (menu bar and Cmd+Shift+L) and from
    `NoteRowMenu.swift:53` (row menu);
  - `RowCommandTests.swift:94-105` asserts the old string, and is **the one existing test that
    changes**, updated as test 32, for the reason in ADR-0059 §D8 and only after gate B;
  - `RowCommandTests.swift:145-150` and `CommandActionTests.swift:48` check `canRun` only and do
    not change;
  - `CardCommand.copyLink`, `BoardCardMenu.copyLink(to:)` (`:155`) and every `CardCommandTests`
    line are the canvas card's own command, and are unaffected;
  - `rg copyLink UITests` returns nothing;
  - two comments become false and are corrected in Task 6: `Sources/MCPServer/VaultHost.swift:271-273`
    and `Sources/CLI/Commands/AppCommands.swift:10-11`.
- **The path-link builder, unchanged on purpose:**
  - `AppCommands.swift:60`, `VaultHost.swift:282`, `ReminderScheduler.swift:164`;
  - `URLSchemeTests.swift:81,98,99`;
  - `scripts/mcp-smoke.py:466`, which checks `note?file=` resource URIs.
- **`RouteState.noteIDs`:** only `VaultController+Routes.swift:54,155`. No test reads it.
- **The `.noteID` handling:** no existing test. `URLSchemeTests.swift:9` only parses the route.
- **`VaultSession.moveFile`/`trashFile`:** called from `VaultSession+Files.swift:28,58,78` and
  `+Journal.swift:320`. No existing test asserts on the contents of `.pergamenum/`. The one that
  checks `.pergamenum/` is absent (`VaultStateTests.swift:30-38`) opens no session, and §D3's
  "unchanged writes nothing" rule keeps it true anyway.

If an existing test other than test 32 turns red for any reason, **stop and report it. Do not edit
it to make it pass** (CLAUDE.md).

**Done when**

- `Pergamenum`, `perg` and `pergamenum-mcp` all build.
- Tests 8, 13, 14, 22 and 29 are green. Tests 8 and 29 pin behaviour that is already right, and
  13, 14 and 22 are negative controls that no stub can fail.
- Every other new or updated test is red on an assertion.
- Every other existing `PergamenumTests` test is green.

---

### Task 2: Coder. The registry, the store, and the session doors (S1, S2)

**Files:** `Sources/Core/Vault/NoteIDRegistry.swift`, `Sources/Vault/NoteIDStore.swift`,
`Sources/Vault/VaultSession+NoteIDs.swift`.

- **`NoteIDRegistry`** (§D1, §D4):
  - `makeID()` returns `UUID().uuidString.lowercased()`.
  - Lookups lowercase their input.
  - `assigning` keeps one id per path.
  - `relocating` first drops the entries at and under each destination, then rewrites the exact
    and prefix matches of `old`.
  - `removing` drops exact and prefix matches.
  - Paths are trimmed of `/`, an empty path matches nothing, and prefixes are compared with
    `+ "/"`.
- **`NoteIDStore`** (§D3):
  - `load()` distinguishes four states:
    - `absent`: neither `note-ids.json` nor `.note-ids.json.icloud` exists;
    - `loaded`;
    - `malformed`: undecodable, or `version != currentVersion`;
    - `evicted`: only the placeholder exists.
  - `save` copies `CategoryRegistryStore.save`: create the directory, use
    `[.prettyPrinted, .sortedKeys]`, write `.atomic`, and return a problem string rather than
    throwing.
- **Session doors** (§D2, §D3, §D7). Each one is `load()`, a pure change, a comparison, and a save
  only if the registry changed:
  - `lookUpNote(id:)` returns `.unreadable` for `malformed`/`evicted`.
  - `mintNoteID(for:)`:
    - refuses a non-`.md` path;
    - resolves the path through `store.url(for:)` and refuses when that throws or the file is
      missing;
    - returns an existing id without writing;
    - refuses under `isDryRun` for a path with no id;
    - returns a new id **only after** `save` has succeeded.
  - `relocateNoteIDs`/`forgetNoteIDs` do nothing under `isDryRun`. On `malformed`/`evicted` they
    record one problem naming `VaultLayout.noteIDsFile` and the path, and write nothing.
- Header doc comments in each file name ADR-0059 and the section each rule comes from.

**Done when:** tests 1-13 are green, and 14 is still green.

---

### Task 3: Coder. Keep the registry in step at the session doors (S3)

**Files:**

- `Sources/Vault/VaultSession+Journal.swift`: `moveFile`, after `apply(mutations)` at `:80`, and
  `trashFile`, after `apply([mutation])` at `:132`;
- `Sources/Vault/VaultSession+Folders.swift`: `:29-31` and `:40-42`;
- `Sources/Vault/VaultSession+Move.swift`: the folder branch, `:150-154`.

What each gets:

- **The calls**, exactly as in ADR-0059 §D5's table. The folder doors pass the folder's own
  `MovedNote(old:new:)` pair, not `outcome.movedNotes` (§D4, last bullet).
- **Doc comments made false by this task:**
  - `VaultSession+Folders.swift:6-9`: the header says the stars are carried "by hand", and now the
    ids are too;
  - `moveFile`/`trashFile`'s doc comments gain one sentence each, saying the registry follows and
    why at this level (§D5: after the dry-run return, after the disk operation, and on the undo
    path).
- **Leave alone:** `renameNote`/`moveNote`/`trashNote` in `+Files.swift`, because their
  `moveFile`/`trashFile` calls already carry it. Also leave the star-follow code as it is: stars
  following a connector undo is a named follow-up, not this chain.

**Done when:** tests 14-24 are green, and all three schemes build. `+Journal.swift` is shared, so
`perg` and `pergamenum-mcp` now compile the Task 1 files for real.

---

### Task 4: Coder. Keep the registry in step for Pratiche «Sposta in…» and its undo (S3, gate C)

**Files:** `Sources/Features/Pratiche/PraticaFileOperations.swift`.

- In `moveFiles(of:to:)`, after the loop at `:160-172`: when `movedMD` is non-nil, call
  `vault.session?.relocateNoteIDs([MovedNote(old: detail.notePath, new: VaultScanner.relativePath(of: movedMD, under: root))])`.
  This covers the collision-renamed base name too.
- In `moveBack(_:)`: for each restored file whose extension is `md`, relocate from
  `relativePath(of: file.to)` back to `relativePath(of: file.from)`. Only for files actually
  restored: the method's own doc comment explains why a failed restore must not be rewritten into.
- **Leave alone:** `trash(filesOf:)` and `restore(_:)`. They never forget an id (§D6).
- The file is 298 lines. It stays under the 400-line `file_length` warning.

**Done when:** test 25 is green, and so are the existing Pratiche tests
(`PraticaFileOperationsRestoreTests`, and the move/undo tests under `Tests/Pratica*`).

---

### Task 5: Coder. The route reads through the session and checks that the file exists (S4)

**Files:** `Sources/App/VaultController+Routes.swift`.

- **`.noteID(let id)`**: switch on `session.lookUpNote(id:)`, and give each outcome its own
  sentence (§D7):
  - `.unknown`: keep the existing «nessuna nota con id …»;
  - `.unreadable`: a sentence naming `note-ids.json`;
  - `.found(path)` with no file: a sentence naming the id and the path, and saying the note was
    moved or deleted outside the app.

  Each returns `false`.
- **Extract** the `.note` case's check (`:42-43`) into one private helper that both cases call, so
  a registry path goes through `store.url(for:)` (`VaultBoundary`) exactly like a `file=` argument.
- **Delete** `RouteState.noteIDs` and its doc comment (`:154-155`). Rewrite the stale comment at
  `:52-53` ("IDs live in the index") to point at ADR-0059.
- The file is 157 lines, so there is no lint risk.

**Done when:** tests 27-31 are green, and all of `Tests/URLSchemeTests.swift` stays green.

---

### Task 6: Coder. The id builder and «Copia link Pergamenum» (S5, after gate B)

**Files:**

- `Sources/Core/URLScheme/PergamenumURL.swift`;
- `Sources/App/VaultController+Routes.swift`;
- `Sources/App/CommandActions.swift`;
- `Sources/MCPServer/VaultHost.swift`, comment only;
- `Sources/CLI/Commands/AppCommands.swift`, comment only.

What changes:

- **`PergamenumLink.note(id:)`**: `build(host: "note", queryItems: [URLQueryItem(name: "id", value: id)])`.
  Update the enum's header comment, which currently says it builds links "for the «Copia link
  Pergamenum» command", to name both forms.
- **`VaultController.pergamenumLink(toNoteAt:)`** (§D8):
  - on a successful mint, it returns the id link;
  - otherwise it returns `PergamenumLink.note(path:)` and records one problem saying the copied
    link is the path form, which will not survive a rename.
- **`CommandActions.copyLinkToOpenNote()`** (`:366-370`) builds its URL through
  `vault.pergamenumLink(toNoteAt: note.relativePath)`. Keep the change to that line and the doc
  comment. The file is 390 lines, and the helper lives on the controller precisely so this file
  does not cross the 400-line `file_length` warning.
- **Correct the two comments:**
  - `VaultHost.swift:271-273`: the resource URI is the **path** form of the app's link, deliberately
    not the id form (ADR-0059 §D8);
  - `AppCommands.swift:10-11`: same builder, path form.
- `pergamenum-mcp` gets no code change, so `scripts/mcp-smoke.py` needs no change.

**Done when:** tests 26 and 32-34 are green, the whole unit suite is green, and all three schemes
build.

---

### Task 7: Verification and the record (S6)

1. **Run the full unit suite** with `TEST-CMD CANDIDATE` below, not only the new files. The rename,
   move and trash doors are shared by every note verb in the app and both connectors. A behaviour
   added there can turn a test red in a module that only shares the door.
2. **Build all three schemes:** `Pergamenum`, `perg` and `pergamenum-mcp` (CLAUDE.md § Commands).
3. **Run `scripts/mcp-smoke.py`** against a built `pergamenum-mcp`. `Sources/MCPServer` changes
   only by a comment, but the server now compiles and runs the keeping-in-step code on every rename
   and trash, and the smoke run is the only check of the protocol layer (CLAUDE.md, AI connector).
4. **Run `swiftlint lint` on the touched files only.** The whole tree fails SwiftLint by design
   (`.github/workflows/ci.yml:12`).
5. **Run `scripts/uitests.sh --status`, then `--affected` at merge time.** This does not block the
   merge (CLAUDE.md merge-gate rule). The GUI-test budget is zero.
6. **Hand check by Stefano (HITL).** Use a Debug build started with
   `open -n "$(ls -dt …/Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1)"` against a
   throwaway vault:
   1. Open a note and press Cmd+Shift+L. The clipboard holds `pergamenum://note?id=…`, and
      `.pergamenum/note-ids.json` now exists with one line.
   2. Rename the note in the app, then move it to another folder. Run `open "<the copied link>"` in
      Terminal. The renamed note opens.
   3. Choose Impostazioni › Avanzate › «Svuota cache e ricostruisci», then open the link again. It
      still works.
   4. Rename the note in Finder, then open the link. It does not open a note, and Impostazioni
      shows a problem naming the old path.
   5. Press Cmd+Shift+L again on the same note. The id is the same one.
7. **The record.** The files are `CLAUDE.md`, `docs/adr/0001-initial-architecture.md`,
   `docs/20260811_Pergamenum_SpecApp.md`, `.claude/protected-interfaces` (gate E only), and
   `docs/adr/0059-note-ids-live-in-a-vault-registry.md`.
   - **`CLAUDE.md`:** one entry for **ADR-0059** in the Chain decision index, straight after
     ADR-0058's, in the same form: "Closes `PG-130`/#230 …, amends ADR-0001 §D2 and SPEC §9/§14 →
     path".
   - **ADR-0001:** a scope note at the head, in ADR-0047 §D12's form, pointing §D2's last
     paragraph at ADR-0059. The body is untouched.
   - **SPEC §9 row (line 396) and §14 Frontmatter row (line 512):** add the *Emendato 2026-09-25
     (ADR-0059)* notes, **gate D**.
   - **`.claude/protected-interfaces`:** the entry proposed in ADR-0059, **only if gate E approves
     it**.
   - **ADR-0059 itself:** if the implementation departs from the record, add a correction paragraph.
     Never edit the decision text silently.
   - **`TODO.md` is not edited in this chain.** `PG-130` is closed in the usual post-merge
     `chore/todo-sync-*` PR.
   - **Handed to the orchestrating session to file, not done here** (ADR-0059 Consequences):
     - stars do not follow a connector undo of a move;
     - a connector undo of a trash restores the note without its id;
     - reminder notifications keep path routes;
     - an iCloud conflict copy of `note-ids.json` is neither detected nor reported;
     - optionally, exposing ids through `perg`/MCP (out of scope here, and asked for by no one yet).

---

## Risks & HITL gates

- **HITL gate A:** accept the departure from the brief's steps 1, 2 and 4 (see above). Needed
  before Task 1.
- **HITL gate B:** what «Copia link Pergamenum» copies. Needed before Task 1, because test 32
  encodes the answer. It also changes the existing test `RowCommandTests.swift:94-105`, and
  CLAUDE.md requires the reason for changing a test to be stated first. The reason is ADR-0059 §D8.
- **HITL gate C:** Pratiche in this chain, or split off.
- **HITL gate D:** the SPEC edits (§9 and §14). SPEC is the authoritative document, and it changes
  only with Stefano's approval.
- **HITL gate E:** the protected-interfaces entry (ADR-0059, Protected-interface proposal).
- **HITL:** commit, push, PR and merge. This plan does none of them.
- **HITL:** Stefano's hand check (Task 7, step 6).
- **No schema change and no file deletion.** `IndexCache.schemaVersion` stays 4. One new file,
  `.pergamenum/note-ids.json`, appears in a vault the first time a link is copied. One struct
  member, `RouteState.noteIDs`, is deleted (Task 5). It is not a file and has no caller.
- **Risk: a future verb that moves a `.md` file with `FileManager` directly will drop ids
  silently.** This is the "skippable step" shape CLAUDE.md warns about. It is mitigated by placing
  the calls at the lowest shared doors, and ADR-0059's inventory is the checklist. It is not
  eliminated.
- **Risk: iCloud.**
  - Two Macs minting at the same moment produce a conflict copy of `note-ids.json`, which the app
    does not merge.
  - An evicted registry refuses every change until it is downloaded again, by design (§D3).
- **Risk: the gap between one door's read and its write** across three processes (§D3) is narrowed
  but not closed. There is no file lock.
- **Risk: copying a link now writes.** The first copy per note writes to the vault. That is a new
  side effect of a gesture that used to be read-only.
- **Dependency: the connectors.** `VaultSession+Journal.swift` is shared, so the two new
  `Sources/Vault` files must be in `sharedSources` from Task 1, or `perg` and `pergamenum-mcp` stop
  linking at Task 3.
- **No external dependency.** No library, SDK or service is involved: Foundation's `UUID` and
  `JSONEncoder` only. Context7 was not needed. Nothing needs provisioning before `/build`.

## TEST-CMD

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

TEST-CMD MODE: brownfield

This command is identical to `.claude/test-cmd`, and it is the merge gate CLAUDE.md names: the
unit suite `PergamenumTests`, whose target `Project.swift` declares with sources `Tests/**`.
`Pergamenum.xcworkspace` already exists in this worktree (generated 2026-09-25). Run
`tuist generate --no-open` again after Task 1 adds three test files and two shared sources.
