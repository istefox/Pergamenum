# Pergamenum — final report and roadmap (step 4 of 4)

Date: 2026-10-31 · Baseline: `main` @ `54cf47e7`, plus PR #1036
(`feat/pg-427-pg-428-underscore-concealment-daily-transclusions`, open, owned by its own lane) ·
Inputs:

- step 1, code, dead code, security: `2026-10-30-pergamenum-audit.md` (all findings in its
  Appendix A), `2026-10-30-pergamenum-surface-inventory.md`, `2026-10-30-pergamenum-audit-periphery-delta.txt`;
- step 2, workflows: `2026-10-31-pergamenum-workflow-audit.md` (W-01…W-16, contract C-01…C-10);
- step 3, GUI and colour: `2026-10-31-pergamenum-gui-audit.md` (token table §3, review §4,
  components §5), preview `2026-10-31-pergamenum-palette-preview.html`.

Nothing in the repository was changed by any of the four steps. This file adds a schedule; it
does not replace `ROADMAP.md` (chains 1–16) or `TODO.md`. Every step below says whether it is
new work or folds into an open ledger entry, so the two documents do not compete.

---

## Part 1 — Report

### 1.1 Numbers across the three audits

| Step | P1 | P2 | P3 | P4 | Notes |
|---|---|---|---|---|---|
| 1 Code | 5 findings, **4 distinct defects** | 27 findings, 19 distinct | 227 | 122 | 23 reviewers, every file read; Periphery + SwiftLint |
| 2 Workflows | 0 | 2 | 11 | 3 | KLM counts on 12 core tasks |
| 3 GUI | 1 | 2 | 2 | 0 | Nielsen 31/40; 104 colour pairs per theme |

Overlaps, counted once in the roadmap: the step 3 P1 (tertiary text contrast) is step 1's
"Contrast" section; step 3's P2 "no component layer" is the open `PG-262` (chain 9); step 3's
consistency score (heuristic 4 = 2/4) is step 2's W-02…W-06.

### 1.2 What matters most, in one paragraph each

**Security.** One real exposure reachable from outside the app: an email attachment name like
`../../../../.ssh/id_ed25519` makes the Pratiche sync copy an arbitrary local file into the vault,
which may sync to iCloud and is served to a model by `pergamenum-mcp` (SEC-01 = S05-01 = S11-01,
first seen in the 2026-09-11 audit, never given an id). Below it, a cluster of local-access
weaknesses around the vault boundary: symlinks are not resolved (S03-01 = SEC-07), the import name
skips `VaultBoundary` (S01-02), the drop folder comes from the vault's own `settings.json` (SEC-05),
«Apri» launches Contenitore files without a type gate or quarantine (S13-01). Confirmed sound:
offline principle (network only in Sparkle and the loopback Plaud client), SQL bound, release
refusals, no `import SwiftUI` in shared sources.

**Data loss.** Three shapes: a `settings.json` that fails to decode is silently replaced, minting a
new vault id and orphaning index, journal and history (S02-01 = SEC-03; same shape in `plaud.json`,
S12-01); leaving a board drops a conflict its own flush creates (S10-workspace-01, regression of
PG-230); MCP tool calls share `dryRun` and the journal across concurrent calls (S06-01).

**The person's machine.** The unit suite, run by the Stop hook at every turn, has left
**1,122,524** `pergamenum.tests.*.plist` files in `~/Library/Preferences`, puts notes in the real
Finder Trash at nine sites (two then delete from `~/.Trash` by a guessed name), and leaves
~1,700 temp vault folders. Every turn adds more, so this is the first code to change.

**Dead code.** 156 production symbols are kept alive only by tests (Periphery delta); the
DesignGallery (38 files, 8,534 lines) ships in Release by ADR-0051 §D6, a decision to revisit;
four regressions of the closed `PG-266`.

**Workflows.** The long flows are already short (capture is 3 actions, scheduling has a learnable
key ladder). Time is lost to recall: the same verb has two names (W-03, W-04, W-08), the same
pair of conflict buttons has two orders (W-02), the create button sits in four different corners
(W-05), pane keys do not follow the sidebar (W-09), and two defaults may steal text-editing keys
from the editor (W-01 Cmd+Left/Right, W-10 Cmd+E; to be confirmed by hand). The contract
C-01…C-10 turns "buttons always in the same place" into ten checkable rules.

**GUI and colour.** The neutrals and the cinnamon accent are already a coherent soft-autumn
palette; the off-season part is the semantic layer (GitHub-blue categories, Material reds, a cool
blue family, a pure white ground). The proposal keeps neutrals and accents exact, brings every
semantic colour into the season under one chroma ceiling, and takes text pairs under the WCAG
floor from 22 to 0 (light) and 12 to 0 (dark). Category separation drops slightly for normal
vision and improves under deuteranopia; categories always carry a name.

### 1.3 Open questions for Stefano (decisions, not defects)

| # | Question | Options | Recommendation |
|---|---|---|---|
| D-1 | W-07: one triage pane for notes and documents, or two names? | (a) one «Da classificare» pane with a kind filter; (b) «Note da classificare» and «Documenti da classificare» | (b) first, it is a rename; (a) only if the two queues are used together daily |
| D-2 | W-12: do notes keep explicit save while boards and Diario autosave? | (a) keep, say it in the indicator; (b) autosave notes too | (a): ADR-0073's quit review already makes explicit save safe; one indicator, one help text |
| D-3 | W-09: renumber the pane key defaults to follow the sidebar? | (a) renumber; (b) keep | (a) only after reading how `ShortcutStore` resolves an override against a changed default |
| D-4 | DesignGallery in Release (ADR-0051 §D6) | (a) keep; (b) `#if DEBUG` | (b): 8.5k lines and the only reason several seams survive in Release |
| D-5 | Cleanup of the 1.1M plists, the Trash entries and the temp vaults | delete / move / leave | only after R-01 lands, or they refill; a destructive operation, Stefano's call |
| D-6 | Palette: accept the proposed §3 tokens after the hand check? | accept / adjust / reject | accept, then adjust individual tokens from the hand check |

---

## Part 2 — Roadmap

### 2.1 How to use it

- **One step = one PR** on a branch `fix/…`, `feature/…`, `refactor/…`, `chore/…` or `docs/…`,
  merged through `/ship`. Nothing is committed directly to `main`.
- **Ledger first.** No step starts through `/build` without a `PG-nnn` id. Step R-00d registers
  them; this file uses `R-nn` only as a schedule key.
- **Path by size.** Steps marked *ADR* go `/spec` → `/workplan` → `/build` → `/ship`, with
  `/workplan` and `/build` in separate sessions. Steps without an ADR go straight to
  `/build <PG ids>` after `/project-tasks` has registered them.
- **Merge gate** is the unit suite plus the in-process tests. A feature adds at most two or three
  GUI tests, each justified in its ADR; `scripts/uitests.sh --affected` runs at merge, a full run
  only before a release.
- **Parallel work** (∥) only where files are disjoint, and never on a lane another session owns
  (`.claude/context.md`). Editor-touching steps wait for the open editor-performance work
  (`PG-401` P1, `PG-402` P2) and are marked so.
- **Reopening a decision.** A step that reopens an ADR or a SPEC §14 decision names it and the
  reason; none of the steps below changes the binding principles, the frontmatter schema or the
  tag grammar, and none adds a network call.
- Sizes as in `ROADMAP.md`: S ≤ 1 day, M 2–4 days, L ≥ 1 week.

Each step lists: **Scope** (finding ids), **Where**, **Size**, **ADR**, **Depends on / ∥**,
**Done when**, **Ledger**.

### 2.2 Phase 0 — prepare (no production code)

**R-00a — Land PR #1036 with its one in-flight finding.**
- Scope: S03-04 (`Wikilink.emphasisMarker` does not strip `_`/`__`, which ADR-0098 now conceals
  inside a link). The other in-flight findings (S08-05, S08-06, S12-08, S12-09, S07-13, S08-10,
  S08-11, T07-tests-15, T02-10) are pre-existing shapes in touched files and go to their batches.
- Owner: the `feat/pg-427-pg-428…` lane, not a new session. Hand it the finding id.
- Done when: #1036 is merged with S03-04 fixed or ledgered; its hand checks G-hand-427/428 run.

**R-00b — One Debug build, two hand checks for the keyboard findings.**
- Scope: W-01 editor half (caret mid-line in a note, Cmd+Left: does the caret move, or does Oggi
  go back a day?), W-10 (Cmd+E in a note: Use Selection for Find, or «Nuovo evento»?).
- Done when: both answers are written into the W-01/W-10 ledger entries. R-12's fix shape depends
  on them.

**R-00c — Palette hand check as a user theme.**
- Build the two proposed JSON files from the step 3 §3 table into the vault's
  `.pergamenum/themes/` under names that are **not** `pergamenum-light.json`/`pergamenum-dark.json`
  (S07-02: a vault theme with the bundled name replaces the bundled theme for the whole process
  and leaks into the next vault). Check the editor page, Oggi week with holidays, Pratiche lanes,
  a board with every sticky, the category sidebar, in both themes.
- Done when: D-6 is answered, with the list of tokens to adjust.

**R-00d — Register everything in `TODO.md`.**
- Run `/project-tasks` on this file: one entry per R-step (or per finding where a step is a
  batch), each with the R-id and the finding ids, and fold-ins appended to the open entries named
  below rather than duplicated.
- Done when: every R-step from R-01 on has a `PG-nnn`, and SEC-01 has an id at last.

### 2.3 Phase 1 — stop the damage (P1 and the machine leak)

**R-01 — Tests stop writing into the person's machine.** *(first code PR)*
- Scope: T02-01, T02-02, T06-01, T06-02, T07-tests-01, T05-01 (temp vaults).
- Where: `Sources/Vault/RecentVaults.swift:36-38`, `OpenTabsStore.swift:47-49`,
  `PinnedTagsStore.swift:18` (`.volatile()` → in-memory store or `removePersistentDomain` on
  release); `VaultDisk.swift:437-443` (`trashItem` gets a test-host branch that moves into a
  per-vault trash folder); the two `ContenitorePaneGapTests` sites that delete from `~/.Trash`;
  `TemporaryVault` cleanup.
- Size S · ADR none (ADR-0051 test-support helpers) · ∥ R-02, R-04.
- Done when: a full unit run leaves the count of `pergamenum.tests.*.plist`, `~/.Trash` entries and
  `pergamenum-*-vault-*` temp folders unchanged (measured before and after).
- Ledger: new. Then D-5.

**R-02 — Hostile attachment names cannot leave Mail's attachment folder.**
- Scope: SEC-01 = S05-01 = S11-01 (P1), SEC-02 (`storePath` from frontmatter opened without a
  containment check), S05-10 (no length cap on the name).
- Where: `PraticaSyncEngine+Messages.swift:115-117`, `PraticaSyncEngine+Attachments.swift:37-40`,
  the `storePath` open site. One helper in `Sources/Core` (pure, shared with the connectors):
  `lastPathComponent`, refuse `..`, `/`, NUL, cap the length, then prove the resolved URL is under
  the message's attachment directory.
- Size S · ADR extends ADR-0036/ADR-0048 (a note in the existing ADR, no new one) · ∥ R-01.
- Done when: unit tests feed `../../x`, `/etc/hosts`, `a\0b`, a 4 kB name and an empty inline part,
  and each is refused or reduced, with nothing read outside the directory.
- Ledger: new (P1).

**R-03 — Never save over a JSON file the app could not read.**
- Scope: S02-01 = SEC-03 (P1, `settings.json`), S12-01 (`plaud.json`), `plaud-drafts.json`,
  vault theme files; the step 1 cross-cutting theme "silent read-then-overwrite".
- Where: `VaultSession+Identity.swift:25-62` and the Plaud ledger store. A decode failure becomes a
  named, non-modal refusal (the file is left as it is, the app runs on defaults in memory and says
  so), as ADR-0052 does for the pratiche ledger.
- Size M · ADR extends ADR-0052 · Depends on nothing · ∥ R-02.
- Done when: a `settings.json` with a stray comma opens the vault on defaults, keeps the same vault
  id directory, and the file on disk is byte-identical afterwards; same for `plaud.json`.
- Ledger: folds into `PG-261` (chain 8, vault stores without an origin marker): append these
  stores to it, or split them out as its first PR.

**R-04 — Leaving a board re-checks the conflict after its own flush.**
- Scope: S10-workspace-01 (P1, regression of PG-230).
- Where: `WorkspaceController.swift:250-263`: check `refusesToLeaveConflictedBoard()` again after
  `flushPendingSave()`, as `settleForVerb()` does (PG-288).
- Size S · ADR none (ADR-0066) · ∥ R-01…R-03.
- Done when: a hosted test makes the flush conflict, selects a folder, and finds the board still
  open in `.conflicted` with its banner.
- Ledger: new, cross-referenced to PG-230. Check against `PG-414`/`PG-415`/`PG-417` (open board
  lifecycle entries) before starting.

**R-05 — MCP tool calls are serialised, or carry their guardrails per call.**
- Scope: S06-01 (P1), S06-07 (`resources/list` answers from a stale index).
- Where: `Sources/MCPServer/VaultHost.swift:52-55`, `main.swift:47`.
- Size S · ADR extends ADR-0007 §D6 · ∥ any.
- Done when: `scripts/mcp-smoke.py <explicit binary>` runs a `dryRun: true` write and a real write
  concurrently and the journal holds exactly the real one; the dry-run file is unchanged.
- Ledger: new.

### 2.4 Phase 2 — P2 defects

**R-06 — The vault boundary resolves symlinks and covers the import name.**
- Scope: S03-01 = SEC-07, S01-02, T01-tests-01 (the refusal test must tell boundary from staleness).
- Where: `VaultBoundary.url(for:)` (resolve links, not only `standardizedFileURL`), the import
  commit's «Nome file», the Contenitore's handling of a dropped symlink.
- Size M · ADR extends ADR-0041 · Depends on R-01 (test hygiene) · ∥ R-07.
- Done when: a symlink inside the vault pointing outside is refused by the app, `perg` and MCP; a
  `../` import name is refused; the boundary test asserts the refusal kind.
- Ledger: new; `PG-261` lists "symlink" too, link the two.

**R-07 — Files that arrive from outside are gated.**
- Scope: SEC-05 (drop folder read from the vault's own `settings.json`), S13-01 («Apri» with no type
  gate and no quarantine).
- Where: Contenitore controller and settings; reuse `AttachmentQuarantine` (the PG-123/PG-155 shape).
- Size S/M · ADR extends ADR-0071 · ∥ R-06.
- Done when: a drop folder named in a synced `settings.json` outside the user's chosen set is
  refused until confirmed on this Mac; an executable type is not launched by «Apri» without a
  confirmation and carries the quarantine attribute.
- Ledger: new.

**R-08 — Parsers refuse hostile numbers and text.**
- Scope: S05-02 (email link text injects a second markdown link), S05-03 (`DrawingSVG` inf/NaN),
  S05-04 (unpadded base64 kept as raw text), SEC-06 (theme dimension `"nan"`/`"inf"`), S05-06
  (unsigned above Int64.max wraps), S05-07 (quadratic tokenizer on `<`).
- Where: `Sources/Core` email/HTML/SVG parsers, `ThemeEngine` dimension parsing.
- Size M · ADR extends ADR-0065 ("round-trips faithfully or is refused") · ∥ R-06, R-07.
- Done when: each hostile input has a unit test that expects a refusal or a clamp, never a trap.
- Ledger: new.

**R-09 — The URL scheme hands focus back on both entry points.**
- Scope: S01-04 = SEC-04 (regression of PG-132), S01-03 (a batch before the vault opens keeps only
  the last route), S01-09 (malformed URL dropped without a log line).
- Where: `.onOpenURL` path and the delegate path in `Sources/App`; one queue, one hand-back.
- Size S · ADR none (PG-132's own) · ∥ any non-App step.
- Done when: a capture via `pergamenum://` from another app leaves that app frontmost on both
  paths; three URLs before the vault opens all run in order.
- Ledger: new, regression of PG-132.

**R-10 — Writes keep the precondition they computed; sections are found by heading, not substring.**
- Scope: S02-02 (`performUndo` writes without `expecting:`), S06-03 (`TimeBlockSection`), S03-02
  (`EventNoteSection`), the Plaud transcript section, S03-03 (`rewritingQuotedRelated` anywhere in
  the note), S02-03 (two creation writes skip `expectingAbsent:`).
- Where: `VaultSession+Journal.swift`, `+TagRename.swift`, the three section helpers in `Sources/Core`.
  Reuse the ADR-0065 §D9.3 `RelatedSection` matcher.
- Size M · ADR none · ∥ R-08.
- Done when: an undo after a save that landed between check and write is refused; `### Timeline`
  and `## Timeline riunione` are left untouched by a time-block write.
- Ledger: new.

**R-11 — Reminders, clipboard and the format bar.**
- Scope: S06-02 (reminders from a previous launch never removed), S01-01 («Incolla come testo
  puro» wipes non-text clipboards), S08-01 (a format-bar press rewrites the whole note and resets
  offset-keyed state).
- Size M · ADR none · **S08-01 waits for PG-401/PG-402** (same restyle path); S06-02 and S01-01 can
  ship first as their own PR.
- Done when: a deleted task's notification is gone after relaunch; an image on the clipboard
  survives a plain paste; a callout flipped open stays open after a bold press.
- Ledger: new.

**R-12 — Keys that belong to the text system stay with it.** *(W-01, P2)*
- Scope: W-01 (Cmd+Left/Right and «Vai a oggi» always enabled and routed to Oggi), the Cmd+E half
  of W-10.
- Where: `ShortcutCommand.swift:383,385`, `CommandActions.swift:337-340`,
  `CommandActions+CanRun.swift:69`, `DiaryToolbar.swift:25-48`.
- Size S · ADR none (contract C-08 below records the rule) · Depends on R-00b.
- Done when: in a note Cmd+Left moves the caret; on Diario it moves Diario's day; on Oggi it moves
  Oggi's; a hosted test covers the routing.
- Ledger: new; `PG-343` (Cmd+Opt+K/O outside `ShortcutCommand`) is a neighbour, same PR if small.

**R-13 — One conflict banner.** *(W-02, P2)*
- Scope: W-02, contract C-09.
- Where: `ConflictBannerCopy.swift:19-25`, `DiaryView+Conflict.swift:16-18`, `BoardChrome.swift:57-61`.
  Build the `ConflictBanner` component in `Sources/DesignSystem` (the first piece of `PG-262`'s
  component layer) and use it on the three surfaces: message · «Ricarica da disco» · «Tieni la mia
  versione».
- Size S/M · ADR amends ADR-0002/ADR-0030 together with R-20 (one ADR for the component layer) ·
  ∥ R-12.
- Done when: the three surfaces render the same component with the same order; a test pins the
  copy from one source.
- Ledger: folds into `PG-262` as its first PR.

### 2.5 Phase 3 — the placement and naming contract (W-03…W-16)

**R-14 — ADR: placement and naming contract.** *(ADR)*
- Scope: contract C-01…C-10 from the workflow audit §4, plus answers to D-1, D-2, D-3.
- Path: `/spec` (short interview on D-1…D-3) → `/workplan` → ADR. Amends ADR-0023 (named once,
  rendered twice: C-10 extends it to every call site) and ADR-0002 (shortcuts).
- Size S (document) · Depends on R-00b · ∥ phase 2.
- Done when: the ADR is merged and lists, for every pane, the toolbar order and the keys.
- Ledger: new; `ROADMAP.md` chain 10 (labels) is absorbed or shipped, check before writing.

**R-15 — One verb, one name.**
- Scope: W-03 («Pianifica oggi» everywhere), W-04 (delete verbs: «Sposta nel Cestino…» with
  confirmation / «Elimina…» with confirmation / undo toast for in-app reversible; category delete
  gains a confirmation), W-08 («Aggiorna» everywhere), W-16 (day navigation labels), C-10 (titles
  from the command catalogue).
- Size M · ADR R-14 · Depends on R-14.
- Done when: every visible title of these verbs comes from `ShortcutCommand.title` or the object's
  command catalogue; a unit test enumerates the catalogue and the menu titles and finds no literal.
- Ledger: new; the category-delete-with-children no-op is already in `PG-258`, fix it here too and
  close it there.

**R-16 — Keys follow the sidebar and the system.**
- Scope: W-09 (pane keys in sidebar order, Vista ▸ «Vai a…» reordered), W-10 (Cmd+Shift+[ / ] =
  previous/next tab; «Wikilink» → Cmd+K; «Nuovo evento» → Cmd+Opt+E; «Aggiungi alle preferite» →
  Cmd+Opt+S or menu-only), C-08 (Cmd+N primary create per pane, Cmd+R refresh from outside,
  Cmd+Opt+I inspector, Cmd+Opt+K classify selection), `PG-343`.
- Size M · ADR R-14 · Depends on R-12, R-14, and on reading `ShortcutStore`'s override resolution.
- Done when: a user override file written before the change still binds the same command after it
  (test); the help sheet lists the new keys.
- Ledger: new + `PG-343`.

**R-17 — Toolbars in one order.**
- Scope: W-05 (create first in the primary group of every pane), W-06 («Ispettore» trailing, last
  item, Cmd+Opt+I, on every pane), W-11 (theme toggle removed from ten toolbars; Vista ▸ Tema and
  Impostazioni stay), W-15 (two filters in Pratiche: distinct placeholder, Cmd+F on the timeline),
  C-01…C-03.
- Where: `HistoryToolbar.swift:60-81` and the ten call sites; each pane's toolbar file.
- Size M · ADR R-14 · Depends on R-14 · ∥ R-15.
- Done when: a hosted test per pane reads the toolbar item identifiers in order and matches the
  ADR's table.
- Ledger: new; removes `PG-262`'s "themeToggleToolbarItem missing in Pratiche and Search" item
  (the toggle goes away instead).

**R-18 — One context-menu builder.**
- Scope: W-14, C-04.
- Where: `NoteRowMenu.swift`, `WorkspaceRow.swift:289-300`, `NoteTreeRow.swift:151-182`,
  `ContenitoreMenuItems.swift`, `PraticaMenuItems.swift`. A shared builder fed by the existing
  command catalogues (`PraticaCommand`, `ContenitoreCommand`, `TaskCommand`). Respect ADR-0069
  (no nested SwiftUI `.contextMenu` inside a `List` row).
- Size M · ADR R-14 · Depends on R-15.
- Done when: every row menu lists its groups in C-04 order; folder rows gain Rinomina and Elimina;
  board rows gain Apri and Mostra nel Finder.
- Ledger: new.

**R-19 — Triage and save state.**
- Scope: W-07 (per D-1; status item «Inbox» renamed; Cmd+Opt+K classifies notes too), W-12 (per
  D-2: one save indicator in the top bar, the model said in its help text).
- Size S/M · ADR R-14 · Depends on R-14.
- Done when: the Note pane shows one indicator; the two queues have distinct names or one pane.
- Ledger: new.

### 2.6 Phase 4 — design system and palette

**R-20 — Palette tokens, enforced by a test.**
- Scope: step 3 §3 table (58 tokens per theme, adjusted by R-00c), the P1 tertiary contrast, the
  chroma ceiling written into each token file's `$description` (C ≤ 0.15 light, ≤ 0.125 dark),
  `font.control.label` 9 → 10 pt, the three remaining non-token literals (S10-workspace-05 sticky
  fallback force-unwrapping a hex, `EditorDecorationDelegate.swift:750`, S09-editor-b-06 caption
  font).
- New test: a Swift Testing suite that loads both bundled theme files and asserts the pairs from
  `check.py` (4.5:1 text, 3:1 non-text, 7:1 primary text on tinted surfaces), so the WCAG floor is
  checked on every PR, not once in a scratchpad.
- Size S/M · ADR amends ADR-0030 (palette values and the chroma ceiling) · Depends on R-00c, D-6 ·
  ∥ phase 3.
- Done when: the contrast test passes on both themes; `PG-391`'s light-theme hand check is run on
  the new palette and closed.
- Ledger: new.

**R-21 — Component layer and missing tokens.** *(ADR, L)*
- Scope: `PG-262` as written (components `PaneHeader`, `EmptyState`, `SectionHeader`,
  `SelectableRowBackground`, `DisclosureChevron`; tokens `spacing.xxs` 2, `spacing.hairline`,
  `font.micro`, `radius.hairline`; three sheet widths `size.sheet.s/m/l` 420/560/720 replacing
  twelve literals; SwiftLint `custom_rules`), plus `UndoToast` (W-13, C-07) next to R-13's
  `ConflictBanner`.
- Size L · ADR amends ADR-0002/ADR-0030 (shared with R-13) · Depends on R-13, R-17.
- Done when: `PG-262`'s own done list, plus the four undo strips replaced by `UndoToast` with
  Cmd+Z reaching the same undo.
- Ledger: `PG-262`.

**R-22 — Motion tokens.**
- Scope: `PG-264` (`motion.quick` 0.15 s, `motion.standard` 0.2 s, `.themedAnimation`), with
  `DisclosureChevron` from R-21.
- Size S · Depends on R-21.
- Ledger: `PG-264`.

### 2.7 Phase 5 — P3/P4 batches (fixed, not parked)

The 227 P3 and 122 P4 findings are fixed in batches by area, one PR each, through
`/build <PG ids>` or `/build sweep`. The finding ids are in Appendix A of the step 1 audit;
the batch is its slice prefix. Cross-cutting themes go first because one change closes many.

| Step | Batch | Scope (step 1 ids) | P3 | P4 | Size | Depends on |
|---|---|---|---|---|---|---|
| R-23 | Main-actor disk work per keystroke or redraw | S03-09, S06-09, S08-02, S08-07, S08-08, S08-09, S09-editor-b-01/-02/-04, S10-workspace-06/-07, S12-09, quick switcher, month view | (in rows below) | | M | **PG-401, PG-402** |
| R-24 | UTF-16 vs Character offsets | S10-workspace-02, `CompletingTextView+Context.swift:153`, the `rangeForUserCompletion` item of `PG-258` | | | S | — |
| R-25 | Test suite clarity and speed | stale RED/stub headers (~56 files, PG-200 shape), duplicated helpers (regression of PG-190: `note(_:)` ×10, session opener ×7, `armedSession` ×4), fixed sleeps (~20, regression of PG-110), T01–T08 remaining | T01 8, T02 6, T03 12, T04 11, T05 6, T06 21, T07 16, T08 24 | 17 | L, split per T-slice | R-01 |
| R-26 | Tooling | X01-01 (`uitests.sh --affected` under-selects), X01-03 (`mcp-smoke.py` without argument runs another worktree's server), rest of X01 | 14 | 2 | S | — |
| R-27 | Dead code | Periphery delta (156 symbols kept alive only by tests), `PG-266` regressions (`PraticaSyncPlan.settings`, `VaultTopBar.theme`, 7 DesignGallery properties, `ShortcutCommand` narration), S03-10, S05-05, S06-08, S07-01 (radio nothing reads), `.claude/protected-interfaces`; D-4 | | | M | `PG-136` decisions |
| R-28 | Docs drift | S01-06, S04-08, S04-09, S06-11, S06-12, S08-05, S08-11, the stale comments in R-00a's lane | | | S | ∥ any |
| R-29 | App | S01 remaining | 5 | 6 | S | R-09 |
| R-30 | Vault | S02 remaining (S02-04…S02-11) | 9 | 2 | M | R-03, R-06 |
| R-31 | Core conventions and markdown | S03, S04 remaining | 18 | 19 | M | R-10 |
| R-32 | Email, pratiche, connectors | S05, S06, S11 remaining | 24 | 24 | M | R-02, R-05, R-08 |
| R-33 | Settings, small features | S07 remaining | 5 | 10 | S | R-20 |
| R-34 | Editor | S08, S09 remaining | 14 | 9 | M | **PG-401, PG-402** |
| R-35 | Workspace | S10 remaining (incl. S10-workspace-04, the stale-delegate guard `CardTextView` still lacks) | 11 | 5 | M | R-04 |
| R-36 | Today, Diario, tasks, recordings | S12 remaining | 12 | 8 | M | R-11 |
| R-37 | Contenitore, DesignGallery, security P3/P4 | S13, SEC remaining | 11 | 20 | M | R-07, D-4 |

Counts are per slice, before removing the ids already scheduled in R-01…R-28; a batch closes
when every id of its slice in Appendix A is fixed or recorded as "won't fix" with a reason in the
PR.

### 2.8 Phase 6 — close

**R-38 — Release check.** Full `scripts/uitests.sh`, the hand checks still owed (`PG-306`,
`PG-393`, `PG-410`, `PG-412`, `PG-414`, `PG-423`, and those this roadmap creates), then
`scripts/release.sh`. Done when a numbered build ships with the new palette and contract.

### 2.9 Order at a glance

∥ = can run in a parallel worktree with the line above (disjoint files).

1. R-00a (PR #1036's lane) · R-00b · R-00c · R-00d (ledger)
2. **R-01** tests stop leaking ∥ R-02 attachments ∥ R-04 board leave ∥ R-05 MCP
3. R-03 JSON stores (`PG-261`) · then D-5 cleanup
4. R-06 boundary ∥ R-07 Contenitore ∥ R-08 parsers ∥ R-09 URL scheme
5. R-10 writes and sections ∥ R-12 text keys ∥ R-13 conflict banner ∥ R-14 contract ADR
6. R-15 names ∥ R-17 toolbars ∥ R-20 palette · then R-16 keys, R-18 menus, R-19 triage
7. R-21 component layer (`PG-262`) · then R-22 motion (`PG-264`)
8. After `PG-401`/`PG-402`: R-11 (format bar), R-23, R-34
9. R-24…R-37 batches, two at a time on disjoint slices
10. R-38 release

| Phase | Steps | P1 | P2 | Size total (rough) |
|---|---|---|---|---|
| 0 | R-00a…d | — | — | 1–2 days, mostly hand checks |
| 1 | R-01…R-05 | 4 defects | machine leak | ≈ 1.5 weeks |
| 2 | R-06…R-13 | — | remaining step 1 P2s + W-01, W-02 | ≈ 3 weeks |
| 3 | R-14…R-19 | — | — | ≈ 2 weeks |
| 4 | R-20…R-22 | tertiary contrast | component layer | ≈ 2 weeks |
| 5 | R-23…R-37 | — | — | ≈ 4–6 weeks, interleavable |
| 6 | R-38 | — | — | 1–2 days |

---

## Appendix — finding → step map

| Finding | Step | Finding | Step |
|---|---|---|---|
| SEC-01 = S05-01 = S11-01, SEC-02 | R-02 | S01-01 | R-11 |
| S02-01 = SEC-03, S12-01 | R-03 | S01-02 | R-06 |
| S10-workspace-01 | R-04 | S01-03, S01-04 = SEC-04 | R-09 |
| S06-01 | R-05 | S02-02 | R-10 |
| T02-01, T02-02, T06-01, T06-02, T07-tests-01, T05-01 | R-01 | S03-01 = SEC-07, T01-tests-01 | R-06 |
| S03-04 | R-00a | S05-02, S05-03, S05-04, SEC-06 | R-08 |
| W-01, W-10 (Cmd+E) | R-00b, R-12 | S06-02 | R-11 |
| W-02, C-09 | R-13 | S06-03 | R-10 |
| W-03, W-04, W-08, W-16, C-10 | R-15 | S08-01 | R-11 |
| W-05, W-06, W-11, W-15, C-01…C-03 | R-17 | S13-01, SEC-05 | R-07 |
| W-07, W-12 | R-19 | step 3 P1 tertiary contrast, §3 tokens | R-20 |
| W-09, W-10, C-08 | R-16 | step 3 component notes §5, W-13, C-07 | R-21 |
| W-14, C-04 | R-18 | motion (step 3 §5) | R-22 |
