Status: Approved (2026-09-23)

# SPEC — Show pratica links on the task side, and lift them to the top of the pratica inspector

## Destination

A SPEC handed to `/workplan`. Today a pratica can link to notes, tasks and boards (ADR-0049), and
the pratica inspector already shows read-only "NOTE COLLEGATE" / "TASK COLLEGATI" / "BOARD
COLLEGATE" sections — but only at the *bottom* of the inspector, under `pratica.md`'s body, and
only from the pratica's side. A task linked by one or more pratiche shows nothing about it. This
SPEC closes that gap: a task row shows which pratica(che) point at it, and the pratica inspector
gets a summary of its links visible without scrolling.

## Objectives

- Opening a task tells you, at a glance, which pratica(che) reference it — without opening every
  pratica to check.
- Opening a pratica tells you, without scrolling past `pratica.md`'s body, how many notes/tasks/
  boards it is linked to.
- No new way to create a link: `linkTask`/`linkNote`/`linkBoard` (ADR-0049) are unchanged. This is
  a read-only display addition on both sides.

## Scope and non-goals

In: a reverse (task → pratica) lookup and its display on the task row; a link-count summary at the
top of the pratica inspector that scrolls to the existing sections.
Out: writing a task→pratica link from the task side (a task still gets linked only by editing the
pratica's own links, per ADR-0049's one-way model); changing how notes/boards are linked; any
change to `pergamenum-dossier-links-*` frontmatter shape; a precomputed/cached reverse index in
`IndexCache` (see Decisions).

## Decisions

- **The task→pratica relation is computed at read time from the pratica side, not stored.**
  `PraticaLinks.tasks` (`noteTitle` + `^id`) is the only source of truth (ADR-0049 §D3); nothing
  new is written to any file. Rejected: a new frontmatter key or index field mirroring the link
  back onto the task's note — ADR-0049 already rejected a symmetric backlink for exactly this
  reason (ADR-0049, "A frontmatter wikilink produces no backlink"), and duplicating the same fact
  in two places is a second source of truth that can drift.
- **The reverse lookup is computed once per `TasksView` body render, not per row and not cached.**
  For every pratica in `PraticheController.pratiche`, parse its `pratica.md` for `PraticaLinks`
  (`PraticaLinks.parse(praticaFileAt:)`), resolve each `TaskReference` against the task being
  drawn via the existing `PraticaLinkResolver.task`, and pass the resulting map down to rows.
  Mirrors the stated precedent in `PratichePane+Links.swift` ("resolution happens here, per draw
  ... costs less than a cached copy that could go stale"), applied symmetrically. Rejected: a
  cached reverse index invalidated on vault reload — more moving parts than a personal vault's
  scale (tens of pratiche) justifies, and a second cache is a second place to go stale.
- **A task linked by more than one pratica shows one badge per pratica, side by side** — same
  shape already used for multiple `#tag` chips on a row. Rejected: showing only the first with a
  "+N" counter — hides which other pratica it is without a second click, and multi-pratica links
  are rare in practice.
- **The task-side badge reuses the existing "resolved link" visual pattern** (`workspaceSegment`'s
  shape in `TasksView+Row.swift`: an icon + name as a plain-color `Button` when the pratica
  resolves uniquely, muted/disabled styling when it does not). Rejected: a new `ViewTagChip`-style
  chip — introduces a second visual language for "a task points at something" next to the one
  that already exists for boards.
- **Clicking a pratica badge on a task navigates to the Pratiche pane with that pratica selected**
  (`navigation.pane = .pratiche`, `pratiche.selection` set to it) — the same action shape used by
  the pratica inspector's own note/task/board rows to open their target. Rejected: opening
  `pratica.md` as a plain note in the editor — the pratica has exactly one editor, its own
  inspector (ADR-0036), and a plain note view would bypass it.
- **The pratica inspector gains one summary line above `pratica.md`'s body**: total counts, e.g.
  "🔗 3 note · 2 task · 1 board", clicking it scrolls the inspector's `ScrollView` down to the
  existing `praticaLinksSection`. The three detailed sections stay exactly where they are today,
  at the bottom. Rejected: moving the three sections themselves to the top — pushes `pratica.md`'s
  own content, the thing actually being read, below a block that is usually empty or small;
  rejected: a summary with no click action — loses the one useful thing a summary should do,
  which is get you to the detail.
- **The summary line is present but reads a muted "nessun collegamento" when all three counts are
  zero** (consistent with the existing per-section empty text), rather than being hidden — so its
  position stays predictable.

## Constraints

- **`pergamenum-dossier-links-*` frontmatter shape is unchanged** — origin: ADR-0049 §D2/§D4,
  reopened by nothing in this SPEC.
- **No new field on `TaskItem`** — the reverse lookup is a view-time computation, not a stored
  property, consistent with the Decisions above.
- **Files shared with `perg`/`pergamenum-mcp` stay Foundation-only** — origin: ADR-0001 §D1. The
  reverse-lookup pure function (candidate list in, resolved pratiche out) belongs in
  `Sources/Core`, same rule `PraticaLinkResolver` itself already follows; only its SwiftUI callers
  live in `Sources/Features`.
- **Never disable or delete a test to make a suite pass** — origin: global rules.
- **Work happens on a feature branch, `/plan` and `/build` in separate sessions** — origin: user
  mandate (CLAUDE.md workflow invariants).

## Stack

Swift 6, SwiftUI, existing `PraticheController` / `PraticaLinks` / `PraticaLinkResolver` types.
No new dependency.

## Data model

No schema change. New pure type: a per-task resolution result, e.g.

```
struct TaskPraticaLink {
    let praticaID: String      // PraticaListItem.id, used to select it on click
    let praticaTitle: String
}
```

produced by a new pure function (exact name/home decided in `/workplan`), shape:

```
func praticheLinking(taskSourcePath: String, taskLocalID: Int?, pratiche: [(id: String, links: PraticaLinks)]) -> [TaskPraticaLink]
```

mirroring `IndexSnapshot.tasks(linkingTo:)`'s existing linear-scan style (`Sources/Index/IndexSnapshot.swift:184-189`).

## API / interfaces

- `TasksView+Row.swift`: `details(_:)` gains a segment listing `TaskPraticaLink`s, styled like
  `workspaceSegment(_:)` (icon `"folder.badge.person.crop"`-style TBD in `/workplan`, exact SF
  Symbol chosen there), one `Button` per resolved pratica.
- `PratichePane+Inspector.swift`: `inspector` gains a summary view above the body, reusing
  `theme.spacing`/`themedText` tokens already used throughout `PratichePane+Links.swift`.
- No change to `PraticaLinksWriter`, `PraticaCommand`, `PraticaLinkPicker`, `VaultPraticheLinks`,
  or the MCP connector — this SPEC touches display only.

## Edge cases

- A pratica's `TaskReference` whose note title is ambiguous or missing: the badge is not shown at
  all on the task row (rather than shown as broken) — the task can't be identified as "this one"
  with confidence, unlike the pratica-side rows which always know their own reference and can mark
  it broken. A `^id` that resolves to a *different* task in the same note is excluded, not shown.
- A task with zero linking pratiche: no badge, no empty-state text (consistent with how the
  `workspaceSegment` badge is simply absent for an unassigned task today).
- A pratica with all three counts at zero: summary line shows muted "nessun collegamento", still
  present, no click action (nothing to scroll to that isn't already visible).
- Two or more pratiche linking the same task: one badge per pratica, order follows
  `PraticheController.pratiche`'s existing display order.
- A pratica renamed/moved: `PraticaListItem.id` used by the click-to-navigate action is read fresh
  on every `TasksView` render (per the no-cache decision above), so it can't point at a stale path.

## Test seams

Existing over new, highest possible:
1. The new pure reverse-lookup function: a Swift Testing unit test, same pattern as
   `Tests/PraticaLinksTests.swift` (`@Suite`/`@Test`/`#expect`, no mocks) — candidate pratiche and
   a task identity in, `[TaskPraticaLink]` out.
2. No new GUI test: this is a read-only display of data already covered by ADR-0049's write-path
   and resolver tests; the visual result is checked by Stefano manually, per the project's
   "milestone verified by hand" convention. (no-test: visual-only addition, no new interaction to
   automate — a click that navigates reuses `navigation.pane`/`pratiche.selection`, both already
   covered by existing pratica-link-row tests.)

## Success criteria

- [ ] R-01 — A task row shows one badge per pratica whose `PraticaLinks.tasks` resolves uniquely
  to that task (matching `sourcePath` + `^id`), styled like the existing board-link badge, and
  shows none when no pratica links to it.
- [ ] R-02 — Clicking a task's pratica badge navigates to the Pratiche pane with that pratica
  selected.
- [ ] R-03 — The reverse lookup is computed once per `TasksView` render (not per row, not cached
  in `@State` or in `PraticheController`), reusing `PraticaLinks.parse` and
  `PraticaLinkResolver.task`.
- [ ] R-04 — The pratica inspector shows a link-count summary line above `pratica.md`'s body,
  reading total notes/tasks/boards linked, or a muted "nessun collegamento" when all three are
  zero.
- [ ] R-05 — Clicking the summary line (when non-empty) scrolls the inspector to the existing
  `praticaLinksSection` at the bottom; the three detailed sections and their content, order and
  accessibility identifiers are unchanged.
- [ ] R-06 — A `TaskReference` that is ambiguous or missing produces no badge on any task row
  (never a "broken link" badge on the task side).
- [ ] R-07 — The new reverse-lookup function has a passing Swift Testing unit suite covering: one
  matching pratica, two matching pratiche (order preserved), zero matches, an ambiguous note
  title, a `^id` that exists in the note but for a different task.
- [ ] R-08 — No `pergamenum-dossier-links-*` frontmatter shape, `PraticaLinks`, `PraticaLinkResolver`
  signature, or write path (`PraticaLinksWriter`, `PraticaCommand`, `PraticaLinkPicker`) changes.
  (no-test: negative/absence criterion, checked by diff review.)

## Not yet specified

- The exact SF Symbol for the task-row pratica badge — chosen in `/workplan` or `/build`,
  consistent with the existing icon set (`folder`/`tray.full`-family, not `checklist` or
  `doc.text` which are already claimed by task/note badges elsewhere).
- Exact wording/format of the inspector's summary line (e.g. whether zero-count categories are
  omitted from a non-empty summary, "3 note · 1 board" vs "3 note · 0 task · 1 board") — a small
  copy decision, resolved in `/build` against the same tone as the existing "NOTE COLLEGATE" /
  empty-state strings.

## Out of scope

- **Linking a task to a pratica from the task side** (a reverse write path): ADR-0049's one-way
  model is unchanged by this SPEC; a task is still linked only by editing the pratica.
- **A precomputed/cached reverse index** in `IndexCache` or `PraticheController`: ruled out in
  Decisions as disproportionate at this vault's scale.
- **Editing or removing a link from the task row or the inspector summary**: both stay read-only
  entry points into the existing pratica-side editing flow (`PraticaCommand`), unchanged.
- **Any change to the per-message note relation** (`pergamenum-mail-note`, ADR-0049): unaffected.

## Domain terms

- **Reverse lookup / backlink display:** showing, on a task, which pratiche point at it — computed
  from the pratiche's own stored links, not a second stored fact. Distinct from a true backlink
  index (rejected by ADR-0049 and not reopened here).
