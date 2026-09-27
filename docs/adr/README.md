# Architecture Decision Records

Every ADR of this project lives here as `NNNN-<slug>.md`. Three rules keep the directory
trustworthy. Each one answers a defect found on 2026-09-26 (issue #581).

## 1. One number, one file

- A number names exactly one file. Two chains in flight took 0061 on the same day.
- The next number is the highest number under `docs/adr/` on `origin/main` plus one. Check it
  again immediately before the merge, including branches about to merge.
- A renumbering is done with `git mv`, so the file's history follows. Both ADRs get one dated
  renumbering note at the head naming the other and the reason. Every reference to the moved
  decision follows it, chosen by meaning (section numbers, topic), never by string. The change
  goes in the register below. Commits, PR bodies and closed tickets from before the rename keep
  the old number; the notes are the bridge.

## 2. A status line is mandatory and says what landed

- Every ADR states its status directly under its title, in the form the file already uses: a
  bulleted `- Status:` line or a `## Status` section.
- `accepted` names its landing evidence, read from git and never recalled. That is the PR whose
  merge brought the implementation to `main`, with the merge commit's short hash as
  `git log --first-parent main` shows it, and the date. A change that reached `main` without a
  merge commit cites the first-parent commit that did; a squash names its PR too.
- `proposed` is only for an ADR whose implementation is not on `main` yet. The merge hash exists
  only after the merge, so the flip to `accepted` is the first docs change after it, not
  something left for a later chain to notice.

## 3. A citation says where the ADR lives

- A number this directory holds means the file here, unless the citation carries another origin:
  a citation qualified with an origin from the table below means that origin even when the number
  exists here.
- An ADR this directory does not hold is cited with its origin in the same sentence, for example
  ADR-0155 of the retired concept-to-code workflow, not a Pergamenum ADR.
- The rule applies to the first citation of a number in each file. Later citations of the same
  number in that file may stay bare; they mean what the first one said.
- A number this directory holds, cited bare but meant in another series, cannot be told apart from
  a correct citation by its text, so no command detects it: qualify it when you write it. Five ADRs
  and one source comment cited the retired concept-to-code workflow's ADR-0053 that way until
  PG-273, while this directory's 0053 is a different record.

## External ADR series

The origins a citation may name, and the phrase that qualifies it. A citation is qualified when its
sentence contains a phrase of the second column, whatever the case and the line wraps. A new origin
is added here and nowhere else: `scripts/check-adr-references.py` reads this table.

| Origin | Qualifying phrase |
|---|---|
| The retired concept-to-code workflow (vibe-coding harness, pre 2026-09-14) | concept-to-code workflow |

## Checking the rules

`scripts/check-adr-references.py` checks the three rules on the working tree, and against
`origin/main` (or `--base <ref>`) when that resolves, so `git fetch origin` first. Exit 0 is clean,
1 a finding, 2 a check it could not run: this table unreadable, not a git repository, bad usage.
`--self-test` runs its own scenarios in throwaway repositories. `.github/workflows/adr-references.yml`
runs both on every pull request and every push to `main`, as an advisory check, never a required
one. The check is not in the pre-push hook, because a comment citation should not stop a push.

It checks less of rule 2 than the rule says: a status line in the head with one of the words
`accepted`, `proposed`, `superseded`, `deprecated` or `rejected`; no ADR on the base that reads
`proposed`; and, as a warning only, a commit hash in a status line that is not on the base's
first-parent line. The PR, hash and date that `accepted` should name are not checked. A record that
reaches `main` ahead of its implementation is reported while it reads `proposed` there.

## Renumbering register

| Old | New | Date | Reason |
|---|---|---|---|
| 0061 (`0061-external-deletion-reaches-the-tabs-and-the-diary.md`) | 0064 | 2026-09-26 | Two ADRs took 0061 on 2026-09-25. The merge-integrity guard (PR #529) landed first and keeps 0061, which `scripts/check-merge-integrity.py`, the pre-push hook, `merge-integrity.yml` and ADR-0062 cite. The external-deletion record (PR #530) moved to the next free number; 0063 was already ADR-0063. Issue #581. |
