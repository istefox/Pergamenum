# SPEC — Pergamenum view query builder

**Topic slug:** pergamenum-view-query-builder

## Objective

A `pergamenum-view` fence (ADR-0009) is hand-written YAML-shaped text: seven keys, a
closed field list, a small boolean `where` grammar. ADR-0033 restored live, interactive
rendering for a closed fence in the main note editor, plus an error card naming the line
when the fence fails to parse — but composing or editing the fence body is still typing
raw text against a grammar with no on-screen reference. This feature adds a visual query
builder, reachable from the fence itself, that assembles a `pergamenum-view` block
through structured controls instead of hand-typed syntax, for both a broken fence
(fix-it) and a working one (edit).

## Scope

**In scope:**
- A SwiftUI sheet presenting all seven `ViewBlock` keys (`from`, `where`, `sort`, `group`,
  `render`, `columns`, `limit`) as structured controls, for a fence in the main note
  editor.
- One entry-point button, present on both states of the fence's rendered chrome: the live
  attachment (ADR-0033/PG-099, a closed and valid fence) and the error card (a closed
  fence that fails `ViewBlock.parse`).
- A new "insert view" command (toolbar/context-menu/`CommandActions`, ADR-0023 pattern)
  that inserts a minimal valid stub (` ```pergamenum-view` / `render: table` / ` ``` `) at
  the caret and opens the builder on it immediately.
- Live validation and a live match count against the vault (debounced, via
  `ViewEvaluator`) as the draft changes.
- A single atomic rewrite of the fence's source range on "Fatto" (one undo step), no write
  to the note before that.

**Out of scope:**
- Workspace `.text` cards (ADR-0029's card exclusion is not reopened).
- `perg`/`pergamenum-mcp` — no CLI/MCP scaffold command. `Sources/Core`/`Sources/Connector`
  gain no new capability; this is UI over the existing `ViewBlock`/`ViewFilter`/
  `ViewEvaluator` machinery.
- A visual editor for the full `where` boolean tree (`or`, `not`, parentheses, arbitrary
  nesting) — see the `where` grammar section below.
- Saved/named views, view templates, or any persistence beyond the fence's own text
  (unchanged from ADR-0009: "no view is ever saved or cached").
- Non-board renderers gaining drag/write behavior — the builder only composes the block;
  ADR-0009's board-is-the-only-writable-renderer rule is untouched.

## Stack

Swift 6, SwiftUI (the sheet and its controls), AppKit bridge for the one-time atomic text
rewrite (same `shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing` path
ADR-0019 and ADR-0029 already use). No new dependency.

## Architecture

### Entry points

1. **Edit an existing fence.** `ViewBlockAttachment`'s hosted chrome (the live render) and
   the error card (`RenderedViewBlock`'s `failed(_:)` state, per PG-099) both gain a
   "Modifica query" affordance. Clicking it reads the fence's current source text (parsed
   into a `ViewBlock` when it parses; the raw text plus the `ViewBlockError` when it does
   not) and opens the sheet seeded from it.
2. **Insert a new fence.** A new editor command inserts the minimal stub at the caret,
   then opens the sheet on the just-inserted (parseable) block — one gesture from an
   empty note to a configured view.

### The sheet

A draft-local `@State`/`@Observable` model, independent of the note's text until
committed. Sections, in the order `ViewBlock`'s keys are declared:

- **Ambito (`from`)** — repeatable rows, each a folder picked from the vault's existing
  folder-tree component (the same tree the Note/Workspace sidebars already draw), each row
  becoming a `path()` term; rows combine with `or`. Empty means the whole vault, matching
  the fence's own default.
- **Filtro (`where`)** — repeatable term rows, joined by `and` only (flat model — no
  visual `or`/`not`/parentheses; see the dedicated section below). Each row picks one of
  the 8 term kinds and gets a kind-specific argument control:
  - `path` — the same folder-tree picker as Ambito.
  - `tag` — the existing tag browser/picker (SPEC §4.4 namespaces), with glob support for
    a pattern like `status-*`.
  - `linksTo` / `linkedFrom` — a searchable picker over vault note titles.
  - `task` — a segmented `open`/`done` control.
  - `has` — a picker over the 18 closed `ViewField` cases.
  - `text` — a plain text field.
  - date comparison (only on `date` or `modified`) — a field picker restricted to those
    two, a comparison-symbol picker (`>`, `>=`, `<`, `<=`, `=`), and a bound control
    supporting all three `ViewDateBound` forms: a calendar date, `oggi`/`oggi-N`, and
    `inizio-settimana`.
- **Ordina (`sort`)** — repeatable field + ascending/descending rows, field restricted to
  the closed `ViewField` list.
- **Raggruppa (`group`)** — visible and enabled only when `render` is `board` (per the
  "Other sections" decision below); a tag-namespace-or-field picker, required before
  "Fatto" enables when `render == .board` (mirrors `ViewBlock.assemble`'s own rule that a
  board with no group is a parse error).
- **Rendering (`render`)** — a 5-way segmented picker (table/board/gallery/calendar/list).
- **Colonne (`columns`)** — a multi-select checklist over the 18 closed fields, showing
  the renderer's `effectiveColumns` as the pre-checked default.
- **Limite (`limit`)** — an optional positive-integer field/stepper.

Live match count: on every draft change (debounced), re-run `ViewEvaluator` against the
assembled (or best-effort partial) block and display "N note corrispondono" — catches a
filter matching zero notes before it is committed, without rendering a full result table
inside the sheet.

"Fatto" is disabled, with an inline one-line reason next to it, whenever the current draft
would not assemble — the same two checks `ViewBlock.assemble` already makes (board
renderer with no group; a `where` that does not parse) computed live in the sheet, so an
invalid draft can never reach the note text. "Annulla" always closes immediately with no
confirmation — the draft never touched the note text, so there is nothing to discard from
the file's point of view.

### `where` grammar — flat model and raw-text fallback

The visual builder only ever constructs a flat conjunction: `term and term and term ...`.
This is the shape ADR-0009's own examples and the vault's real views overwhelmingly need,
and a full nested `and`/`or`/`not`/parentheses tree editor is a materially larger UI
(recursive rows, drag-to-regroup or equivalent) for a case that is rare in practice.

- **New fence / a fence whose existing `where` is already flat AND-of-terms (or has no
  `where` at all):** the Filtro section shows term rows as above.
- **An existing fence whose `where` uses `or`, `not`, or parentheses:** the rest of the
  sheet (Ambito, Ordina, Raggruppa, Rendering, Colonne, Limite) still loads into their
  normal structured controls. Only Filtro falls back to a raw, pre-filled text field for
  the `where` value, still validated live against `ViewFilter.parse` (same inline-error
  and disabled-Fatto behavior as everywhere else in the sheet). The rest of the block is
  never silently dropped.

### Write-back

On "Fatto", assemble the draft into `pergamenum-view` fence body text: `render` and, for
each other key, the section's value — **except `columns`**, which is omitted from the
written text whenever the current selection still equals the renderer's own
`effectiveColumns` (keeps a block that never left its defaults exactly as minimal as a
hand-written one would be, and stays correct if a renderer's default set changes later).
The assembled text replaces the fence's source range in one atomic
`shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing` rewrite — one `Cmd+Z`
undoes the whole edit, matching ADR-0019's drag-resize and ADR-0029's table-cell-commit
precedent. The sheet then closes; the editor's existing fence machinery (parse, attach,
render or error-card) picks up the new text exactly as it would a hand-typed edit.

## Data model

No new persisted state. The draft lives only in the sheet's local view state for the
duration of one edit; nothing is saved, cached, or written until "Fatto", and the written
form is ordinary fence text in the note — unchanged from ADR-0009's "no view is ever saved
or cached" rule.

## UI flows

1. **Fix a broken fence.** Person types (or pastes) a `pergamenum-view` fence that fails
   to parse. The error card shows the line and reason (PG-099) plus "Modifica query". They
   click it; the sheet opens seeded with whatever of the raw text could be recovered field
   by field, or empty where it could not; they fix the problem through structured
   controls; "Fatto" enables once the draft assembles; click closes the sheet and rewrites
   the fence, which now renders live.
2. **Edit a working view.** Person clicks "Modifica query" on a live board/table/etc.
   render; the sheet opens fully seeded from the parsed `ViewBlock`; they change a field
   (e.g. add a sort key); live match count updates; "Fatto" commits the one rewrite.
3. **Insert a new view from scratch.** Person triggers the insert-view command; a minimal
   stub lands at the caret and the sheet opens on it immediately, defaulted to
   `render: table` with an empty scope (whole vault) and no filter; they build up Ambito/
   Filtro/Ordina/Colonne; "Fatto" writes the full block.
4. **Non-flat existing filter.** Person opens the builder on a fence whose `where` already
   uses `or`; every other section loads structured; Filtro shows the original `where` text
   in a validated raw field; they may edit that text directly or leave it untouched while
   changing other sections; "Fatto" still does one atomic rewrite of the whole fence.

## Edge cases

- **Board renderer with no group selected:** "Fatto" stays disabled with the inline reason
  stating a board needs a group, mirroring `ViewBlock.assemble`'s own error text.
- **Raw-text `where` fallback fails to parse after a hand-edit:** "Fatto" stays disabled
  with the `ViewFilter.parse` error's own line/reason shown inline; the rest of the sheet
  remains usable.
- **Fence deleted or its source range changes out from under the sheet** (e.g. another
  edit lands while the sheet is open): the atomic rewrite targets the fence's source range
  at commit time, not at open time; if that range no longer exists or no longer identifies
  the same fence, "Fatto" reports the write could not be applied rather than rewriting the
  wrong text or silently failing.
- **Insert-view command with the caret inside another construct** (e.g. inside an existing
  fence, a table, a list item): follows the same placement rule the app's other
  caret-insert commands already use; no new placement logic invented for this feature.
- **Vault has zero notes matching the current draft:** live match count shows "0 note
  corrispondono" — not an error, a legitimate transient state while composing.
- **`limit` left blank:** omitted from the written block, matching the field's own
  optionality.
- **Ambito (`from`) left with zero rows:** omitted from the written block (whole-vault
  scope), matching the fence's own default.

## Success criteria

- [ ] R-01 — A "Modifica query" affordance is present and functional on both the live
      view attachment (ADR-0033) and the error card (PG-099) for a `pergamenum-view`
      fence in the main note editor.
- [ ] R-02 — Clicking "Modifica query" on a parseable fence opens a sheet fully seeded
      from the fence's current `ViewBlock` (all seven keys reflected in their structured
      controls).
- [ ] R-03 — Clicking "Modifica query" on a fence that fails `ViewBlock.parse` opens the
      same sheet, seeded field-by-field from whatever of the raw text is recoverable.
- [ ] R-04 — A new insert-view editor command inserts a minimal valid stub at the caret
      and opens the builder on it in the same gesture.
- [ ] R-05 — The Ambito (`from`) section presents repeatable rows backed by the vault's
      existing folder-tree picker, each row producing one `path()` term, rows combined
      with `or`.
- [ ] R-06 — The Filtro (`where`) section presents repeatable term rows joined by `and`
      only, one row per one of the 8 term kinds, each with a kind-specific input control
      (folder picker for `path`, tag picker for `tag`, note-title picker for
      `linksTo`/`linkedFrom`, open/done toggle for `task`, field picker for `has`, text
      field for `text`, comparison-symbol + date-bound control for a date/modified
      comparison).
- [ ] R-07 — Opening the builder on an existing fence whose `where` is not expressible as
      flat AND-of-terms (contains `or`, `not`, or parentheses) still loads every other
      section structured, and falls back to a validated raw-text field for `where` alone,
      without dropping or altering any other key.
- [ ] R-08 — The Raggruppa (`group`) section is shown/enabled only when Rendering
      (`render`) is `board`.
- [ ] R-09 — The Colonne (`columns`) section is a multi-select checklist over the 18
      closed `ViewField` cases, pre-checked to the current renderer's
      `effectiveColumns` when the fence declares none.
- [ ] R-10 — The Ordina (`sort`) section presents repeatable field + ascending/descending
      rows restricted to the closed `ViewField` list.
- [ ] R-11 — A live match count against the vault (via `ViewEvaluator`) updates as the
      draft changes, debounced rather than on every keystroke.
- [ ] R-12 — "Fatto" is disabled, with an inline reason shown, whenever the current draft
      would fail `ViewBlock.assemble` (board with no group; an unparseable `where`,
      including the raw-text fallback case).
- [ ] R-13 — "Fatto" performs exactly one atomic rewrite of the fence's source range
      (`shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing`), producing one
      undo step regardless of how many fields changed in the sheet.
- [ ] R-14 — "Annulla" closes the sheet immediately with no confirmation prompt and no
      write to the note text.
- [ ] R-15 — The written fence omits the `columns:` key whenever the final selection
      equals the renderer's `effectiveColumns`, and omits `from`/`limit` when left empty,
      matching a hand-written minimal block.
- [ ] R-16 — The builder does not attach to or open from Workspace `.text` cards; only the
      main note editor gains this feature (no-test: ADR-0029's existing card exclusion is
      the mechanism that already prevents this, verified by absence rather than a new
      assertion).
- [ ] R-17 — No new capability is added to `Sources/Core`, `Sources/Connector`, `perg`, or
      `pergamenum-mcp`; the feature is UI-only over the existing `ViewBlock`/`ViewFilter`/
      `ViewEvaluator` machinery (no-test: a boundary verified by code review and the
      existing `sharedSources` build-break mechanism, not by a dedicated test).
