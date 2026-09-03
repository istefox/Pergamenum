# Memory index

- [TextKit 2 attachment views and accessibility](textkit2-attachment-view-accessibility.md) — a hosted `NSView` is drawn but unreachable until `CompletingTextView.accessibilityChildren()` offers it; unprovable offscreen.
- [Table caret blink after a redirect](table-caret-blink-after-redirect.md) — `setSelectedRange` after `replaceAtomically` runs post the one per-edit grow/reveal pass; re-call `growToFitTheText`, not `makeFirstResponder`.
