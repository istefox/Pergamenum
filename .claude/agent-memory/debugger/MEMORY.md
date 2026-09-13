# Memory index

- [TextKit 2 attachment views and accessibility](textkit2-attachment-view-accessibility.md) — a hosted `NSView` is drawn but unreachable until `CompletingTextView.accessibilityChildren()` offers it; unprovable offscreen.
- [Table caret blink after a redirect](table-caret-blink-after-redirect.md) — `setSelectedRange` after `replaceAtomically` runs post the one per-edit grow/reveal pass; re-call `growToFitTheText`, not `makeFirstResponder`.
- [FSEvents context must own its callback context](fsevents-context-must-own-its-callback-context.md) — teardown returns in 0.0ms without draining; `passUnretained(self)` is a use-after-free.
- [Crash registers over homemade race probes](crash-report-registers-over-probes.md) — resolve `.ips` line numbers against the build live at that timestamp; global-counter race probes lie both ways.
