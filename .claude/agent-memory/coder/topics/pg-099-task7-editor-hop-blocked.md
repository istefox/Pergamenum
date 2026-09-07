---
name: pg-099-task7-editor-hop-runs-through-two-forbidden-files
description: The editor's only seam to RenderedViewBlock is refreshViewBlockHosts → ViewBlockHostStore.rootView, so Task 7's "wire queries/onOpenNote in the editor" cannot be done from its own budget files.
metadata:
  type: project
---

`RenderedViewBlock` has exactly two construction sites in the whole repo:
`Sources/Features/Editor/MarkdownBlocksView.swift:70` (transclusion/export, must stay untouched)
and `Sources/Features/Editor/ViewBlockHostStore.swift:95`, inside `rootView(...)`. The editor
reaches the second one only through `NoteTextView+ViewBlocks.swift`'s `refreshViewBlockHosts`,
which calls `ViewBlockHostStore.rootView(source:theme:)` and passes nothing else.

So `NoteTextView.queries` (and `onEditSource`/`onOpenNote`) cannot reach a drawn fence from
Task 7's own budget (`NoteTextView.swift`, `EditorColumn+Text.swift`, `RenderedViewBlock.swift`,
`ViewRowRenderers.swift`, `ViewGridRenderers.swift`). Two edits outside it are required:
`rootView` gains `onEditSource:`/`onOpenNote:` parameters and forwards them (it already has
`queries:`, added by Task 4 in anticipation), and `refreshViewBlockHosts` iterates
`drawnViewBlocks` as `(opening, drawn)` pairs so it can build the §D10 caret-placement closure
from the opening offset, passing `parent.queries`, `parent.notePath`, `parent.vaultRoot`,
`parent.thumbnails` and `parent.onFollowLink` alongside it.

**Why:** measured 2026-09-07 on the batch-7 worktree, by grepping every `RenderedViewBlock(`
and `rootView(` call site. The batch-7 dispatch listed both files as "already correct … out of
scope", which is true of their own tasks (4 and 5) and not of this hop — the plan gives the
threading to Task 7 and Task 8 is a test-plus-hand-check task on the green-probe path, so no
later task picks it up by itself.

**How to apply:** in this chain, a dispatch that has to make a view block *run* in the editor
needs those two files in its budget. The four `openAction(for:)` click targets, the header's
edit-source control and `editing(_:)`'s `queries:` argument are all reachable without them, and
go green on their own — a suite passing is not evidence the feature is reachable on screen here.

Related: [[only-testing-selects-suite-names-not-file-names]]
