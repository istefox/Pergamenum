# ADR-0047: Categories are a registry in the vault, the tag stays the pointer, and the Obsidian round-trip stops being a constraint

- Status: accepted (plan at `docs/plans/task-categories.md`, all 8 tasks implemented)
- Date: 2026-09-16. Written on the worktree `Pergamenum.worktrees/chore-question-activity`,
  branch `chore-question-activity`, HEAD `7cee42a`. Every line number, signature and call-site
  count below was read out of that tree, not recalled.
- **Numbering note:** `0046` is the highest under `docs/adr/` and `git log --all -- 'docs/adr/0047*'`
  returns nothing. Checked, not assumed.
- Source: the approved `SPEC.md` at the repository root, topic slug `task-categories`, status
  Approved 2026-09-16. Its `## Decisions` and `## Constraints` sections are settled input: this ADR
  registers them with their stated rationale and decides only what the SPEC left to `/workplan` —
  the derivation seams, the cache consequence, the selection model, the lint placement, and the
  inventory of documents the Obsidian amendment touches. The `BRAINSTORM.md`/`UX-BLUEPRINT.md` in
  the root belong to older completed chains and are disregarded.
- **Reopens ADR-0013 §D6 by addition, on the SPEC's own terms.** The five task views stay five and
  stay unchanged; the «Categorie» section is a section beside them, not a sixth view (§D6 below).
- **Amends the documents, not the formats.** Principle 4 of `CLAUDE.md` and SPEC §14 change; no
  on-disk format changes, and no ADR body is rewritten (§D11, §D12).
- Registered and not re-litigated: **ADR-0007** (§D2 shared sources, §D3 a capability is
  implemented once, §D6 the connector write guardrails), **ADR-0013 §D6** (five views, closed;
  grouping is the open axis), **ADR-0020** and **ADR-0032** (the `pergamenum-` prefixed-key
  namespace), **ADR-0021 §D11** (advisory lint findings hang off `NoteViolations`), **ADR-0023**
  and **ADR-0039** (one command catalogue rendered on every surface), **ADR-0024** (flat recursive
  rows, never `DisclosureGroup`, for a tree inside a `List(selection:)`), **ADR-0041 §D9–§D11** and
  **ADR-0043 §D8** (the async write door and its opt-in `expecting:` precondition), **ADR-0046**
  (`writeGuarded`/`writeFileGuarded`).
- **Adds no exception to `CLAUDE.md` principle 2.** Nothing here gains a network path, and the
  Obsidian amendment below removes an obligation rather than opening one.

## Context

Two things ship as one chain because they touch the same documents.

**The first is a category system.** Tasks already carry `#project-<slug>` (SPEC §7.1, parsed into
`TaskItem.project`, `Sources/Core/Tasks/TaskItem.swift:65`) and the app already aggregates them in
the «Per progetto» view (`IndexSnapshot.tasks(for:on:)`, `Sources/Index/IndexSnapshot.swift:280`)
and in the `.project` grouping (`TaskGrouping`, `Sources/Core/Tasks/TaskListOptions.swift:16`). What
does not exist is the *entity*: a project has no name beyond its slug, no colour, no parent, no
deadline, no description, and no way to be created or assigned other than by hand-typing a tag into
a line. Everything a Todoist or Things sidebar shows about a project, this app derives from the
spelling of a tag.

**The second is a product decision already taken and never written down.** On 2026-08-22, during
ADR-0020's implementation, Stefano decided to stop treating Obsidian round-trip compatibility as a
priority constraint, moving the app's direction toward the harness system and personal work
organisation. The decision is recorded twice — `PROJECT_BRIEF.md:613-617` («Probe 2 (round-trip con
Obsidian) deliberatamente non eseguita … decisione di prodotto registrata nell'ADR, non ancora
propagata a `CLAUDE.md`/SPEC §14 (conversazione separata, esplicitamente rimandata)») and
ADR-0020:523 — and in both places it is recorded as *not yet propagated*. Three weeks later the
binding documents still say the opposite: `CLAUDE.md` principle 4 («Obsidian compatibility»), SPEC
line 16 («compatibile con il vault Obsidian Labs»), SPEC line 52 («Compatibilità Obsidian»), SPEC
§14 line 502 («Interoperabilità Obsidian»), and the M2 acceptance criterion at SPEC line 484 («Un
.canvas creato in Pergamenum si apre correttamente in Obsidian e viceversa»). Nine ADRs cite the
round-trip as a reason for a decision. A future decision is still being weighed against a
constraint nobody holds.

### What the code already gives this chain for free, and what it does not

Free: the tag and its parser; the write door with its hash precondition
(`VaultSession.write(_:to:expecting:)`, `Sources/Vault/VaultSession.swift:498`); the one place a
task line is rewritten (`VaultSession.apply(_:to:)`,
`Sources/Vault/VaultSession+Tasks.swift:106-140`, already passing `expecting:` at :139); the
marker-rewrite shape to mirror (`TaskParser.line(for:assigningWorkspace:)`,
`Sources/Core/Tasks/TaskParser+Writes.swift:142-157`); a vault-side JSON store to copy
(`StarredStore`, `Sources/Vault/StarredStore.swift` — atomic write, malformed file reads as empty,
problem returned not thrown); the command-parity mechanism (`TaskCommand` +
`CommandActions.run(_:on:)`); the advisory-lint attachment point (`NoteViolations.taskMarkers`,
defaulted so existing construction sites keep compiling, `Sources/Core/Conventions/NoteViolations.swift:18`);
and a frontmatter parser that already preserves unknown keys in source order
(`Frontmatter.foreignKeys`, `Sources/Core/Conventions/Frontmatter.swift:25-37`).

Not free, and this is the finding that shapes §D5: **the SQLite index cache drops every
`pergamenum-*` key.** `StoredFrontmatter` (`Sources/Index/IndexCache.swift:302-323`) stores
`date`, `tags`, `aliases`, `related` and nothing else, so a `NoteRecord` restored from cache has an
empty `foreignKeys`. Pratiche hit this and worked around it by re-opening the handful of files whose
path ends in `pratica.md` (`Sources/Features/Pratiche/PraticheController+TimelineRead.swift:22-27`,
which names the failure exactly: «la cache non tiene nessuna chiave `pergamenum-*`, quindi ogni
record riusato da una scansione — tutti, dalla seconda scansione in poi — risponderebbe "non è una
pratica"»). A category's linked note can be any note in the vault, so that workaround does not
transfer: it would mean re-reading every note on every scan, which is the cache's entire purpose
inverted.

## Decision

### §D1 — The task line points at a category with the existing `#project-<slug>` tag

Settled by the SPEC. No new marker, no new tag namespace, no new §7.1 row, no change to the
eight-prefix regex of SPEC §4.4 or to `vocabolari.json`. Every task already carrying a project tag
joins the system on the first launch after this ships. `TaskParser` gains a writer, not a field.

### §D2 — The registry is `.pergamenum/categories.json`, and it is not an index

Settled by the SPEC; what this ADR fixes is the shape. `VaultLayout` gains `categoriesFile`
(`Sources/Core/Conventions/VaultLayout.swift`) beside `vocabularyFile` and `starredFile`. A new
`CategoryRegistryStore` (`Sources/Vault/`, in `sharedSources`) copies `StarredStore` exactly:
`load()` reads or returns empty, `save(_:)` writes atomically through a pretty-printed encoder and
returns a problem string rather than throwing.

One divergence from `StarredStore`, and it is deliberate: **a `categories.json` that exists and does
not decode is reported and treated as empty for the session, and is never overwritten by a save.**
Losing a star is nothing; silently replacing a hand-edited registry with an empty one loses the only
copy of data that exists nowhere else. The store therefore carries a loaded-state flag
(`.absent` / `.loaded` / `.malformed`), and every mutation refuses while it is `.malformed`, with
the reason surfaced through `recordProblem`. This is the registry's whole durability story: it is a
vault file under principle 1, not derived state under principle 3, and deleting it loses the
registry and no task.

### §D3 — Slugs are immutable and validation is one pure door that refuses before anything is written

Settled by the SPEC (immutable slugs, two levels, uniqueness across both levels, a parent must be
top-level). The decision here is where the rule lives: one pure type in `Sources/Core`
(`CategoryRegistry.validating(_:)` returning the entry or a typed refusal), called by every
mutation. Not an `assert`-shaped checker a call site can forget — ADR-0041's rule, applied again:
the validator is the only way to obtain a registry a store will accept, so a new mutation inherits
the check instead of remembering it. Slug grammar is `Tag.isWellFormedValue`, already written
(`Sources/Core/Conventions/Tag.swift:37`), never a second regex.

### §D4 — The effective category is an index fact, and «Per progetto» does not change

`IndexSnapshot` gains the derivations — effective category per task (explicit tag, else the linked
note's key, else none), implicit categories, the rolled-up task set, the progress fraction — in a
new `IndexSnapshot+Categories.swift`, `import Foundation` only, in `sharedSources`.

**`TaskView.byProject` and `TaskGrouping.project` keep reading `task.project` literally, and this is
a decision, not an omission.** Inheritance would silently pull a linked note's untagged tasks into
the aggregated project view and into the `.project` grouping, changing what two existing surfaces
show without anybody asking. The explicit no is worth more here than the consistency: the category
rows are the new surface and the only one that rolls up. A future chain that wants the aggregated
view to inherit can say so; this one does not.

Rollup is `done ÷ (open + done)` over the subtree, `[x]` done, `[ ]`/`[>]` open, `[-]` excluded —
the SPEC's rule, which is *not* `TaskItem.State.isOpen ? … ` applied naively: `.rescheduled` counts
as open and `.cancelled` is excluded from both sides of the fraction, so the denominator is not the
task count.

### §D5 — The linked note needs a stored scalar, so `IndexCache.schemaVersion` goes 3 → 4

`NoteRecord` gains `categorySlug: String?`, filled in the one place a record is built from text
(`NoteStore.makeRecord(from:text:document:attributes:at:)`,
`Sources/Vault/NoteStore.swift:111-129`, shared by `read` and by `NoteStore+ReadSurface.record`) by
reading the `pergamenum-category` scalar out of `document.frontmatter.foreignKeys`.
`StoredRecord` gains the same field, defaulted so a row missing it decodes rather than taking the
cache down, and `IndexCache.schemaVersion` (`Sources/Index/IndexCache.swift:212`) becomes `4` with
its reason added to the running comment the way versions 2 and 3 documented theirs.

Without this, R-06 works on a freshly-scanned vault and stops working from the second scan onward —
the exact defect shape Pratiche already paid for. `IndexCache.schemaVersion` is a protected
interface (ADR-0021); this ADR is the decision that spends the bump, and it is the only schema
change this chain is permitted.

Parsing is a scalar read, not a YAML parser: one key, one line, the same `scalar(_:_:)` shape
`MessageDocument+Reading.swift:13` uses, kept in `Sources/Core` with no SwiftUI import.

### §D6 — The sidebar gains a section, `TaskView` stays five, and the selection becomes one derived value

`TasksView` holds `@State var view: IndexSnapshot.TaskView` and hands it to `TaskViewSidebar` as a
binding (`Sources/Features/Tasks/TasksView.swift:11`, `TaskViewSidebar.swift:15`). A category row is
selectable and is not a `TaskView`, so the binding's type has to change. One enum —
`TaskPaneSelection { case view(IndexSnapshot.TaskView); case category(String) }` — replaces the
single variable, which is ADR-0024's decision applied to the second tree in the app: one derived
selection value, not two variables that can disagree about what is selected.

The rows are flat recursive rows with an explicit chevron and hand-drawn depth, never
`DisclosureGroup` — ADR-0024's trap, restated because this is exactly the shape that falls into it.

Per-category list options reuse the existing `@AppStorage("taskListOptions")` JSON map
(`TasksView.swift:29`) under a namespaced key (`category:<slug>`), not a second store: ADR-0013 §D6
put every view's controls in one key precisely so that a new row does not need a new key.

### §D7 — Assignment is an ordinary line replacement through the existing write path

`TaskParser` gains `line(for:assigningCategory:)`, mirroring `assigningWorkspace` (removal through
`withPrecedingSpace`, then append), removing **every** `#project-*` on the line before appending the
chosen one — the SPEC's edge case: the first tag wins at read time, so leaving the second behind
would make the line's meaning depend on order. `VaultSession.TaskChange` gains a case; the write
goes through `apply(_:to:)`, which already passes `expecting:`. No new write door, no batch, no
journal change, and the connectors stay out of it (§D9).

### §D8 — The two commands join `TaskCommand`, and the picker is hosted where the board picker is

`assignCategory` and `removeCategory` become `TaskCommand` cases, so the row context menu, the
Attività toolbar, the Task menu and the «Task collegati» panel render them from one catalogue
(ADR-0023, ADR-0039) and `TaskCommandTests` pins that they do. `removeCategory` is offered only for
a task that has a project tag, the way `.goToBoard` is offered only with a board assigned.

The picker is presented from `RootView`'s sheet host beside `navigation.taskPickingBoard`
(`Sources/App/RootView.swift:147-148`), for ADR-0039 §D4's reason: a sheet owned by `TasksView`
works from `TasksView` and nowhere else, and assignment is offered from four surfaces.

The editor's `#project-` autocomplete is fed by widening `VaultSession.tagSuggestions`
(`Sources/Vault/VaultSession+Notes.swift:144-152`) with the registered, non-archived slugs. That
list already merges used tags with the closed vocabulary and de-duplicates; a registered slug nobody
has typed yet is exactly the case it misses today.

### §D9 — Connectors read, never write, from one shared implementation

Two payloads and two reads in `Sources/Connector` (`VaultCategories.swift`, plus the payload structs
beside the existing ones): `categories` (entries with `implicit`, `archived`, `parent`, `progress`)
and `category-tasks <slug>` (rolled up, grouped as the view groups). `perg` prints them
(`Sources/CLI/Commands/`), `pergamenum-mcp` declares two `readOnlyHint: true` tools
(`ToolCatalogue.reading`) and dispatches them (`VaultHost`). No write tool, no `--allow-write`
surface, so ADR-0007 §D6's guardrails (`isDryRun`, `UnifiedDiff`, `WriteJournal`) are not armed for
anything here — the SPEC says so explicitly, and this ADR repeats it so the implementation does not
add them to the app path out of symmetry.

The MCP SDK stays at 0.12.1. The `Tool(name:description:inputSchema:annotations:)` shape the
catalogue uses is still the documented one upstream (checked 2026-09-16 against the SDK's current
`_autodocs/types.md`); the newer optional `title`/`outputSchema`/`icons` fields are **not** adopted —
they do not exist in the pinned version.

### §D10 — The two lint findings are vault-scoped, so they are produced where the vault is visible

`NoteViolations` gains `categories: [CategoryViolation] = []`, defaulted, exactly as ADR-0021 §D11's
`taskMarkers` was, so the seven existing construction sites keep compiling untouched.
`LintFinding` (`Sources/Connector/VaultPayloads.swift:129-150`, a protected interface) gains one
additive key, `categories`, alongside `taskMarkers` — additive, so no existing consumer breaks.

The finding is produced in `VaultSession.violations(path:title:text:)`
(`Sources/Vault/VaultSession+Search.swift:106-132`) and not in a pure `Core` rule, because neither
rule is note-local: «unknown slug» needs the registry and «linked from more than one note» needs the
index. This is the one place in the lint path that can see both. Both findings are advisory; neither
blocks a write (SPEC §4.7: the linter reports and does not correct).

### §D11 — What the Obsidian amendment ends, and what it does not

**Ends:** the obligation that a future change keep Obsidian able to read the result; the round-trip
as a reason to reject a design; the manual round-trip probe as an acceptance gate (ADR-0020's
Probe 2, SPEC §13's M2 criterion at line 484).

**Stays, and is written down so nobody reads the amendment as wider than it is:** JSON Canvas 1.0
as the `.canvas` format; the `|W`/`|WxH` embed-size suffix; 16-hex node ids; the `pergamenum-`
prefixed-key discipline; the closed four-key frontmatter; the flat namespaced tag regex; wikilinks;
`vocabolari.json`; and **harness conformance entire** (principle 5), which is independent of
Obsidian and which the SPEC's constraints make binding on this chain.

**No test is deleted or disabled.** `CanvasTests.roundTripsAnObsidianCanvas` and its siblings pin
the JSON Canvas format, and the format stays — they are format tests that happen to be named after
Obsidian, not a compatibility gate. `CLAUDE.md`'s rule against disabling a test to make a suite pass
applies here with no exception.

Documents amended, with their dated note: `CLAUDE.md` principle 4 (rewritten: the vault opens
without conversion because the formats are standard, not because compatibility binds); SPEC line 16,
line 52, line 64 (the numbered principle), line 484 (the M2 criterion, annotated as satisfied and
retired, never deleted — it is a historical acceptance record) and §14's «Formato canvas» row at
line 502. `PROJECT_BRIEF.md`'s milestone history is **not** rewritten: it records what was true on
the day, including the 2026-08-22 decision this ADR finally propagates.

### §D12 — Past ADRs get a scope note at the head, never an edited body

An ADR whose *motivation* was the round-trip gets, immediately under its status block, a note of the
form: «**Scope note (2026-09-16, ADR-0047):** the Obsidian round-trip is no longer a binding
constraint. The decision below stands as taken and the format it chose is unchanged; what no longer
applies is the obligation that a future change keep Obsidian able to read the result. Body
untouched.» Nothing else in the file changes.

**The rule (reformulated 2026-09-17, fix-loop on the reviewer's finding — see the paragraph below
for why): a scope note goes where the round-trip is load-bearing for the decision itself — where
removing or changing that fact would change what was decided or which alternative was rejected —
regardless of which section it physically sits in (Context, Decision, a rejected alternative's
reason, or an acceptance probe).** A mention that only states a consequence or side-effect of the
decision (e.g. «and round-trips fine with Obsidian too», or «Obsidian compatibility is unchanged»)
does not qualify even when it sits inside a Context or Decision section, because it is not part of
*why* the decision was made — the test is content, not position. The original (2026-09-16) rule read
the four qualifying sections as the test by themselves; that version is superseded by this one, not
layered under it.

By the reformulated rule, re-running `grep -ril obsidian docs/adr/` and reading every hit's
surrounding paragraph against the load-bearing test (not a section-position count):

**Take a note (11): 0009, 0010, 0018, 0019, 0020, 0021, 0022, 0023, 0024, 0025, 0027** (R-14's «at
least 0019, 0020, 0024» is contained in it).
**Take none (18): 0001, 0002, 0004, 0012, 0013, 0014, 0028, 0029, 0030, 0032, 0033, 0034, 0036, 0040,
0041, 0042, 0043, 0046** — every mention in each is a consequence, a side-effect, or one illustrative
example among several equally-sufficient reasons, never the fact a decision would have gone
differently without.

**Fix-loop re-audit (2026-09-17), replacing the Task 8 correction below it superseded.** The
reviewer of the task-categories chain found that the 2026-09-16 rule's own worked example —
the Task 8 correction on **0032** — argued by content shape («reads like a Consequences-shaped
statement») rather than by the position rule it was supposedly applying, since 0032's hit sits in a
Context section and the position rule alone would have put it in "take a note." Stefano's decision
was to fix the rule itself rather than carry that mismatch, which is the reformulation above. Every
one of the 30 files `grep -ril obsidian docs/adr/` finds (29 plus this ADR, which is not audited
against its own rule) was re-read in full against it, not assumed from the 2026-09-16 pass:

- **0009 reclassified, take-none → take-a-note.** D1's Consequences line does not merely note a
  side effect — it states, in the ADR's own words, that "a vault with views in it opens in Obsidian
  exactly as it does today. **This is the whole reason the design is shaped this way.**" A document
  asserting its own causal reason is load-bearing wherever that sentence sits.
- **0018 reclassified, take-none → take-a-note.** Decision-section text (not Consequences, so even
  the superseded position rule should have caught this): "Both are accepted here **because** the
  alternative — a vault opened from Obsidian showing some embeds as pictures and some as raw
  brackets depending on which spelling a past editor used — is a worse failure than the extra
  recogniser." This is an explicit reason for extending §D3's dual-spelling recognition to the PDF
  case; without it, the ADR gives no reason to accept the extra recogniser there.
- **0032 stays take-none, now by the rule's letter rather than by content-shape argument alone.**
  Its Context hit ("a `pergamenum-plaud-id` … round-trips today with no parser change at all, and
  Obsidian … is unaffected") restates a fact already true for an unrelated reason
  (`Frontmatter.foreignKeys` preserving unknown keys, ADR-0020's mechanism) and draws a consequence
  from it; nothing about *whether* to add the key rests on Obsidian.
- **0004, 0033, 0036 stay take-none**, and the scope note the interrupted 2026-09-17 run had added to
  each on an undocumented ad hoc judgement is removed, restoring all three to their HEAD content.
  0004's "a parser that stops at the ten characters of the date — Obsidian, **or a Pergamenum older
  than this** — still gets the day right" names Obsidian as one of two equally-sufficient examples of
  "any naive reader"; removing it changes nothing the decision needed. 0033's Decision-section
  rejection of ADR-0019's resize handle already fails on its own terms ("**has no spelling for a
  fence**") before the shared-format clause is even reached; its Consequences line ("Obsidian
  compatibility is unchanged") is the textbook excluded shape. 0036's three hits (an `.eml`-only
  alternative rejected on three independently-sufficient counts, of which Obsidian-opacity is one;
  two Consequences-shaped "readable in Obsidian, in the Finder, by `grep`" and "sees them [without
  being told" lines) each have an Obsidian-independent reason that alone would have produced the same
  decision.
- **0001 and 0002 were the closest calls and were kept at take-none.** 0001's Context paragraph
  frames all four binding principles, Obsidian included, as "the reason for the choices, not
  decoration" — strong language — but none of D1 (module layout), D2 (GRDB index), D3 (FSEvents
  reconciliation) or D4 (theming) actually rests on principle 4 in its own text; each cites principle
  1 or 3 by name. 0002's "'vault' is an Obsidian term of art that means nothing to someone who has
  not used Obsidian" sits beside an independent, sufficient reason for the same rename ("Neither word
  says what is in it"); the label would have been retired for clarity alone.
- **Every remaining file already in "take none"** (0012, 0013, 0014, 0028, 0029, 0030, 0034, 0040,
  0041, 0042, 0043, 0046) was re-read in full and confirmed: each hit is either a Consequences-shaped
  compatibility statement, or names Obsidian as one of several interchangeable examples (another
  external editor, another plain-markdown reader, another concurrent writer) in a sentence whose
  point survives that example's removal.
- **No file already in the nine-item "take a note" list changed.** Each still cites the round-trip
  as the explicit reason for a specific mechanism (the `|W`/`|WxH` suffix spelling, the 16-hex node
  id shape matching Obsidian's own generator, the Obsidian-style trash convention A8 rejects, the
  literal-marker trade-off ADR-0021 accepts) — re-confirmed, not re-argued.

This chain's Consequences section (below) is updated to the corrected count of 11, not 9.

### §D13 — What this chain does not touch

No new task-line syntax. No rewrite of any task line by a registry operation (create, rename,
reparent, archive, delete). No change to `.canvas`, to the embed-size suffix, to node ids, or to any
other on-disk format. No category write from a connector. No priorities, natural-language dates,
infinite recurrence or saved views. No weakening of any harness convention. No sixth `TaskView`.
No second index schema bump beyond §D5's.

## Alternatives considered

The SPEC's interview settled ten of these with their rejection reasons; they are registered here in
one line each, not re-argued. The four after them are this ADR's own.

- **A dedicated `@cat(<slug>)` marker** (rejected, SPEC): a new parser field, a new §7.1 row, a new
  lint rule, earned only if a task could belong to a project *and* a different category — which
  nothing asked for.
- **A `#cat-` namespace** (rejected, SPEC): reopens SPEC §4.4's closed eight-prefix regex and the
  harness vocabulary for no gain over `project`.
- **An index note in markdown as the registry** (rejected, SPEC): hand-editable, but colour, parent
  and linked note do not sit well in prose and the parse is fragile.
- **Application Support or the SQLite cache as the registry** (rejected, SPEC): violates principle 1
  and principle 3 — the registry is not derived and must travel with the vault.
- **Rename rewrites the slug through `renameTag`** (rejected, SPEC): coherent, but touches N files
  for one sidebar gesture and forces the display name to equal the tag.
- **A composite `#project-<parent>-<child>` tag** (rejected, SPEC): self-describing on the line, but
  reparenting becomes a slug rename, which immutable slugs forbid.
- **A free-depth tree** (rejected, SPEC): the line carries one tag, so depth beyond two would live
  only in the registry, with no gain for personal use.
- **Registered-only, with an «Altro» bucket** (rejected, SPEC): historical `#project-*` tags vanish
  from the sidebar until registered one by one.
- **Auto-registration on first sight** (rejected, SPEC): the registry fills with typos.
- **Rewriting past ADR bodies instead of noting them** (rejected, SPEC): history lost; an ADR
  records what was decided and why, not what is true now.
- **Store the whole `foreignKeys` array in `StoredFrontmatter`** instead of §D5's one scalar
  (rejected, this ADR): it would also retire the Pratiche workaround, which is its real attraction,
  but it changes what the cache means for every note in the vault — arbitrary multi-line blocks from
  `pergamenum-mail-*` and `pergamenum-dossier-*`, none of them validated at cache-read time, and it
  invites call sites to trust the cache for keys nobody decided it should hold. That is ADR-0036's
  decision to revisit, on its own evidence, not a side effect of adding categories.
- **Re-open the linked note's file at derivation time, as Pratiche does** (rejected, this ADR): the
  workaround is right for Pratiche because the candidates are the handful of paths ending in
  `pratica.md`. A category's home note can be any note, so the same shape means re-reading the whole
  vault on every scan — the cache's purpose, inverted.
- **A sixth `TaskView` case for «category»** (rejected, this ADR): it reads as the smallest diff and
  it breaks the five-element invariant `defaultListOptions`, `taskCounts` and the `@AppStorage` map
  are written against, and reopens ADR-0013 §D6 in exactly the sense §D6 closed. A category row is a
  filter parametrised by slug, not a place with its own semantics; the derived selection enum of
  §D6 says that in the type.
- **A separate vault-wide lint pass for the two category findings** (rejected, this ADR): it would
  keep `violations(path:title:text:)` note-local and pure, which is tidier, but it means a second
  report shape, a second CLI path, a second MCP tool and a `LintFinding` that no longer carries every
  finding about a note. The existing engine already has a vault-scoped seam at the session; one
  advisory array on `NoteViolations` is the smaller, testable change (ADR-0021 §D11's precedent).

## Consequences

### Positive

- Every task already carrying `#project-*` becomes a category member at first launch, with no
  migration, no line rewritten and no file touched.
- The registry is one readable JSON file in the vault: it travels through iCloud with the notes,
  diffs in git, and is editable by hand when the app is closed.
- A category operation (create, rename, recolour, reparent, archive, delete) writes exactly one
  file, which makes R-01 a thing a test can assert by watching the vault rather than by reading the
  UI.
- The five views, their controls, their stored options and «Per progetto» behave exactly as they do
  today (§D4), so the chain's regression surface on existing task behaviour is the selection type
  and nothing else.
- The connectors gain two reads from the same implementation the app uses, so `perg` and the MCP
  server cannot disagree about what a category contains.
- The binding documents stop asserting a constraint nobody holds, and the ADRs whose reasoning
  rests on it (eleven, §D12's fix-loop re-audit — nine at the 2026-09-16 pass) say so at the head
  instead of silently misleading the next reader.

### Negative

- `IndexCache.schemaVersion` 3 → 4 discards every existing cache on first launch. One full rescan,
  once, on a vault that rebuilds in a fraction of a second (principle 3) — but it is a protected
  interface spent, and this chain gets no second bump.
- `NoteRecord` and `StoredRecord` each gain a field for a feature most notes do not use. The
  alternative was worse in kind (see Alternatives), but the cache row grows for everybody.
- The sidebar selection type changes, so `TasksView`/`TaskViewSidebar` and every call site of the
  binding must be updated together; a compiled language makes that loud rather than silent, which is
  the mitigation, not the absence of the cost.
- Effective category and «Per progetto» now answer differently for a task in a linked note with no
  tag. Defensible (§D4), and it is a thing a person can notice and be surprised by; the category
  header is where the rolled-up truth is shown.
- Eleven ADR files change at the head (nine at the 2026-09-16 pass, 0009 and 0018 added by §D12's
  2026-09-17 fix-loop re-audit). Small diffs, but they touch files that are otherwise append-only
  history.

### Neutral

- No new dependency, no SDK bump, no network path, no new frontmatter key outside the sanctioned
  `pergamenum-` prefix, no change to the tag grammar or the vocabulary.
- `.canvas`, the embed suffix and node ids are byte-identical after this chain; a board still opens
  in Obsidian, and nothing promises it will keep doing so.
- Archived categories stay out of pickers but their tasks stay in Oggi, Prossimi and Tutti, so no
  deadline becomes invisible (SPEC edge case, registered).

## Protected-interface proposal

- `IndexCache.schemaVersion` — bumped to `4` by §D5, with the reason recorded in the file's own
  running comment. No further bump in this chain.
- `VaultAPI.LintFinding` — one additive key (`categories`); every existing key keeps its name,
  type and meaning.
- **New, proposed protected:** `CategoryRegistry`'s on-disk shape (the `categories.json` schema and
  its `version` field), for the reason `MessageDocument`'s naming is protected — it is a file format
  in somebody's vault, and a silent change to it loses data that exists nowhere else.

## References

- `docs/plans/task-categories.md` — the implementation plan for this ADR, all 8 tasks completed.
- `SPEC.md` (root), topic `task-categories`, Approved 2026-09-16 — Decisions, Constraints, Data
  model, Test seams, Success criteria R-01…R-16.
- `CLAUDE.md` — binding principles 1 (file over app), 3 (rebuildable index), 4 (amended by §D11),
  5 (harness conformance, untouched); design-system token rule; AI connector section.
- `docs/20260811_Pergamenum_SpecApp.md` — §4.3, §4.4, §4.7, §7.1, §7.4, §13 (M2), §14.
- ADR-0007 §D2/§D3/§D6, ADR-0013 §D6, ADR-0020 (§D on prefixed keys; :523 and Probe 2),
  ADR-0021 §D6/§D11, ADR-0023, ADR-0024, ADR-0032 §D6, ADR-0039 §D2/§D4, ADR-0041 §D9–§D11,
  ADR-0043 §D8, ADR-0046 §D1/§D5.
- `PROJECT_BRIEF.md:605-617` — the 2026-08-22 decision as recorded on the day, and the note that it
  was not yet propagated.
- MCP Swift SDK `_autodocs/types.md`, checked 2026-09-16: the `Tool` initialiser shape in
  `ToolCatalogue.swift` is current; the pinned version is 0.12.1 (`Tuist/Package.resolved`).
