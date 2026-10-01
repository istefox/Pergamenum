# ADR-0078: A note's frontmatter can be hidden through the fold pass, never through the file

- Status: **accepted**. Merged to `main` via PR #785 (`a9bbc88e`, 2026-10-01), for `PG-350`/#775 and
  `PG-351`/#776. Records work already shipped in PR #759 (merged 2026-10-01) plus its command
  surface.
- Date: 2026-10-01. Written against `523de3e0` on `feature/frontmatter-toggle-command`
  (`origin/main`). **Numbering note:** no remote branch and not `origin/main` carries a
  `docs/adr/0078-*` file (checked 2026-10-01). Check again immediately before the merge, per
  `docs/adr/README.md` rule 1.
- Source: the Kepler task "a convenient button near the save button to hide or show the frontmatter"
  (2026-10-01), `PG-350` (mouse-only toggle, no command) and `PG-351` (no ADR).
- **Reopens nothing.** No SPEC §14 decision, no on-disk format, no frontmatter key (SPEC §4.3's
  closed schema is untouched), no `IndexCache.schemaVersion` change, no protected interface, no
  connector JSON.
- **Extends, and changes nothing of:** ADR-0074 §D2 (the fold pass's controller, `FoldController`)
  and ADR-0023 §D1 (a command is named once and rendered on every surface). Amends none.

## Decision

**D1. Hiding is a view of the note, applied through the fold pass.** The frontmatter block's lines
join `NoteFolding.Layout.hiddenLineOffsets`, the set a folded section already uses
(`NoteFolding.hiddenFrontmatter(in:)`, `FoldController.apply(hidesFrontmatter:)`). The text storage
is never edited, so nothing reaches the file and nothing needs saving.

**D2. The state is per tab and transient.** `NoteTab.hidesFrontmatter`, like `foldedEntries`: it is
not persisted, and `showing(_:)` builds a fresh tab, so a tab showing another note starts with the
block visible. A caret inside the block when it is hidden moves to the first visible line after it
(`rescueCaret(in:from:frontmatter:)`).

**D3. One definition of the block's extent.** `NoteFrontmatter` (`Sources/Core/Markdown/`) owns it
(opening `---` on line 1, closing `---` found with `LineBreak.isTerminator`, so CRLF-safe).
`MarkdownStyler` reads it from there instead of its own private copy; the toolbar button's
visibility (`exists(in:)`) and the fold pass cannot disagree with the styler.

**D4. `isFolding` is not enough to know the layout is idle.** `EditorDecorationDelegate.isFolding`
reads folded headings only, so with just the frontmatter hidden the early guard in `FoldController
.apply` returned before recomputing, and showing the block again never reverted. The guard also
reads `lastFoldLayout.hiddenLineOffsets`. Found by `HiddenFrontmatterPass`, not by hand.

**D5. One command, two surfaces (PG-350).** `ShortcutCommand.toggleFrontmatter`, appended at the end
of the enum because raw values key the overrides file (ADR-0005 §D8), section `.view`, default
`Cmd+Opt+Y`: no other binding on `y` in the catalogue or `Sources/`, and no
`com.apple.symbolichotkeys` entry on key code 16 on this machine (2026-10-01). It is remappable in
Impostazioni. `CommandActions.run` calls `VaultController.toggleFrontmatter()`; `canRun` is true only
when the open note has a frontmatter block. The Vista menu entry flips between «Nascondi il
frontmatter» and «Mostra il frontmatter», the tab bar's eye button calls `run` too, so the two are
one command and cannot diverge.

## Evaluation

Valid and low risk: the toggle is view state only, and the fold pass already carried every hazard
(caret rescue, relayout). The value is real for notes whose frontmatter is long (`pergamenum-*`
keys, Pratiche and Contenitore notes). Not done, on purpose: persisting the choice (it would be a
frontmatter key or a sidecar for a pure view preference), a slash-menu entry, and applying it to
Workspace cards (no frontmatter there).

## Verification

`HiddenFrontmatterTests` (extent, pass, tab state), `CommandActionTests` (`canRun`, `run`),
`ShortcutTests` (binding and section; the generic collision walks cover the rest).
