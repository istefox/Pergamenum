---
name: pg-099-task6-reveal-supersedes-caret-rescue
description: ADR-0033 §D4's range-keyed reveal makes §D15's view-block caret rescue unreachable by construction, so Task 5's rescue test and Task 6's reveal tests contradict each other over one fixture.
metadata:
  type: project
---

Wiring ADR-0033 §D4 (a fence whose source range the live selection intersects is not registered
at all) turns `viewBlockCaretRescue` into dead code and turns
`ViewBlockCaretRescue.aCaretInsideTheBodyLineIsRescuedToTheOpeningFenceOffset`
(`Tests/ViewBlockCaretTests.swift`, Task 5, green before Task 6) red. The two are mutually
exclusive by construction, not by an implementation detail: the rescue fires only when a pass
hides a line the caret sits in, and a caret sitting in a line a fence would hide is by definition
inside that fence's range, which reveals it, which hides nothing.

**Why:** measured on 2026-09-07 implementing Task 6. Both suites drive the same fixture,
`editor(ViewBlockCaretFixture.note, caret: insideBodyLine)`, and assert opposite end states —
`ViewBlockCaretRescue` wants the caret moved to the opening fence offset, `ViewBlockRevealIntegration`
wants no marker, no hidden lines and the body line laid out. Only a *stale* reveal answer
(consulted from a stored value updated after the pass rather than from the live selection) makes
the first pass hide, and that variant breaks production: clicking a drawn block would leave it
drawn until the next keystroke, which then types into the hidden fence source.
ADR §D15 already predicted the collision in its own words ("in practice D4 makes this nearly
unreachable"); the accurate word is *unreachable through `applyViewBlocks`* — a programmatic
selection (find match, outline jump, `onScrollApplied`) does go through the reveal path, because
`setSelectedRange` posts the selection notification (see
[[setselectedrange-fires-didchangeselection]]).

**How to apply:** in this chain, do not try to satisfy both — the resolution is the tester's, not
the coder's. Either retarget the rescue test to assert §D4's behaviour (the caret stays on the
now-visible body line) and keep `viewBlockCaretRescue` as defensive code with an honest comment,
or amend §D15 and delete both. A reveal rule with hysteresis (reveal only from a line that is in
the layout, stay revealed while inside) would keep both tests green and keep the rescue live, but
it is an ADR-level change to §D4 and adds per-fence stored reveal state.
