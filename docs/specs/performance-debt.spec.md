Status: Approved (2026-09-29)

# SPEC — Performance debt: index and view queries, mail pipeline, board gestures (PG-138, PG-141, PG-142)

## Destination

One PR that closes #238, #241 and #242: every finding of the three entries that still holds is
fixed with no observable behaviour change (one deliberate exception, the BoardTray staleness fix),
each fix pinned by an equivalence test or, where a natural boundary exists, a work-count test.

## Objectives

The app does the same thing with less work on its hottest paths: the task sidebar and the note
inspector stop re-deriving whole-vault aggregates on every redraw or keystroke, view blocks stop
re-parsing and re-resolving per record, a pratica sync stops allocating per line and querying per
conversation, the timeline and attachment chips stop hitting the disk several times per render,
and a board drag stops rebuilding its snap candidates and stat-ing every visible node per frame.
The test suite itself stops re-reading the source tree.

## Scope and non-goals

In: the 19 findings of PG-138 (7), PG-141 (7 plus the formatter half of the MessageDocument item)
and PG-142 (5, including the three test-only items), re-verified against the code on 2026-09-29
(all still present, seven changed shape). Also in: the two neighbours found during that check on
the same paths (the sorted `allNotes` read three times per view evaluation, the `.text` needle
folded per record).

Out: PG-268 (Audit Fable chain 15 performance nits, a separate entry); time-based benchmarks; any
new instrumentation in production code; a filesystem watch for board folders; a shared static
formatter.

## Decisions

- **One SPEC, one PR** for the three entries. Rejected: three PRs (more review overhead for fixes
  that share the same test seams); PG-138 alone first (splits one measured chain in two).
- **Success is proven by deterministic tests, never by timing.** Equivalence everywhere, work
  counts only at natural boundaries. Rejected: millisecond thresholds on a synthetic vault (flaky
  on CI and on a busy machine); equivalence only (nothing would fail if an N+1 came back).
- **Every cache invalidates exactly.** A cached value is recomputed on every change that can alter
  it; no view ever shows data older than the index it reads. Rejected: tolerating one stale frame
  in the UI (reopens the class of defect ADR-0043/0058/0067 closed).
- **A new index generation that moves on every index change** (every `apply`, scan and watcher
  update), and both LinkedTasksPanel and BoardTray key their caches on it. This also fixes
  BoardTray, which today keys on the task generation and goes stale after an editor save or an
  external edit. Rejected: keying LinkedTasksPanel on the task generation (it would inherit
  BoardTray's staleness); fixing the panel only and filing BoardTray separately (same root cause,
  same fix); dropping the panel item (the gain is smaller, but the latent BoardTray defect stays).
- **Mail conversations, messages and recipients are fetched in batches** (chunked `IN` lists under
  SQLite's bound-parameter limit), with an explicit order everywhere, recipients ordered by the
  table's row id, the order SQLite returns in practice today. Rejected: keeping the N+1 and caching
  only the per-mailbox directory listing (zero order risk, much smaller gain).
- **Date formatters in MessageDocument are created once per parse or render call and reused across
  keys.** Same class, same format, identical bytes. Rejected: a shared static (needs
  `nonisolated(unsafe)`, the concurrency guard the audit marked report-only); `ISO8601FormatStyle`
  (risks different output bytes).
- **Board folder-ness is checked once per node per render**, shared between the card body and its
  accessibility summary. Rejected: a per-load cache (breaks PG-054, which deliberately checks the
  disk so a folder created later or outside the board's siblings is recognised); a cache with a
  filesystem watch (new infrastructure; the watcher does not see folders today).
- **View memoisation is per body evaluation, never across renders**, where caching across renders
  would change when a newly arrived file or a new index state shows up (attachment chip, timeline,
  view block's first frame).
- **The three test-only items of PG-142 are in.** Rejected: leaving them open on #242.

## Constraints

- **Zero user-visible behaviour change**, except BoardTray now refreshing after an editor save or an
  external edit — origin: user mandate (this interview).
- **Mail output is byte-identical** on `EmailFixtureCorpus` and `FormatEdgeCorpus`, run before and
  after every reducer or decoder change — origin: PG-141 (a CRLF divergence was measured during the
  audit run).
- **`Sources/Core` stays Foundation-only**; `perg` and `pergamenum-mcp` build unchanged — origin:
  ADR-0001 §D1, ADR-0007.
- **ADR-0043's sequence stays the ordering authority**; the new index generation is a UI refresh
  signal, not a clock — origin: ADR-0043 §D1, ADR-0067 §D6.
- **PG-054's disk check for board folders stays** — origin: existing behaviour, PG-054.
- **Protected interfaces untouched** (`.claude/protected-interfaces`) — origin: repo rule.
- **No test is weakened, skipped or deleted** — origin: CLAUDE.md.
- **The UI-test change runs through `scripts/uitests.sh --affected`**, never a bare `xcodebuild` —
  origin: CLAUDE.md working agreements.

## Data model

One new derived value on the index side: an **index generation**, a monotonically increasing
integer owned by the session's observable facade, incremented once per landed index change of any
kind. Not persisted, not part of `IndexCache`; `IndexCache.schemaVersion` stays unchanged.

The index snapshot gains a **stored task list** (all tasks, notes then boards, in path order: the
order `allTasks` produces today), rebuilt inside every whole-snapshot replacement and every
single-file update, never lazily.

## API / interfaces

- The session facade exposes the index generation read-only.
- `taskCounts` keeps its signature and result; it reads the stored task list once.
- MailStoreReader's public reads keep their signatures and results, including order.
- No connector payload changes; `VaultAPI` shapes untouched.

## Edge cases

- A single-file update that removes a note's last task, or adds the first, changes the stored task
  list and the counts on the same update.
- An editor save, an external edit arriving through the watcher, a move, a trash and a full rescan
  each move the index generation.
- A counterpart with more conversations than one batch holds (larger than the chunk size) returns
  the same ordered result as with per-conversation queries.
- A counterpart with zero conversations issues no batch query.
- A deleted message stays filtered out in the batched query exactly as today.
- An attachment file that arrives while the chip is on screen shows as usable on the next render.
- A folder created on disk after a board is loaded is still recognised as a folder card.
- A drag during which the board is reloaded from outside: the snap candidates captured at the start
  of the drag are used until it ends (accepted; the model is documented as untouched during a
  gesture).
- MessageDocument frontmatter with a duplicated key: the first occurrence wins, as today; an
  indented line is skipped, as today.

## Test seams

- **Equivalence, through the existing unit suite** (highest existing seam, no new harness):
  - mail: `EmailFixtureCorpus` and `FormatEdgeCorpus`, byte for byte;
  - pratiche: `MessageDocumentTests`, `PraticaTimelineTests`, `PraticheConnectorTests`;
  - index and queries: `RolloverTests`, `TaskViewTests`, `ViewEvaluatorTests`, `ViewQueryTests`,
    `SearchTagRuleTests`;
  - board: `BoardInteractionTests`, `WorkspaceEnterFolderTests`.
- **Work counts only at natural boundaries**, no production counter added for tests:
  - SQL statements issued per counterpart, counted at the SQLite connection with `MailStoreFixture`;
  - the stored task list equals a fresh recomputation after every `replaceAll` and `update`;
  - the index generation observed moving on each kind of landed change.
- **Pure model functions** where the fix creates one: the timeline's next-row map, the top-N
  unresolved-links selection.
- **The UI-test item** runs through `scripts/uitests.sh --affected`.

## Success criteria

- [ ] R-01 — The index snapshot holds a stored task list rebuilt on every whole replacement and
  every single-file update; after each, it equals a fresh recomputation, in the same order.
- [ ] R-02 — `taskCounts` reads the stored task list once per call and every badge still equals
  the count of its list.
- [ ] R-03 — An index generation moves on every landed index change: editor save, external edit,
  move, trash, rescan.
- [ ] R-04 — LinkedTasksPanel and BoardTray refresh on the index generation; a task added by an
  editor save or an external edit appears in both.
- [ ] R-05 — The note inspector's unresolved-links and backlinks lists are not recomputed on a
  keystroke that does not change the index, and show the same entries as today (the top-N
  selection equals the prefix of the full sort).
- [ ] R-06 — A view block parses its fence once per body evaluation and reuses that parse for its
  evaluation; its first frame is unchanged. (no-test: per-body memoisation of a SwiftUI view,
  proven by construction; results pinned by the existing view-block tests)
- [ ] R-07 — One view evaluation reads the sorted note list once and resolves `linksTo`/
  `linkedFrom` once per title, with identical results.
- [ ] R-08 — Glob patterns and `.text` needles are case-folded once per evaluation or query, with
  identical matches.
- [ ] R-09 — The HTML reducer no longer lowercases per character nor copies the buffer per
  paragraph break, and its output is byte-identical on both corpora.
- [ ] R-10 — The MIME decoder compares boundary lines without per-line allocations, and decodes
  every corpus message to identical parts.
- [ ] R-11 — Reading a counterpart issues a number of SQL statements independent of its
  conversation count (bounded by the number of batches), and returns conversations, messages and
  recipients in the same order as today, across a batch boundary. The same holds for resolving a
  pratica's followed conversations (widened at plan gate G4, 2026-09-29).
- [ ] R-12 — A mailbox's store directory is listed at most once per reader.
- [ ] R-13 — MessageDocument reads its frontmatter in one pass (first occurrence wins, indented
  lines skipped) and creates its date formatters once per call; parse and render are identical on
  `MessageDocumentTests` and both corpora.
- [ ] R-14 — The connector's pratica timeline creates one date formatter per call, with identical
  output.
- [ ] R-15 — An attachment chip checks its file once per body evaluation, and a file that arrives
  while the chip is visible shows as usable on the next render. (no-test: per-body memoisation,
  proven by construction; model pinned by `AttachmentChipTests`)
- [ ] R-16 — The timeline computes its entries once per body and finds the "insert here" target
  from a precomputed next-row map, with the same target as today.
- [ ] R-17 — A board card checks folder-ness once per node per render, and a folder created after
  load is still recognised.
- [ ] R-18 — A drag captures its snap candidates once at its start and does not scan the node list
  linearly per tick, with the same snapping result.
- [ ] R-19 — The source-purity and isolation tests walk the source tree once per run and reach the
  same verdicts.
- [ ] R-20 — `WorkspaceOpenStateUITests` scopes its queries and resolves the tree once per
  assertion, green through `scripts/uitests.sh --affected`. (no-test: it is itself a UI test, verified by running it)
- [ ] R-21 — `scripts/mcp-smoke.py` drains the server's stderr without accumulating it, and still
  passes. (no-test: it is itself a script)
- [ ] R-22 — Every existing test passes unchanged; none is weakened, skipped or deleted; `perg` and
  `pergamenum-mcp` build.

## Not yet specified

_none_

## Out of scope

- **PG-268** (chain 15 perf nits: outline reparse, per-row JSON decode, tag-rename preview): a
  separate ledger entry with its own measurements.
- **Timing benchmarks and a synthetic large-vault generator**: rejected as the proof method above.
- **Cross-render caches** for chip, timeline and view block: they would change when new data shows.
- **A folder watch for boards**: new infrastructure for a halved stat count that is already enough.
