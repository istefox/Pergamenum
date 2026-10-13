Status: Approved (2026-10-07)

# SPEC — A conflicted Workspace board outlives the pane and the window (PG-392, #918)

## Destination

A Workspace board that holds edits the app could not save (a conflicted board) is never lost
silently: it survives a pane switch, is named by the quit question on every termination, and is
named by the vault-switch question. The chain ends with a dedicated ADR recording the lifetime
change, `PG-392` closed, and the comments that say otherwise corrected.

## Objectives

ADR-0089 closed the quit question for a board whose pane is on screen and left one hole open
(§D7): a conflicted board is lost, with no question and no problem line, when its pane leaves the
screen, because `WorkspaceController` lives in the view and goes with it. Its remedy was named
there: give the controller the vault's lifetime. This SPEC does that, and brings the vault switch
under the same rule, so the person is asked before the only copy of their edits goes.

## Scope and non-goals

In: the controller's owner and lifetime; what a pane switch does to a clean, dirty and conflicted
board; the quit question reaching a board whose pane is off screen; the vault-switch question
naming a conflicted board; moving `attach`/`detach` to where the vault opens and closes.

Out: the diary at vault switch, «Chiudi la colonna», refusing a window close, any conflict copy on
disk, per-board zoom/pan persistence, remembering the last open board.

## Decisions

- **The controller is created once, with the app's vault controller, and owned by it strongly.**
  `WorkspaceView` receives it instead of creating it. The reference the quit already reads
  (`openBoard`) becomes that owned reference. Rejected: a separate app-level holder — one window and
  one vault per app give it nothing to hold that the vault controller does not.
- **Attach and detach follow the vault, not the view.** They run when a vault opens, switches or
  closes, whether or not the Workspace pane is mounted. Today `onChange(of: vault.root)` fires only
  while the view is mounted. Rejected: keeping them in the view — it is the cause of the loss.
- **A pane leave settles by state.** Saved: the board is released, so the pane re-enters on its
  empty state exactly as today and no stale in-memory board survives (the `.canvas` files never
  reach the watcher, so a retained clean board could go stale). Pending: flushed as today, then
  judged again by its outcome. Conflicted: kept as it is, document, origin and banner. Rejected:
  keeping every board and its history — conflicts that were not real after an outside edit; and
  refusing the switch — it cannot cover a window close and revisits ADR-0054 §D5.
- **The vault switch is asked, and names the conflicted board.** The existing review gains the
  board when it is conflicted, with ADR-0089's sentences and rules: «Salva» never writes it,
  cancels the switch and reveals its banner; «Annulla» cancels; only «Non salvare» lets it go.
  Chosen by the person at the interview, against the recommendation to leave it out. Rejected: a
  conflict copy on disk — already rejected in ADR-0089.
- **The mirror of the open board path is derived, not written by the view.** The window's history
  keeps working on the same value.

## Constraints

- **ADR-0054 §D5** — nothing is written over the other writer and nothing is discarded without a
  choice; refusing to close a window over a conflict stays out. Origin: existing ADR.
- **ADR-0089** — «Salva» and «Salva tutto» never write a conflicted board; the reveal order and the
  caps are unchanged. Origin: existing ADR.
- **ADR-0066** — one reset door and every leave path settles, flushes, then resets. Origin:
  existing ADR.
- **ADR-0052's cross-vault lesson** — memory read from vault A is never saved over vault B's file.
  Origin: existing ADR.
- **A check before an `await` is a filter** (`CLAUDE.md`) — a re-entry during a flush must be
  asked again after it. Origin: working agreement.
- **The diary and «Chiudi la colonna» are unchanged.** Origin: user mandate in this interview
  (scope confirmed).
- No on-disk format, schema, frontmatter key or protected interface changes; `perg` and
  `pergamenum-mcp` build and behave unchanged. Origin: existing ADRs 0001, 0007.

## Stack

Swift 6, SwiftUI with the existing observation model. The controller stays in the app target; it
must not be imported by `Sources/Core` or `Sources/Connector`.

## Data model

No new entity. One existing object changes owner: `WorkspaceController` (board, document, origin,
save state) belongs to the vault controller for as long as a vault is open. Its save state values
(saved, pending, conflicted) decide what a pane leave keeps.

## API / interfaces

- The vault controller exposes the controller as an owned property; `openBoard` is that property.
- The vault switch builds its review with the board when it is conflicted (ADR-0089's `Board`
  item); the quit review is unchanged.
- The open-board path used by the window's history is read from the controller.
- A new release step on the controller for "leave the pane": flush, then release if and only if
  the board ended saved.

## UI flows

- Conflicted board, switch pane, come back: the same board with its conflict banner.
- Clean board, switch pane, come back: the empty Workspace state, as today.
- Quit (Cmd+Q, red button on the last window, logout) with a conflicted board on another pane: the
  ADR-0089 question names the board; a cancel reveals the Workspace pane and the banner.
- Switch vault with a conflicted board, pane mounted or not: the vault-switch question names it.

## Edge cases

- Re-entering the pane while the leave flush is still running must not release the board; the
  decision is made after the flush, from the state read then.
- A flush that is refused on leave turns the board conflicted; it is then kept, not released.
- A vault switch whose save leaves the board conflicted cancels the switch, as it already does for
  a note.
- The first launch, and a vault switch from no vault, build nothing to ask about.
- A pending route (`pergamenum://canvas`) that arrives while no pane is mounted still opens its
  board when the pane mounts.
- A conflicted board whose vault is the one being switched to is not in play: the controller
  rebinds to the new store only after the question.

## Test seams

Highest seam: the vault controller with a real controller and a temporary vault, as the existing
quit tests already build it (`QuitTestSupport`'s conflicted-board helper), plus the in-process
hosted-view tests for the pane leave. Pane re-entry is driven through the controller's leave step,
not a GUI. Quit and vault-switch questions are tested through the same injectable `ask` the
existing tests use. No GUI test: ADR-0071's bound on the GUI suite, and ADR-0089 added none.

## Success criteria

- [ ] R-01 — The workspace controller is created once, with the vault controller, and is the same
  object before and after the Workspace pane leaves and re-enters the screen.
- [ ] R-02 — A conflicted board keeps its document, origin and conflicted state across a pane
  leave and re-entry, and the pane shows its banner.
- [ ] R-03 — A pane leave with a pending board flushes it; a board that ends saved is released (the
  pane re-enters on its empty state); one that ends conflicted is kept.
- [ ] R-04 — A re-entry during the leave flush does not release the board.
- [ ] R-05 — A quit with a conflicted board while the Workspace pane is not on screen asks the
  ADR-0089 question naming the board; «Salva» and «Salva tutto» cancel and reveal the banner;
  only «Non salvare» lets it go and writes nothing.
- [ ] R-06 — A vault switch with a conflicted board, pane mounted or not, asks a question naming
  it; «Salva» cancels the switch and reveals the banner; «Annulla» cancels; only «Non salvare»
  proceeds, writing nothing to the other writer's file.
- [ ] R-07 — After a vault switch the controller is bound to the new vault's store with no board
  open and no state from the old vault; attach and detach run whether or not the pane is mounted.
- [ ] R-08 — The window's history (back and forward to a board) and a `pergamenum://canvas` route
  on a cold pane open the same boards as before.
- [ ] R-09 — The diary, «Chiudi la colonna», the 10 s and 2 s caps and every on-disk format are
  unchanged, and `perg` and `pergamenum-mcp` still build.
- [ ] R-10 — A dedicated ADR records the change and amends ADR-0089 §D7/§D8 and ADR-0066's
  attach/detach ownership; the comment at the pane's disappear handler and the "to be filed"
  residual in ADR-0089/ADR-0073 are corrected; `PG-392` is closed. (no-test: documentation and ledger obligation, nothing a test can assert)

## Not yet specified

- Whether the diary should be asked about at vault switch (it survives a switch untouched today:
  the switch never calls it). Left to its own ticket.

## Out of scope

- **Diary at vault switch** — not touched by the switch; a separate decision, not needed to stop
  the board loss.
- **Window-close refusal** — ADR-0054 §D5 puts it out; the red button already reaches the quit
  question.
- **Conflict copy on disk** — rejected in ADR-0089 (alternatives 1 and 4).
- **Remembering the last open board, per-board zoom and pan** — no such state exists today.
- **A badge or marker for a conflicted board while the pane is off screen** — the question at
  quit and switch is the only new surface; a marker is a separate UI decision.

## Domain terms

- **Conflicted board** — a Workspace board whose autosave was refused because the file moved on
  (ADR-0054); its edits exist only in memory.
- **Leave** — the Workspace pane leaving the screen (pane switch). A window close is not a leave:
  it reaches the quit question.
