---
name: table-caret-blink-after-redirect
description: A programmatic setSelectedRange to a location a keystroke just created (e.g. NoteTextView+TableCaret.swift's Return redirect) can leave the model selection and first responder both correct while no caret renders, because the note's one "keep the caret on screen" call already ran against the stale pre-redirect selection.
metadata:
  type: project
---

`NoteTextView.Coordinator.textDidChange` runs `growToFitTheText(textView, revealingCaret:
true)` (`NoteTextView+Coordinator.swift`) exactly once per edit, synchronously, as part of
`replaceAtomically`'s own `didChangeText()` call. Any claimant (`NoteTextView+TableCaret.swift`,
`NoteTextView+EmbedCaret.swift`, `NoteTextView+ListEditing.swift`) that calls
`textView.setSelectedRange(_:)` *after* `replaceAtomically` returns is calling it after that one
grow/ensure-layout/scroll-to-reveal pass already ran — against the selection as it stood
*before* the claimant moved it. The model ends up right (`selectedRange()` and
`window?.firstResponder` both correct) but nothing subsequently asks TextKit 2 to lay out or
reveal the caret's real final location — a text-storage-correct insertion point with nowhere
guaranteed to draw itself.

**Evidence, PG-089-adjacent table-caret-blink bug (2026-09-03):** `firstRect(forCharacterRange:)`
for the final selection came back a fully degenerate `(0,0,0,0)` immediately after an unfixed
redirect — this project's own documented "not laid out yet" signature (CLAUDE.md working
agreement), never a legitimate zero-width caret rect (a real caret rect still carries a nonzero
origin/height, confirmed by two control probes in the same harness). `firstResponder` was
independently confirmed always correct, both before and after any fix — ruling out a missing
`makeFirstResponder` as the cause for this specific bug shape, contrary to the naive first guess.

**Fix:** call the same `growToFitTheText(textView, revealingCaret: true)` a second time,
immediately after the corrected `setSelectedRange` — reusing the Coordinator's own established
"make a newly-grown/newly-relocated caret visible" tool rather than inventing a second one.

**Why:** any future claimant in this same command-chain family that redirects a keystroke's
selection to a location that did not exist before the keystroke needs the identical second call,
by the same reasoning — see [[textkit2-attachment-view-accessibility]] for the same "TextKit 2
lays out lazily" class of gap in this codebase's editor.

**How to apply:** when a bug report is "the edit/text is correct but the caret doesn't
visibly move/blink," check first whether `firstResponder` is actually wrong (rare — it usually
isn't, this codebase's own click/redirect paths are generally careful about it) before assuming
it; the more likely fault in this codebase is a `setSelectedRange` that landed after the one
per-edit grow/reveal pass already consumed the previous selection.

**Test-harness ceiling, confirmed again:** a `Tests/*.swift` fixture's `NSWindow` never becomes
`isKeyWindow == true` even after an explicit `makeKeyAndOrderFront(nil)` call in this project's
`xcodebuild test` environment, so `firstRect`/frame-autoresize evidence gathered this way cannot
be trusted as proof either way — only as a same-harness-vs-same-harness comparison (a genuinely
laid-out control location vs the location under test, both probed in one otherwise-identical
fixture). Whether the pixel actually renders after a fix needs the XCUITest suite or a manual
check; a unit test here can only assert `selectedRange()` and `window?.firstResponder`, per
`Tests/TableCaretTests.swift`'s own convention.

**Round 2 (2026-09-03): the layout fix above was not the whole bug.** After the `growToFitTheText`
second call landed, the human confirmed live that the caret still never blinks in the gap before
the next real keystroke, even though typing immediately afterward works and renders a normal
blinking caret right away. Root cause: on macOS 14+, a TextKit-2-backed `NSTextView` draws its
caret through a real hosted `NSTextInsertionIndicator` subview (`NSTextInsertionIndicator.h`,
`AppKit.framework`), running in its default `.automatic` display mode — documented to
"automatically stop and start blinking during typing and dictation". That is a category test keyed
to AppKit's own ordinary key-event path (`interpretKeyEvents` → `insertText(_:)` → selection
changed), not to an arbitrary programmatic `setSelectedRange(_:)`. A claimant's redirect is
model-correct (`selectedRange()` and `firstResponder` both right) but is not "typing" by that
test, so the indicator's automatic mode never restarts the blink for it — it just sits in
whatever phase it was already in, indefinitely, until an actual keystroke finally does count.
**Fix:** call `textView.updateInsertionPointStateAndRestartTimer(true)` — `NSTextView`'s own
documented subclasser hook for "selection changed out of band, redraw and restart the blink" —
immediately after the layout-ensuring `growToFitTheText` call, never before (same zero-rect-trap
reasoning as round 1: restarting the blink against an unlaid-out rect is the fault, not the cure).

**A second, narrower headless ceiling found while trying to test this:** at a location that is
exactly the document's own end (the common case for this redirect — appending a paragraph after
the last block), *neither* `firstRect(forCharacterRange:)` *nor* its TextKit-2 fallback
(`caretRectOnScreen()`/`NSTextLayoutFragment.textLayoutFragment(for:)`) reliably returns a
non-degenerate rect in this project's `xcodebuild test` harness, fix present or not — unlike the
"genuinely laid-out control location" round 1 relied on, which was mid-document, not at the very
end. Do not add a caret-rect assertion for an end-of-document redirect target; it is not a signal
this harness can read either way, and chasing it burns time the human's live check makes moot
anyway. `firstResponder`/`selectedRange()` remain the only two headless-safe proxies for this
family of bug.

**Round 3 (2026-09-03, orchestrator, not a debugger dispatch): still not fixed.** An unconditional
`textView.textLayoutManager?.textViewportLayoutController.layoutViewport()` was added right after
`growToFitTheText`, on the theory that `growToFitTheText`'s own call is gated behind a >0.5pt
frame-height change and is routinely skipped for a bare `\n`. Hand-verified live: **still no
caret**, and this is also the build the newer, harder evidence came from — the human confirmed
that repeated Backspace right after the redirect *also* never shows a caret, even though each
Backspace visibly and correctly deletes a character (walking back into the table's own concealed
header content). That is the important new fact: Backspace is not claimed by `claimsTableCommand`
at all, so it reaches `super.doCommand(by:)` → `deleteBackward(_:)` through AppKit's completely
ordinary `interpretKeyEvents` path — the exact path `NSTextInsertionIndicator`'s own docs say
*should* count as "typing" and restart the blink. It didn't. That rules out "this specific edit
doesn't count as typing" as the whole story: once the indicator is in whatever bad state the
redirect left it in, even a wholly ordinary subsequent keystroke inherits the same missing caret.

**Round 4 (2026-09-03, debugger dispatch): resign/reclaim first responder, tried, not yet
independently hand-verified by the human.** Added, ordered last (after layout and the blink-restart
hook, on the same "layout before restart" reasoning as round 2):
```swift
if let window = textView.window {
    window.makeFirstResponder(nil)
    window.makeFirstResponder(textView)
}
```
Reasoning: `NSTextInsertionIndicator`'s only documented state-machine hook at all is
`becomeFirstResponder`/`resignFirstResponder` (`.automatic` on become, `.hidden` on resign) — and
this text view never actually resigns and reclaims first responder across the redirect (it already
held it, and keeps holding it), so the indicator is never told to rebuild itself from scratch
against the redirect's outcome. Forcing an explicit resign+reclaim cycle, after the caret's real
geometry is already correct (past `growToFitTheText`), asks AppKit to construct a fresh indicator
rather than nudge a half-stuck one. Full `PergamenumTests` suite (2082 tests) stays green, and
`focusColumn(_:)`'s own `index != focusedColumnIndex` guard makes the reclaim's re-triggered
`onTakeFocus?()` a no-op when the column was already focused, so no visible side effect is expected
from that path. **This could not be verified by the debugger dispatch itself** — no tool in this
environment can observe a blinking caret or drive a live keyDown sequence — so whether it actually
fixes the symptom (for Return, and for the harder Backspace-repeat case) is still open pending a
human hand check. If it turns out insufficient too, the next thing worth trying is asynchronous
reclaim (`DispatchQueue.main.async`) instead of synchronous, since AppKit's own indicator
construction might not complete within the same run-loop turn as the `makeFirstResponder` call —
untried as of this round. If that also fails, this is very plausibly Apple's own open
`FB17103305` (TextKit 2 caret regression, unresolved as of this writing) and no app-level fix may
exist short of dropping to TextKit 1 for this text view, which is a much larger change than
anything tried so far and was out of scope for this round.
