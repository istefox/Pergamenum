# Roadmap point 1 — bookkeeping hygiene

## Context

The extended audit run earlier this session found that the project's tracking files have
drifted from reality: work that actually shipped and merged to `main` is still recorded as
open or in-progress in `TODO.md`, in three `concept-to-code` manifest files, and in the
auto-memory chain-history index. This is bookkeeping-only drift — confirmed by cross-checking
`git log` and the manifests' own `topic_full_title` against `TODO.md`'s closed entries — no
functional code changes are needed, only correcting the records so future sessions (and
`vibe-status`) don't chase already-finished work.

Four items, all confirmed already merged:

- **PG-018** (ADR-0029, editor WYSIWYG unification) — merged via PR #164/#165, manifest
  `docs/manifests/2026-09-02-editor-wysiwyg-unification.manifest.yml` shows
  `current_step: "completed"`, `status: "completed"`, gate 5 approved 2026-09-03. `TODO.md`
  still lists it under "Blocked / Decisions Needed" as `- [ ]`.
- **PG-081** (breadcrumb dedup) — merged via PR #120 (`bddc299`). `TODO.md` already shows it
  `[x]` closed 2026-08-30. Only its manifest is stale:
  `docs/manifests/2026-08-30-pg-081-deduplicate-breadcrumb-rendering.manifest.yml` still says
  `current_step: "step_e4_commit"`, `status: "in_progress"`.
- **PG-073** (editable Link card title) — merged via PR #138 (`1c65688`). `TODO.md` already
  `[x]` closed 2026-08-31. Manifest
  `docs/manifests/2026-08-31-pg-073-add-an-editable-title-affordance.manifest.yml` has
  `current_step: "completed"` but `status: "in_progress"` (inconsistent pair).
- **PG-074** (interactive To Do checkbox + task indexing) — merged via PR #137 (`57a3dce`).
  `TODO.md` already `[x]` closed 2026-08-31. Manifest
  `docs/manifests/2026-08-31-pg-074-give-the-to-do-tool-an-interactiv.manifest.yml` still says
  `current_step: "step_h2_plan"`, `status: "in_progress"` — the tracked chain never advanced
  past planning because the work landed through a different/faster path, but the manifest was
  never reconciled.

`MEMORY.md`'s "Chain memory" index (`~/.claude/projects/-Users-stefer-Developer-Pergamenum/memory/MEMORY.md`)
lists `pg-081`, `pg-074` under "Active chains" and `pg-073` isn't listed there at all currently
— it should move `pg-081`/`pg-074` to "Archived chains" to match the corrected manifests, in
the same one-line format the other archived entries already use.

## Changes

1. **`TODO.md`**
   - Header (line 4): `Updated: 2026-09-02 · Open: 6 (P1: 0) · In progress: 0` →
     `Updated: 2026-09-04 · Open: 3 (P1: 0) · In progress: 0` (3 = PG-076, PG-072, PG-014).
   - PG-018 entry (line 115): flip `- [ ]` → `- [x]`, extend the trailing comment
     `<!-- src:session opened:2026-08-17 runs:2 -->` to add `closed:2026-09-03`, and append one
     closing bullet under the existing three, in the same voice/style as neighboring entries,
     stating: full scope delivered via ADR-0029 (`concept-to-code` chain, manifest
     `docs/manifests/2026-09-02-editor-wysiwyg-unification.manifest.yml`), Modifica/Lettura
     toggle removed, GFM tables now a real editable grid, all four §D16 probes confirmed by
     hand, merged PR #164/#165, unit suite 2082/2082 green. Note the one known accepted
     limitation (caret-blink after table-edge redirect, Apple FB17103305) without re-opening it.

2. **Three manifest files** — bookkeeping-only field correction, no other content touched:
   - `2026-08-30-pg-081-deduplicate-breadcrumb-rendering.manifest.yml`:
     `current_step: "step_e4_commit"` → `"completed"`; `status: "in_progress"` → `"completed"`.
   - `2026-08-31-pg-073-add-an-editable-title-affordance.manifest.yml`:
     `status: "in_progress"` → `"completed"` (`current_step` already `"completed"`).
   - `2026-08-31-pg-074-give-the-to-do-tool-an-interactiv.manifest.yml`:
     `current_step: "step_h2_plan"` → `"completed"`; `status: "in_progress"` → `"completed"`.
   - Each file's `next_action` hint line (currently "Run /skill concept-to-code ... to start
     Step 1 interview") will be updated to something like: "Chain complete retroactively —
     work shipped via PR #<n> outside the tracked chain steps. Nothing further to run."

3. **`MEMORY.md`** (auto-memory index) — move `pg-081-deduplicate-breadcrumb-rendering` and
   `pg-074-give-the-to-do-tool-an-interactiv` from the "Active chains" list to the "Archived
   chains (last 10)" list, formatted like the existing archived entries (`step=completed,
   status=completed, next: Run /skill concept-to-code <topic> to ...`). `pg-073` is not
   currently in either list in `MEMORY.md`, so no edit needed there for it.

## Out of scope for this step

- The other roadmap items (SwiftLint error-level splits, `PG-014`/`PG-076`/`PG-072`, the
  `ADR-0030 Sparkle` question, running `scripts/uitests.sh`) — untouched, tackled in later
  roadmap steps.
- `ridimensionamento-maniglie-embed-editor` and `workspace-ui-creazione-board-toolbar-e-r`,
  which `MEMORY.md` lists with `step=?, status=?` — their manifests already read
  `completed`/`completed`, so the memory index entries are also stale, but fixing the parser
  that produced the `?` (rather than just the recorded value) is a tooling concern, not a
  one-line data fix; flagged but not corrected here to keep this step to the four items
  actually re-verified against `git log`.

## Verification

- `grep -c "^- \[ \]" TODO.md` → 3 (down from 4).
- `grep "^current_step:\|^status:" <each manifest>` → all read `"completed"`.
- Visual diff of `MEMORY.md` shows `pg-081`/`pg-074` under "Archived chains", removed from
  "Active chains".
- No source code, test, or build file touched — no build/test re-run needed for this step.

**Status: done, verified.**

---

# Roadmap point 2 — clear the two SwiftLint error-level violations

## Context

`swiftlint --quiet` currently reports two `type_body_length` **errors** (not warnings — the
150-line-over-error threshold is 350, and this is the one severity level that should block a
clean lint pass): `Sources/Features/Editor/TableGridView.swift` (371 lines) and
`Sources/Features/Workspace/WorkspaceController.swift` (353 lines). Both are pure structural
debt — no behavior is wrong, the classes have just grown past the configured limit as features
landed on top of them (`TableGridView` from the recent ADR-0029 GFM-table work,
`WorkspaceController` incrementally over many chains). This repo has a standing, already-used
fix for exactly this shape of problem (`PG-055`/`PG-056`, `TODO.md`): move whole `// MARK:`
sections verbatim into new sibling `TypeName+Concern.swift` files as `extension TypeName { ... }`,
widening only the stored properties/helpers the moved code actually touches from `private` to
plain internal (file-scoped `private` can't reach across files; nothing needs public/broader
exposure). Two Explore agents read both files end-to-end and confirmed the split boundaries,
the properties each move would force open, and that no test reaches into internals by name in
a way either split would break — see their reports above in this session.

`WorkspaceController.swift` already has eight sibling extension files
(`+Crop`, `+Drawing`, `+Duplicate`, `+Gestures`, `+Import`, `+Nodes`, `+Tools`, `+Viewport`);
this just adds two more, following the exact same convention. `TableGridView.swift` has no
sibling files yet — this introduces the pattern for it, same convention.

Both files live under `Sources/Features/**`, not `Sources/Core`/`Connector`/`Vault`/`Index`, so
per `CLAUDE.md`'s AI-connector section neither is in `sharedSources` — no `Project.swift`
change and no `perg`/`pergamenum-mcp` build impact. `tuist generate` is still needed after
adding the two new files so Xcode's generated project picks them up (existing convention: never
hand-edit the `.xcodeproj`).

## Changes

1. **`Sources/Features/Editor/TableGridView.swift`** — remove three MARK sections, moved
   verbatim into two new files (kept together because Committing/Structural/Reading-back call
   into each other):
   - New **`TableGridView+Rendering.swift`**: `// MARK: Drawing what the note says` (lines
     159–378) — `update(with:theme:)`, `rebuildFields()`, `makeCell(isHeader:)`,
     `applyCellValues()`, `applyColours()`, `layoutGrid()`, `layout(label:buttons:startingAt:y:)`,
     `computedWidths()`, `width(of:weight:)`, `alignment(_:)`, `draw(_:)`.
   - New **`TableGridView+CellCommit.swift`**: `// MARK: Committing a cell` +
     `// MARK: The structural affordances` + `// MARK: Reading the grid back` (lines 380–553) —
     `NSTextFieldDelegate` glue, add/remove row/column actions, `commit(_:)`, `position(of:)`,
     `value(at:in:)`, `restoreValue(of:)`, `isEditingACell`, `restoreFocus(near:)`,
     `makeControl(...)`, `makeGroupLabel(...)`.
   - Stored properties/`Metrics` enum that both moved files need (`table`, `fields`, `widths`,
     `rowPillRect`/`columnPillRect`, `focused`, the six `NSColor` properties, the lazy label/
     button controls, `controlButtons`/`controlLabels`, `Metrics`) drop from `private` to plain
     internal in the base file — kept `private` only where nothing outside the base file still
     touches them (none, per the Explore report: the Drawing section alone already forces
     effectively all of them open).
   - Remaining in the base file: class decl, `Metrics`, stored properties, `init(frame:)`/
     `init?(coder:)`, `isFlipped`, `intrinsicContentSize`, `controlsWidth`,
     `groupWidth(labelWidth:buttonCount:)` — ~140 lines, well clear of 350.

2. **`Sources/Features/Workspace/WorkspaceController.swift`** — remove two cohesive slices of
   the oversized `// MARK: Editing` section into two new files:
   - New **`WorkspaceController+TextEditing.swift`**: `beginTextEdit`, `endTextEdit`,
     `beginTitleEdit`, `endTitleEdit`, `toggleFold` (lines 533–608). No privacy changes needed —
     every property/method these touch (`editingTextNodeID/Draft`, `editingTitleNodeID/Draft`,
     `foldedHeadings`, `croppingNodeID`, `endCrop`, `select(nodeID:adding:)`, `setText`,
     `setTitle`) is already plain internal, consistent with the existing extension files already
     reading/writing controller state from outside.
   - New **`WorkspaceController+Files.swift`**: `fileURL(for:)`, `selectedFileURLs`,
     `loadEmailHeaders(for:)`, `headerBlock(of:)`, `subfolder(for:)` (lines 619–701). One privacy
     change: `emailHeaders` drops from `private(set) var emailHeaders` to plain `var emailHeaders`
     in the base file, since `loadEmailHeaders` (its only writer) moves out.
   - Net: 353 → 269 class-body lines, comfortable margin under 350. `mutate`/`undo`/`redo`/
     `apply` and the `// MARK: Saving` section stay untouched in the base file — moving them
     isn't needed to clear the error and would force `history`/`saveTask`/`autosaveDelay` open
     for no benefit.
   - Confirmed safe against tests: `Tests/CardFoldTests.swift` and
     `Tests/WorkspaceControllerTests.swift` call `toggleFold`/`foldedHeadings`/`beginTextEdit`/
     `endTextEdit`/`beginTitleEdit`/`endTitleEdit` directly by name, but all were already
     internal — moving file location changes nothing about visibility.

3. Run `tuist generate --no-open` so the four new files are registered in the generated Xcode
   project (per `CLAUDE.md`: never hand-edit `.xcodeproj`/`.xcworkspace`).

## Verification

- `swiftlint --quiet` — zero `error:` lines (the two `type_body_length` errors gone); remaining
  `file_length`/`line_length` warnings on these two files are expected to persist or shrink,
  not a blocker for this step.
- `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' build`
  — succeeds (pure code motion, but a moved `private → internal` change is exactly the kind of
  thing that silently breaks a `swift build` if a symbol collides; must confirm clean).
- `xcodebuild ... test -only-testing:PergamenumTests` — 2082/2082 still green (no functional
  change expected, but this specific class of edit — widening `private` — is the one place a
  silent behavior change could sneak in if two same-named helpers exist in different scopes).
- Pure code motion: no new tests needed, no SPEC/ADR impact.
