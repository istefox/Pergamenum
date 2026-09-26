Status: Approved (2026-09-26)

# SPEC — Documentation consistency: the record says what the tree does

## Destination

A SPEC handed to `/workplan`. Closes issue #581 (Audit Fable chain 14, promoted from `PG-267`)
in one docs-only PR: the app spec, the ADRs, the brief, the task ledger and the code comments
stop contradicting the tree and each other. No behaviour changes: no Swift statement, no script,
no workflow is edited, and the unit suite builds and passes untouched.

## Objectives

- The app spec, ADR-0001 and the brief no longer say that a note's id lives in the index. ADR-0059
  §D10 listed exactly these amendments on 2026-09-25 and none of them was applied.
- One ADR number names one document. The second ADR-0061 becomes ADR-0064 and every reference to
  it follows, while every reference to the merge guard keeps saying 0061.
- No comment and no document cites an ADR this repository does not hold without saying where it
  lives. Today 65 files cite «ADR-0155 §D1», an ADR of the retired concept-to-code workflow, and
  most of those comments still describe a batch that was red weeks ago.
- Every ADR's status line tells the truth about its implementation. Today 24 read `proposed`
  (19 in a bulleted line, five in a «Status» section the first measurement missed), and two
  status lines say the implementation is pending or missing while it is on `main`.
- The task ledger stops carrying `PG-156`, a finding ADR-0033 closed on 2026-09-07.
- The brief's 2026-08-13 changelog entry says, beside its own text, that the Conformità pane it
  describes was removed by ADR-0038.
- The three conventions that would have prevented the duplicate number, the phantom citation and
  the stale status lines are written down where the ADRs live, so the next chain cannot repeat
  them by accident.

## Scope and non-goals

In: the six items of issue #581 as measured on this tree (widened where the audit undercounted,
see Decisions), a short README for the ADR directory, and one new ledger entry proposing the
reference-check script as a follow-up.

Out, one line each, detail in Out of scope: the reference-check script itself; the truthfulness
of comments that do not cite ADR-0155; the ADR-0038 residues in the interface (chain 13 item 5);
normalising the form of every status line; the «to be moved by the operator» boilerplate at the
head of three ADRs; the brief's Status section; the closure of `PG-267` itself and the ledger's
header counts; the app spec's §4.1 tree; tracking the «board surface» idea as a ledger entry; the
ROADMAP's own chain 14 text.

## Decisions

- **Renumber the external-deletion ADR, not the merge guard** — the two ADR-0061 landed the same
  day, the merge guard first (PR #529) and the external-deletion one second (PR #530), whose own
  head already records that it was written when no 0061 existed. The merge guard's number is
  baked into the operational tooling (the integrity script, the pre-push hook, the workflow, the
  45 references in ADR-0062, a CLAUDE.md working agreement); the external-deletion number lives
  in comments, one plan, one index label and two ledger lines. Rejected: renumbering the merge
  guard — it landed first and the cost is an order of magnitude higher. Rejected: no
  renumbering, a disambiguating note only — the defect the issue names stays.
- **The new number is 0064, the next free one** — the issue proposed 0063, which chain 3 took on
  2026-09-26 (ADR-0063 is cited by its own SPEC, plan, CLAUDE.md and the ledger). Rejected:
  shifting 0063 to 0064 to keep the sequence chronological — two renumberings instead of one; the
  chronology is recorded in the renumbering note instead.
- **The rename keeps history and both heads record it** — the file is renamed with git so its
  history follows; each of the two ADRs gets one dated renumbering note at its head naming the
  other, and no other line of either body changes. The external-deletion ADR's existing
  «Numbering note» stays verbatim; the new note sits beside it. Rejected: rewriting the existing
  note — it is the record of what was known when it was written.
- **Every reference follows, plans and closed ledger entries included** — a pointer that resolves
  to the wrong document is the defect itself, not history. The plan that implemented the
  external-deletion ADR gets its references updated plus one head line recording the change; the
  closed `PG-234` entry's marker and the ROADMAP line that says «post-ADR-0061» about spurious
  deletions follow too. Rejected: leaving plans and ledger untouched as history — they would
  point at the merge guard.
- **ADR-0155: rewrite all 65 citations, with two rules** — Stefano's choice. In Swift files
  (18 under Sources, 36 under Tests) the reference and the now-false claim («stubbed to a
  wrong-but-safe constant», «every test below is red because…», «the coder fills the bodies»)
  go; a fact that still holds (a signature the tests were written against, a dependency injected
  rather than read) keeps its sentence, phrased without the number. In the 11 documents (three
  ADR bodies, eight superpowers plans) the first mention per file is qualified as the retired
  concept-to-code workflow's ADR, not a Pergamenum one, and the narrative is not rewritten.
  Rejected: the 18 Sources files only, the issue's letter — 36 test files keep telling a reader
  the suite is red. Rejected: one central explanation with the citations intact — resolves the
  reference, leaves 65 false sentences.
- **Status lines: the whole class, not the audit's 16** — 19 ADRs read `proposed` (the audit
  missed 0022, 0054 and 0055), 0026 says «implementation pending» and 0044, one of the 19,
  «decided, not implemented» while CI exists, and 0023, 0024, 0025, 0027, 0028 read «Proposed»
  under a «Status» heading the first measurement missed (corrected at the plan gate, 2026-09-26).
  All 25 get a status statement that says accepted and names the landing evidence read from git:
  the merging PR when there is one, otherwise the first-parent commit that brought the file to
  `main`, with its date; where the record's PR did not carry the implementation, the implementing
  PR is named too. Each file keeps the status form it already uses (a bulleted `Status:` line or
  a `## Status` heading), rewritten in place. Rejected:
  the issue's 16 — three ADRs and two qualifiers keep lying. Rejected: normalising all 64 files
  to one form — diff noise carrying no information.
- **`PG-156` is closed, not narrowed** — ADR-0033 (PR #178, 2026-09-07) put `pergamenum-view`
  fences back in the editor, so the entry's claim is false. The «board surface outside the text
  flow» idea already lives in the ROADMAP's chain 16 item 2 and needs no second home. Rejected:
  narrowing the entry to that idea — the id's history is about a defect that is closed.
- **The conventions live in a README in the ADR directory** — a reader browsing the ADRs finds
  them there; CLAUDE.md gets one pointer line. Rejected: a CLAUDE.md working agreement — the
  file is already long and these rules are needed when writing an ADR, not on every turn.
  Rejected: nowhere — the next chain can repeat the same errors.
- **Verification by grep; the check script is a follow-up** — the mandate is docs only. The
  checks a reviewer runs are listed under Test seams; a new ledger entry, filed in this same PR
  the way the 2026-09-26 entries were, proposes the script. Rejected: shipping the script in this
  chain — it would make the criteria repeatable but breaks the mandate.
- **Amendment notes follow the forms already prescribed** — the app spec's §9 route row and §14
  frontmatter row get the inline «Emendato 2026-09-25 (ADR-0059)» note ADR-0059 §D10 spells out,
  in Italian like the rows around them, and the original sentence stays readable; ADR-0001 §D2's
  last paragraph is amended inline and the ADR's head gets a scope note in the form the eleven
  ADRs amended by ADR-0047 §D12 carry, exactly as ADR-0059 §D10 asks; the brief's summary of
  §14 gets the same inline amendment; the brief's 2026-08-13 changelog entry gets one note at its
  end and none of its own sentences change. Rejected: rewriting the rows or the changelog
  sentence — «add a note beside, never edit history» is the issue's own rule.
- **Ledger edits by hand, in the ledger's own format** — `PG-156` gets the checkbox, a closing
  sentence naming ADR-0033 and PR #178, and the closed marker the other closed entries carry; the
  follow-up gets the next free id and the header's last-id counter rises with it. The header's
  open counts and `PG-267`'s own closure are left to the post-merge ledger sync that follows every
  merge. Rejected: leaving `PG-156` to that sync — the issue names it as this chain's deliverable.

## Constraints

- **Docs only, no behaviour change** — origin: user mandate (#581, ROADMAP chain 14). Every hunk
  in a Swift file is a comment; nothing under scripts, workflows, the Tuist manifest or the
  package list changes.
- **App-spec edits are a HITL gate** — origin: ADR-0059 §D10. Satisfied by this SPEC's approval
  and by the commit gate of `/ship`, which shows the diff.
- **History is annotated, never rewritten** — origin: issue #581 item 6 and ADR-0047 §D12's
  scope-note precedent.
- **One number, one file; a renumbering is recorded at both heads** — origin: this SPEC, becoming
  the README's first rule.
- **The landing check applies to this PR** — origin: ADR-0062. A renamed ADR is a new path with a
  blob that path never held, so it passes; nothing is restored.
- **The ledger's format belongs to the task tool** — origin: the existing ledger conventions, which
  hand-filed entries already follow.
- **Language** — origin: CLAUDE.md. The app spec's notes are Italian, like the rows they sit in;
  the brief's notes follow the language of the passage; ADRs, README, comments and the ledger
  stay English.

## Stack

Markdown, Swift doc comments, one git rename. No tooling change.

## Data model

Not applicable. The README's renumbering register is a list of entries, each with the old
number, the new number, the date and the reason; the first entry is 0061 to 0064.

## API / interfaces

None. No protected interface is touched.

## Edge cases

- **A reference is followed by meaning, not by string.** «ADR-0061» meaning the merge guard
  (ADR-0062, the tooling, the CLAUDE.md working agreement, the closed `PG-240`, `PG-241` and
  `PG-251` entries) stays. The discriminators are the section numbers and the topic: deletion,
  tabs, diary, absence marker and `PG-234` name the external-deletion ADR; merge, landing,
  override, side-pick and `PG-240` name the merge guard.
- **An ADR-0155 comment that carries a still-true fact** keeps the fact. Two known shapes: a
  signature the tests were written against, which widening would break; a dependency injected
  into a model rather than read there. The sentence stays, the number goes.
- **ADR-0044's status line points at a section that says the CI is not yet built.** The line is
  replaced; the section stays as the record of the decision, and the line names the workflow's
  landing on `main`.
- **ADR-0022's line says it will be accepted at a gate of a retired chain.** It becomes accepted
  with its landing; its superseded-in-part notes from ADR-0024 and ADR-0025 stay.
- **Three ADRs open with a stale «to be moved by the operator» paragraph.** The paragraph is
  history and stays; their existing «Status» section is rewritten in place below it.
- **The brief lists «conformità» among the connector's read tools.** That is the MCP lint tool,
  which ADR-0038 kept, so the line is true and is not touched.
- **Old commits and PR bodies keep saying ADR-0061 for the external-deletion work.** The two
  renumbering notes are the bridge; git history is not rewritten.
- **The ledger header's counts go stale the moment `PG-156` is checked by hand.** Left to the
  post-merge sync on purpose; the SPEC records it so nobody «fixes» it twice.

## Test seams

No unit test: nothing executable changes. The seam is a set of repository checks a reviewer runs
at the review step of `/build`, listed here so each criterion is checkable:

- one file per ADR number in the ADR directory (duplicate detection over the numeric prefix);
- no «ADR-0061» left that means the external deletion (a search over Sources, Tests, docs, the
  ledger, the ROADMAP and CLAUDE.md, each hit classified by the discriminators above);
- no «ADR-0155» under Sources or Tests; in the 11 documents, every file's first mention carries
  the qualifier;
- no ADR whose status reads proposed, pending or not implemented; every ADR has a status line;
  every PR number or commit a status line cites is on `main`'s first-parent history;
- the Swift diff is comment-only (every added or removed line in a Swift file starts with a
  comment marker), nothing changed under scripts, workflows, the Tuist manifest or the package
  list;
- the amendment notes and the README exist where the criteria say.

The Stop hook's unit build proves the comment edits still compile. The script that would make
these checks repeatable is the follow-up entry (R-14).

## Success criteria

- [ ] R-01 — The app spec's §9 `note?id=` row and §14 Frontmatter row each carry an inline
  «Emendato 2026-09-25 (ADR-0059)» note saying the id is recorded in the vault's note-id
  registry file, not in the frontmatter nor in the index, follows every rename and move the app
  performs, and is stable until the file is renamed outside the app; the original wording of
  each row stays readable beside the note. (no-test: documentation; checked by search)
- [ ] R-02 — ADR-0001 §D2's last paragraph says the ids live in the vault registry per ADR-0059,
  and the ADR's head carries a scope note in ADR-0047 §D12's form pointing at ADR-0059; no other
  line of the body changes. (no-test: documentation)
- [ ] R-03 — The brief's summary of the §14 decisions no longer says note ids live in the index;
  the clause carries an inline amendment naming ADR-0059. (no-test: documentation)
- [ ] R-04 — Exactly one file per number exists in the ADR directory; the external-deletion ADR
  is 0064 in both its file name and its title line; its git history follows the rename.
  (no-test: documentation; checked by duplicate search and history)
- [ ] R-05 — Both the merge-guard ADR and the renumbered ADR carry one dated renumbering note at
  the head naming the other and the reason; the renumbered ADR's original numbering note stays
  verbatim; nothing else in either body changes. (no-test: documentation)
- [ ] R-06 — No reference to the external-deletion decision says 0061: the eleven source files,
  the three test files, the implementing plan (plus one head line recording the change),
  CLAUDE.md's index label, the closed `PG-234` ledger entry's marker and the ROADMAP's
  «post-ADR-0061» line all say ADR-0064, and CLAUDE.md's index keeps both entries in place. Every
  reference that means the merge guard still says 0061. (no-test: documentation; checked by
  classified search)
- [ ] R-07 — No file under Sources or Tests mentions ADR-0155; every stale claim of a stub or a
  red batch in those 54 files is gone; a still-true fact keeps its sentence without the number;
  every added or removed line in a Swift file is a comment line. (no-test: comments; checked by
  search and a comment-only diff filter)
- [ ] R-08 — In each of the 11 documents that cite ADR-0155, the first mention carries the
  qualifier that it is the retired concept-to-code workflow's ADR, not a Pergamenum one; no other
  sentence in those files changes. (no-test: documentation)
- [ ] R-09 — No ADR reads proposed, pending or not implemented. The 25 in the class (the 19 whose
  bulleted line read proposed, 0044 among them; 0026's «implementation pending»; 0023, 0024,
  0025, 0027 and 0028, whose «Status» section read Proposed) say accepted and name their landing
  on `main` (PR number, or first-parent commit when the file landed without one) with its date,
  plus the implementing PR where the record's PR did not carry it; each file keeps the status
  form it already had, rewritten in place. (no-test: documentation)
- [ ] R-10 — Every PR number and commit a status line cites is read from git and is on `main`'s
  first-parent history; none is recalled from a ticket or an ADR body. (no-test: documentation;
  checked by ancestry)
- [ ] R-11 — `PG-156` is checked as closed with a sentence naming ADR-0033 and PR #178
  (2026-09-07) and a closed marker in the ledger's own format; the header's counts and `PG-267`
  are untouched. (no-test: ledger)
- [ ] R-12 — The brief's 2026-08-13 changelog entry ends with one note saying the Conformità pane
  and its «Verifica conformità» command were removed on 2026-09-11 by ADR-0038 while the CLI and
  MCP lint tools remain; none of the entry's own sentences change; the connector tool list that
  mentions «conformità» is untouched. (no-test: documentation)
- [ ] R-13 — A README exists in the ADR directory with three rules and a register: one number one
  file, the next number is the highest plus one, a rename keeps history and is recorded at both
  heads and in the register; a status line is mandatory, accepted names the landing evidence,
  proposed is only for an implementation not yet on `main`; a citation of an ADR the directory
  does not hold is qualified with its origin. The register's first entry is 0061 to 0064.
  CLAUDE.md gains one line pointing at it. (no-test: documentation)
- [ ] R-14 — A new ledger entry with the next free id proposes the reference-check script (unique
  numbers, every cited ADR resolves or is qualified, no proposed status with an implementation on
  `main`), P4, pointing at this chain; the header's last-id counter is raised to match.
  (no-test: ledger)
- [ ] R-15 — Nothing changes under scripts, workflows, the Tuist manifest or the package list; the
  unit suite builds and passes. (no-test: verified by the Stop hook's build and a path check on
  the diff)

## Not yet specified

_none_

## Out of scope

- **The reference-check script** — proposed by R-14, built in its own chain, so this one stays
  docs only as mandated.
- **Comments that do not cite ADR-0155** — their truthfulness was not measured here; a general
  comment audit is a different chain.
- **ADR-0038 residues in the interface** (a tooltip, an orphan comment) — ROADMAP chain 13 item 5.
- **Normalising the status-line form across all ADRs** — no information gained, diff noise.
- **The «to be moved by the operator» paragraphs at the head of ADR-0023, 0024, 0025** —
  history of how those files were written; they stay.
- **The brief's Status section** — no milestone is reached by this chain.
- **`PG-267`'s closure and the ledger header's counts** — the post-merge sync does both.
- **The app spec's §4.1 tree** — ADR-0059 §D10 leaves it alone on purpose; not reopened.
- **A ledger entry for the «board surface» idea** — the ROADMAP's chain 16 item 2 holds it; a
  ledger id is opened only if Stefano asks.
- **The ROADMAP's chain 14 text** — a dated audit report; its «renumber one (0063)» stays as the
  audit wrote it, and this SPEC records the departure.

## Domain terms

- **Landing evidence** — the PR whose merge brought a file to `main`, or, when the file arrived
  without a merge commit, the first-parent commit that did; always read from git.
- **Qualified citation** — a reference to an ADR outside this repository that names its origin in
  the same sentence, so a reader does not look for it in the ADR directory.
