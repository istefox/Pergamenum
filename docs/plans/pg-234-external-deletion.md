# Plan: PG-234 / #511, an external deletion reaches the editor tabs and the Diario pane

- SPEC: `SPEC.md` (Approved 2026-09-25), success criteria R-01…R-09. Its Decisions and Constraints
  are registered as settled; the one place this plan goes past the SPEC's letter (ADR-0061 §D6, the
  move race) waits on gate G1 below and is not decided on Stefano's behalf.
- ADR: **new, ADR-0061**,
  `docs/adr/0061-external-deletion-reaches-the-tabs-and-the-diary.md` (status proposed). Why an
  ADR: the change widens a shared signal every consumer switches on (hard to reverse), deliberately
  suppresses the deletion signal for a move while leaving it for a trash (surprising without
  context), picks one pending-state shape over another the SPEC left open, and records several
  explicit "not fixed" items a later reader would otherwise reopen. Every prior change to this
  reconcile/write plumbing got one (ADR-0043, 0046, 0054, 0055, 0056, 0057, 0058).
- Written against `5531f72`. Every file:line below was read from that tree on 2026-09-25.
- UI budget: **zero GUI tests**. Everything is asserted in-process (ADR-0061 Acceptance).

## Before `/build` (orchestrator, each item a HITL point)

1. **Base.** PR #519's merge dropped the whole of PR #515 (ADR-0060, 16 other files) from `main`;
   `origin/fix/restore-pr515-adr0057-followups` (`88e91de`) restores it and was unmerged when this
   was written. Land the restore on `main` first, then bring this branch up to `main`. The branch
   has no commits of its own (`5531f72..HEAD` is empty; the work is `SPEC.md` modified plus two
   untracked files), so this is a fast-forward. The restore touches `SPEC.md` nowhere and, among
   the files this plan edits, only `VaultSession+Watching.swift` (`append`, from `:65`, below
   every line cited here) and `CLAUDE.md` (the ADR-0060 index line; Task 6 adds ADR-0061's after
   it). `PergamenumApp.swift:128` becomes `:162`; nothing in this plan edits it.
2. `tuist install` (once per fresh worktree) and `tuist generate --no-open`.
3. **Gate G1: approve ADR-0061 §D6** (the absence marker at `VaultSession.moveFile`) or pick
   Alternative 4b (relocation claims on `VaultController`). The finding: once a missing path is
   reported as `.deleted` (R-07), the watcher's reconcile for a rename's or move's vacated source
   runs at the rename's first `await`, before `movedNote`, and would close the renamed note's tab
   (`VaultController+Files.swift:52-55,77-80`, `VaultController+Move.swift:53,146`). SPEC Decision
   4's ordering argument holds for the trash and not for moves. Recommendation: §D6. It adds nothing
   for the trash, so R-09 stands as written. Tasks 3 and 4 name what changes under 4b.
4. **Gate G2: approve rewriting three existing assertions** that pin the contract R-07 replaces,
   not deleting them: `Tests/VaultWriteOrderingTests.swift:281` (`missing.change == nil`), `:303`
   (`missing.isEmpty`) and `Tests/VaultSessionTests.swift:398` (`reconcile(["N.md"]).isEmpty` after
   a removal). Each one becomes "reports exactly `.deleted` for that path". Every other assertion
   in those three tests (index row dropped, clock advanced once, apply ordering) stays word for
   word.
5. Commit and push stay HITL at the end of `/build`, as always.

## Ownership and order

Tasks 1 and 2 belong to the tester, 3 to 5 to the coder, 6 to whoever closes the chain. This is a
compiled target: the tester owns every signature the tests name, the coder owns the bodies. Task 1
leaves the build green **and the suite green** (a shape change with no behaviour change). Task 2
leaves it building with the new tests red on their assertions. The declared red exists only if
the tasks run in this order.

---

### Task 1 (tester): the shape change, behaviour preserved (R-04, R-07, R-08)

Declares every signature the tests use. The production edits are the ones the new shape forces
and change no behaviour.

Signatures:

- `Sources/Vault/VaultSession+Watching.swift:10-14`: `ExternalChange` gains the nested
  `enum Content: Equatable, Sendable { case text(String); case deleted }` and `let content:
  Content` replaces `let text: String` (ADR-0061 §D1). No `text` accessor. Doc comment updated to
  name both cases.
- `Sources/Vault/NoteTab.swift:87-105`: `externalChangePending: VaultSession.ExternalChange
  .Content?`; a nested `enum CatchUp: Equatable { case adopted, asked, vanished }`; `@discardableResult
  mutating func catchUp(to incoming: VaultSession.ExternalChange.Content) -> CatchUp`. Placeholder
  body: `.text(s)` runs today's body unchanged and returns `.asked`/`.adopted`; `.deleted` changes
  nothing and returns `.adopted` (wrong on purpose, so Task 2's tests are red on assertions).
- New `Sources/Features/Editor/ConflictBannerCopy.swift`: `struct ConflictBannerCopy: Equatable`
  with `message`, `acceptLabel`, `keepLabel` (`String`, the shape ADR-0053's seams use) and
  `init(pending: VaultSession.ExternalChange.Content)`. Placeholder body: today's three strings for
  both cases. The view is not wired to it yet (Task 5).
- `Tests/TemporaryVaultSupport.swift`: `func remove(_ relativePath: String) throws`, a
  `FileManager.removeItem` at `root.appending(path:directoryHint: .notDirectory)`. Test support,
  written in full here.

Forced production edits, behaviour unchanged:

- `Sources/Vault/VaultDisk.swift:449`: `ExternalChange(path: relativePath, content: .text(text))`.
- `Sources/App/VaultController+Watching.swift:35`: `tab.note.catchUp(to: change.content)`.
- `Sources/App/VaultController+Editing.swift:93` and `:119`: `catchUp(to: .text(result.text))`.
- `Sources/App/VaultController+Editing.swift:126`: `guard var note = openNote, case .text(let
  incoming)? = note.externalChangePending else { return }`. A `.deleted` pending returns early
  until Task 5.

The staleness sweep, seventeen mechanical edits (grep of `externalChangePending`, `catchUp(to:`,
`ExternalChange(`, `.text` on a change, across `Sources/` and `Tests/`, run 2026-09-25):

| File | Lines | Edit |
|---|---|---|
| `Tests/VaultControllerReconcileTests.swift` | 55, 109, 128 | wrap the expected text in `.text(...)` |
| `Tests/VaultControllerWriteCatchUpTests.swift` | 64, 76, 92 | `catchUp(to: .text("incoming"))` |
| `Tests/VaultControllerWriteCatchUpTests.swift` | 66, 113, 147, 223, 316 | wrap in `.text(...)` |
| `Tests/VaultControllerWriteCatchUpTests.swift` | 89 | constructor `externalChangePending: .text("stale")` |
| `Tests/VaultWriteOrderingBatch3Tests.swift` | 131, 177 | wrap in `.text(...)` |
| `Tests/VaultWriteOrderingBatch3Tests.swift` | 83 | `changes.first?.content == .text(external)` |
| `Tests/VaultWriteOrderingTests.swift` | 297 | `changes.first?.content == .text(note("External."))` |
| `Tests/VaultSessionTests.swift` | 394 | `changes.first?.content == .text(<the literal written at :392>)`: exact equality with the bytes the test wrote, a strengthening of `.contains("Tre.")`, not a weakening |

Comparisons against `nil` (`VaultControllerReconcileTests.swift:81,146`,
`VaultControllerWriteCatchUpTests.swift:80,95,129,226,247,272`,
`VaultWriteOrderingBatch3Tests.swift:150`, `EditorColumnView.swift:76`) and
`VaultController+Tabs.swift:383`'s `externalChangePending: nil` compile unchanged. Neither connector
references `ExternalChange`, `reconcile` or `selfWrittenHashes` (grep of `Sources/CLI`,
`Sources/MCPServer`, `Sources/Connector`, no match).

Then `tuist generate --no-open` (a new source file).

**Done when:** `Pergamenum`, `perg` and `pergamenum-mcp` build; the whole `PergamenumTests` bundle
is green, the three G2 assertions included (their rewrite is Task 2).

### Task 2 (tester): the red tests (R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-09)

Rules for every new test: no sleep, no timer, no racing two tasks (ADR-0043 §D9). A test that builds
a `VaultController` stops the watcher `open` started (`controller.watcher?.stop();
controller.watcher = nil`, both reachable: `VaultController.swift:120`), so the only
reconciliation it sees is the one it calls. A disk or session test uses a bare `VaultDisk`/
`VaultSession` with `rescan()`, which starts no watcher (`VaultWriteAbsentPreconditionTests.swift:15`
is the shape). A deletion is `vault.remove(_:)`, never a session door, so it never lands in
`selfWrittenHashes`. Each test carries a one-line comment saying whether it is red on today's code
or a guard that is green today, as `VaultWriteAbsentPreconditionTests.swift` does.

New `Tests/ExternalDeletionReconcileTests.swift` (disk and session):

| # | Test | Asserts | Covers | Today |
|---|---|---|---|---|
| 1 | an absent path is reported deleted | `disk.reconcile` after `remove`: `change == ExternalChange(path:, content: .deleted)`, `record == nil`, sequence advanced exactly once, `matchedSequence == nil` | R-07 | red |
| 2 | an unreadable file is not a deletion | bytes `FF FE 00 01` at the path: `change == nil` | §D2 | green, guard |
| 3 | an iCloud placeholder is not a deletion | `Nota.md` removed, `.Nota.md.icloud` written beside it: `change == nil` | §D2 | green, guard |
| 4 | the session reports a deletion and drops the row | `session.reconcile` returns exactly `[.deleted]` for the path; `index.note(at:) == nil` | R-07 | red |
| 5 | a path this session moved away is not reported | `session.moveFile(A→B)`: one entry for `A` in `selfWrittenHashes`; `session.reconcile(["A.md"]) == []`; no entry for `A` left | §D6 (G1) | red (no entry today) |
| 6 | a failed move leaves no absence behind | `moveFile(from: "A.md", to: "../fuori.md")` throws (passes `exists`, which answers `false` outside the vault, and is refused by `VaultDisk.moveFile`'s boundary); no entry for `A`; after `remove("A.md")`, `reconcile` reports `.deleted` | §D6 | red |
| 7 | a stale absence is dropped once the path is found present | `moveFile(A→B)`, no reconcile of `A`; external write at `A`, `reconcile` reports `.text`; `remove("A.md")`, `reconcile` reports `.deleted` | §D6 | red |
| 8 | a trashed path is still reported deleted | `session.trashFile(at:)`, then `reconcile` reports `.deleted` | R-09 | red |

Rewrites in existing files (gate G2), red until Task 3:

- `Tests/VaultWriteOrderingTests.swift:281`: `#expect(missing.change == VaultSession.ExternalChange(path: "N.md", content: .deleted))`.
- `Tests/VaultWriteOrderingTests.swift:303`: `#expect(missing == [VaultSession.ExternalChange(path: "N.md", content: .deleted)])`.
- `Tests/VaultSessionTests.swift:398`: `#expect(await session.reconcile(["N.md"]) == [VaultSession.ExternalChange(path: "N.md", content: .deleted)])`.

New `Tests/VaultControllerExternalDeletionTests.swift` (controller; two-column setup through
`splitEditor()`/`focusColumn(_:)` as `VaultControllerReconcileTests.swift:36-57` does; a second
tab in one column through `openNoteInNewTab(at:)`, since `openNote(at:)` reuses a preview tab,
`VaultController+Tabs.swift:123`):

| # | Test | Asserts | Covers | Today |
|---|---|---|---|---|
| 9 | a clean tab on a deleted note closes in every column | `A.md` open in both columns, both clean; `remove`, `reconcile`: no tab shows `A.md` in either column; `closedTabPaths` and `recentNotePaths` hold no `A.md` | R-03 | red |
| 10 | a clean background tab closes too | `A.md` in a background tab of the focused column, `B.md` active; after: `B.md` still active, `A.md` gone | R-03 | red |
| 11 | a dirty tab is asked and keeps its text | pending `== .deleted`, `text` untouched, tab still open, file still absent | R-04 | red |
| 12 | newest wins on a dirty buffer | external text change, then deletion: pending `.deleted`; external recreation: pending `.text(recreated)` | §D3 | red |
| 13 | «Scarta ed elimina» closes without writing | dirty tab, `.deleted` pending, `acceptExternalChange()`: tab gone, file still absent, `closedTabPaths` holds no `A.md` | R-06 | red |
| 14 | «Tieni la mia versione» then a save recreates the file | `keepLocalVersion()`: pending `nil`, tab dirty; `await saveOpenNote()`: file on disk equals the buffer, pending `nil`, tab clean | R-05 | red |
| 15 | a buffer undone to clean can still be kept and saved | dirty, deletion, buffer set back to `savedText`, `keepLocalVersion()`: `hasUnsavedChanges`; save recreates the file | R-05, §D5 | red |
| 16 | the banner for a deletion never offers a reload | `ConflictBannerCopy(pending: .deleted)`: labels «Scarta ed elimina» / «Tieni la mia versione», no «Ricarica da disco» in any field; `.text` copy is today's three strings exactly | R-04 | red |
| 17 | a session move reconciled before `movedNote` still follows | tab on `A.md`; `controller.session?.moveFile(A→B)`, `controller.reconcile(["A.md"])`, `movedNote(from:to:)`: the tab shows `B.md` | §D6 (G1) | green, guard |
| 18 | a trash ends in the same state in either order | order 1: `controller.trashNote(at:)` then `reconcile`; order 2 (fresh vault): `session.trashFile`, `reconcile`, then `trashedNote(at:)`. Both: no tab on the path, neither list holds it, no problem recorded | R-09 | green, guard |

Additions to `Tests/DiaryWatcherReloadTests.swift`, beside the two text-change tests:

| # | Test | Asserts | Covers | Today |
|---|---|---|---|---|
| 19 | a clean day reloads to empty on an external deletion | external write, `reconcile` (the pane shows it); `remove`, `reconcile`: `diary.prose == controller.emptyDiaryNote(for: testDay)`, `isSettled` | R-01 | red |
| 20 | a pending day is untouched by an external deletion | pane showing the file, local text appended (not settled), `remove`, `reconcile`: the local text is still there | R-02 | green, guard |

Then `tuist generate --no-open` (new test files).

**Done when:** the three targets build; every new test except the five guards (2, 3, 17, 18, 20)
fails on its assertions, as do the three G2 rewrites (none on a crash or a compile error); every
other test in the bundle is green.

### Task 3 (coder): the vault layer (R-01, R-07, R-09)

- `Sources/Vault/VaultScanner.swift`, beside `evictedNoteName(from:)` (`:174-180`): the inverse,
  `static func evictedPlaceholderName(for noteFileName: String) -> String` (`"." + name +
  ".icloud"`), so one file owns the naming rule both ways (§D2).
- `Sources/Vault/VaultDisk.swift:437-443`: the failed-read branch keeps its mutation exactly (record
  `nil`, one `nextSequence`) and decides the change on existence (§D2): something at the path →
  `nil`; nothing, and the placeholder exists → `nil`; boundary failure → `nil`; nothing at all → an
  absence entry in `selfWritten` matches (return its sequence as `matchedSequence`, change `nil`),
  else `.deleted`. Use the existing `fileExists(_:)` (`:288-290`, existence, not readability).
  Update the branch comment and the doc comment at `:420-433`, which still describes `selfWritten`
  as "for a later task".
- The absence marker (**G1**). One named constant beside `selfWrittenHashes` in
  `Sources/Vault/VaultSession.swift:113`, a string no SHA-256 hex digest can be and not `""`, with
  a doc comment saying what it means and that it is matched only in the absent branch.
- `Sources/Vault/VaultSession+Journal.swift:66-106` (`moveFile`): after the `isDryRun` return and
  before the hop, reserve a provisional sequence and append `(provisional, marker)` for `oldPath`;
  after the hop, correct it to the removal mutation's sequence (`mutations.first { $0.path ==
  oldPath }`, stamped at `VaultDisk.swift:391`); in the `catch`, remove it before rethrowing. The
  new path's hash stays recorded after the hop, as today (`:92`). `trashFile` (`:121-156`) is **not
  touched**.
- `Sources/Vault/VaultSession.swift:121-149`: `reserveProvisionalSequence`,
  `reconcileProvisionalSequence(at:provisional:actual:)` and `removeSelfWrittenEntry(at:sequence:)`
  widen from `private` to `internal`, one comment each naming `VaultSession+Journal.swift` as the
  reader (ADR-0045's convention). Update `selfWrittenHashes`' doc comment (`:95-113`): it now holds
  hashes and absences.
- `Sources/Vault/VaultSession+Watching.swift:37-59` (`reconcile`): on an unmatched result, drop the
  path's absence entries whose sequence is below `result.mutation.sequence` (§D6, stale absence);
  the matched branch and its pruning are unchanged. Update the doc comment at `:28-36`, which says
  a missing path is not reported.

Test 19 (R-01) can turn green here already: `VaultController.reconcile` calls
`didChangeExternally` for every change it receives (`VaultController+Watching.swift:37`), and
`DiaryController.externalChange(at:)` needs nothing more.

Under 4b instead of G1: none of the marker bullets; the `VaultScanner`/`VaultDisk` bullets stand, and
test 5 is rewritten to assert the vacated path **is** reported (the controller absorbs it, Task 4).

**Done when:** tests 1 and 4-8 and the three G2 rewrites are green, 2 and 3 stay green, the three
targets build, and `VaultControllerMoveNoteTests.swift:81` is still green.

### Task 4 (coder): the controller closes a vanished clean tab (R-01, R-02, R-03, R-04, R-09)

- `Sources/Vault/NoteTab.swift`: `catchUp(to:)`'s body per ADR-0061 §D3's table. Dirty: pending takes
  the incoming content, `.asked`. Clean `.text`: today's adoption, `.adopted`. Clean `.deleted`:
  nothing changes, `.vanished`. Doc comment names all three results.
- `Sources/App/VaultController+Tabs.swift:317-331`: extract the door, `func closeTabs(_ ids:
  [NoteTab.ID], ofVanishedNote relativePath: String)` (close each id through `closeTab`, then
  remove the path from `closedTabPaths` and `recentNotePaths`); `trashedNote(at:)` collects its ids
  as today and calls it. Doc comment: the one place a tab closes because its file is gone.
- `Sources/App/VaultController+Watching.swift:29-39` (`reconcile`): for each change, collect the
  ids `catchUp` answers `.vanished` for inside `updateTabs(showing:)`; for a `.deleted` change call
  `closeTabs(_:ofVanishedNote:)` after the loop, **even with no ids** (ADR-0061 §D4), then
  `didChangeExternally?(change.path)` as today, for every change. Doc comment updated.
- `VaultController+Tabs.swift` is 390 lines; SwiftLint warns at 400. If the file crosses it,
  `movedNote`, `trashedNote` and the new door move together, unchanged, into a new
  `Sources/App/VaultController+TabFollowUps.swift` in this same task (a pure move, ADR-0045's
  shape) rather than adding a warning; `tuist generate --no-open` after.

Under 4b: add the relocation claims here (`VaultController+Files.swift` `renameNote`/`moveNote`,
`VaultController+Move.swift`'s two batch paths), claimed before the session call and released after
the follow-up on every exit path, and `reconcile` skips closing a claimed path's tabs.

**Done when:** tests 9-12 and 19 are green; 17, 18 and 20 stay green; so do
`VaultControllerMoveNoteTests.swift:81` and every other test in the bundle.

### Task 5 (coder): the two verbs and the banner (R-04, R-05, R-06)

- `Sources/App/VaultController+Editing.swift:125-131` (`acceptExternalChange`): `.text` as today;
  `.deleted` closes the focused tab through `closeTabs(_:ofVanishedNote:)` and writes nothing.
- `Sources/App/VaultController+Editing.swift:134-136` (`keepLocalVersion`): `.text` as today;
  `.deleted` clears pending **and sets `savedText = ""`** (ADR-0061 §D5). Doc comments on both say
  what each does for each case.
- `Sources/Features/Editor/ConflictBannerCopy.swift`: the real body. `.text` returns today's three
  strings unchanged; `.deleted` returns the new message plus «Scarta ed elimina» and «Tieni la mia
  versione». The message wording is the SPEC's open item, settled here against the existing tone
  («La nota è cambiata su disco mentre la stavi modificando.»); a suggestion, not a decision:
  «La nota è stata eliminata dal disco mentre la stavi modificando.»
- `Sources/Features/Editor/EditorColumn+Conflict.swift`: render from
  `ConflictBannerCopy(pending:)`, reading the pending value of the tab the banner belongs to; the
  two buttons keep `focused(vault.acceptExternalChange)` / `focused(vault.keepLocalVersion)`. Pass
  the strings through `LocalizedStringKey(_:)` so they stay extractable for the English
  localization the project is built for. Theme tokens only, as today. Header comment updated.

**Done when:** tests 13-16 are green and the whole bundle is green.

### Task 6: verification and records (R-08, R-09)

- Build all three schemes (`Pergamenum`, `perg`, `pergamenum-mcp`) from the commands in
  `CLAUDE.md` (R-08).
- Run the **whole** `PergamenumTests` bundle, not the new files alone: the change is to a signal
  every reconcile test and several write-ordering tests share.
- SwiftLint on the touched files: no new warning.
- `scripts/uitests.sh --status`, then `--affected` per the merge rule. No GUI test is added.
- Read over the doc comments that described the old contract and now lie: `VaultDisk.reconcile`,
  `VaultSession+Watching.swift`'s header and `reconcile`, `selfWrittenHashes`, `OpenNote`
  (`externalChangePending`, `catchUp`), `VaultController+Editing.swift`'s two verbs,
  `EditorColumn+Conflict.swift`'s header, `trashedNote`, `moveFile`. Tasks 3-5 each own theirs;
  this is the check that none was missed.
- `CLAUDE.md`: one line for ADR-0061 in the chain decision index, after ADR-0060's (restored).
- ADR-0061: status to accepted at merge; if G1 went to 4b, rewrite §D6 and Alternative 4 to match
  before merging, never leave the ADR describing a mechanism that was not built.
- R-09 is an ordering argument (no-test in the SPEC). Tests 8 and 18 pin what can be pinned: a
  trash is still reported, and both orders end in the same state.
- Hand checks, suggested for Stefano's verification (not a gate this plan sets): delete an open
  clean note from Finder (tab closes); edit a note and delete it from Finder (banner, both
  buttons); rename and move an open note from the sidebar (tab follows); move a folder holding an
  open note by drag (tab follows, see Risks).

---

## Requirement coverage

| R | Task(s) |
|---|---|
| R-01 | 2 (test 19), 3, 4 |
| R-02 | 2 (test 20), 4 |
| R-03 | 2 (tests 9, 10), 4 |
| R-04 | 1 (signatures), 2 (tests 11, 16), 4, 5 |
| R-05 | 2 (tests 14, 15), 5 |
| R-06 | 2 (test 13), 5 |
| R-07 | 1 (signatures), 2 (tests 1, 4, G2 rewrites), 3 |
| R-08 (no-test) | 1, 6 |
| R-09 (no-test) | 2 (tests 8, 18), 3, 4, 6 |

## Risks and HITL gates

- **G1 (above) is the one real decision.** The move race is inferred from the code and the SDK
  header, not reproduced; confidence it is real is high because the suite's own
  `VaultControllerMoveNoteTests.swift:81` exercises exactly that path with a live watcher.
- **A duplicate FSEvents delivery of a vacated path**, after the first one consumed the marker and
  before `movedNote`, would still close the tab (ADR-0061 §D6, named, not engineered around).
- **Folder moves: assumption, not verified.** A batch move of a folder (`VaultSession+Move.swift:144`)
  moves a directory, and its tab follow-up (`follow(_:)`) runs after the batch's awaits. The plan
  assumes FSEvents reports the directory path only, which `VaultWatcher`'s `.md` filter drops; if it
  reported each child `.md`, a clean tab on a child would close before `follow`. Folder rename
  (`VaultController+Folders.swift:63-65`) follows synchronously and is not exposed. The last hand
  check in Task 6 is the way to find out.
- **Pratiche direct `FileManager` moves** (`PraticaFileOperations.swift:48,166`) now close a clean
  tab on a message instead of leaving it on a dead path (ADR-0061 §D7). Behaviour change, arguably
  better, not asked for by the SPEC.
- **External renames close the tab** rather than follow it (§D7). Today they leave it on a dead
  path, so this is not a regression.
- **A silent close.** Whether a clean tab closing on an external deletion should also record a
  sentence in the problems list is Stefano's call, not this plan's (§D7).
- **Contract change across the suite.** Twenty existing lines change (seventeen mechanical, three
  G2 rewrites); no test is deleted or disabled. The full bundle, not the new files, is the gate.
- **`TODO.md` on `main`** still lists #518, a closed duplicate of #511; worth tidying when this
  chain's TODO sync runs.
- HITL, as always: the base update, commit, push and merge. No schema change, no deletion, no
  dependency, no externally provisioned resource.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield
