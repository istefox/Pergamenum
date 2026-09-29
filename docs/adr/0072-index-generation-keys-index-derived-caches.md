# ADR-0072: One index generation keys every index-derived cache; a disk-derived value is cached for one body evaluation, never longer

- Status: **proposed**. The implementation is not on `main` yet; the flip to `accepted` names the
  PR and its merge commit (`docs/adr/README.md` §2).
- Date: 2026-09-29. Written before the implementation, against `3cdc97fb` on
  `kepler/fix-fable-chain-debt`. `origin/main` at `e653cbdc` changes none of the files below: it
  adds PG-274's CRLF line walk (`Sources/Core/Markdown`, `Sources/Core/Conventions`,
  `ListNesting.swift`, `MarkdownStyler.swift`) and #677's doc comment moved inside
  `Sources/Core/Email/MIMEParameter.swift`, none of which this record touches. Every line number
  below was read from `3cdc97fb`.
- **Numbering note.** `0070` is the highest ADR on `origin/main`. No local or remote-tracking branch
  holds a `docs/adr/0071*` or `docs/adr/0072*` file, and
  `git log --all -- 'docs/adr/0071*' 'docs/adr/0072*'` is empty (checked 2026-09-29). `0071` is
  reserved by a parallel chain in flight, so this record takes `0072`. Check again immediately
  before the merge (`docs/adr/README.md` §1): if `0071` has not landed by then, or another record
  took `0072`, renumber with `git mv` and a dated note.
- Source: the approved repo-root `SPEC.md` (2026-09-29) for `PG-138`/#238, `PG-141`/#241 and
  `PG-142`/#242. Plan: `docs/plans/pg-138-pg-141-pg-142-performance-debt.md`, which cites R-01 to
  R-22. There is no brainstorm for this chain: the repo-root `BRAINSTORM.md` belongs to `PG-018`
  and `UX-BLUEPRINT.md` to Pratiche (ADR-0036). Nothing here changes a Pratiche screen, so that
  blueprint's constraints hold unchanged.
- **Extends ADR-0043 §D1 (the per-path sequence stays the only ordering authority), ADR-0067 §D6 (a
  second UI signal beside the per-path landed generation, answering a different question),
  ADR-0003 §D6 (`taskGeneration` keeps every reader but one), ADR-0036 (the mail reader's queries)
  and ADR-0045 §D3 (the widening-comment convention). Amends none.** ADR-0033 §D7 (a view block
  refreshes on the scan generation) and ADR-0065 §D8.2 (the zone a mail date is written in) are
  untouched. No on-disk format, frontmatter key, `IndexCache.schemaVersion` (stays 5) or protected
  interface changes.

## Context

### What the SPEC asks

Three ledger entries of performance debt, re-verified on 2026-09-29: every finding still holds and
seven changed shape since the 2026-09-12 audit. The SPEC fixes all of them in one PR with no
observable behaviour change, with one deliberate exception (the Workspace tray, below), and proves
each fix by an equivalence test, or by a work count where a natural boundary exists. It also
decides several things this record registers without reopening: every cache invalidates exactly,
mail output stays byte-identical, formatters are built once per call and never shared as statics,
board folder-ness is checked once per node per render, PG-054's disk check stays, and view
memoisation lasts one body evaluation.

What the SPEC leaves to the design is where the new index signal lives, what rule decides how long
a cached value may live, and how the batched mail queries keep today's order. Those are the
decisions below.

### Evidence (facts, read at `3cdc97fb`)

- **F1. Four counters already exist, and none answers "did the index change".**
  - `scanGeneration` (`VaultController.swift:283`) moves only when a scan or a cache clear finishes.
  - `taskGeneration` (`:296`) moves on those two and on `recordTaskWrite()`: capture, task drop and
    the Tasks pane. An editor save does not move it.
  - `landedGenerations` (`VaultSession.swift:108`, ADR-0067 §D6) is per path and moves only through
    `announce`. The watcher's reconcile and a rescan never announce.
  - The per-path sequence (ADR-0043 §D1) is actor-isolated and also advances on the watcher's reads.
- **F2. The index changes in exactly two places.** `VaultSession.index` is `private(set)`
  (`VaultSession.swift:89`) and is mutated only by `rescan()`, through `index.replaceAll`
  (`:393`), and by `apply(_:)`, through `index.update` (`:553`). `apply` serves every write, move,
  trash, folder door and watcher reconcile. `IndexSnapshot` has exactly those two mutating entry
  points (`IndexSnapshot.swift:41`, `:52`).
- **F3. `allTasks` is computed on every read** (`IndexSnapshot.swift:171-179`), sorting every note
  and every board by path. `taskCounts` (`:369-376`) reads it five times through
  `tasks(for:on:)` and once more through `rolledOverTasks`.
- **F4. Two panels re-derive whole-vault aggregates on every body evaluation.**
  `LinkedTasksPanel.swift:23` calls `tasks(linkingTo:)` in `body`. The note inspector calls
  `backlinks(toTitle:)` (`VaultBrowser.swift:283`), and `unresolvedLinks().prefix(10)` (`:299`)
  sorts every unresolved target to show ten. The inspector re-evaluates on keystrokes it does not
  care about, because its body reads the open note.
- **F5. The Workspace tray has a latent staleness defect.** `BoardTray.swift:138` keys its
  `.task(id:)` on `taskGeneration`, so a `^[[Board.canvas]]` task added by an editor save or an
  external edit is absent from «Task assegnati» until a rescan or an in-app task write.
- **F6. Several values are recomputed several times per body evaluation:**
  - the attachment chip asks the disk for its file state through each of about eight computed
    properties (`AttachmentChip.swift:114-153`);
  - the pratica timeline re-filters its entries on every read of `entries` (`:43`), including once
    per row inside `following(_:)` (`:195-200`);
  - a board card stats its folder twice (`BoardContentLayer.swift:79`, `:230`);
  - a view block parses its fence in `body` and again in `evaluate()` (`RenderedViewBlock.swift:51-54`,
    `:88-90`).
- **F7. The counterpart read is N+1.** `conversations(counterpart:within:)`
  (`MailStoreReader.swift:123-154`) issues one statement for the ids, then two per conversation.
  `messages(inConversation:)` orders by `m.date_sent` alone (`:106`), and neither recipients query
  has an `ORDER BY` (`:207-245`).
- **F8. A drag rebuilds its snap candidates on every tick.** `updateDrag` (`WorkspaceController+Gestures.swift:24-45`)
  looks the anchor up with a linear `document.node(id:)` and filters every node, per pointer event.

## Decision

### §D1 — The index generation is counted by the snapshot, in its two mutating doors

`IndexSnapshot` gains `private(set) var generation: Int`, incremented once at the end of
`replaceAll(with:duration:)` and once at the end of `update(_:at:)`. By F2 these are the only ways
the index can change, so no present or future mutation site can change the index without moving the
counter. This is CLAUDE.md's working agreement on unskippable checks applied to a signal: the
counter lives where the change happens, not in a step each caller must remember.

The counter moves inside the same mutating access as the contents. An observer of
`VaultSession.index` therefore sees new contents and a new generation in one set, and there is no
window in which a cache could store new data under an old key or old data under a new key. An
`apply` whose mutations are all stale applies nothing and moves nothing. A folder move that updates
forty rows moves the counter forty times; it only has to be monotonic. The counter is not persisted
and not part of `IndexCache`.

### §D2 — The facade owns the value views read, monotonic across vaults

`VaultController` exposes `indexGeneration: Int` read-only, computed as
`indexGenerationBase + index.generation`. `indexGenerationBase` is `private(set)` and is raised to
`indexGeneration + 1`:

- in `open(_:)`, before `session = newSession` (`VaultController.swift:226`);
- in `close()`, before `session = nil` (`:257`).

A new session's snapshot starts at 0, so without the base a key built on vault A's generation 3
would equal one built on vault B's generation 3, and a memo would hand vault A's answer to vault B.
That is ADR-0052's cross-vault lesson. The SPEC's "owned by the session's observable facade" holds:
the facade is the only place a view reads the generation from, and the snapshot only counts.

### §D3 — A UI signal, not a clock

This registers the SPEC constraint. ADR-0043 §D1's per-path sequence stays the only ordering
authority: nothing orders a write, a read or a reconciliation by this counter. The counters now
answer one question each:

| Counter | Moves when | Read by |
| --- | --- | --- |
| `scanGeneration` | a full scan or a cache clear finishes | view blocks (ADR-0033 §D7), note tree |
| `taskGeneration` | as above, plus an in-app task write | reminders, Tasks pane, Today |
| `landedGenerations[path]` | this path changed through a session door | Pratiche inspector (ADR-0068 §D16) |
| `indexGeneration` (new) | anything in the index changed, by any route | index-derived caches (§D4, §D5) |
| VaultDisk per-path sequence | a disk operation on the path, watcher reads included | the ordering guard in `apply` only |

No reader moves from one counter to another, except BoardTray (§D5).

### §D4 — An index-derived value is cached on the index generation, synchronously

Three values are memoised on `(indexGeneration, input)`:

- `LinkedTasksPanel`'s `tasks(linkingTo: title)`;
- the note inspector's `backlinks(toTitle:)`;
- the note inspector's unresolved links.

The memo is one small type, `IndexKeyedMemo`, in `Sources/App`. It is a `@MainActor` final class
with a single `(key, value)` slot, held in `@State` and deliberately not observable, so filling it
never schedules a render. A hit returns the stored value. A miss computes from `vault.index` and
stores the result.

It is synchronous on purpose. `.task(id:)` runs after the first frame, so the panel and the
inspector would first draw empty and then fill, which is a first-frame change the SPEC forbids.
Correctness comes from the key, never from the view's identity: SwiftUI may drop the `@State`
storage whenever it likes, and that only costs one recomputation.

The unresolved-links list becomes `unresolvedLinks(limit: Int? = nil)`. It selects the member keys
with the same filter as today, sorts them with the same comparator over the same iteration order,
takes the prefix, and builds the `sources` arrays only for the entries it keeps. Existing callers
pass no argument and take the same code path, so `unresolvedLinks(limit: n)` equals
`unresolvedLinks().prefix(n)` by construction, ties included. The saving is not asymptotic: it is
the memo plus not building source lists for entries nobody sees.

### §D5 — BoardTray changes counter: the one deliberate behaviour change

`BoardTray`'s key moves from `taskGeneration` to `indexGeneration`, through one pure
`static func refreshKey(for:board:)` that a unit test can check without rendering (the shape of
`RenderedViewBlock.taskID`). A task assigned to a board by an editor save or an external edit now
appears in «Task assegnati» when the index takes it in, not at the next rescan. The tray keeps its
`.task(id:)` shape, since it already draws empty first today, and it keeps its per-document
references cache. The cost is one `tasks(assignedToWorkspace:)` per index change while the tray is
on screen, a filter over the stored list (§D6) rather than a sort.

### §D6 — The snapshot stores its task list

`allTasks` becomes a stored `private(set) var` with the same name, type and order: notes then
boards, each in path order. It is rebuilt at the end of `replaceAll` and of `update`, never lazily,
so every existing reader is unchanged. `taskCounts` makes one pass over it, using one predicate per
view that `tasks(for:on:includingCompleted:)` also uses, so a list and its badge cannot drift.

`IndexSnapshot.swift` is at 395 of SwiftLint's 400-line warning. The task-view block (`TaskView`,
`tasks(for:…)`, `rolledOverTasks`, `taskCounts`) therefore moves verbatim into
`IndexSnapshot+TaskView.swift`. That file is named in `Project.swift`'s `sharedSources`, because
`Sources/Index` files are listed by hand and `perg` and `pergamenum-mcp` compile the snapshot.

### §D7 — A disk-derived value is cached for one body evaluation, never across renders

What the disk says can change without the index knowing. That covers an attachment Mail finishes
writing, a folder created beside a board, and a pratica file. Such values are computed at most once
per body evaluation and passed to every part of that body that needs them:

- the chip's file state;
- the board card's folder-ness, shared by the card and its accessibility summary;
- the timeline's filtered entries and its next-row map;
- the view block's fence parse.

**Action-time reads stay live.** A click, a double-click, «Apri», Quick Look, and the chip's AppKit
menu (whose entries are built when the menu opens, ADR-0069) ask the disk when the person acts, as
they do today.

The explicit no's, so nobody "optimises" them later:

- **No per-load cache of board folder-ness.** It would break PG-054, which checks the disk so that a
  folder created later, or outside the board's siblings, is recognised.
- **No folder watch.** The watcher does not see folders, and a watch would be new infrastructure to
  halve a stat count this rule already halves.
- **No `@State` chip, timeline or view-block cache across renders.** It would change when newly
  arrived data shows up.

### §D8 — Mail reads are batched and their order is explicit

`conversations(counterpart:within:)` keeps its id query unchanged (`last_sent DESC`). It then reads
messages and recipients per chunk of at most `batchSize` ids (default 500), with one statement for
each per chunk. Zero ids issue no batch statement. `messages(inConversation:)` goes through the
same primitive with one id, so there is one query text, not two that could drift.
`MailStorePreparation.resolveFollowedConversations` reads a pratica's followed conversations
through the same batched primitive, with the same order guarantees (plan gate G4, which widened
R-11 on 2026-09-29).

- **Messages are ordered `m.date_sent, m.ROWID`.** Today's `ORDER BY m.date_sent` returns
  equal-date rows in the order the scan produced them, which is rowid order for this table. The
  tie-break makes that explicit. A characterization test pins it on today's code before any change.
  If that test is red on today's code, the premise is false and the chain stops (plan gate G3).
- **Recipients are ordered `r.ROWID`**, in the batch and in the single-message query. Not
  `position`: switching to `position` could change today's order wherever the two differ.
- **The batch size stays under SQLite's bound-parameter limit.** SQLite reports that limit as 999
  before 3.32.0 and 32766 after (sqlite.org `limits.html`). The batch size is an init parameter
  with a default, so a test can cross a batch boundary on a small fixture.
- **A mailbox's store directory is remembered per reader, when found.** A miss is listed again on
  the next call, exactly as today. SPEC R-12's "at most once" is read as applying to a mailbox that
  has one (plan gate G2).
- **Statement counts are measured in the test target.** The test counts through `sqlite3_trace_v2`
  on the connection's handle; `MailStoreConnection.handle` widens its getter to internal (ADR-0045
  §D3 comment). No counter is added to production code.

### §D9 — Formatters once per call; frontmatter read once

This registers SPEC decisions. `MessageDocument` builds one `ISO8601DateFormatter` per `parse` and
one per `render`, and resets its options or its zone before every use, so each string is the same as
from a fresh formatter. The connector's pratica timeline builds one per call. No shared static
(`nonisolated(unsafe)` is what the audit marked report-only), and no `ISO8601FormatStyle` (it risks
different bytes).

`MessageDocument.parse` reads its frontmatter into one first-occurrence map, skipping indented
lines. `storeReferences(in:)` keeps its own scan, because its predicate is a prefix test on the
trimmed line, not the key match, and unifying the two would move which line starts the block.

### §D10 — A drag captures its snap candidates when it begins

`WorkspaceController.dragAnchorID` is replaced, line for line, by `dragSnap: BoardDragSnap?`.
`beginDrag` builds it once: the anchor's frame and every other node's frame. `endDrag` clears it,
and so does ADR-0066's transient reset door. Each tick still reads `zoom` and `snapsToGrid` live and
calls the same `BoardGeometry.snapped`.

The replacement must be line for line because the class body sits at 349 of SwiftLint's 350-line
error. The file header's rule already says the model is untouched during a gesture. The SPEC
accepts one edge: if the board reloads from outside during a drag, the captured candidates are used
until release.

### §D11 — Named, not fixed

- **TodayView keys on `taskGeneration`** (`TodayView.swift:62`), so it is stale after an editor save
  in the same way BoardTray was. This is the `PG-270` family.
- **An editor view block refreshes on `scanGeneration`** (ADR-0033 §D7), so a fence listing a note
  does not re-run when that note is saved.
- **Two of the three source guards lack a positive file count** (`PG-128`, the `e19` finding).
  The shared source-tree snapshot R-19 introduces does not close it for them.

## Alternatives considered

1. **Key both views on `taskGeneration`, and widen it to move on every index change.** Rejected.
   `taskGeneration` drives reminder rescheduling (`PergamenumApp.swift:297`), the Tasks pane and
   Today. Moving it on every save would reschedule every notification per save and change three
   surfaces the SPEC leaves alone. The SPEC also rejects keying the panel on it as it stands,
   because the panel would inherit BoardTray's staleness.
2. **Key on `landedGenerations`.** Rejected. It is per path, while a panel's answer depends on any
   note. It also moves only through `announce`, so an external edit and a rescan (F1) are both
   missed, which is exactly R-04's case.
3. **A counter on `VaultSession`, bumped in `apply` and after `replaceAll` in `rescan`.** A real
   option, and the one this design started from. It works today, because both mutation sites are
   in one file. Rejected in favour of §D1: a third mutation site added later to
   `VaultSession.swift` could forget the bump, while a counter inside the snapshot's own mutating
   doors cannot be skipped. It would also have needed the same vault-switch base (§D2), so it saves
   nothing there.
4. **No memo; rely on Observation to skip the work.** Rejected. Observation decides when a body
   runs, not what it recomputes. The inspector's body re-runs on keystrokes because it reads the
   open note (F4), and everything inside it is recomputed each time.
5. **`.task(id:)` plus `@State` for the panel and the inspector (BoardTray's shape).** Rejected: an
   empty first frame, then a fill. That is a visible change on every note opened.
6. **Precompute a tasks-by-link-title map in the snapshot.** Rejected. It would be an index-wide map,
   rebuilt on every update, for panels that show one title at a time. The stored task list is the
   SPEC's data model, and the memo costs one filter per index change per visible panel.
7. **Keep the mail N+1 and cache only the directory listing.** The SPEC rejects this: zero order
   risk, but a much smaller gain.
8. **Order recipients by `position`.** Rejected: it could change today's order wherever `position`
   and row order disagree. A semantic reordering is a separate decision with its own test.
9. **Cache board folder-ness per load, or watch the folders.** The SPEC rejects both (§D7): the
   first breaks PG-054, and the second is new infrastructure.

## Consequences

### Positive

- The task sidebar, the linked-tasks panel and the note inspector stop re-deriving whole-vault
  aggregates on redraws that do not change the index. `allTasks` stops sorting the vault on every
  read.
- BoardTray stops being stale after an editor save or an external edit.
- A counterpart read issues a statement count bounded by its batches, not its conversations.
- The chip, the timeline and the board card stop hitting the disk several times per render, and a
  drag stops scanning the node list on every tick.
- The index signal cannot be skipped by a future mutation site (§D1).

### Negative

- A fifth counter exists, and a reader has to pick the right one. §D3's table is the guide, and it
  lives here rather than in a code comment that would drift.
- BoardTray now recomputes on every index change, which means every save, instead of on task
  writes. The work is a filter over the stored list.
- Every `update` now rebuilds the stored task list: one sort of the notes by path, paid once per
  change instead of once per read. Reads outnumber changes by orders of magnitude.
- `MailStoreReader`'s initializers gain a defaulted `batchSize:` parameter. It exists for the test
  that crosses a batch boundary, not for the app.
- `MailStoreConnection.handle`'s getter is internal. Only the test target uses it; the existing
  isolation guards still forbid `SQLite3` in the connector front ends.

### Neutral

- No on-disk format, cache schema, frontmatter key, connector payload or protected interface
  changes.
- The connectors compile a snapshot that carries a counter they never read.
- Mail output is byte-identical by constraint and pinned by digest tests on both corpora.

## References

- `SPEC.md` (approved 2026-09-29): Decisions, Constraints, R-01 to R-22.
- `TODO.md`: `PG-138`/#238, `PG-141`/#241, `PG-142`/#242, `PG-128`, `PG-270`, `PG-268`.
- ADR-0003 §D6, ADR-0033 §D7, ADR-0036, ADR-0043 §D1, ADR-0045 §D3, ADR-0052, ADR-0066,
  ADR-0067 §D6, ADR-0068 §D16, ADR-0069.
- SQLite, "Limits In SQLite", maximum number of host parameters: <https://www.sqlite.org/limits.html>.
- SQLite, `sqlite3_trace_v2`, `SQLITE_TRACE_STMT` and `SQLITE_TRACE_PROFILE`:
  <https://www.sqlite.org/c3ref/trace_v2.html>.
