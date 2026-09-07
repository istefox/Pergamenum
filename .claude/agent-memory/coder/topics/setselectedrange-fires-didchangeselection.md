---
name: setselectedrange-fires-didchangeselection
description: A programmatic `setSelectedRange` posts the selection notification synchronously in this repo's editor fixtures - unlike `textView.string =`, which fires one too but never `textDidChange`.
metadata:
  type: project
---

Measured on 2026-09-07 with a throwaway `swiftc` probe (a plain `NSTextView(usingTextLayoutManager: true)`
in an `NSWindow`, a delegate counting callbacks):

- `textView.setSelectedRange(_:)` calls the delegate's `textViewDidChangeSelection(_:)`
  **synchronously**, whether or not the view is first responder, and **again for an unchanged
  range** - two identical calls produce two callbacks.
- `textView.string = "…"` also fires one, with the caret already moved to the end of the new text.
- `textView.string = "…"` fires **no** `textDidChange` (programmatic text changes never notify).

**Why it matters here:** every caret rescue in the editor (`rescueCaret`, `tableCaretRescue`,
`viewBlockCaretRescue`) moves the selection from inside `applyStyling`, where `isStyling` is still
`true` because of its own `defer` - so anything added to `textViewDidChangeSelection` runs
re-entrantly inside a styling pass. `isStyling` is a flag and not a counter, so a second
`applyStyling` entered from there clears it on the way out and leaves the rest of the outer pass
unguarded. It also means the test fixtures in `Tests/ViewBlockCaretTests.swift` /
`Tests/TableCaretTests.swift` run the selection callback twice before their explicit
`applyStyling` call, which decides what state a "first pass" actually sees.

**How to apply:** guard any new `applyStyling`-triggering work in `textViewDidChangeSelection`
with `!isStyling`, and never reason about a fixture's first pass without counting the two
callbacks `string =` and `setSelectedRange` fire before it. Related:
[[pg-099-task6-reveal-supersedes-caret-rescue]].
