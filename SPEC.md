# SPEC — PG-089 + PG-029 + PG-065

**Topic slug:** pg-089-pg-029-pg-065-outline-drag-cursor

Three grouped P3 findings, bundled into one hybrid chain at Stefano's explicit request. They
share no code and are independent of one another; grouping is purely a scheduling convenience
(one interview, one plan, one commit) — see TODO.md for each finding's own history.

## Objectives

1. **PG-089** — during an outline-section drag (PG-019), hovering a row with no valid drop
   target shows macOS's default "+" (copy) cursor instead of a "not allowed" one. A first
   attempt (`DropDelegate.dropUpdated(info:) -> .forbidden`) fired correctly but did not change
   the system cursor, and was reverted. This chain retries with a lower-level `NSCursor` push,
   the pattern already used elsewhere in this app (`BoardHandles.swift`, `BoardCropEditor.swift`,
   `WorkspacePaneDivider.swift`, `EditorColumns.swift`) for cursor feedback outside a drag
   session — the open question is whether it also works *during* a SwiftUI `.draggable`/
   `.dropDestination` session, which none of those four precedents exercise.
2. **PG-029** — nothing on screen shows that a note draft is parked (PG-028: stepping out of the
   composer keeps title/folder/topic/template for the next `Cmd+N`). Add a badge on the
   "Nuova nota" toolbar button (`VaultBrowser.swift`) when a draft is parked.
3. **PG-065** — no wrapper type distinguishes a board-file path from a folder path;
   `WorkspaceBoardResolution.unique(String)` (`Sources/Core/Tasks/WorkspaceBoardResolver.swift`)
   is the reviewer-identified natural entry point. This chain introduces the wrapper there only
   — `WorkspaceItemKind`, `WorkspaceTree.Node.Kind`, `WorkspaceSelection` and
   `PendingWorkspaceDelete` are explicitly left untouched (scoped down from the reviewer's
   broader four-type suggestion, Stefano's choice).

## Scope

In scope:
- `Sources/Features/Editor/OutlinePane.swift` — cursor feedback during outline-section drag.
- `Sources/Vault/VaultController.swift`, `Sources/Vault/VaultController+Notes.swift` — expose
  whether a draft is parked.
- `Sources/Features/Editor/VaultBrowser.swift` — badge on the "Nuova nota" toolbar button.
- `Sources/Core/Tasks/WorkspaceBoardResolver.swift` — new `BoardPath`/`FolderPath` wrapper types,
  `WorkspaceBoardResolution` cases updated to carry `BoardPath` instead of `String`.
- Every call site of `WorkspaceBoardResolution.unique(String)`'s payload (read, not redesigned).

Out of scope:
- `WorkspaceItemKind`, `WorkspaceTree.Node.Kind`, `WorkspaceSelection`, `PendingWorkspaceDelete`
  — stay on bare `String`/existing shape (PG-065's own reviewer note: "the gap is the missing
  conversion between them, not any one type's own design" — this chain narrows to the first,
  lowest-risk introduction site only).
- A "riprendi bozza" row in the note list (considered and declined for PG-029 — badge only).
- PG-090 (folding an Outline heading doesn't hide nested children from the index) — unrelated,
  already tracked separately.

## Stack

No new dependency. Swift 6, SwiftUI + AppKit interop (`NSCursor`), matching
`Sources/Features/Workspace/BoardHandles.swift`'s existing push/pop pattern.

## Architecture

### PG-089 — cursor during outline-section drag

The existing drag mechanism (`OutlinePane.swift`, from the PG-019 chain) uses SwiftUI's
`.draggable`/`.dropDestination` (Transferable-based), not `NSDraggingSource`. The four existing
`NSCursor.push()/.pop()` precedents in this repo all live on plain `.onHover`, outside any drag
session — `.onHover` may not fire, or may fire inconsistently, once AppKit's own drag session
takes over cursor ownership, which is the likely reason the first attempt's `DropProposal
.forbidden` had no visible effect (`DropProposal` only ever offered a copy/move/forbidden
*badge* on the drag image, never full cursor replacement, and neither approach has been
confirmed to fight a live `NSDraggingSession`'s own cursor management successfully in this
SDK).

Approach: track drag-session state (`draggingEntry`, already present) plus per-row hover state,
and push `NSCursor.operationNotAllowed` when hovering a row that is not a valid drop target
while `draggingEntry != nil`, popping when the hover ends or the drag ends. If, after
implementation, manual verification shows no visible cursor change (same outcome as the first
attempt), the change is reverted cleanly and PG-089 is re-closed as attempted-and-reverted a
second time, documented in TODO.md exactly as the first attempt was — this is an accepted,
pre-agreed possible outcome, not a chain failure.

### PG-029 — parked-draft badge

`VaultController.noteDraft: NoteDraft?` (`VaultController.swift`) already holds the draft;
`isComposingNote: Bool` is true while the composer sheet/pane is shown. A draft is "parked"
exactly when `noteDraft != nil && !isComposingNote` (the existing private `parkedDraft`
computed property in `VaultController+Notes.swift` already expresses "has a non-empty title";
combine it with `!isComposingNote` to mean "and nobody's looking at it right now").

Add a public `var hasParkedDraft: Bool` to `VaultController` (or widen `parkedDraft`'s access
and combine at the call site — coder's choice, whichever matches this file's existing visibility
conventions). `VaultBrowser.swift`'s "Nuova nota" toolbar button (`Button { vault.beginNewNote()
} label: { ... }`) gets a small badge (SF Symbol overlay or `.badge()`-style dot, matching this
app's existing toolbar/badge visual language — no new design token) driven by that boolean.

Clears when the draft is picked back up (`beginNewNote()` sets `isComposingNote = true`) or
discarded (`endNewNote()`, which already nils `noteDraft`) — both already flip the boolean's
inputs, so no new clearing logic is needed beyond reading `hasParkedDraft` reactively.

### PG-065 — `BoardPath`/`FolderPath` wrapper

Two small wrapper types in `Sources/Core/Tasks/WorkspaceBoardResolver.swift` (or a new sibling
file in the same directory, coder's choice on file organization):

```swift
struct BoardPath: Hashable, Sendable { let value: String }
struct FolderPath: Hashable, Sendable { let value: String }
```

`WorkspaceBoardResolution.unique(String)` becomes `.unique(BoardPath)`. `resolve(_:in:)` and
`board(inFolder:among:)` are updated to construct/return `BoardPath`; `board(inFolder:among:)`'s
`folder` parameter becomes `FolderPath` (or stays `String` if the coder finds that call sites
overwhelmingly pass a raw string with no folder-typed origin yet — judgment call, state which
was chosen and why). Every call site reading `.unique(let path)`'s payload updates from `String`
to `.value` access, or gains a small `.value` read at the point the raw string is actually
needed (e.g. handing it to `CanvasStore`/file APIs that still take `String`).

No conversion between `BoardPath`/`FolderPath` and the four out-of-scope union types is
introduced — they keep using bare `String` until (if ever) a future chain widens the pattern,
per Stefano's explicit scope choice.

## Data model

No persisted data model changes. `BoardPath`/`FolderPath` are in-memory wrapper types only, not
serialized, not stored on disk, not part of any cache schema (`IndexCache.schemaVersion`
untouched).

## API

No connector surface (`VaultAPI`, CLI, MCP) touched by any of the three findings — all three are
UI-affordance or internal-type-safety changes with no new capability a connector would expose.

## UI flows

- **PG-089**: user drags an Outline section row; while hovering a row that is not a valid
  insertion point, the cursor shows "not allowed" instead of the default copy "+".
- **PG-029**: user types a title in the note composer, steps out without saving (draft parked);
  the "Nuova nota" toolbar button shows a small badge. Pressing `Cmd+N` (or clicking the badged
  button) reopens the composer with the draft restored and the badge clears; discarding the
  draft (Esc / explicit cancel, whichever `endNewNote()` is already wired to) also clears it.
- **PG-065**: no user-visible UI change — internal type safety only.

## Edge cases

- **PG-089**: dragging over the insertion-line drop zones themselves (valid targets) must keep
  the normal drag cursor — only rows with no `.dropDestination` underneath get the "not allowed"
  cursor. Cursor must pop cleanly if the drag ends outside the Outline pane entirely (window
  drag-out, Esc-cancel) — no permanently "stuck" forbidden cursor after the drag ends.
- **PG-029**: a draft with an empty title is never "parked" (matches existing `parkedDraft`
  threshold) — no badge for a folder-only or template-only draft with no title typed.
- **PG-065**: `WorkspaceBoardResolution.ambiguous`/`.notFound` cases carry no path payload and
  are unaffected. Every existing call site must compile against `BoardPath` instead of `String`
  — a build break at any missed call site is expected and must be fixed, not routed around with
  an implicit `String`-convertible conformance (that would defeat the type-safety purpose of the
  wrapper).

## Success criteria

- [ ] R-01 — Hovering an Outline row with no valid drop target during a section drag shows
      `NSCursor.operationNotAllowed` instead of the system default copy cursor.
- [ ] R-02 — Hovering a valid insertion-line drop zone during the same drag still shows the
      normal drag-copy cursor feedback (no regression to PG-019's existing behavior).
- [ ] R-03 — The cursor is restored to normal when the drag ends, by drop or by cancellation,
      with no stuck "not allowed" cursor afterward.
- [ ] R-04 — If manual verification shows the NSCursor approach also has no visible effect, the
      change is cleanly reverted and TODO.md documents this as a second attempted-and-reverted
      outcome for PG-089, closing this requirement as "not achieved, documented" rather than
      leaving a half-working change in the tree (no-test: manual visual judgment call on whether
      the cursor changed, not something a unit test can assert).
- [ ] R-05 — `VaultController` exposes whether a note draft is currently parked (has a
      non-empty title and the composer is not showing).
- [ ] R-06 — The "Nuova nota" toolbar button in `VaultBrowser.swift` shows a badge when a draft
      is parked, and no badge otherwise.
- [ ] R-07 — The badge disappears once the parked draft is picked back up via `Cmd+N`/the
      toolbar button, or explicitly discarded.
- [ ] R-08 — `WorkspaceBoardResolution.unique` carries a `BoardPath` wrapper instead of a bare
      `String`; `WorkspaceBoardResolver`'s functions are updated accordingly.
- [ ] R-09 — Every existing call site of `WorkspaceBoardResolution.unique`'s payload compiles
      against the new `BoardPath` type with no implicit string-convertible bypass.
- [ ] R-10 — `WorkspaceItemKind`, `WorkspaceTree.Node.Kind`, `WorkspaceSelection` and
      `PendingWorkspaceDelete` are left unmodified by this chain (no-test: a scope boundary
      confirmed by reading the diff, not an assertable runtime behavior).
- [ ] R-11 — Unit suite green (`bash .claude/test-cmd`), including new/updated tests for
      `WorkspaceBoardResolver`'s `BoardPath`-returning functions and for `VaultController`'s
      parked-draft boolean.
- [ ] R-12 — `xcodebuild build` succeeds with no new SwiftLint error-level violations.
- [ ] R-13 — Manual hand-check on a throwaway vault (Definition of Done, blocking): drag an
      Outline section and observe the cursor over an invalid row (R-01/R-02/R-03); park a draft
      by stepping out of the composer and observe the toolbar badge, then clear it via Cmd+N and
      via discard (R-06/R-07) (no-test: visual/manual confirmation, not something a unit test
      can assert).
