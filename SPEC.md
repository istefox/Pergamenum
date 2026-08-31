# SPEC — PG-073: editable title affordance for the Link card

**Topic slug:** pg-073-add-an-editable-title-affordance

## Objectives

SPEC §6.4 row 7 (Link tool) and §6.5 ("Card link URI") both require: *"icona per schema, titolo
editabile"* — an editable title on every Link card. This has never been implemented:
`CanvasNode.Kind.link(url: String)` carries only the URL, `NodeCard.linkCard(_:)` renders the raw
URL string as the card's primary text, and `WorkspaceController.addLink(_:at:)` creates the node
with no title of any kind. This chain closes that gap.

## Scope

In scope:
- A new `pergamenum-title` prefixed property on a `.link` `CanvasNode`, read/written the same way
  `CardTextStyle`'s `pergamenum-textColor`/`pergamenum-textAlign` and `CanvasCrop`'s
  `pergamenum-crop` already are — never a change to `Sources/Core/Canvas/JSONCanvas.swift` itself.
- A new `CardCommand` case that switches a Link card into an inline-editable title field, offered
  in both the context menu and the board's command bar (ADR-0023 §D1 parity), analogous to
  `.editText` on a `.text` card.
- `NodeCard.linkCard(_:)` rendering the title when present, falling back to the URL when absent —
  identical to today's display for every existing Link card on disk.
- Empty-title-on-commit clears the property (removed, never stored as `""`) — the non-destructive
  rule `CardTextStyle`/`CanvasCrop` already follow.

Out of scope:
- Any change to double-click behavior (still `NSWorkspace.open(URL)`, SPEC §6.4 row 7 — unchanged).
- Any change to the Link creation sheet's own fields (URL entry stays exactly as it is; a title is
  never mandatory at creation).
- Any character limit or validation on the title text (none exists elsewhere in the Workspace for
  a card-scoped text property, and none is added here).
- `.canvas` markdown or JSON Canvas schema changes beyond the one new prefixed key.

## Stack

No new dependency. Same layers as ADR-0027 (Nota/Testo unification): `Sources/Core/Canvas/` (no
change), `Sources/Features/Workspace/` (`CanvasNode.unknown`-backed property type, `CardCommand`,
`WorkspaceController`, `NodeCard`, `BoardCardMenu`).

## Architecture

**Storage — `LinkCardTitle`, a new file mirroring `CanvasCrop.swift`/`CardTextStyle.swift`
exactly.** One prefixed key, `pergamenum-title`, on `CanvasNode.unknown`. `CanvasNode.init?`
already funnels an unrecognised key into `unknown` and `rawValue` already re-emits it (the same
mechanism `CardTextStyle`'s doc comment describes), so JSON Canvas round-trip and Obsidian
compatibility (CLAUDE.md principle 4) come for free with zero change to `JSONCanvas.swift`.

```swift
enum LinkCardTitle {
    static let key = "pergamenum-title"

    static func read(from node: CanvasNode) -> String? {
        guard case .string(let value)? = node.unknown[key], !value.isEmpty else { return nil }
        return value
    }
}
```

A malformed or empty stored value reads as absent, never corrected, never removed — the same rule
`CanvasCrop.read`/`CardTextStyle.read` already follow (they document it explicitly; this type
inherits it rather than re-deciding it).

**Editing flow — a new `CardCommand.renameLink` case, sitting where `.editText` sits for `.text`
cards.** `CardCommand.available(for:isCroppable:hasCrop:)` gains: for a `.link` node, prepend
`.renameLink` to the command list (same slot `.editText`/`.open` occupy — the "opener" position).
`BoardCardMenu.run(_:on:)` gains a `.renameLink` case calling a new
`WorkspaceController.beginTitleEdit(nodeID:)`, modeled line-for-line on the existing
`beginTextEdit(nodeID:)`/`endTextEdit(commit:)` pair (`WorkspaceController.swift:524-541`): a
transient `editingTitleDraft: String` seeded from `LinkCardTitle.read(from:)` (or `""` when
absent) on begin, written through to the node's `pergamenum-title` key via `setTitle(_:forNodeID:)`
on commit — mutating the document once, on commit, never per keystroke, exactly like the existing
text-edit pair's own documented reason.

`NodeCard.linkCard(_:)` (or its caller) is threaded the node's `editingTitleDraft` binding when
`workspace.editingTitleNodeID == node.id`, rendering a `TextField` in place of the static `Text(url)`
line; otherwise unchanged. Return or click-away commits (`endTitleEdit(commit: true)`); Esc cancels
(`endTitleEdit(commit: false)`) — same as the text-card precedent.

**Empty commit → property removed, not stored empty.** `setTitle(_:forNodeID:)` removes the
`pergamenum-title` key entirely when the committed string is empty, mirroring
`setColor(_:forNodeIDs:)`'s documented "never writing a default" rule (`WorkspaceController.swift`,
`setTextColor` doc comment) — the card falls back to the URL display, identical to the never-set
case.

## Data model

One new key on `CanvasNode.unknown`, present only on `.link` nodes that have had a title set:

| Key | Type | Meaning | Absent means |
|---|---|---|---|
| `pergamenum-title` | string | User-set display title for a Link card | Card displays the raw URL (today's behavior) |

No frontmatter, no index, no schema bump — this is a Workspace/canvas-only property, same class as
`pergamenum-crop`/`pergamenum-textColor`/`pergamenum-textAlign`.

## API

No connector surface (`VaultAPI`) change — Link card titles are a Workspace-editing concern with
no note/task/connector consumer, same as crop state and text color/alignment before it.

New symbols (app-only, not in `sharedSources` — same exclusion `CardCommand.swift`'s own header
documents, "the connectors have no board-editing surface"):
- `LinkCardTitle` (new file, `Sources/Features/Workspace/LinkCardTitle.swift`)
- `CardCommand.renameLink` (new case)
- `WorkspaceController.editingTitleDraft: String`, `.editingTitleNodeID: String?`,
  `.beginTitleEdit(nodeID:)`, `.endTitleEdit(commit:)`, `.setTitle(_:forNodeID:)`

## UI flows

1. **Create a Link card** — unchanged. The existing creation sheet sets the URL only; no title
   field is added to it.
2. **View a Link card, no title set** — unchanged. Card shows the URL and its scheme caption.
3. **Rename a Link card** — new. User invokes «Rinomina» (or equivalent title) from the card's
   context menu or the board's command bar. The card's title area becomes an editable `TextField`
   seeded with the current title (or empty, if none). Typing edits a transient draft only. Return
   or clicking away commits; Esc cancels and discards the draft.
4. **View a Link card with a title set** — the title replaces the URL as the card's primary text;
   the scheme caption is unchanged.
5. **Clear a title** — user renames to an empty string and commits. The `pergamenum-title` key is
   removed; the card reverts to displaying the URL, indistinguishable from a card that never had a
   title.
6. **Double-click a Link card** — unchanged in every state above: always `NSWorkspace.open(URL)`.

## Edge cases

- **Existing `.canvas` files with Link nodes, authored before this ships**: no `pergamenum-title`
  key present → `LinkCardTitle.read` returns `nil` → URL display, byte-identical to today. No
  migration.
- **Obsidian round-trip**: Obsidian does not understand `pergamenum-title` and preserves it
  unread/unmodified, per CLAUDE.md principle 4 and the identical precedent already shipped for
  `pergamenum-crop`/`pergamenum-textColor`/`pergamenum-textAlign`.
- **Duplicate a Link card** (`CardCommand.duplicate`)**: the title travels with the copy — every
  other `unknown` key already does (`WorkspaceController+Duplicate.swift`'s documented behavior for
  `pergamenum-crop`), and this key is copied by the same undifferentiated mechanism, no special
  case needed.
- **Rename while another card is also being title-edited**: only one node id can be
  `editingTitleNodeID` at a time (mirrors `editingTextDraft`'s single-node-at-a-time model);
  beginning a new title edit while one is in flight commits or discards the prior one first,
  exactly as beginning a new `.editText` session does today.
- **Malformed stored value** (e.g. a non-string JSON value under the key, from a hand-edited
  file): reads as absent, never corrected, never removed — same rule as `CanvasCrop`/
  `CardTextStyle`.

## Success criteria

- [ ] R-01 — `LinkCardTitle.read(from:)` returns the stored `pergamenum-title` string when present
      and non-empty, `nil` when the key is absent, empty, or holds a non-string JSON value
- [ ] R-02 — A `.link` `CanvasNode` with no `pergamenum-title` key round-trips through
      `CanvasStore.save`/`.load` byte-identical to today (no key is ever written for the
      never-set case)
- [ ] R-03 — `CardCommand.available(for:isCroppable:hasCrop:)` includes a rename command for a
      `.link` node and excludes it for every other node kind
- [ ] R-04 — Invoking the rename command begins an inline title edit seeded from the node's
      current title (or empty, when unset)
- [ ] R-05 — Committing a non-empty title writes `pergamenum-title` on the node and the card
      displays the title instead of the URL
- [ ] R-06 — Committing an empty title removes the `pergamenum-title` key entirely (never writes
      `""`) and the card falls back to displaying the URL
- [ ] R-07 — Canceling an in-flight title edit (Esc) discards the draft and leaves the node's
      stored title unchanged
- [ ] R-08 — `NodeCard.linkCard(_:)` displays the stored title when present, the raw URL when
      absent, for every existing (pre-feature) Link card with no `pergamenum-title` key
- [ ] R-09 — Duplicating a Link card that has a title copies the `pergamenum-title` key to the new
      node
- [ ] R-10 — Double-click on a Link card still opens the destination via `NSWorkspace.open(URL)`
      in every title state (set, unset, mid-edit-cancelled)
- [ ] R-11 — test-cmd (`-only-testing:PergamenumTests`) builds clean and passes 100%
- [ ] R-12 — `Pergamenum`, `perg`, and `pergamenum-mcp` schemes all build clean (no new file
      needed in `sharedSources`, since this feature has no connector-facing surface)
- [ ] R-13 — Manual hand-check on a live vault confirms: entering/committing/canceling the inline
      title edit, the empty-clear fallback, and that the new `pergamenum-title` key survives an
      open/edit/save round-trip in Obsidian unmodified (no-test: requires a human driving the
      actual pointer/keyboard interaction and an external app, matching this repo's standing
      precedent that drag/resize/inline-edit gestures are hand-checked, not XCUITest'd)
