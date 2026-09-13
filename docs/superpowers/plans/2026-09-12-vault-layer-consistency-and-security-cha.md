# Plan — The vault layer gets one boundary, one walk, and one place where the disk is touched

- **ADR:** `docs/adr/0041-vault-layer-consistency-and-security-cha.md`. Everything below cites it
  as **ADR-0041 §D1…§D13**.
- **Requirement ids.** `SPEC.md`, this chain: `R-01`…`R-12`. Every one is cited by at least one
  task below, and no id outside that set is cited. The `PG-*` numbers are `TODO.md` ledger ids and
  the `§D*` numbers are ADR-0041 cross-references; neither is ever used as a requirement id.
- **Harness:** none created. The gate is the project's existing `.claude/test-cmd`
  (`-only-testing:PergamenumTests`), which picks up new Swift Testing cases with no edit, plus
  `scripts/uitests.sh` before the merge to `main` and both connector builds, per CLAUDE.md. No new
  script, no new anchor, nothing to name back.
- **Branch:** `refactor/vault-layer-consistency-and-security` off `main`. Never on `main` directly.

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test`
TEST-CMD MODE: brownfield

> Unchanged from `.claude/test-cmd`, verified byte-for-byte against it. Every test this plan adds
> is a Swift Testing case in `Tests/`, compiled into `PergamenumTests`, and is picked up with no
> edit to that file. **Do not widen it to the whole scheme**: CLAUDE.md's «the UI suite is not in
> `test-cmd`» rule is load-bearing and was paid for once already, in two hours of hunting an
> external culprit for something the assistant was doing to itself.

EXTERNAL DEPENDENCY: xcodebuild | binary | provisioned: true
EXTERNAL DEPENDENCY: python3 | binary | provisioned: true

> **No new dependency is added by this chain** — no SPM package, no framework, no service, no
> network of any kind (ADR-0041 §D13). The two lines above are the tools the acceptance steps
> need: `xcodebuild` for every build and test, `python3` for `scripts/mcp-smoke.py` at `R-10`.
> Both are verifiable kinds and G13 probes them for real.

CODER-MODEL CANDIDATE: opus

> Swift 6 strict concurrency: this chain introduces an `actor` (`VaultDisk`) that a `@MainActor`
> `@Observable` class awaits on its hottest path, passes a `Sendable` outcome back across that
> boundary, and turns ~35 production call sites `async` — including four SwiftUI callbacks that
> must wrap in `Task { }`. It also closes a path-traversal hole and makes a widely-called
> accessor (`NoteStore.url(for:)`, 31 call sites) throwing. Every one of ADR-0155's
> compiled-language hazards is present. Not a Sonnet job.

---

## Order, and why it is this order

The SPEC and `TODO.md:345` both fix the dependency order, and it is not negotiable:
**`PG-122` → `PG-145` → `PG-140` (paired with `PG-145`) → `PG-137`.**

1. **`PG-122` first (Tasks 1-2).** The walk helper must be *built from* the boundary, or it is the
   way around it (ADR-0041 §D3.1). Building the walk first and retrofitting the guard means
   auditing the walk's callers twice.
2. **`PG-145` next (Tasks 3-5).** Task 3 (the file relocation) runs **first inside this slot**,
   before any content edit, because a rename-plus-edit in one commit is the hardest kind of diff
   to review and the easiest to rebase wrongly. Tasks 4 and 5 then delete the drifted copies.
3. **`PG-140` (Tasks 6-7)**, written in terms of Task 4's walk. Task 6 also produces the
   single-read record derivation that Task 8's actor needs — which is why the SPEC pairs the two
   items rather than sequencing them.
4. **`PG-137` last (Tasks 8-9).** Every file it touches is a file Tasks 1-7 have already made
   throwing, moved, or deleted code from. Doing it first means doing the async migration twice
   (ADR-0041, Alternatives).
5. **Task 10** is the sweep, the two manual verifications, and the ledger.

Batching suggestion for the orchestrator: {1} · {2} · {3} · {4} · {5} · {6} · {7} · {8} · {9} · {10}.
**Nothing in this plan should be fanned out in parallel worktrees.** Tasks 2, 4, 5, 6 and 7 all
edit `NoteFileOperations.swift`, `FolderFileOperations.swift` and `BoardFileOperations.swift`, and
Tasks 8 and 9 both edit `VaultSession.swift`. Sequential is the only safe order here.

---

## What changes an observable contract, and every call-site found

Grepped across `Sources/` and `Tests/` before this plan was written. The coder does not have to
discover these.

| Symbol | Change | Call-sites that must move with it |
| --- | --- | --- |
| `NoteStore.url(for:)` | non-throwing → `throws` (ADR-0041 §D2) | **31 sites.** In `throws` context already, mechanical: `VaultSession+Journal.swift:60`, `:65`, `:107`, `:112`, `:147`, `:151`, `:302`; `FolderFileOperations.swift:208`, `:322`, `:391`, `:397`; `FolderFileOperations+Move.swift:121`; `NoteFileOperations.swift:172`, `:224`, `:270`, `:274`, `:297`, `:361`, `:374`; `BoardFileOperations.swift:152`, `:172`, `:193`, `:269`, `:273`, `:286`, `:304`, `:313`. **Need a decision each:** `VaultSession.swift:113` (`exists(_:)`, non-throwing, returns `Bool` — a violation must answer `false`, not throw, or every existence check becomes throwing), `VaultController+Routes.swift:43`, `Sources/App/WindowPlace.swift:65`, `Tests/CardRoundTripTests.swift:149`. |
| `NoteStore.StoreError.outsideVault` | **removed**; `VaultBoundary.Violation.outsideVault` replaces it | Only three lines, all inside `NoteStore.swift` (`:64` declaration, `:69` description, `:134` throw). **Verified: zero references anywhere else in `Sources/` or `Tests/`.** Nothing catches it by case today, so nothing breaks silently — but grep once more before deleting. |
| `NoteFileOperations.FileChange` | → `VaultFileChange` in `Sources/Core/Vault/` (ADR-0041 §D4) | **19 refs, 5 files.** `NoteFileOperations.swift:63`, `:73`, `:74`, `:82`, `:118`, `:167`, `:169`, `:190`; `FolderFileOperations.swift:142`, `:143`, `:202`, `:204`, `:240`; `BoardFileOperations.swift:38`, `:39`, `:108`, `:208`; `FolderFileOperations+Move.swift:21`; `Tests/FolderFileOperationTests.swift:246`. All mechanical. **No typealias is left behind.** |
| `VaultLayout` | moves `Sources/Vault/VaultSettings.swift:279-296` → `Sources/Core/Conventions/VaultLayout.swift` | **36 refs, all unchanged** — the type keeps its name and stays target-internal. Nothing to edit; verify by building. |
| `NoteStore.linkTargets(in text:)` | **signature unchanged**, becomes a wrapper (ADR-0041 §D7) | `Tests/TransclusionTests.swift:182`, `:221` are the only external callers. They must keep compiling and keep passing unchanged; if either goes red, the single-parse refactor changed behaviour. |
| `VaultSession.write(_:to:)` | → `async throws` (ADR-0041 §D9) | **33 production sites.** Unqualified, inside session extensions: `+TimeBlocks:43`, `:98`; `+Journal:273`, `:281`; `+Diary:43`; `+Notes:62`, `:191`, `:192`; `+BoardDrop:78`; `+Watching:56`; `+EventNotes:79`; `+TagRename:81`; `+Files:28`; `+Tasks:167`, `:216`, `:245`; `+SampleViews:29`; `MCPServer/VaultHost.swift:62`. Qualified: `PraticaEntryComposer.swift:54`, `:84`; `NuovaPraticaWizard.swift:463`; `PraticheController.swift:1247`, `:1284`, `:1374`; `DossierWriter.swift:32`; `PraticaCommandActions.swift:307`; `RecordingsController.swift:330`; `VaultWrites.swift:285`; `VaultController+Editing.swift:15`, `:40`. **`PlaudVaultStore.swift:164`, `:181` match the grep but are that type's own `write` — verify, do not assume, before touching them.** Plus every test that calls `try session.write(…)` (at least `VaultSessionTests`, `NoteHistoryTests`, `VaultSessionFileOperationsTests`, `ViewConnectorTests`, `TagRenameTests`). |
| `VaultController.saveOpenNote()` | → `async` (follows from the row above) | **4 production sites:** `CommandActions.swift:178`, `EditorColumn+Text.swift:140`, `NoteTabBar.swift:77`, `EditorColumn+Closing.swift:40`. Plus `VaultController+Editing.swift:36` (internal, from `restoreVersion`). Tests: `NoteHistoryTests.swift:265`, `:291`; `NoteTabTests.swift:201`; `VaultTests.swift:413`. |
| `VaultHost.perform(_:_:)` and its four dispatch tables | → `async` | Called only from `VaultHost.call` (`:45`), which is already `async`. `Sources/Connector/VaultWrites.swift`'s 12 functions follow. `perg` needs **no** structural change — `Sources/CLI/main.swift`'s `dispatch` is already `async throws`. |
| `VaultSession.moveStar(from:to:)` | joined by `moveStars(_:)`, batch (ADR-0041 §D8) | `moveStar` keeps its single-path form for `renameFolder`'s per-note follow-up; `VaultSession+Move.swift:104` is the loop that becomes one batch call. `Tests/StarredTests.swift` asserts on the result, not the call count — read it before assuming. |

**After the contract changes: run the full unit suite, not just the vault tests.** `VaultLayout`
and `VaultFileChange` land under `Sources/Core/**`, which both command-line targets compile;
`NoteStore`, `VaultSession` and the three file-operation types are reached by roughly half of the
219 files in `Tests/`. A green `VaultSessionTests` proves nothing about `CanvasStoreTests`,
`TransclusionTests`, `VaultMoveTests` or `PraticheControllerTests`.

---

## Task 1 — The boundary is a resolver, and `Sources/Core` is where it lives (R-01, R-02)

Cross-refs: ADR-0041 §D1, §D2; `Sources/Vault/NoteStore.swift:48-60`, `:74-76`, `:120-136`;
`Sources/Core/Vault/FileOperationError.swift` for the file shape and comment style in that folder.
Budget: `Sources/Core/Vault/VaultBoundary.swift`, `Sources/Core/Conventions/VaultLayout.swift`,
`Sources/Vault/VaultSettings.swift`, `Sources/Vault/NoteStore.swift`,
`Tests/VaultBoundaryTests.swift` (~300 lines)

**Tester declares** (ADR-0155 — the declaration is the tester's, the body is the coder's; on Swift
a batch that leaves the target unable to build produces no red tests at all):

```swift
struct VaultBoundary: Sendable {
    let root: URL
    init(root: URL)
    func url(for relativePath: String) throws -> URL
    func contains(_ url: URL) -> Bool
}

extension VaultBoundary {
    enum Violation: Error, CustomStringConvertible, Equatable {
        case outsideVault(String)
        var description: String { get }
    }
}
```

**Coder implements:**

1. `init` resolves once: `root.resolvingSymlinksInPath().standardizedFileURL`. **Copy the doc
   comment at `NoteStore.swift:48-55` across verbatim** — it records the regression that made
   resolve-once necessary and is the reason this cannot be simplified to a per-call resolve.
2. `url(for:)` appends, standardises the result, and compares against the root with a trailing
   separator — `NoteStore.assertInsideVault`'s existing comparison at `:129-135`, moved, not
   rewritten. Throws `Violation.outsideVault(relativePath)` on failure.
3. `contains(_:)` is the same comparison over a `URL` the caller already holds. It does not throw.
4. `VaultLayout` moves from `VaultSettings.swift:279-296` to
   `Sources/Core/Conventions/VaultLayout.swift`, unchanged. Foundation only.
5. `NoteStore` gains `private let boundary: VaultBoundary`, keeps `let root: URL` (31 call sites
   read it), and `assertInsideVault` is **deleted**, not kept as a forwarder.
   `StoreError.outsideVault` is deleted with it.

**Tests (red first):** `Tests/VaultBoundaryTests.swift`

- `../../etc/passwd`, `../sibling/x.md`, `a/../../x.md`, `a/b/../../../x.md` → each throws
  `.outsideVault` with the **original** relative path in the payload, not the resolved one (the
  message is for a person reading a problem list).
- `a/../b.md` → resolves to `<root>/b.md` and does **not** throw. Collapsing `..` inside the vault
  is legal; escaping it is not. This pair is the whole of the guard's precision.
- An absolute path (`/etc/passwd`) and a path with a leading `/` → throws.
- `""`, `"."`, `"./x.md"` → assert the behaviour the coder chooses and state it in the doc
  comment; the important thing is that it is decided, not that it is any particular answer.
- **Symlink case, and it must be a real one:** create a temporary directory, symlink a second path
  to it, build a `VaultBoundary(root: <symlink path>)`, and assert that
  `url(for: "Nuova.md")` — a file that **does not exist yet** — resolves and does not throw. This
  is the regression `NoteStore.swift:48-55` documents; it is the one test that would have caught it.
- A unicode path, a path containing a literal `%2e%2e`, and a path with a trailing slash → none
  escapes.
- `contains(_:)` agrees with `url(for:)` on every case above.
- `NoteStore.read`/`write` still refuse `../` (R-02's pre-existing coverage — find the existing
  assertions first and keep them, adjusting only the error type they expect).

---

## Task 2 — Ten call sites stop joining a path onto the root by hand (R-01, R-02)

Cross-refs: ADR-0041 §D2 and the Context section's table (nine sites) plus its tenth gap (the raw
`Data(...).write(to: store.url(for:))` at `FolderFileOperations.swift:321`,
`BoardFileOperations.swift:171`, `:287`); `TODO.md:245`.
Budget: `Sources/Vault/NoteStore.swift`, `Sources/Vault/CanvasStore.swift`,
`Sources/Vault/VaultSession+Journal.swift`, `Sources/Vault/ThumbnailStore.swift`,
`Sources/Features/Workspace/WorkspaceController+Files.swift`,
`Sources/Features/Workspace/BoardCardMenu.swift`,
`Sources/Features/Pratiche/PraticheController.swift`,
`Sources/Features/Pratiche/PraticaSyncEngine.swift`, plus the 31 `url(for:)` call sites in the
staleness table, plus `Tests/VaultBoundaryCallSiteTests.swift` (~450 lines)

**Tester declares:** `NoteStore.url(for:) throws`, and — for each of the four call sites whose
enclosing function is not yet `throws` — the new signature. Read each one before declaring:
`ThumbnailStore.thumbnail(for:width:)` returns a `Task` and must answer `nil` rather than throw
(a thumbnail that cannot be drawn is not an error worth unwinding a view for);
`WorkspaceController.fileURL(for:)` already returns `URL?` and answers `nil`;
`BoardCardMenu`'s open-in-Finder branch is inside a gesture and must refuse silently rather than
crash; `VaultSession.exists(_:)` returns `Bool` and a violation answers `false`. **The other five
become `throws` and their callers propagate** — that is the SPEC's deliberate signature change.

**Coder implements:** every site in the ADR's Context table plus the three raw-bytes writes, each
resolving through `VaultBoundary` (directly, or through the now-throwing `NoteStore.url(for:)`).
`CanvasStore` gains its own `VaultBoundary` the same way `NoteStore` does — it already resolves
its root at `CanvasStore.swift:19-21`, so this is a delegation, not a new resolve.

**Do not change any behaviour beyond the refusal.** No renaming, no reordering, no «while I am
here». Every hunk in this task should be one of: a `try` added, a `throws` added, a `guard let …
else { return nil }` added, or a `root.appending(path:)` replaced.

**Tests (red first):** one adversarial case per guarded site, ten in total including Task 1's
pre-existing `NoteStore` coverage — that is `R-02` stated exactly.

- `CanvasStore.load(board: "../../evil.canvas")` and `save(_:board:)` → throws, and **no file
  exists** at the escaped path afterwards (assert on the file system, not only on the throw).
- `VaultSession.moveFile(from:to:)` with `../` on each side in turn → throws, and the source file
  is still where it was.
- `VaultSession.trashFile(at: "../x.md")` → throws, and nothing reached the Trash.
- `ThumbnailStore.thumbnail(for: "../../Pictures/x.png", width: 200)` → the task's value is `nil`,
  and no file was read (assert on the value; state the mechanism in a comment).
- `WorkspaceController.fileURL(for:)` over a `CanvasNode` whose `file` is `../../etc/passwd` →
  `nil`.
- `BoardCardMenu`'s open branch, driven through whatever seam the file already offers, with the
  same node → nothing is opened. If there is no testable seam, extract the path decision into a
  testable pure function rather than adding a UI test; say so in the commit message.
- `PraticheController.readTimeline` over a message note whose frontmatter names an attachment
  `../../../secret.pdf` → the row is produced with that attachment omitted or the read refuses;
  either is acceptable, silently resolving outside the vault is not.
- `PraticaSyncEngine.regenerationPlan` with a `praticaFolder` containing `../` → throws
  `RegenerationFailure` or the boundary violation; never reads the escaped file.
- The three raw-bytes writers: a `VaultFileChange` whose `path` is `../evil.canvas` handed to
  `renameFolder`/`renameBoard`/`moveBoard`'s apply loop → recorded in `failures`, and **no file
  written outside the root**. This is the gap the SPEC does not name; assert it explicitly.

**Every one of these tests must assert on the file system, not only on the thrown error.** A guard
that throws after writing is not a guard.

---

## Task 3 — `VaultController` and its seventeen extensions leave the vault layer (R-04)

Cross-refs: ADR-0041 §D6; `Project.swift:78-118` (`sharedSources`), `:203-205` (app target glob);
CLAUDE.md's «never edit the `.xcodeproj` — change `Project.swift` and run `tuist generate`».
Budget: 18 file moves, no content change; `Project.swift` untouched (~0 lines of content)

**Orchestrator or coder, but in a commit of its own with nothing else in it.**

1. `git mv Sources/Vault/VaultController.swift Sources/App/` and the same for the seventeen
   `VaultController+*.swift` files (`+Conformance`, `+Diary`, `+Editing`, `+Files`, `+Folders`,
   `+Import`, `+Move`, `+Notes`, `+Routes`, `+Search`, `+Session`, `+Settings`, `+Tabs`,
   `+TaskDrop`, `+Tasks`, `+TimeBlocks`, `+Watching`).
2. **`tuist generate --no-open` immediately after**, before anything else. The generated project
   lists files by path; without this the build fails naming the compiler rather than the cause
   (CLAUDE.md).
3. **No `Project.swift` edit.** The app target globs `Sources/**` minus the two tool directories,
   and **no `VaultController*` file appears in `sharedSources`** — verify this by reading
   `Project.swift:78-118` rather than trusting the sentence.
4. Build the app, `perg` and `pergamenum-mcp`. The two tool builds are the proof that nothing was
   in `sharedSources`.

**Tests:** none added. The suite must be **byte-for-byte identically green** before and after —
this task changes no line of code. If any test moves, something other than a file move happened.

**Verification for R-04, and the grep must be anchored:**

```
grep -rn "^import SwiftUI" Sources/Vault/     # must return nothing
ls Sources/App/VaultController.swift          # must exist
```

An unanchored `grep -rn "import SwiftUI" Sources/Vault/` reports `VaultState.swift` — a false
positive from its own doc comment at `:8`, which quotes the string while explaining why the file
must not contain it. Do not «fix» `VaultState.swift`.

---

## Task 4 — Three vault walks become one, built from the boundary (R-03)

Cross-refs: ADR-0041 §D3; `VaultScanner.swift:39-70`, `:185-196`; `CanvasStore.swift:184-232`;
`FolderFileOperations.swift:78-129`.
Budget: `Sources/Core/Vault/VaultWalk.swift`, `Sources/Vault/VaultScanner.swift`,
`Sources/Vault/CanvasStore.swift`, `Sources/Vault/FolderFileOperations.swift`,
`Tests/VaultWalkTests.swift` (~380 lines)

**Tester declares:**

```swift
struct VaultWalk: Sendable {
    struct Entry: Sendable {
        let url: URL
        let relativePath: String
        let name: String
        let isDirectory: Bool
        let byteSize: Int?
        let modifiedAt: Date?
    }
    init(boundary: VaultBoundary, subfolder: String = "", keys: Set<URLResourceKey> = []) throws
    func forEach(_ body: (Entry) -> Void)
}
```

**Coder implements:**

1. One `FileManager.enumerator(at:includingPropertiesForKeys:options:)` with
   `[.skipsPackageDescendants]`, built from `boundary.url(for: subfolder)` — **the boundary is the
   only way in**, which is what stops the walk being the route around Task 2 (ADR-0041 §D3.1).
2. `VaultLayout.isExcludedDirectory(name)` decides, and the walk calls `skipDescendants()`. Three
   callers stop remembering.
3. The root path is standardised **once in `init`** and relative paths are computed by prefix-drop
   — `VaultScanner.relativePath(of:under:)`'s per-file `standardizedFileURL` (`:190-191`) goes
   away. That is `PG-140`'s `perf-VaultScanner.swift-a0b`, closed here.
4. `keys` defaults to empty (`byteSize`/`modifiedAt` come back `nil`); `VaultScanner` passes its
   four. A caller that asks for nothing must not pay for a `resourceValues` call per file.
5. `VaultScanner.scan()`, `CanvasStore.walk()` and `FolderFileOperations.walk(_:)` are rewritten
   as calls. **`VaultScanner` keeps its own cache-reuse logic** — reusing an `IndexCache.Entry` is
   not a walk concern and must not migrate into the helper.
6. `VaultScanner.relativePath(of:under:)` is `static` — check for external callers before deleting
   it; keep it as a wrapper if anything outside the file uses it.

**Tests (red first):**

- A fixture vault with `.git/`, `.obsidian/`, `.pergamenum/`, `.trash/` and a normal folder: the
  walk yields nothing from any dot-directory and everything from the normal one — **and yields no
  entry for files *inside* an excluded directory**, which is what `skipDescendants` buys over a
  filter.
- `subfolder: "01 Progetti"` yields only that subtree, with relative paths still measured from the
  **vault root**, not from the subfolder.
- `subfolder: "../escape"` → `init` throws (the boundary, inherited).
- A symlinked vault root: relative paths are correct and no entry escapes.
- `keys: []` yields `nil` for `byteSize` and `modifiedAt`; the four-key set yields values.
- **Equivalence, the important one:** over a fixture vault of at least fifteen files across three
  levels including two dot-directories, the new walk's set of relative paths equals what
  `VaultScanner.scan()` indexed *before* this task. Write this assertion against the current
  implementation first (record the expected set in the test), then flip the implementation.
- `CanvasStoreTests` and `FolderFileOperationTests` stay green unchanged. If either needs editing,
  the walk changed behaviour and that is a defect, not a test to adjust.

---

## Task 5 — One apply-plan loop, and `rename` stops re-implementing `renamePlan` (R-03)

Cross-refs: ADR-0041 §D4, §D5; `NoteFileOperations.swift:88-127` (`renamePlan`), `:204-256`
(`rename`), `:226-250` (the loop); `FolderFileOperations.swift:312-327`;
`BoardFileOperations.swift:159-177`, `:280-290`; `VaultSession+BoardDrop.swift:66`.
Budget: `Sources/Core/Vault/VaultFileChange.swift`,
`Sources/Core/Vault/VaultPlanApplication.swift`, `Sources/Vault/NoteFileOperations.swift`,
`Sources/Vault/FolderFileOperations.swift`, `Sources/Vault/BoardFileOperations.swift`,
`Sources/Vault/FolderFileOperations+Move.swift`, `Sources/Vault/VaultSession+BoardDrop.swift`,
`Tests/VaultPlanApplicationTests.swift`, `Tests/NoteRenameCharacterizationTests.swift` (~420 lines)

**Write the characterization test FIRST, against the current `rename`, and land it green before a
single line of `rename` changes.** ADR-0041 §D5 names the one behavioural difference to watch:
today's `rename` reads each note *after* the move with a `readPath` substitution (`:235`);
`renamePlan` reads *before*, substituting `writePath` (`:106-118`). The bytes should be identical.
«Should be» is how the two copies drifted in the first place.

**Tester declares:**

```swift
struct VaultFileChange: Equatable, Sendable {
    let path: String
    let before: String
    let after: String
}

enum VaultPlanApplication {
    struct Outcome: Equatable, Sendable {
        var rewrittenPaths: [String] = []
        var failures: [String] = []
    }
    static func apply(
        _ changes: [VaultFileChange],
        writing: (VaultFileChange) throws -> Void
    ) -> Outcome
}
```

Read `NoteFileOperations.swift:61-74` before declaring `VaultFileChange` — it must carry exactly
the fields the existing type carries, with the same names, or nineteen call sites change meaning
as well as name.

**Coder implements:**

1. `NoteFileOperations.FileChange` → `VaultFileChange` across all 19 references in the staleness
   table. **No typealias.**
2. `VaultPlanApplication.apply` — the loop, the failure-string format
   (`"\(change.path): \(error)"`, matching all six existing copies **exactly**, so no caller's
   assertion changes), and `rewrittenPaths`.
3. Six call sites replaced. The note writer closure is `try store.write($0.after, to: $0.path)`;
   the `.canvas` writer closure is
   `try Data($0.after.utf8).write(to: try store.url(for: $0.path), options: .atomic)` — which is
   where the three raw-bytes writes of Task 2 keep the guard they acquired.
4. `rename` becomes `renamePlan` + move + two `apply` calls, per ADR-0041 §D5's sketch. Its doc
   comment at `:205-208` (the file moves first, the links after, and why) still governs and stays.

**Tests (red first, then the characterization test must stay green):**

- `VaultPlanApplicationTests`: an empty change list → empty outcome. Three changes, all succeed →
  three `rewrittenPaths`, no failures. Three changes, the middle one's writer throws → two
  `rewrittenPaths`, one failure naming that path, **and the third is still attempted** (this is
  the shape `R-06` will lean on in Task 7). The failure string format matches the six originals
  character for character.
- `NoteRenameCharacterizationTests`: a vault of three notes where A links to B by title, B links
  to itself, and C is unreadable (a directory where a file is expected, or a non-UTF-8 file).
  Rename B. Assert the **complete** outcome — `newPath`, the exact `rewrittenPaths` array in
  order, the exact `failures` array — and the exact bytes of all three files afterwards. Run it
  against the current implementation; commit it green; then swap the implementation and re-run.
- A rename where the target title collides → still throws `alreadyExists`, nothing written.
- A rename of a note referenced by a `.canvas` node → the board is repointed exactly as before
  (`BoardFileOperationsTests` and `CanvasStoreTests` must stay green unedited).

---

## Task 6 — A read parses once, stats once, and a caller that wants the text asks for the text (R-05)

Cross-refs: ADR-0041 §D7; `NoteStore.swift:79-103`, `:157-173`; `VaultSession+Journal.swift:70-76`;
`TODO.md:324` (`perf-NoteStore.swift-ce3`, `-bf6`, `perf-VaultSession+Journal.swift-462`).
Budget: `Sources/Vault/NoteStore.swift`, `Sources/Vault/VaultSession+Journal.swift`,
`Sources/Vault/NoteFileOperations.swift`, `Tests/NoteStoreReadTests.swift` (~240 lines)

**Tester declares:**

```swift
extension NoteStore {
    func text(_ relativePath: String) throws -> String
    static func linkTargets(in document: NoteDocument) -> [String]   // the real one
    static func linkTargets(in text: String) -> [String]             // unchanged wrapper
    func record(from data: Data, attributes: [FileAttributeKey: Any], at relativePath: String) throws -> NoteRecord
}
```

`record(from:attributes:at:)` is the piece Task 8's actor also needs — declaring it here is what
lets Task 8 be about concurrency and nothing else.

**Coder implements:**

1. `read` parses `NoteDocument.parse(text)` **once** and passes the document to both the
   frontmatter read and `linkTargets`. The `static func linkTargets(in text: String)` keeps its
   signature (two test callers) and becomes a two-line wrapper.
2. `text(_:)` — boundary, `Data(contentsOf:)`, UTF-8 decode, `throw .notUTF8` on failure. No
   parse, no wikilink scan, no transclusion scan, no task parse, no SHA-256.
3. `record(from:attributes:at:)` — everything `read` derives, given bytes and attributes the
   caller already has. `read` is re-expressed in terms of it.
4. `NoteFileOperations`'s rename/search callers that only need the body switch from
   `store.read(…).1` to `store.text(…)`. **Find them by grep, not by memory**; `:172`, `:224` and
   `:270` in the `url(for:)` table are the neighbourhood to start in.
5. `VaultSession.moveFile` (`VaultSession+Journal.swift:70-76`) reads once: one `Data(contentsOf:)`,
   `NoteStore.hash` over those bytes, `record(from:attributes:at:)` over the same bytes. The
   second `store.read(newPath)` goes.

**Tests (red first):**

- `read` over a note with frontmatter, three wikilinks, one transclusion, one image embed and two
  tasks produces **exactly** the record it produces today — write the expected record out in full,
  field by field, and compare by whole value. `NoteRecord` is `Equatable`; use it.
- `linkTargets(in text:)` and `linkTargets(in document:)` agree on the same input, including the
  transclusion rule of ADR-0010 §D7 (`![[nota]]` counts, `![[foto.png]]` does not).
  `Tests/TransclusionTests.swift:182`, `:221` stay green unedited.
- `text(_:)` returns the same `String` `read` returns, refuses `../`, and throws `.notUTF8` on
  invalid bytes.
- `record(from:attributes:at:)` given the bytes and attributes of a file on disk equals
  `read`'s record for that file — the equivalence Task 8 depends on.
- `moveFile` still records the journal entry with the same `hashBefore`/`hashAfter` and still
  updates the index at both paths (`Tests/VaultSessionJournalTests.swift` must stay green
  unedited).
- **The double-parse is gone, asserted structurally:** `NoteStore.read`'s body contains exactly one
  `NoteDocument.parse` call. A grep-based assertion in the test file, in the shape
  `Tests/SharedSourcesPurityTests.swift` already uses for file-walking checks, if the coder wants
  it enforced rather than reviewed.

---

## Task 7 — A batch move computes one plan, and one failed item does not stop the rest (R-05, R-06)

Cross-refs: ADR-0041 §D8; `VaultSession+Move.swift:56-115` (and its doc comment at `:60-69`,
which is the decision and stays); `VaultSession+Starred.swift:32-42`;
`FolderFileOperations.repointBoardsPlan:199`; `TODO.md:324`
(`perf-VaultSession+Move.swift-2a6`, `perf-VaultSession+Starred.swift-4d9`).
Budget: `Sources/Vault/VaultSession+Move.swift`, `Sources/Vault/VaultSession+Starred.swift`,
`Sources/Vault/FolderFileOperations.swift`, `Tests/VaultBatchMoveTests.swift` (~320 lines)

**Tester declares:**

```swift
extension VaultSession {
    func moveStars(_ pairs: [(old: String, new: String)])   // one save for the whole batch
}

extension FolderFileOperations {
    /// Every `.canvas` change for every moved path, computed in one walk.
    func repointBoardsPlan(moves: [(from: String, to: String)]) -> (changes: [VaultFileChange], failures: [String])
}
```

`moveStar(from:to:)` **keeps its single-path form** — `renameFolder` calls it per note it took
with it, and that is a different caller with a different shape.

**Coder implements:**

1. `moveItems` computes one plan for the batch: one `VaultWalk` (Task 4), one
   `repointBoardsPlan(moves:)` producing every `.canvas` change at once, one
   `VaultPlanApplication.apply` (Task 5), one `moveStars`.
2. The per-item file-system moves stay per item and stay independently attempted.
   **`VaultSession+Move.swift:60-69`'s doc comment is the contract** and is not reopened: an item
   that already moved is never rolled back, the loop carries on, and the caller receives per-item
   results. `VaultMoveBatch.plan`'s refuse-before-writing-a-byte guarantee is unchanged — what
   became per-batch is the work, not the decision.
3. A `.canvas` whose repoint fails lands in `failures` for the batch, not for the item — say so in
   the doc comment, because it is a real change in where a failure is attributed.
4. `moveStars` saves `starred.json` once. `moveStar` is re-expressed as `moveStars([pair])`.

**Tests (red first):**

- **`R-05`'s call-count assertion, on a batch of N > 1.** Inject a counting seam — the cleanest is
  a closure on `FolderFileOperations` counting walk invocations, or a `VaultWalk` initialised with
  a counter the test owns. Move five notes into one folder and assert: **one** walk, **one**
  `starred.json` write, **one** frontmatter parse per file touched. Before this task the same
  fixture produces five walks and five starred writes — record both numbers in the test's comment
  so a future reader sees what was bought.
- **`R-06`, with the failing item in the middle:** a batch of at least three where item 2's
  destination already holds a file of that name (or item 2's path contains `../`, exercising
  Task 2's guard inside a batch). Assert: items 1 and 3 moved and are on disk at their new paths,
  item 2 did not move and is still at its old path, the outcome names item 2 in `failures` and
  items 1 and 3 in `movedNotes`, and **no rollback happened** — item 1 is not back where it
  started.
- A batch of five where three are starred: `starred.json` contains the three new paths, none of
  the old ones, and was written once.
- A batch where two notes are referenced by the same `.canvas`: the board is re-encoded **once**
  with both nodes repointed, not twice.
- An empty batch and a single-item batch both behave as before (`Tests/VaultMoveTests.swift`,
  `Tests/VaultMoveBatchTests.swift`, `Tests/StarredTests.swift` stay green unedited).

---

## Task 8 — The disk work of a write moves to one actor, and ordering stops being an accident (R-07)

Cross-refs: ADR-0041 §D9, §D10, §D11; `VaultSession.swift:181-221`; ADR-0001 §D2.3, §D3.3;
ADR-0007 §D6; `Project.swift:78-118`.
Budget: `Sources/Vault/VaultDisk.swift`, `Sources/Vault/VaultSession.swift`, `Project.swift`,
`Tests/VaultDiskTests.swift`, `Tests/VaultWriteOrderingTests.swift` (~420 lines)

**Tester declares:**

```swift
actor VaultDisk {
    init(store: NoteStore, history: NoteHistory)

    struct WriteOutcome: Sendable {
        let record: NoteRecord
        let hash: String
        let sequence: UInt64
        let journalProblem: String?
    }

    func write(
        _ text: String, to relativePath: String,
        precomputedHash: String,
        journalEntry: WriteJournal.Entry?,
        journal: WriteJournal?,
        recordsHistory: Bool
    ) async throws -> WriteOutcome
}

extension VaultSession {
    @discardableResult
    func write(_ text: String, to relativePath: String) async throws -> WriteResult
}
```

`WriteResult` and `WriteOutcome` (the session's existing enum at `VaultSession.swift:133-154`) are
**unchanged** — do not touch them. The actor's `WriteOutcome` is a different, new type; if the
name collision is confusing, name the actor's `DiskWriteOutcome` and say so in the commit.

**Coder implements:**

1. `VaultDisk` performs, in one hop: `boundary` check → atomic byte write → stat →
   `NoteStore.record(from:attributes:at:)` (Task 6) → `history.record` when `recordsHistory` →
   `journal.record(entry)` when a journal was passed. It owns
   `private var sequences: [String: UInt64]` and stamps each outcome.
2. `VaultSession` gains `@ObservationIgnored private let disk: VaultDisk` and
   `private var appliedSequence: [String: UInt64]`, and its `write` follows ADR-0041 §D9's sketch
   **in that order**:
   - `existing` read for the journal, unchanged;
   - `isDryRun` short-circuit **before** the hop — ADR-0007 §D6's first guardrail (`--dry-run`
     never reaches disk) depends on this line staying where it is;
   - `hash = NoteStore.hash(Data(text.utf8))` and `selfWrittenHashes[path] = hash` **before** the
     `await` (§D10 — the file cannot exist yet, so the watcher can never see a write whose hash
     the session has not recorded);
   - `await disk.write(…)`;
   - the sequence guard (§D11), then `index.update`, then the journal problem, then `return`.
3. `history.record` and the journal append are **passed into** the actor, not performed after it.
   `relativePath.hasSuffix(".md")` still decides whether history is recorded (ADR-0011 §D2) — the
   decision stays on the main actor, the writing moves.
4. The actor asserts the hash it computed equals `precomputedHash` and returns a
   `journalProblem` naming the mismatch if not. It should be impossible; a silent disagreement
   here would mean the text changed across the boundary.
5. `Project.swift`: add `"Sources/Vault/VaultDisk.swift"` to `sharedSources` (ADR-0007 §D2 — a
   file outside the globs that a tool needs must be named by hand). Then `tuist generate --no-open`.
6. The 33 call sites in the staleness table gain `await`. `saveOpenNote()` becomes `async` and its
   four call sites wrap in `Task { }`. **Mechanical only — no other change in this task.**

**Tests (red first):**

- `VaultDiskTests`: a write produces the file, the returned record equals `store.read`'s record for
  it, the history directory gained a version, and the journal gained an entry with the right
  `hashBefore`/`hashAfter`.
- `recordsHistory: false` writes no version. A `.canvas` path is the real case.
- A `../` path throws before any byte is written (the boundary, inherited).
- The sequence increments per path and is independent across paths.
- **`R-07`'s ordering test, and it must be deterministic rather than timed.** Two writes to the
  same relative path, both awaited: the file holds the second text, the index holds the second
  record, `selfWrittenHashes` holds the second hash. Then force the inversion — apply the outcomes
  in reverse order through whatever seam makes that possible (the cleanest is a test-visible
  `apply(_ outcome:)` on the session) and assert the **older record is dropped** and the index
  still holds the newer one. Assert on the drop, not only on the end state, or the test passes by
  accident when the guard is missing.
- **The §D10 hazard, asserted directly:** after `write` returns, `selfWrittenHashes[path]` equals
  `NoteStore.hash` of the bytes on disk. And, the stronger form: a test that inspects
  `selfWrittenHashes` from a task scheduled between the hash assignment and the actor's completion
  sees the hash already recorded. If no seam exists for that, assert the ordering in the
  implementation by reading it and say so — do not weaken the first assertion to compensate.
- **ADR-0007 §D6 regression:** with `isDryRun = true`, `write` returns a `WriteResult`, the file
  does **not** exist, no history version was recorded, and no journal entry was appended. This is
  the guardrail most easily broken by moving the short-circuit past the `await`.
- **ADR-0001 §D2.3 regression:** the index is updated after the write and holds the record derived
  from what was actually written, not from the text passed in. Write a note, mutate the file
  underneath through a second path, and confirm the index reflects the write, not the mutation.
- `Tests/VaultSessionTests.swift`, `Tests/NoteHistoryTests.swift`,
  `Tests/VaultSessionJournalTests.swift`, `Tests/VaultSessionFileOperationsTests.swift` and
  `Tests/TagRenameTests.swift` gain `await` and stay green otherwise. **If any assertion needs
  changing, stop** — the write's semantics were supposed to be untouched.

---

## Task 9 — The tail call sites and both connectors adopt the same pattern (R-08, R-09)

Cross-refs: ADR-0041 §D9's tail-sites paragraph; `SPEC.md` R-08's list;
`Sources/MCPServer/VaultHost.swift:44-60`; `Sources/Connector/VaultWrites.swift`;
`Sources/CLI/main.swift:11-30`; `Tests/ReleasePipelineTests.swift:180-200`.
Budget: `Sources/Features/Workspace/WorkspaceController+Files.swift`,
`Sources/Features/Workspace/BoardCardMenu.swift`,
`Sources/Features/Pratiche/PraticheController.swift`,
`Sources/Features/Pratiche/PraticaSyncEngine.swift`,
`Sources/Features/Recordings/RecordingsController.swift`,
`Sources/MCPServer/VaultHost.swift`, `Sources/Connector/VaultWrites.swift`,
`Tests/ReleasePipelineTests.swift` (~300 lines)

**Tester declares:** the new `async` signature of each touched function, read from the file rather
than guessed. `VaultHost.perform(_:_:)` and its four dispatch tables (`readNotes`, `readWork`, and
the two write tables — read `:58-60` for the real names) become `async throws`;
`VaultWrites`'s twelve functions follow.

**Coder implements:**

1. The seven tail sites `await` the session's now-async write rather than growing disk hops of
   their own. **No new actor, no second pattern** — that is the whole point of folding `R-08` into
   this chain rather than doing it twice.
2. `VaultHost.call` (`:45`) already `await`s; `perform` and the tables gain `async`. **No protocol
   change**: the same tool names, the same JSON schemas, the same `isError` semantics for a
   refusal (`:47-52`'s doc comment still governs).
3. `perg` needs no structural change (`main.swift`'s `dispatch` is `async throws` already).
   Confirm by building, not by reading.
4. `Tests/ReleasePipelineTests.swift:186-193`'s `DispatchSemaphore(value: 0)` +
   `finished.wait(timeout:)` blocks whichever actor runs it. Replace with a
   continuation-based wait that preserves the timeout and still throws `ProcessTimeoutError`.
   **Do not remove the timeout** — a hung `xcodebuild` subprocess with no timeout is a test that
   never finishes.
5. `PraticaSyncEngine` is an `actor`: its `write` hop is the existing `@MainActor` closure. Do not
   hold a non-`Sendable` value across the new suspension.

**Tests (red first where behaviour changes, green throughout where it does not):**

- `Tests/PraticheControllerTests.swift`, `Tests/PraticaSyncTests.swift`,
  `Tests/RecordingsControllerTests.swift` gain `await` and stay green otherwise.
- `Tests/ReleasePipelineTests.swift` passes, including its timeout path — add a case that drives a
  deliberately-slow command and asserts `ProcessTimeoutError` is thrown, if one does not exist.
- **`R-09`, and it is a build gate, not a unit test:**
  `xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build`
  and the same for `pergamenum-mcp`. Both must succeed. A file under `Sources/Core/**` that
  imports AppKit or SwiftUI breaks both, and the break is reported as a compiler error naming
  something else (CLAUDE.md, ADR-0007 §D2). This is the gate on the five new `Sources/Core` files.

---

## Task 10 — The sweep, the two verifications a person has to do, and the ledger (R-09, R-10, R-11, R-12)

Cross-refs: `.claude/protected-interfaces`; CLAUDE.md's merge rules; ADR-0041 §D13;
`TODO.md:245`, `:312`, `:323`, `:343`.
Budget: `TODO.md`, `docs/adr/0041-…md`, `docs/adr/0001-initial-architecture.md`,
`docs/adr/0007-ai-connector-mcp-over-the-vault.md`, `CLAUDE.md` (~90 lines; no production code)

**Orchestrator, not the coder, for steps 5-8.**

1. **The full unit suite**, `.claude/test-cmd` as written — not the vault subset. `VaultLayout` and
   `VaultFileChange` moved into `Sources/Core/**`, `NoteStore` and `VaultSession` changed
   signature, and roughly half of the 219 test files reach one of them.
2. **Both connector builds** (`R-09`, repeated here because Tasks 1, 4, 5 and 8 each added a file
   the tools compile and the last check was two tasks ago).
3. **Protected interfaces.** Run `interface-check.sh` against `.claude/protected-interfaces` and
   confirm by hand that `IndexCache.schemaVersion`, `VaultAPI.LintFinding`,
   `CompletingTextView+Pasteboard.swift`, `ImportNaming.recordingNoteTitle`,
   `PraticaNaming.messageFileName`, `Dossier.render`, `VaultAPI.PraticaSummary` and
   `MessageDocument.isPendingAttachmentEntry` appear in **zero** hunks of `git diff main...HEAD`.
   Four of those live in files this chain edits. **If any is touched, stop and report — do not
   adjust the protected-interfaces file.**
4. **Principle 2, by grep.** `git diff main...HEAD` contains no `URLSession`, no `Network.`, no
   `NWConnection`, no `socket(`, no `http`. Five new `Sources/Core` files, all Foundation-only.
   State the grep and its zero result in the report.
5. **`scripts/uitests.sh`** before the merge to `main`, per CLAUDE.md's standing rule. Kill stale
   instances first; read the per-test seconds before believing a red (60.2 s names the launch
   timeout, not a defect).
6. **`R-10`, by hand:** rebuild `pergamenum-mcp` and run
   `python3 scripts/mcp-smoke.py <binary>`. It must complete with no regression. The MCP protocol
   layer has no unit tests and cannot have them (ADR-0007, Consequences); this is the only check
   there is. *(no-test: manual operational verification against a running stdio server, not a
   Swift Testing assertion.)*
7. **`R-11`, by hand, with Stefano at the keyboard:** build `perg` Release, point it at a scratch
   vault (never `~/Labs`), and run `note rename`, `note move`, `journal undo` and a `--dry-run` of
   each end to end. Confirm the dry run prints a diff and writes nothing, and that `journal undo`
   still refuses when the file has moved on. *(no-test: manual CLI verification against a real
   vault, not an automated assertion.)*
8. **`R-12`, the ledger:** tick `PG-122`, `PG-145`, `PG-140` and `PG-137` in `TODO.md` (lines 245,
   343, 323, 312) with a reference to ADR-0041 and this PR; close GH #222, #245, #240, #237 with
   the same reference. Add ADR-0041 to CLAUDE.md's «Chain decision index» (one line, existing form)
   and a three-to-five-line block to the «Decisions from later chains» section covering §D1's
   resolver shape, §D6's relocation, §D9-§D11's actor and ordering rule, and §D12's narrowing.
   Append a cross-reference to ADR-0001 and ADR-0007 in the shape ADR-0025 and ADR-0037 use —
   **do not rewrite either ADR's original text**; ADR-0041 extends them and says so in its own
   «Relationship» section. Check `PROJECT_BRIEF.md`'s Status section rather than assuming: this
   closes no milestone, so most likely no change. *(no-test: ledger and documentation bookkeeping,
   not a code assertion.)*

---

## Risks, dependencies, and the HITL gates

- **The boundary guard is the reason this chain is P1, and a wrong guard is worse than none.** An
  over-strict `url(for:)` refuses legitimate paths — a vault under a symlinked home directory, a
  note whose name contains `..`, a relative path with a leading `./`. Task 1's symlink test is the
  specific regression this repo has already had once (`NoteStore.swift:48-55`). Run the app against
  the real Labs vault after Task 2, not only after Task 10.
- **`VaultSession.write` becoming `async` is the largest single change here**, and the four
  SwiftUI call sites that must wrap in `Task { }` are exactly where unordered starts appear. §D11's
  sequence number is what makes that harmless to the index. If the ordering test in Task 8 is
  written as a timing test (sleep, then assert) it will pass without the guard and prove nothing.
- **A `Task { }` around `saveOpenNote()` changes when the editor's buffer is marked saved.**
  `saveOpenNote` sets `note.savedText = note.text` after the write; with an `await` in between, a
  keystroke can land in that window. Read `VaultController+Editing.swift:12-22` before wiring, and
  decide deliberately whether `savedText` records the text that was written or the text as of the
  return. The first is correct; the second silently loses a keystroke's worth of «unsaved» state.
- **Four protected interfaces live in files this chain edits** (`PraticaNaming.messageFileName`,
  `Dossier.render`, `VaultAPI.PraticaSummary`, `ImportNaming.recordingNoteTitle`).
  `interface-check.sh` BLOCKS on any of them. Task 10 step 3 is the check; do not defer it to the
  end if Tasks 2 and 9 touched those files.
- **`tuist generate` must run after Task 3 and after Task 8's `Project.swift` edit.** CLAUDE.md is
  explicit: the generated project lists files by path, and the failure names the compiler rather
  than the cause. A `git stash`/`git checkout` between tasks needs one too.
- **The characterization test in Task 5 is the only thing between «`renamePlan` computes the same
  changes» and «changes that look the same».** It must be committed green against the *old*
  implementation before `rename` is touched. If it is written after, it tests the new behaviour
  against itself.
- **Two type relocations (`VaultLayout`, `FileChange`) plus eighteen file moves guarantee a merge
  conflict** with any in-flight branch touching `Sources/Vault`. Check `git branch -a` before
  starting; this chain should have `main` to itself.
- **`PlaudVaultStore.swift:164`, `:181` match the `try write(` grep but are probably that type's
  own method.** Verify before touching. A wrong `await` there is a compile error, which is the
  good case; a right-looking wrong edit is not.
- **HITL gates**: the branch creation; every commit and every push; the merge to `main`, gated
  behind `scripts/uitests.sh` and both connector builds; Task 10 step 7's manual `perg` pass
  against a real vault (it moves files); closing the four GitHub issues; and the operator's
  decision on the protected-interface proposal below, which BLOCKS once it exists.

## PROPOSED PROTECTED INTERFACES

```
Sources/Core/Vault/VaultBoundary.swift:VaultBoundary.url(for:) — added per ADR-0041 §D1; the vault's only path-resolution door. A signature change that removes `throws`, or a behaviour change that resolves symlinks per call instead of once at construction, silently reopens the path-traversal gap this chain closed and reintroduces the symlinked-vault regression recorded at NoteStore.swift:48-55.
```

Propose only. The architect cannot write `.claude/protected-interfaces`; the operator creates the
entry by hand if they want it, and it BLOCKS from then on. **Recommendation: add it after this
chain merges, not at Gate 2** — the coder creates this function in Task 1 and may refine it in
Task 2, and a block on a signature that is still being written is a block nobody will understand.
`VaultWalk`, `VaultPlanApplication`, `VaultFileChange` and `VaultDisk` are deliberately **not**
proposed: internal structure, expected to keep moving.

## PROPOSED AUDIT PROFILE

```
risk: high — the chain's first item is a path-traversal fix, and its last moves every note write in the app onto a new concurrency boundary. A wrong guard writes outside somebody's vault; a wrong ordering rule leaves the index disagreeing with the files, which ADR-0001 §D2.3 exists to prevent. Not reversible in the sense that matters: a note written to the wrong place is noticed late or never.
task_type: legacy-integration — surgery on working, heavily-tested code across 21 files and five layers, where roughly half of 219 test files depend on the exact behaviour of the two types being changed. No new algorithm is invented; the whole difficulty is not breaking what is there.
```
