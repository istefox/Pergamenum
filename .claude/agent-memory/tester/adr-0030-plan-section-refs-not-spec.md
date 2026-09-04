---
name: adr-0030-plan-section-refs-not-spec
description: In the ADR-0030 editor-typography plan/manifest, "SPEC §N" citations for behaviour details are the plan document's own section numbers, not docs/20260811_Pergamenum_SpecApp.md's — and the referenced companion doc doesn't exist in-tree.
metadata:
  type: project
---

The plan `docs/superpowers/plans/2026-09-04-editor-page-typography-noteplan.md` (ADR-0030,
"editor page typography") cites "SPEC §8" for behaviour claims (e.g. Task 3: "a `.code` span
inside a heading keeps the mono face at the heading's size (SPEC §8)"). `docs/20260811_Pergamenum_SpecApp.md`
§8 is "Calendario e integrazione Apple" — completely unrelated. ADR-0030 itself also cites a
second document, `docs/20260904_Editor_Page_Roadmap.md`, as the source of "Phase A" — that file
does not exist anywhere in this worktree.

**Why:** tracing the actual mechanism (`MarkdownStyler.spans(in:)` emits a line's `.heading`
span before that line's inline spans; `MarkdownAttributedText.attributed(_:theme:)` applies
`addAttributes(range:)` in that emission order, so a later span's `.font` replaces rather than
composes with an earlier one on the overlapping range) shows the plan's literal claim
("keeps the mono face at the heading's size") doesn't hold under the coder instructions given
for that task (a plain `theme.nsFont(.mono)` for `.code`, no context-aware resizing described
anywhere). Writing a test that asserts the exact heading-matched point size would have been
inventing a requirement neither the real SPEC nor any in-tree doc states.

**How to apply:** for any task in this chain (Tasks 4-9 remain) that cites "SPEC §N" for a
behaviour detail, check first whether that section number matches the real
`docs/20260811_Pergamenum_SpecApp.md`, or is actually a section of the plan/manifest itself, or
cites the missing roadmap doc. If unverifiable, assert only the part of the claim that traces
directly to the coder's stated instructions and the existing mechanism, and file a PLAN
DEVIATION rather than asserting an invented number — see
[[pergamenum-tester-stub-pattern]] for the sibling convention on this same ADR chain (Task 2's
`ProseTypographyTests.swift` already logged one such deviation for a similarly mis-cited file).
