# ADR-0049: A pratica links to notes, tasks and boards by writing the shape the rename passes already rewrite

- Status: accepted, proposed for the `feat-note-project` branch (on top of `a501823`).
- Date: 2026-09-18. Written after reading, at the line, every file it names on this worktree.
- Source: `SPEC.md` at the repository root, Status Approved (2026-09-18), topic
  «Collegamenti Pratiche a note, attività e workspace». Its `## Decisions` and `## Constraints`
  are settled input: cardinalities, the by-title rule, the "broken, never silently removed"
  rule, the column-not-inline layout, the inspector staying `pratica.md`, and read+write through
  the connector are recorded there and are not re-litigated here. What this ADR decides is the
  *mechanism* the SPEC left open.
- **Extends ADR-0036** (Pratiche) by adding two frontmatter families to files it owns. It does
  **not** amend §D5 (the inspector is the one editor of `pratica.md` — §D9 below keeps it),
  does **not** amend §D6 (the sync's closed list of automatic rewrite triggers stays at four —
  §D6 below says why a manual link write is not a fifth), and does **not** touch §D12's
  `Dossier` codec, whose `render` is a protected interface (§D1 below is the decision not to).
- **Extends the note↔task↔board link family of ADR-0021 and ADR-0039** to a fourth participant.
  ADR-0021 §D1's `^id(N)` identity and §D3's "the rename is free because the marker is a
  wikilink" argument are reused verbatim; neither is amended.
- **Reopens nothing.** No SPEC §14 decision, no on-disk format, no protected interface
  (`Dossier.render`, `VaultAPI.PraticaSummary`, `PraticaNaming.messageFileName`,
  `MessageDocument.isPendingAttachmentEntry`, `IndexCache.schemaVersion`,
  `VaultAPI.LintFinding` are all untouched — §D1, §D4 and §D12 are the decisions that keep
  them so), no `IndexCache.schemaVersion` bump, no new dependency, no new design token, no
  network call. CLAUDE.md principle 2 gains no exception: every byte read here was written to
  this vault by this app.
- Depends on: **ADR-0036** in full, **ADR-0021** §D1–§D4, **ADR-0022** (the board creation flow
  reused unchanged, and the by-title rule), **ADR-0025** §D5 (`WorkspaceBoardResolver`),
  **ADR-0039** §D3 (a picker hosted on `RootView` so every surface reaches it), **ADR-0040**
  §D3 (the `"[[name]]"` spelling already used inside a `pergamenum-mail-*` value),
  **ADR-0042** §D8 (`MessageFrontmatterPatch`, the generalized one-line surgery),
  **ADR-0043** §D8 (the opt-in `expecting:` hash precondition), **ADR-0007** §D6 (the three
  connector write guarantees), **ADR-0001** §D1 (`Sources/Core` imports no SwiftUI).

---

## Context

A pratica (ADR-0036) is an isolated domain. Notes, tasks and boards already relate to one
another — a task carries `^[[board.canvas]]` and plain wikilinks (ADR-0021 §D1), a board's tray
lists the notes it carries and the tasks assigned to it (§D7/§D8), a task navigates to both
(ADR-0039) — and a pratica participates in none of it. The SPEC asks for two relations: a
pratica to many notes, many tasks and many boards; and one email message of its timeline to at
most one note, shown aligned beside that message's row.

Four things were read at the line before deciding, and each one moved the decision:

**1. The cache stores no foreign key, and the Pratiche layer already knows it.**
`IndexCache.StoredFrontmatter` (`Sources/Index/IndexCache.swift:307-328`) persists `date`,
`tags`, `aliases` and `related` — nothing else. So a `NoteRecord` a scan reused from the cache,
which is every unchanged file from the second scan of a vault onward, comes back with
`foreignKeys` empty. `Dossier.parse(praticaFileAt:)`'s own doc comment
(`Sources/Core/Pratiche/Dossier.swift:61-80`) says this out loud and draws the conclusion the
whole feature rests on: *the index names the candidates by path and the file decides*.
`PraticheController.listItems` (`PraticheController+TimelineRead.swift:22-33`) and
`VaultAPI.praticaNotes` (`Sources/Connector/VaultPratiche.swift:99-119`) both already open the
handful of `pratica.md` files rather than trust the index for a `pergamenum-*` key.

**2. Both rename passes read the whole file, and the index reads only the body.** This is the
finding that decides the reference format.

- `NoteFileOperations.renamePlan` (`Sources/Vault/NoteFileOperations.swift:106-121`) loops over
  `knownPaths`, reads each note's **whole text** with `store.text(path)`, and runs
  `NoteRename.rewritingLinks`. Its own comment at `:107-111` says the frontmatter is included on
  purpose.
- `BoardFileOperations.renamePlan` (`Sources/Vault/BoardFileOperations.swift:95-112`) does the
  same thing for a board rename, with `oldName`/`newFileName` as the needle.
- `knownPaths` is `index.allNotes.map(\.relativePath)` at all three call sites
  (`VaultSession+Files.swift:22`, `VaultSession+Folders.swift:24` and `:54`) — which includes
  `pratica.md` **and** every `email/*.md`.
- `NoteRename.rewritingLinks` (`Sources/Core/Conventions/NoteRename.swift:22-44`) rewrites every
  `[[Target]]` anywhere in the text it is given, and then also every `- "Target"` quoted
  block-list line anywhere in it (`rewritingQuotedRelated`, `:51-67`).
- `NoteStore.linkTargets(in document:)` (`Sources/Vault/NoteStore+ReadSurface.swift:27-35`)
  scans `document.body` **only**. So the index's backlink graph never sees a frontmatter
  wikilink, while the rename pass always does. A future reader will assume both or neither;
  neither is true.

**3. `Dossier.merging` deletes an owned key whose list has gone empty.**
`Dossier.merging(_:into:)` (`Sources/Core/Pratiche/Dossier.swift:121-145`) keeps every key it
does **not** own byte-for-byte at its original position (§D12's C4), and drops an owned key that
`render` omitted. `DossierWriter.update` (`Sources/Features/Pratiche/DossierWriter.swift:25-44`)
performs that merge on every membership change a sync makes. Any key folded into `Dossier` is
therefore a key a future `Dossier` value built without it can erase; any key left foreign to it
is preserved for free, in both directions.

**4. «Rigenera» replaces the file wholesale, and its opacity guarantee is structural.**
`regenerationPreview` (`Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift:670-730`)
builds `prepared.noteText` from the Mail store, diffs it against the file on disk and hands both
back inside a `RegenerationPlan` whose `prepared` is `fileprivate`; `commitRegeneration`
(`:735-740`) writes `prepared`, not `replacementText`. That is ADR-0036 §D21's whole
implementation of "the bytes shown in the diff are the bytes written", and ADR-0045 §D4 refuses
to split the file for it. Anything the store cannot reconstruct is destroyed by a regeneration
unless it is carried into `prepared` **before** the diff is taken.

---

## Decision

### §D1 — The general links are their own codec, foreign to `Dossier`

Three new keys on `pratica.md`, in the SPEC's own `pergamenum-dossier-links-*` pattern:

| Key | Shape | Holds |
|---|---|---|
| `pergamenum-dossier-links-notes` | `- "[[Titolo]]"` block list | notes linked to this pratica |
| `pergamenum-dossier-links-tasks` | `- "[[Nota]] ^id(3)"` block list | tasks linked to this pratica |
| `pergamenum-dossier-links-boards` | `- "[[Nome.canvas]]"` block list | boards linked to this pratica |

They live in a new type, `PraticaLinks` (`Sources/Core/Pratiche/PraticaLinks.swift`), which
parses and renders over `Frontmatter.ForeignKey` through the existing `DossierYAML` subset and
merges in place with `Dossier.merging`'s own C4 rule. **`Dossier` is not extended**: its
`ownedKeys` stays seven, its `render` — a protected interface whose entry in
`.claude/protected-interfaces` says a shape change "silently unmakes every pratica already on
disk" — is untouched, and `interface-check.sh` never fires.

Two reasons, and the second is the load-bearing one. First, folding the links in would spend a
protected interface on a change that needs nothing from it. Second, Context finding 3: a key
owned by `Dossier` is a key `Dossier.merging` erases the moment a `Dossier` value is built
without it, and `DossierWriter.update` runs that merge on every membership change a sync makes.
A person's links must not be one refactor away from being deleted by an automatic sync write.
Kept foreign, they are preserved byte-for-byte by a rule that already exists and is already
tested.

### §D2 — Every reference is written as a wikilink, because that is the shape both rename passes already rewrite

`- "[[Titolo]]"`, `- "[[Nome.canvas]]"`, `- "[[Nota]] ^id(3)"`, and on a message file
`pergamenum-mail-note: "[[Titolo]]"`.

R-07 ("renaming the target does not break the link") then costs **no new code at all**, for
notes and for boards alike, by Context finding 2: a note rename and a board rename both read
every indexed note's whole text — `pratica.md` and `email/*.md` among them — and rewrite every
`[[…]]` in it. This is ADR-0021 §D3's argument ("the rename requirement is free because the
marker is a wikilink") applied to a second carrier, and it is verified the same way §D3 verified
itself: a unit test over the pure function, not a claim about a screen.

The wikilink form is also already the spelling this key family uses for a resolved reference:
ADR-0040 §D3 writes a placed attachment as `"[[name]]"` inside
`pergamenum-mail-attachments`. Nothing new is being invented here, only reused.

**Rejected: the bare title, `- "Titolo"`.** It *would* also follow a rename — but only through
`NoteRename.rewritingQuotedRelated`, which matches any `- "…"` line anywhere in a file
regardless of which key it sits under, and whose own doc comment
(`NoteRename.swift:17-21`) calls that breadth "a silent corruption this type was never meant to
cause". A pratica's links must not be hostage to a helper documented as over-broad, and a bare
board reference `- "Vecchia.canvas"` would be rewritten by a *note* rename that happened to
match it.

**Rejected: a vault-relative path.** The SPEC's own Decisions rule it out, and ADR-0022's rule
("a wikilink names a note by title, never by path") is what makes a folder move free.

### §D3 — A task is named by its note and its `^id`, never by its text

`[[Nota]] ^id(3)` reads as what it is: the task carrying `^id(3)` inside the note titled `Nota`.
Linking a task that has no `^id` yet allocates one through `TaskParser.nextLocalID(in:)` plus a
single guarded line rewrite — the mechanism `TaskParser.insertingSubtask`
(`Sources/Core/Tasks/TaskParser+Writes.swift:214-243`) already performs for a parent task,
staleness guard included. The `^id` marker survives a rename of its note because the caret and
the parentheses sit outside the wikilink's replaced range, which is the property ADR-0021 §D3
measured and pinned.

**Rejected: the task's own text as its title.** Editing a task's wording is routine and two
tasks share a wording far more often than two notes share a title; the link would break on the
most ordinary edit there is, and break silently.

**Rejected: a vault-wide task identifier.** ADR-0021 §D2 refused a registry on purpose ("no
counter is persisted anywhere, which is principle 3 applied to identity"). This feature is not
the place to reverse that, and does not need to.

### §D4 — `IndexCache.schemaVersion` stays at 4, and the reason is that nothing new is cached

Every fact this feature introduces is read from the file that owns it:

- `pratica.md`'s three keys come back through `PraticaLinks.parse(praticaFileAt:)`, the exact
  shape and the exact reason `Dossier.parse(praticaFileAt:)` has (Context finding 1). The
  handful of `pratica.md` files the index already points at are opened; the whole index never is.
- A message's key comes back through `MessageDocument.parse`, which
  `PraticheController.readTimeline` already runs once per `email/*.md` file when a pratica is
  selected, and which `VaultAPI.timeline(ofPraticaFolder:)` already runs on the connector side.
- Resolution reads `IndexSnapshot.resolve(title:)` (`Sources/Index/IndexSnapshot.swift:106-108`)
  and `CanvasStore.allBoards()`, both unchanged and both already cached the way they were.
- A task's `localID` is already parsed out of `rawLine` by `TaskParser`, which is ADR-0021 §D4's
  own "no schema change, no version bump" holding unchanged.

**The corollary is a rule for the coder, restated from ADR-0021 §D4 because it is the same
trap: do not add a field to `StoredRecord` or `StoredTask`.** Doing so creates the cache/file
disagreement the version constant exists to prevent, and then requires the bump this decision
avoids. ADR-0047 §D5 spent the 3 → 4 bump for a fact that genuinely had to be stored per note;
this feature has no such fact.

The hazard the bump would otherwise be covering is real and is named instead: **a link must
never be read off `NoteRecord.frontmatter.foreignKeys`.** On a cache-reused record that array is
empty, so the links would work on a freshly scanned vault and vanish from the second launch
onward — the exact defect shape Pratiche already paid for once.

### §D5 — One resolver, assembled from the two that exist, never a third index

`PraticaLinkResolver` (`Sources/Core/Pratiche/PraticaLinkResolver.swift`, Foundation-only)
answers one three-case question — `unique(path)` / `ambiguous` / `missing` — for all four
relations, and it answers it by delegating:

- **board** → `WorkspaceBoardResolver.resolve(_:in:)` literally, unchanged. Its
  `WorkspaceBoardResolution` cases map one-to-one; the ambiguity behaviour the SPEC's Edge cases
  point at is therefore the behaviour that already ships, not a new one.
- **note** → `IndexSnapshot.resolve(title:)`'s `[String]` folded into the same three cases:
  zero is `missing`, one is `unique`, more is `ambiguous`.
- **task** → the note half exactly as above, then the `^id` looked up among that note's tasks.

Candidates are **passed in**, never fetched inside the resolver — `WorkspaceBoardResolver`'s own
stated rule, because `CanvasStore.allBoards()` is an uncached full filesystem walk and a
resolver called per row must not repeat it.

`missing` is what "broken" means in the UI. **Nothing is ever removed on a miss** (the SPEC's
own decision): the reference stays on disk exactly as written, and the surface that draws it
says so.

### §D6 — The per-message key is `pergamenum-mail-note`, written by the patch, and ADR-0036 §D6 is not reopened

The key joins the `pergamenum-mail-*` family on the message file, holds the wikilink form, is
absent when there is no link, and is written by
`MessageFrontmatterPatch.applying(line:forKey:before:to:)` — the generalized one-line surgery
ADR-0042 §D8 built precisely so a second key could not drift from the first's rules. This is its
third key. Every other byte of the file is untouched.

The key is also a stored property of `MessageDocument.MailFrontmatter` (`linkedNote: String?`,
defaulted `nil`, declared after `pendingInlineImages`) and is rendered and parsed by
`MessageDocument` like the rest of the family. Both halves are needed and neither is redundant:
the patch is what an ordinary link/unlink uses, and the render/parse pair is what makes §D7's
carry-over possible and what keeps a re-rendered file from dropping the key.

**ADR-0036 §D6 governs what a *sync* rewrites, and it stays at four triggers.** Linking a note
is a person's explicit action on one file, of the same nature as «Rigenera» — which §D6 already
excludes from its own count for the same reason. No automatic trigger is added, no rewrite
happens during a sync because of this feature, and a message file with no link is byte-identical
to one written before this ADR. This is stated out loud because §D6 has been amended twice and
widened once already, and the next reader will reach for a fifth amendment that is not needed.

### §D7 — «Rigenera» carries the link across, and it does so before the diff is computed

`regenerationPreview` reads the on-disk `pergamenum-mail-note` out of `currentText` and patches
it into `prepared.noteText` **before** `UnifiedDiff.between` runs, so the plan's
`replacementText`, its diff and the bytes `commitRegeneration` writes are one and the same.

Patching `replacementText` alone would compile, look right in the sheet and silently destroy the
link, because `commitRegeneration` writes `prepared` (Context finding 4). `PreparedMessage`
is `fileprivate` in that same file and its `noteText` is a `var`, so the change is three lines
inside `PraticaSyncEngine+Messages.swift` and crosses no access boundary — ADR-0045 §D4's
"keep the cluster whole" holds untouched.

Without this decision a regeneration deletes a fact the Mail store has no copy of, which is the
one kind of loss a regeneration is not allowed to cause.

### §D8 — The per-message column lives inside the timeline row, and there is no second scroll view

Each message row becomes an `HStack` of the existing message lane plus a fixed-width note slot
at the trailing edge. The lane's own ~70 % (R-25's third carrier of direction) is computed on
`width - gutter` inside the `containerRelativeFrame` closure the row already has
(`PraticaTimelineView.swift:140-142`), so lanes and column cannot overlap.

Vertical alignment is then a property of layout rather than of arithmetic, and the column
scrolls in sync with the timeline because there is exactly one scroll view. A message with no
linked note draws an empty slot at that height, which is what the SPEC's Edge cases describe.

**Rejected: a second `List`/`ScrollView` beside the timeline, synced by scroll offset.** Row
heights change whenever a row expands (R-24), SwiftUI offers no supported scroll-offset sync,
and this repository has paid twice already for layout that depends on measured geometry inside a
culling list — ADR-0029's culling deallocation and CLAUDE.md's `firstRect` zero-rectangle trap,
which fails by silently clamping rather than by erroring.

**Rejected: an inline expansion under the row.** The SPEC rejected it: the point is reading the
email and its note side by side.

### §D9 — The column is read-only, and the inspector is never switched

The slot draws the linked note's title and opening lines and opens it in the editor —
`vault.openChosenNote(at:)` plus `navigation.pane = .notes`, the same two calls
`PratichePane.openPraticaNote` already makes. No text view is bound to the note in the column.

This is ADR-0036 §D5's reasoning applied to a second surface without reopening it: *n* live text
views bound to *n* files inside a `List` that culls its rows, while a background sync may rewrite
those same files, is the shape of every text-loss defect this repo has documented. The pratica
inspector keeps showing `pratica.md` and only `pratica.md`, whatever row is selected — R-09 is
satisfied structurally, because nothing in this chain writes the inspector's content at all.

### §D10 — The commands join the two catalogues that exist, and one picker serves all four relations

`PraticaCommand` gains `.linkNote`, `.linkTask`, `.linkBoard`; `MessageCommand` gains
`.linkNote` and `.unlinkNote`, and its `available` takes a second argument
(`hasLinkedNote:`). The new pratica cases are declared **before** `.delete`, because
`PraticaMenuItems.menu(for:)` keys its divider on `.delete` and anything after it would be drawn
below the separator that belongs to the destructive verb.

The consequence is an observable-contract change and is named rather than left to be discovered:
`PraticaCommand.allCases.count == 7` and `MessageCommand.allCases.count == 6`
(`Tests/PraticaCommandTests.swift:18` and `:70`) become 10 and 8, and every call site of
`MessageCommand.available(hasAttachments:)` — `PraticaCommandActions.swift:50` plus three in
that same test file — changes with the signature.

**One new picker, `PraticaLinkPicker`**, modelled on `WorkspacePicker`'s shape (filter field,
list, footer, 380×380) and parameterised by target kind, with a «Crea nuova…» row that satisfies
the SPEC's "existing or new" in one surface. It is hosted on `RootView` behind a
`Navigation` field, which is ADR-0039 §D3's decision reused for the same reason: the command is
offered from more than one surface and a sheet hosted in one of them cannot be reached from the
others.

**Rejected: reusing `QuickSwitcher`.** Its own doc comment states the constraint — *"One caller,
one question. The note pane asks 'where do I go'"* — and its `field`'s `.task` consumes
`vault.consumePendingSearch()`, so a picker opened from a pratica would swallow a queued
`pergamenum://search` query. It also offers headings and the daily note, which are not link
targets.

**Rejected: generalising `WorkspacePicker`.** Its signature is `let task: TaskItem`; widening it
for a second consumer changes ADR-0039's flow to buy nothing a sibling view does not buy more
cheaply.

### §D11 — The write door is `DossierWriter`'s shape, with the `expecting:` precondition it already carries

The links writer is a second read-modify-write of exactly `DossierWriter.update`'s form: read
through `session.read`, parse, mutate, merge in place, write with
`expecting: record.contentHash` (ADR-0043 §D8), return the same Italian refusal sentence on a
`VaultSession.WriteRefusal`, and write nothing at all when nothing changed.

The precondition matters more here than it does for the dossier itself. A links write and a
running sync's dossier write touch the same file's frontmatter from two different actors, and
the loser of that race must be told rather than silently dropped — which is the whole of
ADR-0046 §D1's argument, applied to the one door this feature adds.

### §D12 — The connector gets read and write, in `Sources/Connector`, and the CLI/MCP asymmetry stays as it is

A new file, `Sources/Connector/VaultPraticheLinks.swift`, holds every capability: reading a
pratica's links with each reference's resolution state, reading the per-message links of its
timeline, linking and unlinking each of the four relations, and creating a note/task/board
already linked. The two front ends only translate — `Sources/CLI` reads flags and prints,
`Sources/MCPServer` declares schemas — which is CLAUDE.md's own rule that a capability
implemented in one front end is a capability the other does not have.

- **`VaultAPI.PraticaSummary` is a protected interface and is not touched.** The new read is a
  new payload type; `PraticaTimelinePayload.Entry`, which is not protected, gains `linkedNote`
  additively.
- **Writes carry the three existing guarantees** (`isDryRun`, `UnifiedDiff`, `WriteJournal`)
  because they go through `VaultSession.write` after `VaultAPI.arm`, like every other connector
  write. On MCP the new write tools are absent from `tools/list` without `--allow-write` and
  their `dryRun` defaults to **true**; on the CLI `--dry-run` is opt-in. That asymmetry is
  ADR-0007 §D6's existing contract (`Sources/CLI/Writing.swift:13`), it is deliberate, and it is
  not "fixed" here.
- **ADR-0036 R-36 keeps holding**: no `MailStore`, `EMLXReader` or `SQLite3` name appears in the
  new file. Every byte it reads was written to the vault by a sync that already ran.
  `Tests/SharedSourcesPurityTests.swift` covers the new file automatically, since it walks the
  `Sources/Core` and `Sources/Connector` directories rather than a list.

---

## Alternatives considered

- **Fold the three keys into `Dossier`, taking it from seven keys to ten.** Rejected in §D1: it
  spends a protected interface for nothing, trips `interface-check.sh`, and — the real reason —
  makes a person's links deletable by `Dossier.merging` the first time a `Dossier` value is
  constructed without them, on a write path a sync performs routinely.
- **Keep the links in a sidecar file** (`.pergamenum/pratica-links.json`, `StarredStore`'s
  shape). Rejected: principle 1 says the content lives as a readable file, and ADR-0036 made a
  pratica *its folder*. A link that disappears when the folder is copied elsewhere is not the
  same object as the pratica it belongs to. The frontmatter is already where a pratica's own
  facts live.
- **Write the links as ordinary wikilinks in `pratica.md`'s body.** Rejected by the SPEC's own
  Decisions, and correctly: it works for notes and needs a second, different mechanism for tasks
  and boards, and the body is a text a person edits freely, where an app-owned list would fight
  them.
- **Store bare titles rather than wikilinks.** Rejected in §D2: it survives a rename only via
  `rewritingQuotedRelated`'s deliberately over-broad `- "…"` match, which its own doc comment
  names as a corruption risk.
- **Reference a task by its text.** Rejected in §D3: the most ordinary edit there is would break
  it, silently.
- **Add a vault-wide task identifier.** Rejected in §D3: ADR-0021 §D2 refused a registry on
  purpose.
- **Cache the links on `NoteRecord` and bump `IndexCache.schemaVersion` to 5.** Rejected in §D4:
  it buys a list that is already assembled from files the pane opens anyway, and spends a bump
  that discards every existing cache in the process.
- **A second scroll view beside the timeline, synced by offset.** Rejected in §D8: dynamic row
  heights, no supported sync API, and a failure mode this repo has documented twice.
- **Switch the inspector's content to the selected row's note.** Rejected by the SPEC and by
  §D9: it would reopen ADR-0036 §D5 to deliver less than the aligned column delivers.
- **Reuse `QuickSwitcher` as the note picker.** Rejected in §D10: one caller, one question, plus
  a pending-search side effect that would be stolen from a route.
- **Expose the feature read-only through the connector.** Rejected by the SPEC: an assistant
  working the vault without the app is precisely the case this is for, and the write guarantees
  that make that safe already exist.

---

## Consequences

### Positive

- R-07 costs no new code for notes and boards: the two rename passes already rewrite the exact
  bytes §D2 writes, and a unit test over `NoteRename.rewritingLinks` proves it without a window.
- R-08 gets a second, free signal at the write layer:
  `NoteFileOperations.danglingLinks(for:knownPaths:)` scans whole text, so trashing a linked note
  already reports the pratica that pointed at it.
- No cache bump, so no vault pays a full rescan on first launch after this ships — unlike
  ADR-0047, which had to.
- No protected interface changes, so `interface-check.sh` stays quiet and none of the four
  Pratiche invariants it guards is put at risk.
- Nothing on disk changes shape for a pratica that uses no links: `pratica.md` and every message
  file are byte-identical to what ships today until a person links something.
- The resolver is made of the resolvers that exist, so the ambiguity behaviour a person sees for
  a pratica link is the one they already know from a task's board marker.
- `MessageFrontmatterPatch` gains its third key without gaining a third set of rules, which is
  what ADR-0042 §D8 generalized it for.

### Negative

- **A vault-wide note rename now rewrites files inside a pratica's `email/` folder.** That is
  new: until now only a sync and an explicit «Rigenera» wrote there. It is not a §D6 trigger
  (§D6 is about the sync) and it is exactly what R-07 asks for, but a person watching file
  modification times will see message files touched by an operation that has nothing to do with
  Mail. Named here rather than discovered later.
- **A frontmatter wikilink produces no backlink and no entry in "Link non risolti"**, because
  `NoteStore.linkTargets` scans the body only (Context finding 2). A linked note does not know,
  from the index, that a pratica points at it. Accepted: the SPEC asks for no reverse lookup, and
  adding one would mean either scanning foreign keys for links vault-wide or storing the relation
  a second time.
- **Linking a task can write a second file.** A task with no `^id` gets one allocated in its own
  note, so a link gesture on a pratica writes two files. Guarded and journalled like any other
  write, but it is more than the one file a person would expect.
- **Two catalogue counts and one `available` signature change**, so five existing assertions and
  one call site are updated in the same task rather than left to fail later.
- **The timeline's message lane gets narrower** by the width of the gutter, on every pratica,
  including those with no linked note at all. A column that appears only when something is linked
  would reflow the whole timeline the moment a link is added, which is worse.
- **`pratica.md`'s frontmatter grows a third family of keys.** Three of the seven closed note
  keys plus seven dossier keys plus three links keys is a long block above a short note. It stays
  within the `pergamenum-` prefixed-key discipline (ADR-0020's precedent) and the closed four-key
  schema is untouched, but the file is denser to read by hand.

### Neutral

- `Dossier` and `PraticaLinks` each treat the other's keys as foreign, so each preserves the
  other byte-for-byte through §D12's C4 rule, in both directions, with no coordination between
  them.
- The broken state needs no new design token: the `questionmark.square.dashed` glyph plus
  `textTertiary` is the treatment `BoardTray.noteRow` already gives an unresolved reference.
- `QuickSwitcher.Choice.createNote` and `WorkspacePicker` are left exactly as they are; this ADR
  adds a sibling rather than widening either.
- The per-message relation stays 0/1 and the manual timeline entries (Nota/Telefonata) stay
  unlinkable, both per the SPEC's Out of scope. Nothing here forecloses widening either later:
  the key is a scalar and would become a list, and a manual entry has no file of its own to
  carry a key, which is the real reason it is out of scope rather than an oversight.

---

## Tests

The SPEC's Test seams are adopted as written, and nothing is invented beside them:

- **Codec** — round-trip of the three `pratica.md` keys and of `pergamenum-mail-note`, including
  byte-preservation of every foreign key neither codec owns, and a `pratica.md` carrying dossier
  keys and links keys merged in either order.
- **Rename and breakage** — `NoteRename.rewritingLinks` over a rendered `pratica.md` and a
  rendered message file, asserting the reference follows a note rename and a board rename and
  that a task reference keeps its `^id`; plus resolution returning `missing` for a deleted target
  and `ambiguous` for a duplicated title.
- **Connector** — the new reads and writes through a `TemporaryVault`, including that a
  `dryRun` write changes no byte and that a write tool is absent from the catalogue without
  `--allow-write`.
- **Regeneration** — a message carrying a link, regenerated, still carries it, and the diff shown
  contains the key (§D7's guarantee, asserted on the plan rather than on the file).
- **Visual** — by hand, through `scripts/uitests.sh` before the merge, per the SPEC: no new
  automated UI test in this iteration.

---

## References

- `SPEC.md` (root, Approved 2026-09-18) — the source of every decision recorded above as settled.
- ADR-0036 §D5, §D6, §D12, §D21 — the inspector's single-editor rule, the sync's rewrite
  triggers, the dossier line codec, the regeneration opacity guarantee.
- ADR-0021 §D1–§D4 — `^id`, the caret-outside-the-range rename property, and the "no schema
  change, no version bump" argument this ADR repeats.
- ADR-0022, ADR-0025 §D5 — by-title references, the board creation flow, `WorkspaceBoardResolver`.
- ADR-0039 §D3 — a picker hosted on `RootView`.
- ADR-0040 §D3, ADR-0042 §D8 — the `"[[name]]"` spelling and `MessageFrontmatterPatch`.
- ADR-0043 §D8, ADR-0046 §D1 — the `expecting:` precondition and why a refusal is reported.
- ADR-0047 §D5 — the last `IndexCache.schemaVersion` bump, and the rule this ADR declines to
  spend again.
- ADR-0007 §D2, §D6 — `sharedSources`, and the three connector write guarantees.
- `docs/plans/pratiche-note-task-workspace-links.md` — the implementation plan for this ADR.

---

## Implementation notes (chain 2026-09-18)

Appended by the implementation chain whose plan is
`docs/plans/pratiche-note-task-workspace-links.md`. **Nothing above is altered.** Four things the
chain measured against the plan's own stated file list and this ADR asked to have recorded back.

### 1. Task 5's three sections are appended from `PratichePane+Inspector.swift`, not `PratichePane.swift`

The plan's Task 5 names `PratichePane.swift` as the one file modified. R-04 itself is what moves
the edit: the three sections have to land "sotto il corpo di `pratica.md`", inside the same
scroll view the body already draws, and that view is built by `PratichePane+Inspector.swift`'s
`inspector`, not by `PratichePane.swift` (which only assembles the pane's outer split and toolbar).
The new file `PratichePane+Links.swift` (§D9's own new sections) is unchanged from the plan; only
the one-line call site — `if pratiche.selection != nil { praticaLinksSection }`, right after the
existing body if/else — moved to the file that actually owns the scroll view.

### 2. Task 6's note-slot column has no SPEC-given width

§D8 fixes the shape (a fixed-width trailing slot inside the row's own `HStack`) but not a number.
`PraticaTimelineView.noteSlotWidth` is `200`pt, chosen to hold a linked note's title plus up to
three opening lines (`PraticaMessageNoteSlot.openingLines(of:limit:)`) without starving the
message lane's own 70% at the pane's ordinary widths. Nothing else in the SPEC or this ADR names
a number for it; the plan's own §D8 text is silent on it too. If a future pane-width change makes
this feel cramped or wasteful, the value lives in exactly one place.

### 3. `pratica`'s and `message`'s CLI verbs are split into sub-dispatch functions, and `VaultHost`'s write switch is split into a new file — both for the reason ADR-0045 already named once

`main.swift`'s `dispatch(_:_:)` grows two new second-level groups, `praticaGroup`/`messageGroup`
(ADR §D12), each keyed on `arguments.word(1)`: `pratica <riferimento>` still shows when the second
word is not a verb, and shifts to `link-note`/`unlink-note`/`link-board`/`unlink-board`/
`link-task`/`unlink-task`/`create-note`/`create-task`/`create-board` otherwise. `praticaGroup`
itself delegates to two further functions, `praticaLinkVerb`/`praticaCreateVerb`, because one
switch covering all nine verbs plus the existing `show` fall-through crosses SwiftLint's
cyclomatic-complexity ceiling — the same debt shape ADR-0045 resolved for `type_body_length`,
applied here to a `switch`'s branch count instead of a type's line count, and resolved the same
way: split along an existing seam (link verbs vs. create verbs), no behaviour change.

On the MCP side, `VaultHost`'s write-tool switch crossed `type_body_length` the moment the new
`pratica_link_note`/`pratica_unlink_note`/`pratica_link_board`/`pratica_unlink_board`/
`pratica_link_task`/`pratica_unlink_task` cases were added, so they live in a new file,
`Sources/MCPServer/VaultHost+PraticheLinks.swift`, following ADR-0045 §D2's own convention
literally: an extension of the same type, not a new type, and `session`/`reply(_:)` widen from
`private` to `internal` with a one-line comment on each naming the file that reads it. No new
`type_body_length` or cyclomatic-complexity warning remains on either touched file after the
split; `swiftlint --quiet` was re-run against both to confirm.

### 4. One lint warning found and fixed inside Task 5, not carried forward

`PratichePane+Links.swift`'s shared row builder, `linkRow`, was first written with seven
parameters (reference, display name, resolution, icon, missing-help text, `onOpen`, `trailing`)
and tripped SwiftLint's `function_parameter_count` warning on first lint pass. The five static
fields are bundled into a private `LinkRowContent` struct; `onOpen` and `trailing` stay discrete
parameters, since they are the two things a call site actually varies in shape rather than in
value. `linkRow` is `private` to this one file, so the change reaches only its three existing call
sites, all updated in the same edit. Confirmed by re-linting the file after the change: zero
warnings.

### 5. `main.swift`'s outer `dispatch` was already over SwiftLint's complexity ceiling, and one more case was accepted rather than split further

`dispatch(_:_:)` (the group-name switch, not `praticaGroup`/`messageGroup` from note 3) was
already at cyclomatic complexity 16 against a ceiling of 10 before this chain touched it — a
warning this codebase already carries on every group-selector switch of this shape. Adding the
`"message"` case (the `"pratica"` case's mapping changes in place, adding no branch) moves it to
17. No further split is made: the function's own doc comment already states the reason a group
lives here rather than being folded into `run`, and a ten-th branch is normal growth for a
dispatch table whose job is exactly this, not a new problem this chain introduced. Left as
measured debt growth on an existing warning, not a new violation.

### 6. Two ADR-0049 payload types moved out of `VaultPayloads.swift` into `VaultPraticheLinks.swift`

`PraticaLinkTarget`/`PraticaLinksPayload` were first declared in `VaultPayloads.swift` beside
`PraticaTimelinePayload`, in the file's existing "Pratiche" extension. That file was 396 lines
before this chain (under SwiftLint's 400-line ceiling) and 421 after — a new `file_length`
violation, confirmed against a baseline lint of the pre-chain file with the project's own
`.swiftlint.yml`. Both types are declared and almost entirely consumed by
`VaultPraticheLinks.swift` (Task 7's own new file); only `PraticaTimelinePayload.Entry.linkedNote`
still names `PraticaLinkTarget`, which needs the same module, not the same file. Moving the two
declarations there and trimming the two doc comments they left behind brings `VaultPayloads.swift`
back to exactly 400 lines, with no other behaviour change; both files re-lint clean and all three
targets (`Pergamenum`, `perg`, `pergamenum-mcp`) were rebuilt to confirm.

### 7. `PraticaCommandActions.swift` crossed `type_body_length` a second time; the fix widens the existing split rather than starting a new one

Task 4's own `PraticaCommandActions+Links.swift` already exists precisely because
`PraticaCommandActions.swift` crossed `type_body_length` once (its own header says so). What Task
4 moved out was not quite enough: `requestLink`, `handleNoteLink` and `praticaContextTags` stayed
in the primary file — reachable only from `run(_:on:)`/`run(_:on:detail:)`, which also stay there
— and `linkNote(_:toMessageAt:)` stayed too, on the stated reasoning that it was "the same
picker-to-write plumbing the primary file already hosts." Once these functions existed, the
primary struct's body measured 300 lines against a 250-line ceiling — a genuinely new warning,
confirmed absent from a baseline lint of the pre-chain file with the project's own `.swiftlint
.yml`. All four functions move into the existing `+Links.swift` file rather than a third one:
`requestLink`/`handleNoteLink`/`praticaContextTags` widen from `private` to `internal` with a
comment each, matching `reload()`'s own precedent in that file; `linkNote(_:toMessageAt:)` moves
too, since both of its call sites already lived in `+Links.swift` by that point — the "stays
there" reasoning no longer held once the split needed to go one function further.
`praticaPath(detail:)`, called by the relocated `handleNoteLink`, widens the same way. The primary
file's `type_body_length` warning is gone; its pre-existing `file_length` warning (already over
400 lines at baseline, unrelated to this chain) grows from 407 to 417, which is measured debt
growth on an existing warning, not a new one. Both files re-lint clean of any new warning; the app
target was rebuilt to confirm.

## Addendum (2026-09-23): the task side reads the relation back

The Negative consequence "a frontmatter wikilink produces no backlink" still holds for the index
and for notes. A *task* row now shows the pratiche that link it (`TaskPraticaLookup`,
`TasksView+Pratiche.swift`), computed once per `TasksView` render from each `pratica.md` through
`PraticaLinks.parse(praticaFileAt:)` and `PraticaLinkResolver.task`, and never stored: §D3, §D4
(`IndexCache.schemaVersion` stays 4) and §D5 are unchanged, and nothing in this ADR's body is
reopened. The pratica inspector also gains a link-count line above `pratica.md`'s body that
scrolls to the three sections of Task 5, which stay as they are. Plan:
`docs/plans/pratiche-links-task-side-and-inspector-summary.md`.
