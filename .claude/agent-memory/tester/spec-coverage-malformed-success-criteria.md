---
name: spec-coverage-malformed-success-criteria
description: spec-coverage.sh --list reports every R-NN as MALFORMED for a Pergamenum feature SPEC.md whose Success criteria section uses "- [ ] R-NN — text" checkbox bullets, even though the IDs are real and inside a recognized "## 9. Success criteria" heading.
metadata:
  type: project
---

Ran `bash ~/.claude/skills/concept-to-code/scripts/spec-coverage.sh --spec SPEC.md --plan
<plan>.md --list` against `SPEC.md` for the editor-wysiwyg-unification chain (PG-018,
2026-09-02/03). Exit code 3, every `R-01`..`R-15` reported `MALFORMED`, plus:

```
spec-coverage: a well-formed ID was found outside every recognized section — recognized
headings are: Success criteria, Acceptance criteria, Definition of done
```

The SPEC does have a `## 9. Success criteria` heading with well-formed IDs directly under
it, in the form `- [ ] R-03 — Blockquote \`>\` (unbounded nesting) ...`. The script's
parser apparently doesn't accept the `- [ ] ` checkbox prefix ahead of the ID (or some
other detail of that exact bullet shape), and reports every ID as found "outside" the
section it is plainly inside.

**Why it matters:** don't trust the script's `MALFORMED`/exit-3 verdict as "the SPEC
declares no IDs" and fall back to briefing from plan task text — that skips a real,
well-formed Success Criteria section. Read `SPEC.md`'s own Success Criteria section
directly (`grep -n "^##" SPEC.md` to find it, then `Read` it) and brief from the R-NN
bullets there; they are real generator/verifier requirement IDs (ADR-0048) and each maps
cleanly onto a plan task's cited "(R-03)"/"(R-05, R-09, R-10)" etc. suffixes.

**How to apply:** whenever `spec-coverage.sh --list` on this project's SPEC.md files exits
non-zero with `MALFORMED`, don't stop at the tool's verdict — open the SPEC and check
whether a real Success Criteria (or Acceptance/Definition of done) section exists with
`R-NN` bullets before falling back further. Worth flagging to the user that the script may
need a fix for this bullet format, since it will recur on every SPEC.md in this repo that
uses `- [ ] R-NN — ...` checkboxes (which appears to be this project's standard style).
