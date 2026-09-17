Status: Approved (2026-09-16)

# SPEC — Task categories and the end of the Obsidian round-trip

**Topic slug:** task-categories

## Destination

A SPEC ready for `/workplan`, covering two things that ship as one chain: a category system for
tasks that exists independently of any note (a registry in the vault, a sidebar section, an
assignment gesture, an optional linked note) and the propagation of a product decision already
taken on 2026-08-22 but never written into the binding documents: Obsidian round-trip
compatibility is no longer a constraint. `/workplan` produces the ADR inventory; this SPEC fixes
what the ADR must say.

## Objectives

- Create, name, colour, order, nest and archive categories from the app, with no note involved.
- Assign a task to a category from the task itself (menu, composer, drag, editor autocomplete),
  never by hand-typing a tag.
- See categories as first-class rows in the Attività sidebar, each with its progress, in the shape
  of Todoist or Things, while every fact still lives in a markdown line or a readable JSON file in
  the vault.
- Optionally tie a category to a note, so the note's own checklist counts as the category's work.
- Stop carrying "Obsidian must see the same thing" as a constraint on every future decision, and
  say so in the documents that currently claim otherwise.

## Scope and non-goals

In scope: the category registry, its lifecycle (create, edit, reorder, reparent, archive, delete),
the sidebar section and its category view, the four assignment gestures, the linked-note key and its
inheritance rule, implicit categories for unregistered tags, read-only exposure through both
connectors, and the documentation amendment for the Obsidian scope change.

Not in scope: any new task-line syntax, any rewrite of existing task lines when a category changes,
category writes through the connectors, priorities, natural-language date parsing, infinite
recurrence, saved views in the sidebar, changes to any on-disk format (`.canvas`, embed size suffix)
that Obsidian compatibility once motivated.

## Decisions

- **The task line points at a category with the existing `#project-<slug>` tag** — no new marker,
  no new tag namespace. Every task already carrying a project tag joins the system on day one, the
  parser and the "Per progetto" grouping stay what they are, and the harness tag regex is untouched.
  Rejected: a dedicated `@cat(<slug>)` marker — a new field in the parser, a new §7.1 row, a new lint
  rule, and worth it only if a task could belong to a project *and* a category that differ, which
  nothing asked for. Rejected: a `#cat-<slug>` namespace — reopens the closed eight-prefix regex of
  SPEC §4.4 and the harness vocabulary for no gain over `project`.
- **The registry lives in the vault, as `categories.json` beside `vocabolari.json` under
  `.pergamenum/`** — a readable file that travels with iCloud, satisfies Principle 1, and is not an
  index (deleting it loses the registry, not any task). Rejected: an index note in markdown —
  hand-editable but the metadata (colour, parent, linked note) does not sit well in prose and the
  parse is fragile. Rejected: Application Support or the SQLite cache — violates Principles 1 and 3.
- **Slugs are immutable; renaming changes only the display name** — no task line is ever rewritten
  by a category operation. Rejected: rename-rewrites-the-slug through `renameTag` — coherent but
  touches N files for one sidebar gesture and forces the display name to equal the tag.
- **Two levels: category and sub-category, the child has its own slug and the parent is recorded
  only in the registry** — a task reads `#project-offerte`; the registry says `offerte` belongs to
  `vibrofer`. Reparenting is a registry edit. Slugs are unique across the whole registry, both
  levels. Rejected: a composite `#project-<parent>-<child>` tag — self-describing on the line but
  reparenting becomes a slug rename, which the previous decision forbids. Rejected: a free-depth
  tree — the line carries one tag, so the tree would live only in the registry, with no gain over
  two levels for personal use.
- **An unregistered `#project-*` tag found on a task is an implicit category** — shown in the
  sidebar with a muted style and a one-click "Registra" that promotes it. Nothing disappears at
  adoption. Rejected: registered-only with an "Altro" bucket — historical tags vanish until
  registered one by one. Rejected: auto-registration on first sight — the registry fills with typos.
- **Categories get a sidebar section of their own under the five views** — this reopens ADR-0013
  §D6's "five views, closed": the five stay five and unchanged, the section is an addition, not a
  sixth view in the sense §D6 closed (a category row is a filter over the same tasks, parametrised by
  slug, not a new place with its own semantics). Rejected: grouping-only inside existing views —
  keeps today's model, misses the point. Rejected: replacing "Per progetto" — a removal, not an
  addition, and the aggregated view still earns its place.
- **A linked note is recorded as `pergamenum-category: <slug>` in the note's frontmatter** — the
  prefixed namespace ADR-0020 and ADR-0032 already sanctioned, accepted by the frontmatter rules
  without any code change. Rejected: a bare `category` key — reopens §4.3's closed schema and the
  linter flags it. Rejected: no key, tag-in-`tags:` only — cannot tell "the category's home note"
  from "a note that mentions the category".
- **The linked note's tag-less tasks inherit the category** — derived by the index, no line
  rewritten; an explicit `#project-*` on the line always wins. Rejected: navigation only — a
  project note's checklist would not count until every row is tagged by hand.
- **Delete touches the registry only; archive hides the row and removes the category from pickers**
  — the tasks keep their tag and reappear as an implicit category (delete) or stay visible in
  Oggi/Prossimi/Tutti (archive). Rejected: delete strips the tag from every line — a batch rewrite
  for a sidebar gesture. Rejected: archive hides the tasks from the date views — a real deadline
  becomes invisible.
- **A parent row rolls up its children** — count, progress, deadline badge and the category view
  include the whole subtree, the view groups direct tasks first and then one section per child.
  Rejected: literal own-slug-only — a container parent shows empty.
- **Connectors read categories, never write them** — one read for the registry (with implicit
  categories marked), one read for a category's tasks (rolled up, grouped as the view is), both in
  the shared API layer so `perg` and `pergamenum-mcp` cannot drift. Rejected: an assignment write
  behind `--allow-write` — more surface to test, not asked for in this chain. Rejected: app-only —
  contradicts ADR-0007.
- **The Obsidian scope change is a rewritten principle, a new ADR, and a scope note on the ADRs
  whose motivation was the round-trip** — bodies of past ADRs are not rewritten; the on-disk
  formats they chose (JSON Canvas 1.0 for `.canvas`, the `|W`/`|WxH` embed suffix, 16-hex node ids)
  stay as they are. What ends is the obligation that a future change keep Obsidian able to read the
  result, and the round-trip probe as an acceptance test. Rejected: rewriting ADR bodies — history
  lost. Rejected: CLAUDE.md and SPEC only — a reader of ADR-0020 still believes the round-trip binds.

## Constraints

- **Harness conformance stays binding (Principle 5)** — wikilinks, the four-key frontmatter, the
  flat namespaced tag regex and `vocabolari.json` are harness conventions, not Obsidian ones; the
  Obsidian amendment must not weaken them. Origin: user mandate in this interview ("solo il
  round-trip").
- **No task line is rewritten by a registry operation** — create, rename, reparent, archive, delete.
  Origin: user choice, immutable slugs.
- **Note frontmatter keys outside the four harness keys carry the `pergamenum-` prefix** — origin:
  ADR-0020 §D, ADR-0032 §D6 and the frontmatter rules that implement them.
- **The five task views of SPEC §7.4 stay five** — origin: ADR-0013 §D6; the sidebar section is an
  addition, see the decision above.
- **A capability a connector exposes is implemented once in the shared API layer** — origin:
  ADR-0007 §D3, CLAUDE.md "AI connector".
- **Every write goes through the vault session's single write door, with the `expecting:` hash
  precondition where a line is replaced** — origin: ADR-0043 §D8, ADR-0046.
- **Assignment writes carry the connector guardrails only when issued by a connector** — not
  applicable in this chain since connectors do not write; noted so `/workplan` does not add them to
  the app path. Origin: ADR-0007 §D6.
- **A view uses colour only through a token** — the category colour is a *palette choice* stored in
  the registry by name, resolved to a token at render time, never a hex value in a view. Origin:
  CLAUDE.md design-system rule.
- **UI language Italian, code and files English** — origin: CLAUDE.md.

## Stack

Unchanged: Swift 6, SwiftUI, the shared-sources connector architecture. The registry type, the
index derivations and the read payloads must live where both connectors compile them (no SwiftUI
import), or the tool builds break by design.

## Data model

**Category** (registry entry): `slug` (immutable, unique across the registry, matches the tag value
grammar `[a-z0-9]+(-[a-z0-9]+)*`), `name` (display, free text), `color` (a name from a small fixed
palette, not a hex), `symbol` (an SF Symbol name from a restricted picker, optional), `description`
(one line, optional), `deadline` (a calendar date, optional), `parent` (a slug, optional, must name a
top-level category: depth is at most two), `order` (position among siblings), `archived` (bool).

**Registry**: an ordered list of categories plus a format version. Loaded with the vault, saved
atomically on every change, absent file means empty registry. A malformed file is reported and
treated as empty for the session, never silently overwritten.

**Implicit category**: a `#project-<slug>` value present on at least one task and absent from the
registry. Derived by the index, has only a slug, is never persisted.

**Task ↔ category**: the task's `project` tag, already parsed. Precedence for a task's effective
category: explicit tag on the line, else the `pergamenum-category` of the note the task lives in,
else none. A task on a `.canvas` board inherits nothing (a board has no frontmatter).

**Note ↔ category**: `pergamenum-category: <slug>` in frontmatter, one slug per note, at most one
note per category (a second note naming the same slug is a lint finding, and the category's "home"
is the first one found in vault order, deterministically).

**Rollup**: a parent's task set is its own effective tasks plus each child's; progress is
done ÷ (open + done) over that set, counting `[x]` as done and `[ ]`/`[>]` as open, `[-]` excluded.

## API / interfaces

- Registry read/write on the vault session (create, update, reorder, reparent, archive, unarchive,
  delete, promote-implicit).
- Task write: "assign category" replaces an existing `#project-*` tag on the line or appends one;
  "remove category" removes it. Both are ordinary line replacements through the write door with the
  `expecting:` precondition.
- Task command catalogue gains `assignCategory` and `removeCategory`, rendered on toolbar, menu bar
  and context menu by the existing parity mechanism (ADR-0023, ADR-0039).
- Index: effective category per task, implicit categories, per-category rolled-up task list and
  progress, the note linked to a category.
- Connector reads: `categories` (registry entries with `implicit: true|false`, archived flag, parent,
  progress) and `category-tasks <slug>` (the rolled-up list, grouped as the app view groups it).
  `perg` prints them, `pergamenum-mcp` declares them; both from the shared API.
- Lint: one advisory finding for a `pergamenum-category` naming a slug that is neither registered
  nor implicit, one for a slug linked from more than one note. Both through the existing rule engine
  and the protected `LintFinding` shape.

## UI flows

- **Sidebar**: under the five views, a "Categorie" section: top-level rows with colour dot, symbol,
  name, open count and a progress ring; children indented under a disclosure; implicit categories in
  a muted style with a "Registra" affordance; archived ones in a collapsed "Archiviate" group; a "+"
  in the section header to create. Flat recursive rows, never `DisclosureGroup` (ADR-0024's trap).
- **Category editor** (sheet or popover): name, slug (proposed from the name, editable only at
  creation), colour, symbol, description, deadline, parent. Slug collisions and depth violations
  refuse with a message; nothing is written until valid.
- **Category view**: header with name, description, deadline and rolled-up progress; then the direct
  tasks; then one group per child. Grouping/sorting/density controls as in every view, remembered
  per category.
- **Assignment**: context menu and toolbar "Assegna categoria…" opens a picker (registered,
  non-archived, grouped parent → child); a picker in the quick-capture composer; drag of a task row
  onto a category row; typing `#project-` in the editor on a task line offers the registered slugs.
- **Linked note**: from the category editor, "Collega una nota…" writes the frontmatter key; from the
  category header, "Vai alla nota"; in the note inspector, the category is shown with a way to unlink.
- **Reorder/reparent**: drag among sibling rows reorders; drag onto a top-level row reparents;
  writes the registry only.

## Edge cases

- Task carries two `#project-*` tags: the first wins, as today; the assign command replaces all of
  them with the chosen one.
- Category deleted while a task picker is open: the picker refreshes; a stale choice is refused,
  not applied.
- Linked note deleted, moved or renamed: the link is by slug in the note, so a move keeps it; a
  deletion makes the category simply unlinked, no registry change.
- `pergamenum-category` naming an implicit slug: inheritance works; the lint finding says the slug
  is unregistered, not that the key is wrong.
- Registry names a parent that no longer exists (hand-edited file): the child is shown at top level
  with a warning badge; the registry is not auto-repaired.
- Archiving a parent archives the subtree; unarchiving a child whose parent is archived unarchives
  the parent too.
- The composer's category picker and the assign command never offer archived categories; an
  archived category's tag typed by hand still resolves to it.
- Rollup and inheritance are index facts: closing the registry file or editing it by hand while the
  app runs is picked up like any other vault change (file watcher), and the index is rebuilt from
  the vault scan alone (Principle 3).

## Test seams

Existing seams only, one level each:

- **Unit — registry**: decode/encode round-trip, format version, unique slugs, parent validity,
  depth two, archive cascade, malformed file handling.
- **Unit — parser writes**: assign/replace/remove `#project-*` on a line, indentation and other
  markers preserved (the seam `TaskMarkerWriteTests` already uses).
- **Unit — index**: effective category with precedence, implicit categories, inheritance from the
  linked note, rollup and progress, board tasks inherit nothing (the seam `IndexCacheTests` and
  `TaskTests` use).
- **Unit — connector API**: the two read payloads, implicit flag, rollup (the seam the existing
  `VaultAPI` payload tests use).
- **Unit — command catalogue**: the two new commands render on every surface (`TaskCommandTests`).
- **UI — one test**: the "Categorie" section appears with a registered and an implicit row, and
  clicking a row opens the category view. Found by accessibility identifier, launched with the three
  standard flags. The sidebar drag is not UI-tested while PG-162 is open; its drop logic is covered
  at the unit seam `TaskDropTests` uses.
- **Docs**: the amendment criteria are `no-test`.

## Success criteria

- [ ] R-01 — A category can be created, renamed, recoloured, given a symbol, description and
  deadline, reordered, reparented, archived, unarchived and deleted from the app, with no note
  opened or written, and each operation changes only the registry file.
- [ ] R-02 — Slugs are unique across both levels, immutable after creation, and a parent is always a
  top-level category; a violating edit is refused before anything is written.
- [ ] R-03 — Assigning a category from context menu, toolbar, composer, sidebar drag or editor
  autocomplete writes `#project-<slug>` on the task line, replacing any existing project tag,
  preserving everything else on the line, through the write door with the hash precondition.
- [ ] R-04 — A `#project-*` value with no registry entry appears in the sidebar as an implicit
  category with a "Registra" affordance that creates the entry with that slug.
- [ ] R-05 — The sidebar section lists top-level rows with colour, symbol, name, open count and
  rolled-up progress, children under a disclosure, archived ones collapsed; clicking a row shows the
  category view with direct tasks then one group per child.
- [ ] R-06 — A note with `pergamenum-category: <slug>` is the category's home: "Vai alla nota" from
  the category, the category shown in the note inspector, and every task in that note without an
  explicit project tag counts as the category's; an explicit tag wins.
- [ ] R-07 — Deleting a category removes only the registry entry and its tasks reappear as an
  implicit category; archiving hides the row and the picker entry while the tasks stay in
  Oggi, Prossimi and Tutti.
- [ ] R-08 — Rollup progress equals done ÷ (open + done) over the subtree, cancelled excluded, and
  the parent's deadline badge and count use the same set.
- [ ] R-09 — `perg` and `pergamenum-mcp` both expose the registry read (with implicit and archived
  flags, parent and progress) and the category-tasks read, from one shared implementation; the MCP
  smoke script exercises both.
- [ ] R-10 — The lint engine reports a `pergamenum-category` naming an unknown slug and a slug
  linked from more than one note, as advisory findings through the existing `LintFinding` shape.
- [ ] R-11 — The registry type, index derivations and read payloads compile in both connector
  targets (no SwiftUI import in their files).
- [ ] R-12 — CLAUDE.md Principle 4 is rewritten so that the Obsidian round-trip is no longer a
  binding principle, keeping the on-disk formats and the harness principle as they are; SPEC §14 and
  the compatibility line in SPEC §2 are amended the same way, dated. (no-test: documentation)
- [ ] R-13 — A new ADR records the product decision of 2026-08-22, what ends (the round-trip
  obligation and the probe as acceptance), what stays (formats, harness conformance), and lists every
  ADR that receives a scope note. (no-test: documentation)
- [ ] R-14 — Every ADR whose recorded motivation was Obsidian round-trip (at least 0019, 0020, 0024)
  carries a scope note at its head pointing to the new ADR, with its body untouched. (no-test:
  documentation)
- [ ] R-15 — SPEC §7.4 gains the "Categorie" sidebar section as an amendment naming ADR-0013 §D6 and
  stating the five views are unchanged; §7.1 gains one line saying `#project-<slug>` is the category
  pointer and where the registry lives. (no-test: documentation)
- [ ] R-16 — Full unit suite green, both connector builds green, the UI suite run by hand before
  merge with the one new UI test green.

## Not yet specified

- The exact palette of category colours and the restricted symbol picker's list: a design-token
  question for the mockup step, not a behaviour question.
- Whether the category deadline should surface anywhere beyond the category header, sidebar badge
  and connector payload (for instance in Prossimi). Default for this chain: it does not.

## Out of scope

- **Category writes from the connectors** — not asked for; a later chain can add `assign-category`
  behind `--allow-write` on the same shared implementation.
- **Rewriting task lines on rename, delete or reparent** — ruled out by the immutable-slug decision.
- **A third nesting level** — the line carries one tag; two levels cover the personal-use case.
- **Changing `.canvas`, embed-size or node-id formats** now that the round-trip no longer binds —
  nothing needs to change; the amendment removes an obligation, not a format.
- **Weakening harness conventions** — Principle 5 is independent of Obsidian and stays.
- **Priorities, natural-language dates, infinite recurrence, saved views** — the other proposals from
  this conversation, each its own chain.

## Domain terms

- **Categoria**: a registry entry, or an implicit one derived from a tag. The word "progetto" stays
  in the tag (`#project-`) and in the existing "Per progetto" view and "Progetti" grouping, which are
  not renamed: the tag is the pointer, the category is the entity.
- **Nota collegata**: the one note carrying `pergamenum-category: <slug>`; the category's home, not a
  requirement for its existence.
