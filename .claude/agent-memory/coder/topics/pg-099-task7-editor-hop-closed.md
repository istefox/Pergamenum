---
name: pg-099-task7-editor-hop-closed
description: The editor→RenderedViewBlock hop is wired as of 2026-09-07 - refreshViewBlockHosts now passes queries/onOpenNote/onEditSource; the earlier "hop blocked" shard describes a state that no longer holds.
metadata:
  type: project
---

Supersedes [[pg-099-task7-editor-hop-runs-through-two-forbidden-files]], whose diagnosis was
correct and is now **spent**: `NoteTextView+ViewBlocks.swift`'s `refreshViewBlockHosts` iterates
`drawnViewBlocks` as `(opening, drawn)` pairs and passes `parent.queries`, `parent.notePath`,
`parent.vaultRoot`, `parent.thumbnails`, `onOpenNote: parent.onFollowLink` and a caret-placing
`onEditSource` into `ViewBlockHostStore.rootView(...)`, which gained the last two as defaulted
parameters and forwards all of them. Verified 2026-09-07 with a full build plus the whole unit
suite (2339 tests, 74 suites, green).

**Why it is worth a note rather than being left to the code:** the old shard says the editor
"still never passes `queries`", and a dispatch reading it as current would re-diagnose a gap that
is closed, or worse, re-wire it. The property that stays true is the *shape*, not the gap:
`RenderedViewBlock` has exactly two construction sites (`MarkdownBlocksView.swift`, untouched, and
`ViewBlockHostStore.rootView`), so every input a drawn fence can ever reach is decided in that one
function - and every parameter of it defaults, which is what keeps the transclusion and export
surfaces at today's rendering by construction rather than by care.

**How to apply:** anything that wants to give a drawn fence a new capability adds a defaulted
parameter to `rootView` and passes it from `refreshViewBlockHosts`, never from a second
construction site. The closures must be rebuilt on every styling pass, not captured once:
`Coordinator.parent` is a struct SwiftUI replaces per update, so a closure captured at
`makeNSView` time would keep calling an older column's `onFollowLink`.

Related: [[only-testing-selects-suite-names-not-file-names]],
[[tuist-install-before-generate-in-agent-worktrees]]
