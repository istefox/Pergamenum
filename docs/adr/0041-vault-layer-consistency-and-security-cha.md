# ADR-0041: The vault layer gets one boundary, one walk, and one place where the disk is touched

- **Status**: accepted
- **Date**: 2026-09-12
- **Context**: `SPEC.md` (this chain), `TODO.md` Deep Refactor Roadmap — `PG-122` (GH #222),
  `PG-145` (GH #245), `PG-140` (GH #240), `PG-137` (GH #237)
- **Relates to**: ADR-0001 §D1, §D2.3, §D3.3 — **extended and made mechanical, not amended**;
  ADR-0007 §D2, §D3, §D6 — **§D3 is completed, §D2's file list grows by one name, §D6 stands**
- **Reopens**: nothing. No SPEC §14 decision is revisited and no on-disk format changes.

## Context

Four findings from the deep-refactor pass land on the same eleven files. Three of them are
about the same missing abstraction seen from three angles, and the fourth cannot be done
safely until the other three have reduced the number of places that touch the disk. They are
designed together because designing them apart means designing the same helper four times and
discovering the fourth time that the first three chose differently — which is, precisely, the
defect `PG-145` records.

**The security gap is real and is the reason this chain is `P1`.** `NoteStore` resolves its
root once at construction (`NoteStore.swift:56-60`) and checks every path it is handed against
that root in `assertInsideVault` (`:125-136`). The check is `private`, and it is called from
exactly two places: `read` (`:81`) and `write` (`:110`). Every other path in the vault layer
that turns a caller-supplied relative string into a URL does it by hand, with
`root.appending(path:)` and nothing else:

| Where | Line | What reaches it |
| --- | --- | --- |
| `NoteStore.url(for:)` | `NoteStore.swift:74` | the unguarded door 31 call sites use to get a URL |
| `CanvasStore.url(forBoard:)` | `CanvasStore.swift:25` | a board path from a `^[[…]]` marker |
| `VaultSession.moveFile` | `VaultSession+Journal.swift:58` | `perg note move`, the MCP `note_move` tool |
| `VaultSession.trashFile` | `VaultSession+Journal.swift:106` | `perg note trash`, the MCP `note_trash` tool |
| `ThumbnailStore.thumbnail(for:width:)` | `ThumbnailStore.swift:43` | a `.canvas` node's `file` property |
| `WorkspaceController.fileURL(for:)` | `WorkspaceController+Files.swift:12` | a `.canvas` node's `file` property |
| `BoardCardMenu` open-in-Finder | `BoardCardMenu.swift:181` | a `.canvas` node's `file` property, handed to `NSWorkspace.shared.open` |
| `PraticheController.readTimeline` | `PraticheController.swift:775` | an attachment name out of a message note's frontmatter |
| `PraticaSyncEngine.regenerationPlan` | `PraticaSyncEngine.swift:758` | a pratica folder name plus a derived file name |

A `.canvas` file is ordinary JSON that a person can edit in any text editor, that Obsidian can
write, and that this app's own drag-and-drop writes from a pasteboard payload. A message note's
frontmatter is generated from an `.emlx` whose filename Apple Mail chose. A wikilink is typed
text. The `pergamenum://note?file=` route is a URL anybody can hand the app. None of these is
trusted input, and every one of them reaches a row of that table.

**There is a tenth gap the SPEC does not name, found while reading the apply-plan loops.**
Three of the six loops do not write through `NoteStore` at all:

```swift
try Data(change.after.utf8).write(to: store.url(for: change.path), options: .atomic)
```

at `FolderFileOperations.swift:321`, `BoardFileOperations.swift:171` and `:287`. Each is
correct about *why* it bypasses `NoteStore.write` — a `.canvas` is not a note and the planned
text is already an encoded document — and each therefore also bypasses the one check
`NoteStore.write` performs. `change.path` comes out of `repointBoardsPlan`, which built it from
a vault walk, so today it is in practice safe; it is safe by provenance, which is exactly the
kind of safety that stops being true when somebody adds a seventh caller. This ADR closes it
with the same guard as the other nine and counts it as part of `R-01`.

### The three drifted copies, at the line

Three implementations of "walk the vault, skip the dot-directories":
`VaultScanner.swift:49-70` (asks for four resource keys, reuses cache rows),
`CanvasStore.walk()` at `CanvasStore.swift:190-232` (yields folders and boards), and
`FolderFileOperations.walk(_:)` at `FolderFileOperations.swift:91-129` (yields note paths and a
subfolder count under one subtree). Two of them carry a doc comment saying they mirror a third
— `CanvasStore.swift:187` says «The walk mirrors `VaultScanner.scan()`» and
`FolderFileOperations.swift:78` says «The walk mirrors `CanvasStore.allBoards()`» — which is a
comment doing the work a function should be doing.

Six implementations of "perform the planned changes, collecting failures":
`NoteFileOperations.rename` at `:226-250` (which does not consult a plan at all — see below),
`FolderFileOperations.renameFolder` at `:312-327` (two loops), `BoardFileOperations.renameBoard`
at `:159-177` (two loops), `BoardFileOperations.moveBoard` at `:280-290`, and
`VaultSession+BoardDrop.swift:66`. Every one of them is the same eight lines: iterate
`[FileChange]`, write, append to `rewrittenPaths` on success, append to `failures` on error.

And `NoteFileOperations.rename` (`:204-256`) re-implements what `renamePlan` (`:88-127`) already
computes: it reads each known path, rewrites its links with `NoteRename.rewritingLinks`, writes
it back, and records «non leggibile» for the ones it could not read — which is, line for line,
what `renamePlan` produces as `plan.noteChanges` plus `plan.failures`. Two spellings of one
rule, in one file, thirty lines apart.

### What the async move actually costs, measured rather than assumed

`PG-137` names `VaultSession.swift:196` and `:218`. Line 196 is
`index.update(try store.read(relativePath).record, at: relativePath)` — a full re-read of the
file that was just written, off disk, on the main actor, including a `NoteDocument.parse` that
runs twice (see §D7). Line 218 is `history.record(text, for: relativePath)` — a second file
written to disk, synchronously, on every `.md` save. Both happen on every keystroke that
triggers an autosave.

Making `VaultSession.write` `async` is not free, and the measurement matters:

- **20 unqualified call sites** inside `VaultSession` extensions (`+Tasks` ×3, `+Notes` ×3,
  `+TimeBlocks` ×2, `+Journal` ×2, `+Watching`, `+TagRename`, `+SampleViews`, `+Files`,
  `+EventNotes`, `+Diary`, `+BoardDrop`, plus `PlaudVaultStore` ×2 and `VaultHost` ×1).
- **13 qualified call sites** outside it (`PraticaEntryComposer` ×2, `NuovaPraticaWizard`,
  `PraticheController` ×3, `DossierWriter`, `PraticaCommandActions`, `RecordingsController`,
  `VaultWrites`, `VaultController+Editing` ×2).
- `saveOpenNote()` — the one the editor calls — has **four** production call sites
  (`CommandActions.swift:178`, `EditorColumn+Text.swift:140`, `NoteTabBar.swift:77`,
  `EditorColumn+Closing.swift:40`).
- `perg` is **already `async throws` end to end**: `Sources/CLI/main.swift`'s `dispatch` and
  every group it calls are `async`. The CLI absorbs this change with no structural edit.
- `pergamenum-mcp`'s `VaultHost.call` is already `async`; only `perform` and the four dispatch
  tables under it are not.

So the cascade is about thirty-five production call sites, not the three hundred a naive grep
suggests, and the one binary that could have made it expensive already awaits everything.

### The hazard the async move creates, which the finding does not mention

ADR-0001 §D3.3 refuses suppression windows and recognises the app's own writes by content hash:
`selfWrittenHashes[relativePath] = hash` at `VaultSession.swift:195`, set from the hash
`store.write` returned. Today the file cannot exist before that line runs, because the write is
synchronous. Move the write behind an `await` and the FSEvents batch can, in principle, arrive
and be reconciled before the main actor gets its continuation back — at which point the app's
own write is misread as an external edit and, if the editor holds unsaved changes, raises the
conflict prompt of §D3.4 against itself.

The 200 ms debounce makes this unlikely. «Unlikely» is the argument ADR-0001 §D3.3 already
rejected once, by name. This ADR closes it structurally in §D10 rather than relying on the
debounce.

## Decision

### §D1 — The guard is a resolver, not an assertion: there is no way to obtain a URL inside the vault without passing it

`Sources/Core/Vault/VaultBoundary.swift`, a `Sendable` value type holding the resolved root:

```swift
struct VaultBoundary: Sendable {
    let root: URL
    init(root: URL)                                  // resolvingSymlinksInPath().standardizedFileURL, once
    func url(for relativePath: String) throws -> URL // the only door
    func contains(_ url: URL) -> Bool                // for a URL that arrived from elsewhere
}

extension VaultBoundary {
    enum Violation: Error, CustomStringConvertible { case outsideVault(String) }
}
```

**The shape is the decision.** `assertInsideVault(url, path) throws` is an assertion: a call
site may make it or not, and nothing says which. `url(for:) throws -> URL` is a resolver: a
call site that wants a URL has no other way to get one, so forgetting the check is not a thing
a programmer can do. This repository has made this move before and said why — ADR-0007 §D2's
«the rule enforces itself instead of being remembered», ADR-0025 §D1's refusal to derive a
board path from a folder name. A security check that depends on being remembered is a security
check with a half-life.

Symlinks are resolved **once, in `init`**, and never again. This is not tidiness either: the
comment at `NoteStore.swift:48-55` records the regression that made it necessary —
`resolvingSymlinksInPath` does nothing for a path that does not yet exist, so a not-yet-created
note under a symlinked vault kept the unresolved spelling while the root had the resolved one,
and every write was refused as «outside the vault». `VaultBoundary` inherits that comment
verbatim along with the behaviour.

`contains(_:)` exists for the two call sites that are handed a `URL` rather than a relative
string (Quick Look's `selectedFileURLs`, and a dropped file's URL). It is the same comparison,
not a second rule.

**A violation throws. It never logs and continues.** The SPEC settles this and the reason is in
the table above: the input is a wikilink, a URL-scheme parameter, or a `.canvas` node property.
A path-traversal attempt that produces a logged line and a successful write outside the vault
is a vulnerability with a paper trail.

### §D2 — `NoteStore.url(for:)` becomes `throws`, and `StoreError.outsideVault` is retired in favour of `VaultBoundary.Violation`

`NoteStore` keeps its `root` property (31 call sites read `store.root` or `store.url(for:)`) and
gains a `boundary: VaultBoundary` it delegates to. `url(for:)` becomes
`func url(for relativePath: String) throws -> URL`, and `assertInsideVault` is deleted rather
than kept as a private forwarder.

This is the deliberate signature change the SPEC names, and it is the whole of the fix: making
the *door* throwing is what converts «nine call sites forgot the check» into «nine call sites
will not compile until they handle it». Making the guard available but optional would have
fixed the nine sites that were audited and none of the ones written next year.

`NoteStore.StoreError` loses its `.outsideVault` case and keeps `.notUTF8`. Two error types
spelling the same refusal is the drift this chain exists to remove, and the case has no call
site outside `NoteStore.swift` itself (`:64`, `:69`, `:134` — verified, there are no others in
`Sources/` or `Tests/`), so retiring it costs nothing.

**The 31 `store.url(for:)` call sites are listed in the plan, not left for the coder to find.**
Twenty-six of them are already inside `throws` functions in the four Vault file-operation
files; the remaining five (`VaultSession.swift:113`, `VaultController+Routes.swift`,
`FolderFileOperations+Move.swift`, `Sources/App/WindowPlace.swift`,
`Tests/CardRoundTripTests.swift`) each need a decision, and the plan makes it for each.

### §D3 — One walk, parameterised by subtree and by resource keys, standardising the root once

`Sources/Core/Vault/VaultWalk.swift`:

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
    init(boundary: VaultBoundary, subfolder: String, keys: Set<URLResourceKey>) throws
    func forEach(_ body: (Entry) -> Void)
}
```

Three properties, each of which is one of the three findings:

1. **It is built from a `VaultBoundary`, not from a `URL`.** Every path it yields has already
   passed the guard, so the walk cannot be the way somebody re-enters the vault layer around
   `PG-122`'s fix. This is the composition the SPEC asks for, spelled as a type dependency
   rather than as a convention.
2. **The exclusion rule is consulted in one place.** `VaultLayout.isExcludedDirectory` decides,
   and `skipDescendants()` is called by the walk — not by three callers who each remembered.
3. **The root is standardised once, in `init`.** `VaultScanner.relativePath(of:under:)`
   (`:190-191`) calls `root.standardizedFileURL.path(percentEncoded: false)` on every file of
   every scan; the walk computes it once and drops the prefix. That is `PG-140`'s
   `perf-VaultScanner.swift-a0b`, closed for free by `PG-145`'s helper, which is the reason the
   SPEC pairs them.

`VaultLayout` moves from `Sources/Vault/VaultSettings.swift:279-296` to
`Sources/Core/Conventions/VaultLayout.swift`. It is four string constants and one predicate over
a file name — a naming convention, which is what ADR-0001 §D1 says `Core` is for — and `Core`
cannot depend on `Vault`, so the walk could not otherwise reach it. All 36 call sites are
unchanged: the type keeps its name and both files are target-internal to the same module.

`VaultScanner`, `CanvasStore.walk()` and `FolderFileOperations.walk(_:)` are rewritten as calls
to it. `VaultScanner` keeps its own cache-reuse logic, which is not a walk concern.

### §D4 — The apply-plan loop is one pure function over `[VaultFileChange]`, with the writer injected

`Sources/Core/Vault/VaultPlanApplication.swift`:

```swift
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

The writer is **injected rather than assumed**, because the note/`.canvas` split is a real
distinction this repo has stated twice (`BoardFileOperations.swift:168-170`: «a `.canvas` is not
a note and the planned text is already the encoded document»), not an accident to be unified
away. What is shared is the loop, the failure-string format and the `rewrittenPaths`
bookkeeping; what is not shared stays at the call site, one line long and visible.

`NoteFileOperations.FileChange` moves to `Sources/Core/Vault/VaultFileChange.swift` as
`VaultFileChange`, because `Core` may not reference `Vault`. Nineteen references across five
files change name; the plan lists all nineteen. **No typealias is left behind.** A type with two
names is a type a future reader has to check twice, and the migration is mechanical.

The `.canvas` writer closure resolves its URL through `try store.url(for:)` (§D2), which is how
the three raw-bytes writes named in the Context section acquire the guard they never had.

### §D5 — `NoteFileOperations.rename` is deleted down to a call to `renamePlan` plus the applier

```swift
let plan = try renamePlan(relativePath, to: newTitle, knownPaths: knownPaths)
// move the file first — see the existing doc comment at :205-208, which still governs
var outcome = Outcome(newPath: plan.newPath, failures: plan.failures)
let notes = VaultPlanApplication.apply(plan.noteChanges) { try store.write($0.after, to: $0.path) }
let boards = VaultPlanApplication.apply(plan.boardChanges) { try Data($0.after.utf8).write(to: try store.url(for: $0.path), options: .atomic) }
```

One behavioural difference must be checked rather than assumed, and the plan requires a
characterization test **before** the change: today's `rename` reads each note *after* the file
has moved, substituting `newPath` for the renamed note (`:235`); `renamePlan` reads *before*,
and performs the same substitution as `writePath` when it builds the change (`:106-118`). The
bytes are identical either way, and both record `"\(path): non leggibile"` for an unreadable
file — but «identical by inspection» is how the two copies drifted in the first place. A golden
test over a three-note vault, written against the current implementation and re-run against the
new one, is what makes this a refactor rather than a rewrite.

### §D6 — `VaultController` and its seventeen extensions move to `Sources/App/`, in one commit, with no content change

`Sources/Vault/` holds eighteen files whose names begin with `VaultController`. One of them
imports SwiftUI (`VaultController.swift:4`); the other seventeen are extensions on a
`@MainActor @Observable` type that exists to be watched by SwiftUI views, which is app-shell
code whether or not it names the framework. All eighteen move to `Sources/App/`, beside
`PergamenumApp`, `RootView`, `CommandActions` and `VaultCommands`.

**This goes beyond the SPEC's scope item 3, which names one file, and the reason is that the
intermediate state is worse than either end.** A type declared in `App` and extended from
seventeen files in `Vault` leaves the vault layer full of exactly the code the finding is about,
while making the type harder to find than it is today. `R-04` is satisfied by moving one file;
the finding is not. The cost is eighteen `git mv` calls with no content change plus one
`tuist generate`, in a task of its own, verified by a build.

Three consequences worth stating:

- **No `Project.swift` edit is needed.** The app target globs `Sources/**` minus the two
  command-line-tool directories (`Project.swift:203-205`), and no `VaultController*` file
  appears in `sharedSources` — it never did, which is ADR-0007 §D3 working as designed. Neither
  connector is affected by the move, so `R-09` is about `Sources/Core` growing, not about this.
- **`tuist generate` runs immediately after**, per CLAUDE.md: the generated project lists files
  by path and the build fails naming the compiler rather than the cause.
- **`R-04`'s verification grep must be anchored.** `grep -rn "import SwiftUI" Sources/Vault/`
  reports `VaultState.swift` — a false positive from its own doc comment at `:8`, which quotes
  the string while explaining why the file must not contain it. The check is
  `grep -rn "^import SwiftUI" Sources/Vault/`, and it must return nothing.

### §D7 — A read parses once and stats once; a caller that wants only the text asks for the text

`NoteStore.read` (`:79-103`) parses the document twice: `NoteDocument.parse(text).frontmatter`
at `:93`, and again inside `Self.linkTargets(in: text)` at `:94`, whose body opens with
`let document = NoteDocument.parse(text)` (`:165`). The fix is to parse once and pass the
document to both consumers.

`static func linkTargets(in text: String) -> [String]` **keeps its signature** — it has two
external call sites, both in `Tests/TransclusionTests.swift` (`:182`, `:221`) — and becomes a
thin wrapper over a new `linkTargets(in document: NoteDocument)`. One implementation, two entry
points, no drift surface.

`NoteStore` gains `func text(_ relativePath: String) throws -> String`: the guard, the read, the
UTF-8 decode, and nothing else. `PG-140`'s `perf-NoteStore.swift-ce3` is about the callers that
pay a full record derivation — parse, wikilink scan, transclusion scan, task parse, SHA-256 —
to obtain a `String` they then rewrite. The rename/search callers switch to it.

`VaultSession.moveFile` (`VaultSession+Journal.swift:70-76`) reads the moved file twice: once as
`Data(contentsOf: destination)` to hash, once as `store.read(newPath)` to derive the record. It
becomes one read, hashed and derived from the same bytes, through a new
`NoteStore.record(from:at:)` that takes the `Data` and the file's attributes. That helper is
also what §D9's actor returns, which is why the two findings are one change.

### §D8 — A batch move computes one plan: one walk, one repoint pass, one starred rewrite

`VaultSession.moveItems` (`VaultSession+Move.swift:70-110`) loops over items and calls
`moveNote` / `moveBoard` / `moveFolder` per item. Each of those runs `repointBoardsPlan`, which
walks the vault and re-encodes every `.canvas` that names the moved path. A batch of ten notes
therefore walks the vault ten times and re-encodes the same boards ten times
(`perf-VaultSession+Move.swift-2a6`). Each `moveStar` writes `starred.json`
(`VaultSession+Starred.swift:41`), so ten moved starred notes write it ten times
(`perf-VaultSession+Starred.swift-4d9`).

After this chain: one `VaultWalk` for the batch, one repoint pass computing every change for
every moved path at once, one `VaultPlanApplication.apply`, and one
`moveStars(_ pairs: [(old: String, new: String)])` that saves once.

**Failure stays best-effort per item, and the existing doc comment at
`VaultSession+Move.swift:60-69` is the reason, restated rather than reopened.** An item that
already moved is not rolled back to satisfy an all-or-nothing contract the file system does not
provide; the caller receives which items succeeded and which failed. `VaultMoveBatch.plan`'s
refuse-before-writing-a-byte guarantee is unchanged — what becomes per-batch is the *work*, not
the *decision*.

### §D9 — The disk work of a write moves to one actor; the index update stays exactly where it is

`Sources/Vault/VaultDisk.swift`, added by hand to `sharedSources` (ADR-0007 §D2's rule: a file
outside the globs that a tool needs must be named):

```swift
actor VaultDisk {
    init(store: NoteStore, history: NoteHistory)

    struct WriteOutcome: Sendable {
        let record: NoteRecord
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
```

One actor hop performs, in order: the boundary check, the atomic byte write, the stat, the
record derivation (§D7's helper), the version-history write, and the journal append. Five disk
operations that are today five separate synchronous main-actor calls become one suspension.

`VaultSession.write` becomes `async throws` and keeps its body's shape and its order:

```swift
let existing = (journal != nil && !isDryRun) ? try? read(relativePath) : nil
guard !isDryRun else { return WriteResult(path: relativePath, text: text) }

let hash = NoteStore.hash(Data(text.utf8))     // §D10 — on the main actor, before the hop
selfWrittenHashes[relativePath] = hash          // §D10 — before the file can exist

let outcome = try await disk.write(text, to: relativePath, precomputedHash: hash, …)

guard outcome.sequence > appliedSequence[relativePath, default: 0] else { … }  // §D11
appliedSequence[relativePath] = outcome.sequence
index.update(outcome.record, at: relativePath)
if let problem = outcome.journalProblem { recordProblem(problem) }
return WriteResult(path: relativePath, text: text)
```

**ADR-0001 §D2.3 is preserved literally, not approximately.** «Writes go to files first, index
second» is still true; the index is still updated immediately after the write and still never
written as the primary effect of a user action; the cache is still disposable. What changed is
*which thread moves the bytes*, and nothing else. The crash window §D2.3 cares about — a crash
between the file write and the index update leaving the file correct and the cache stale — is
the same window, on the same side, and a stale cache is still recovered by a scan.

`isDryRun` is evaluated **before** the hop, so a dry run still never reaches the actor and ADR-0007
§D6's first guardrail is untouched. The journal is passed *into* the actor rather than written
after it, so the entry and the bytes it describes are written under one serialization — which is
slightly stronger than today, where a crash between them could leave a journal entry for a write
that did not happen.

**The tail sites (`R-08`)** — `WorkspaceController+Files`, `BoardCardMenu`, `PraticheController`
(×2), `PraticaSyncEngine`, `RecordingsController`, `MCPServer/VaultHost` — adopt the same
pattern: `await` the session's now-async write rather than growing their own disk hops.
`VaultHost.perform` and its four dispatch tables gain `async`, as do the twelve functions of
`Sources/Connector/VaultWrites.swift`. `perg` needs no structural change at all
(`Sources/CLI/main.swift`'s `dispatch` is already `async throws`). `Tests/ReleasePipelineTests.swift:189`'s
`DispatchSemaphore.wait(timeout:)` — which blocks whichever actor runs it — becomes a
continuation-based wait.

### §D10 — The hash is computed on the main actor, before the hop, and that is what keeps ADR-0001 §D3.3 true

`selfWrittenHashes[relativePath]` is set from `NoteStore.hash(Data(text.utf8))` **before** the
`await`, not from the hash the actor returns.

The reasoning is the whole of the Context section's last subsection. The hash is a pure function
of text the main actor already holds; computing it there costs microseconds of CPU and zero I/O,
which is not what `PG-137` is about. Computing it there makes it impossible for an FSEvents batch
to observe a file whose hash the session has not yet recorded, because at the moment the hash is
recorded the file does not exist. The actor still returns the hash it wrote; the session asserts
the two agree and records a problem if they do not, which would mean the text was mutated across
the boundary and is worth knowing about.

This is a *strengthening* of ADR-0001 §D3.3, not an amendment. §D3.3's argument was that
suppression windows are timing-dependent and hash comparison is not; the async move would have
smuggled a timing dependency back in through the side door, and this closes it with the same
reasoning that closed it the first time.

### §D11 — Ordering is a per-path sequence number the actor stamps, not an assumption about continuation scheduling

An `actor` serialises its own isolated state, so two `write` calls for the same path cannot
interleave on disk. It does **not** guarantee that the two main-actor continuations resume in
the order the actor completed them: continuation scheduling on the main actor is FIFO in
practice and is not a documented guarantee, and a call site that starts a write from inside
`Task { }` (which a SwiftUI callback must) has no ordering of its own at all.

So `VaultDisk` keeps `private var sequences: [String: UInt64]`, increments per path, and stamps
each outcome. `VaultSession` keeps `appliedSequence: [String: UInt64]` and **drops an outcome
whose sequence is lower than the one already applied**. An older record can never overwrite a
newer one in the index, whatever order the continuations arrive in.

This is what `R-07`'s «two rapid writes to the same relative path» test asserts, and it is
deterministic rather than timing-sensitive: the test drives two writes, awaits both, and checks
that the index holds the second text and that the sequence bookkeeping recorded exactly one
drop when the order is forced to invert.

**Explicitly rejected, as the SPEC requires**: `Task.detached` fire-and-forget per call. It gives
neither disk ordering nor index ordering, and it is what a naive `Task { await save() }` at a
SwiftUI call site amounts to — which is why §D11 exists rather than being left as a call-site
discipline.

### §D12 — `read` stays synchronous, which narrows the SPEC deliberately

The SPEC's Architecture section says «`VaultSession`'s write path (and the equivalent read
path)». This ADR moves the write path only, and leaves `read` synchronous.

Three reasons, and the call is recorded here rather than left implicit:

1. **The finding does not name it.** `PG-137` cites `VaultSession.swift:196` and `:218`, both in
   the write path. `R-07` and `R-08`, the two criteria that must be satisfied, are both about the
   write path and the tail call sites. Nothing in the success criteria asks for an async read.
2. **The cost is already being removed.** A read is one `Data(contentsOf:)` plus a parse; §D7
   halves the parse and gives callers who want only the text a door that skips the derivation
   entirely. That is the measurable part of the read's main-actor cost.
3. **An async read is a much larger and worse change.** `VaultSession.read` has 25 call sites,
   several of them inside synchronous `@Observable` computed properties that SwiftUI evaluates
   from `body`. A `body` cannot `await`. Converting them means caching read results in stored
   state and invalidating that cache — a second index, in the facade, with its own staleness
   rules. That is a larger design than this chain, and it would be a bad one.

If a cold read ever shows up in a profile, it gets its own ADR with a measurement attached.
Guessing now would be paying for a problem that has not been shown to exist, which is the same
judgement ADR-0001 made about GRDB and about module extraction.

### §D13 — What this chain does not touch

Stated so that a reader does not have to infer it: no on-disk format changes — not note
frontmatter (SPEC §4.3's closed four keys), not the tag grammar (§4.4), not JSON Canvas 1.0, not
`.pergamenum/` layout, not `IndexCache.schemaVersion`. No user-visible behaviour changes, no new
setting, no new UI. No network call is added anywhere; principle 2 and its two named exceptions
(ADR-0031, ADR-0032) are untouched. The five task views of ADR-0013 §D6, the board addressing of
ADR-0025 §D1 and the write guardrails of ADR-0007 §D6 are all left exactly as they are.

## Relationship to ADR-0001 and ADR-0007

**ADR-0001 §D1 (folder layers, one-way arrows) — reinforced, not amended.** §D1 declared
`Features → {Core, Vault, Index, DesignSystem}`, `{Vault, Index} → Core`, `Core → stdlib`, and
said the arrows would be enforced by review rather than by the compiler. Review let two of them
slip: `VaultController.swift` put SwiftUI inside `Vault`, and `VaultLayout` — a pure naming
convention, which §D1 names as `Core`'s job — sat in `Vault` where `Core` could not reach it.
§D3 and §D6 above put both back on the right side of the arrow. Nothing about §D1's decision
changes; this chain is §D1 being applied rather than revised.

**ADR-0001 §D2.3 (files first, index second) — preserved literally, and made mechanical.** See
§D9. The invariant survives verbatim; what used to hold because the code happened to be
synchronous now holds because §D11 makes out-of-order application impossible. That is a stronger
guarantee than the one §D2.3 was written against.

**ADR-0001 §D2.1/§D2.2 (the index is disposable, a migration failure rebuilds) — untouched.**
No schema change, no migration, `IndexCache.schemaVersion` unmoved. It is a protected interface
and the plan checks that it appears in zero hunks of the diff.

**ADR-0001 §D3.3 (content-hash self-write recognition) — preserved, and a new hazard closed
before it could open.** See §D10.

**ADR-0001 §D3.4 (external-change prompt) — untouched.** The conflict prompt fires on the same
condition, from the same place.

**ADR-0007 §D2 (one set of files, three binaries) — extended by exactly one name.**
`Sources/Vault/VaultDisk.swift` joins `sharedSources`; everything else this chain adds lands
under `Sources/Core/**`, which is already a full glob and needs no manifest edit. The property
§D2 prizes — a stray `import SwiftUI` in `Core` breaks both connector builds — is what makes
`R-09` a real gate rather than a formality, and it is why `VaultBoundary`, `VaultWalk`,
`VaultFileChange`, `VaultPlanApplication` and `VaultLayout` are Foundation-only by construction.

**ADR-0007 §D3 (`VaultSession` owns the vault, `VaultController` is the observable facade) —
completed, not amended.** §D3 moved the *behaviour* out of `VaultController` and left the
*file* in `Sources/Vault`, where its `import SwiftUI` contradicted ADR-0001 §D1. §D6 above
finishes the move §D3 started. The split itself — what lives on the session, what lives on the
facade — is unchanged, and the async surface change stays on the session side of it exactly as
§D3 arranged.

**ADR-0007 §D6 (writing is off by default, reversible, never silent) — all three guardrails
stand.** `--allow-write` gating is untouched; `dryRun` still defaults to true and still
short-circuits before any disk contact (§D9); `WriteJournal` still records path, hash-before,
hash-after and previous text, and `journal undo` still refuses on a hash mismatch. The journal
write moves *inside* the actor, which is a location change that makes the entry and the bytes
it describes share one serialization.

**ADR-0016's journalled move/rename/trash — untouched in contract, touched in implementation.**
`moveFile` and `trashFile` keep their journal vocabulary and their `pathBefore` semantics; §D7
only stops `moveFile` reading the same file twice.

## Alternatives considered

**Keep `assertInsideVault` as an assertion and call it from the nine sites.** Rejected. It fixes
the nine call sites that were audited in September 2026 and nothing about the tenth, written
later by somebody who did not read this ADR. The resolver shape of §D1 makes the check
unforgettable rather than merely available, at the cost of a throwing `url(for:)` — which is the
cost worth paying, because the compiler then does the auditing.

**Leave `NoteStore.url(for:)` non-throwing and add a second, throwing `resolved(_:)`.** Rejected,
and this repository has rejected the same shape twice before: ADR-0007 §D6's refusal of a
`preview` variant beside every write («two code paths for one behaviour and the second one
drifts») and ADR-0025's refusal of a lenient second board-path derivation. A non-throwing door
left standing beside a throwing one is a door people will keep using.

**Log a boundary violation and continue.** Rejected on the SPEC's own reasoning, restated: the
untrusted input in these paths comes from wikilinks and the URL scheme. A refusal that writes a
line to the log and then performs the write is not a refusal.

**Make the walk an `AsyncSequence`.** Rejected. The three callers are synchronous and two of
them (`CanvasStore.allBoards`, `FolderFileOperations.walk`) are called from synchronous
contexts that would each need their own `async` cascade, for a walk whose cost `VaultScanner`
already moves off the main actor with `Task.detached` at `VaultSession.swift:251`. An
`AsyncSequence` here buys nothing and spends a second concurrency migration.

**Unify the note writer and the `.canvas` writer inside `VaultPlanApplication`.** Rejected. The
two differ for a stated reason — a `.canvas` is not a note, carries no version history, and its
planned text is already an encoded document — and folding them would mean either running
`.canvas` files through `NoteHistory` or giving the applier an `isNote` flag, which is the same
branch with worse manners. Injecting the writer keeps the difference one visible line long.

**Move only `VaultController.swift` and leave its seventeen extensions in `Sources/Vault`.**
Rejected, see §D6. It satisfies `R-04` and leaves the finding standing, in the worst possible
intermediate state: the declaration in one layer and its whole implementation in another.

**Keep `VaultSession.write` synchronous and move only `history.record` to a detached task.**
Rejected. It is the cheapest change here and it is genuinely tempting — it removes the second
file write from the main actor for about six lines of diff. It also gives up on ordering
(two rapid saves would record versions out of order), leaves the `store.read` re-read at `:196`
on the main actor, and leaves the vault with two write paths where one is async and unobservable.
It fails `R-07` as written.

**Make `write` synchronous but have the actor serialise through a per-path `Task` chain, so that
call sites never await.** Rejected. A caller that does not await cannot be told the write failed,
and every one of the thirty-three call sites currently handles `throws` — `saveOpenNote` turns a
failure into `recordProblem`, `VaultWrites` turns it into a connector refusal. Silently
discarding those is a worse bug than a slow main actor.

**Convert `read` to `async` as well, per the SPEC's parenthetical.** Rejected for this chain, see
§D12, with the reasoning recorded so the next reader can reopen it against a measurement rather
than against a guess.

**Do the four items as four chains, in four PRs.** Rejected, and this is the decision the SPEC
itself makes. `PG-145`'s walk helper and `PG-122`'s guard are the same seam — the walk must be
built *from* the boundary or it is the way around it. `PG-140`'s per-batch plan is written in
terms of `PG-145`'s helper. `PG-137`'s actor wants `PG-140`'s single-parse record derivation, or
it moves a double parse to a background thread and calls it fixed. Four PRs means building the
same helper four times and rebasing three of them onto each other.

**Do `PG-137` first, since it is the one with the user-visible payoff.** Rejected. It is the
change that most needs the other three to have finished: every file it touches is a file
`PG-122` makes throwing and `PG-145` deletes code from. Doing it first means doing the async
migration twice.

## Consequences

### Positive

- A path that escapes the vault is refused at ten call sites instead of two, and the refusal is
  structural: obtaining a URL requires passing the guard, so the eleventh call site inherits it
  without anyone remembering.
- Three walks become one, six apply-loops become one, and `rename`'s thirty-line duplicate of
  `renamePlan` becomes four lines. Two doc comments that say «this mirrors that» can be deleted,
  because the mirroring is now a function call.
- A batch move of ten notes walks the vault once instead of ten times, re-encodes each affected
  `.canvas` once instead of ten times, and writes `starred.json` once instead of ten times.
- Every `.md` save stops doing two file writes and a full re-read-and-parse on the main actor.
  On a large note during fast typing this is the difference the finding was raised about.
- The read path parses each note once instead of twice, on every read, everywhere — including
  inside the cold scan, which reads every note in the vault.
- `Sources/Vault` becomes what ADR-0001 §D1 said it was: file-system access with no user
  interface in it. `grep -rn "^import SwiftUI" Sources/Vault/` returns nothing, and stays that
  way because a violation is now visible in one grep rather than buried in eighteen files.
- ADR-0001 §D3.3's hash mechanism gets stronger rather than weaker under concurrency (§D10), and
  §D2.3's ordering stops depending on the code happening to be synchronous (§D11).

### Negative

- **The diff is large and most of it is mechanical.** Thirty-one `store.url(for:)` call sites,
  nineteen `FileChange` references, eighteen file moves, about thirty-five `await`s. A review
  that skims it will miss the three lines that matter. The plan's task boundaries exist to keep
  the mechanical changes in separate commits from the behavioural ones.
- **`VaultSession.write` becoming `async` is an irreversible-feeling API change.** Every caller
  is now in an async context, and a future synchronous caller has no door. This is intended —
  there should be no synchronous write path — but it is a constraint the codebase did not have
  yesterday.
- **`VaultController+Editing.saveOpenNote()` becomes `async`,** which means its four call sites
  wrap it in `Task { }`. Each of those is a place where two saves can now be started out of
  order. §D11 makes that harmless to the index, not harmless to reason about.
- **Three files under `Sources/Features/Pratiche` and one under `Recordings` are touched by both
  `PG-122` and `PG-137`,** and they contain four protected interfaces (`PraticaNaming.messageFileName`,
  `Dossier.render`, `VaultAPI.PraticaSummary`, `ImportNaming.recordingNoteTitle`). None should
  change; `interface-check.sh` blocks if any does, and the plan makes verifying it a named step
  rather than a hope.
- **A characterization test for `rename` has to be written against code that is about to be
  deleted.** It is throwaway work in the sense that it tests an implementation, and it is the
  only thing standing between «`renamePlan` computes the same changes» and «`renamePlan`
  computes changes that look the same».
- `VaultLayout` and `FileChange` moving means two type relocations in a chain that also does a
  concurrency migration. Both are name-preserving and target-internal, but a merge conflict
  against any in-flight branch touching those files is certain.

### Neutral

- No on-disk format changes, so no migration, no version bump, no compatibility window. A vault
  written by the build before this chain and one written after are byte-identical.
- The MCP protocol surface does not change: `tools/list` answers the same names with the same
  schemas, and `scripts/mcp-smoke.py` should pass unmodified. That it *should* is why `R-10`
  requires running it rather than reasoning about it.
- `perg`'s command surface does not change, and its `async` entry point absorbs the session's new
  `async` writes with no structural edit.
- The UI does not change. The acceptance criterion for the whole chain is that a person cannot
  tell, except that the editor stops hitching on large saves.

## Protected-interface proposal (ADR-0053 — proposed, not written)

```
Sources/Core/Vault/VaultBoundary.swift:VaultBoundary.url(for:) — the vault's only path-resolution door; a signature change that removes `throws`, or a behaviour change that resolves symlinks per call instead of once at construction, silently reopens the path-traversal gap ADR-0041 §D1 closed and reintroduces the symlinked-vault regression recorded at NoteStore.swift:48-55
```

**Propose only, and with one caveat the operator should weigh.** This entry is not the usual
kind: it is not a JSON payload an external caller parses, nor an on-disk name that orphans files
if it changes. It is a security invariant whose weakening is invisible in review — the diff that
breaks it looks like a simplification. That is the argument for protecting it, and it is also why
`interface-check.sh` blocking on it from Gate 2 would be awkward: the coder *creates* this
function in Task 1, and adding is not blocked, but any refinement during Tasks 2-4 would be.
**The recommendation is to add the entry after this chain merges, not at Gate 2.**

Not proposed, deliberately: `VaultWalk`, `VaultPlanApplication`, `VaultFileChange` and
`VaultDisk`. They are internal structure, expected to keep moving, and protecting them would
block the next refactor for no invariant's sake.

## References

- `SPEC.md` — this chain's scope, architecture and the twelve success criteria `R-01`…`R-12`
- `TODO.md` Deep Refactor Roadmap — `PG-122:245`, `PG-137:312`, `PG-140:323`, `PG-145:343`
- GitHub issues #222, #245, #240, #237
- ADR-0001 §D1, §D2, §D3 — `docs/adr/0001-initial-architecture.md`
- ADR-0007 §D2, §D3, §D6 — `docs/adr/0007-ai-connector-mcp-over-the-vault.md`
- ADR-0011 §D2 (version history on every `.md` write), ADR-0012 §D6 (starred notes are paths),
  ADR-0016 §D1/§D3 (the journal's move and trash vocabulary), ADR-0017 (derived state lives
  beside the vault), ADR-0025 §D1 (a board is addressed by its own path), ADR-0026 §D1/§D7
  (a move repoints `.canvas` nodes and rewrites no wikilink)
- `docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md` — the plan
