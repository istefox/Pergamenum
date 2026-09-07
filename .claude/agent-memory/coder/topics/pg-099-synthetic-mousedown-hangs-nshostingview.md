---
name: pg-099-synthetic-mousedown-hangs-nshostingview
description: A synthetic mouseDown dispatched straight to a mounted NSHostingView hangs the test process here; SwiftUI-in-attachment interaction has to be hand-checked, never unit-tested.
metadata:
  type: project
---

`hosting.mouseDown(with: <synthetic NSEvent>)` sent directly to a mounted `NSHostingView` never
returns in this sandboxed agent environment - not slow, hung, confirmed twice under a 180 s bound
by step-by-step bisection. Everything around it is fast: building the hosting view, the
attachment, the text storage, the text view and the window, ordering the window front,
`makeFirstResponder`, `ensureLayout`, mounting the view through `loadView()` and a 0.1 s `RunLoop`
pump together took 0.12 s. Same class of hazard as `NSView.beginDraggingSession`, which is
documented to block until the drag ends.

**Why:** measured on 2026-09-06/07 by the PG-099 Task 3 probe
(`Tests/ViewBlockAttachmentProbeTests.swift`, deleted by Task 4 as the plan instructs - the text
survives in commit `1569199`). SwiftUI's own event-tracking machinery inside
`NSHostingView.mouseDown(with:)` appears to wait synchronously for a following event through a
real event queue, which a directly-dispatched synthetic event never delivers.

**How to apply:** never assert on a click, a drag or first-responder movement *through* a click
inside an `NSTextAttachmentViewProvider`-hosted SwiftUI view from a unit test - the whole suite
hangs, and `.claude/test-cmd` runs at the end of every turn. Assert the static preconditions
instead (the view mounted, its frame equals what `attachmentBounds` returned, a hit-test at the
interactive point resolves to a descendant of the host and not to the enclosing
`CompletingTextView`) and send the dynamic half to a hand check, which is what ADR-0029 §D16 did
for the table grid too.

Also measured in the same run and not a defect of any one file: `xcodebuild` printing "Restarting
after unexpected exit, crash, or test timeout" a handful of times over a long full-suite run, in
unrelated suites (`EntryComposerTests`, note-tabs), recovering by itself and finishing with the
correct count. Pre-existing environment instability, not evidence against whatever was running
when it hit.
