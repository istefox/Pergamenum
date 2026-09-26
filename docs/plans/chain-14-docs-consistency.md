# Plan: chain 14 (#581, PG-267), documentation consistency

- **SPEC:** `SPEC.md` (Approved 2026-09-26), success criteria R-01…R-15. Its Decisions and
  Constraints are registered as settled and not reopened. In six places the tree contradicts the
  SPEC's own measurement or reaches past its enumerated lists; each is listed under gate G1 with the
  resolution this plan recommends, none decided on Stefano's behalf.
- **Citation convention used below:** ADR-0155 is an ADR of the retired concept-to-code workflow, not a Pergamenum ADR; this directory never held it.
- **ADR outcome: no new ADR.** The chain changes no architecture, contract, on-disk format or code
  path. Its decisions are documentation conventions plus a one-time renumbering, and their durable
  record is the ADR directory's own README (three rules and a renumbering register, each entry with
  its reason) and the two dated head notes, which is where the next person writing an ADR reads.
  Against the significance test: a real trade-off existed (which 0061 moves), but it is not hard to
  reverse (another `git mv`), and it stops being surprising once both heads carry the note. No
  override applies: no security or compliance boundary, the constraint is written down rather than
  invisible, and there is no deliberate deviation a later reader would "fix". An ADR about ADR
  numbering would also spend a number on the sequence this chain repairs. Existing ADRs that govern
  parts of the work, cited unchanged:
  - **ADR-0059 §D10** fixes what is amended (ADR-0001 §D2's last paragraph, SPEC §9 and §14 rows)
    and how (inline «Emendato» notes, a head scope note). Tasks 7.
  - **ADR-0047 §D12** fixes the scope-note form and its placement under the status block. Task 7.
  - **ADR-0038** is the removal the brief's changelog note names. Task 7.
  - **ADR-0033** (PR #178) is what closes `PG-156`. Task 8.
  - **ADR-0062**'s landing check runs on this PR's push. A renamed file is a new path with a blob it
    never held, so it passes; nothing here restores an old blob.
  - **ADR-0061 (merge-integrity guard)** keeps its number; ADR-0044's relocation convention is not
    needed because no ADR is drafted.
- **Baseline:** `HEAD` is `93b1e8b`; `origin/main` is `43ca911`, two commits ahead, `TODO.md` only
  (PR #591 closed `PG-096` and moved the header's open count from 73 to 72). Every count, line and
  hash below was read on 2026-09-26 from those two trees with `git`, `grep` and `sed`. None is
  recalled from the issue or the ROADMAP.
- **Scope:** docs only. No Swift statement, script, workflow, `Project.swift` or
  `Tuist/Package.swift` changes. Every Swift hunk is a comment line. No test is added, removed or
  skipped, and no `tuist generate` is needed: no file under `Sources/` or `Tests/` is added or
  removed, and the renamed file is under `docs/`.
- **UI budget:** zero GUI tests. Nothing observable changes.

## Before `/build` (orchestrator; each item is a HITL point)

1. **Bring `origin/main` in first:** `git fetch origin`, then `git merge origin/main`. The merge is
   clean (`TODO.md` changed only on `main`). It must land before any `TODO.md` edit (Tasks 2 and 8),
   or the ledger conflicts. After it, re-read `TODO.md` line 1: if `lastId` is no longer 272, Task 8's
   new entry takes `lastId + 1`, not `PG-273`.
2. **Re-measure before editing** (block B below). If any count differs from this plan, stop and
   report: chain 13 (`PG-266`, dead code) runs in parallel and may have moved comment lines.
3. **Gate G1: approve the departures D1–D6** below.
4. **Commit gates.** Task 1's rename is committed alone, as a pure `git mv` with no content change,
   so `git log --follow` sees a 100 % rename. Every commit is HITL, as is the push.

Block B (expected values on the merged tree; bash, from the repo root):

```bash
grep -rn "ADR-0061" Sources | wc -l                     # 25 lines, 11 files
grep -rn "ADR-0061" Tests | wc -l                       # 7 lines, 3 files
grep -n "0061" docs/plans/pg-234-external-deletion.md | wc -l   # 14 (13 «ADR-0061» + the path on :7)
grep -rn "ADR-0155" Sources | wc -l                     # 20 lines, 18 files
grep -rn "ADR-0155" Tests | wc -l                       # 39 lines, 36 files
grep -rl "ADR-0155" docs | grep -v chain-14 | wc -l     # 11 files (14 lines)
```

## Departures from the SPEC's letter (gate G1)

- **D1. The status-line class is 25 ADRs, not 26.** The SPEC counts 0044 twice: it is one of the 19
  that read `proposed`, and it is named again for «decided, not implemented». Measured: 24 files
  whose status value does not start with `accepted`, plus 0026 (accepted, «Implementation
  pending»), is 25.
- **D2. 0023, 0024, 0025, 0027 and 0028 already have a status: a `## Status` section whose first
  paragraph reads «Proposed — …».** The SPEC measured them as having none (the audit's grep looked
  for `Status:` lines). The SPEC's own Decision already names the rule that settles it: «each file
  keeps the status form it already uses (a bulleted `Status:` line or a `## Status` heading)».
  Recommended: rewrite that paragraph in place and add no bulleted line. R-09's «gain a status line
  in their neighbours' bulleted form» and the edge case «the new status line goes under the title,
  above [the to-be-moved paragraph]» rest on the mismeasurement. Adding a bullet while «Proposed»
  stays under the heading would fail R-09's first sentence. The «to be moved by the operator»
  paragraphs of 0023–0025 stay untouched either way.
- **D3. R-06 reaches two references its enumerated list omits,** both covered by its first
  sentence («No reference to the external-deletion decision says 0061»):
  - `docs/adr/0063-connector-input-hardening.md:20`, «as ADR-0054/0055/0058/0061 already recorded».
    This points at the external-deletion ADR's Path note; the merge guard has none.
  - The prose of the closed `PG-234` entry, «implements ADR-0061», beside the marker the SPEC names.
  - CLAUDE.md line 504's link path (`docs/adr/0061-external-deletion-…`) changes with its label.
- **D4. Landing evidence for 0017 and 0030 names two PRs.** Each record reached `main` in a PR that
  did not carry its implementation. 0017 came through the docs-only PR #82 and was implemented by
  PR #83 (`feature/pg-004-state-outside-vault`). 0030 rode in PR #167, the Sparkle branch, and was
  implemented by PR #169 (`feat/editor-page-typography-noteplan`). The SPEC's definition (the PR that
  brought the file) is kept and the implementing PR is added, both read from git, so the line tells
  the truth about the implementation, as the Objective asks. For the other 23 the landing merge's
  diff was checked to carry `Sources/` (or, for 0044, `.github/workflows/ci.yml`) changes. For 0024
  and 0026, whose landing branches carry another chain's name, the implementation's own symbols were
  found in that merge's diff (`WorkspaceSelection`, `VaultItemDrag.swift`).
- **D5. The renumbered ADR's existing status line cites `c2cf19b`, PR #530's branch commit, not a
  first-parent one.** The merge is `638f5e4`. R-05 forbids touching any other line, so the line
  stays and the new renumbering note names the merge. The R-10 ancestry check is therefore scoped to
  the 25 lines this chain writes. Several other accepted ADRs cite base commits (`ef8d28d`,
  `a501823`) that were never meant as landing evidence.
- **D6. Citations of other ADRs this repository does not hold remain.** They are outside the SPEC's
  measured scope (R-07 and R-08 name ADR-0155 only). After this chain, the Objective sentence «No
  comment and no document cites an ADR this repository does not hold without saying where it lives»
  holds for ADR-0155 only. Measured:
  - ADR-0073 in `Tests/CardTextViewTests.swift:122`, `Tests/MarkupHidingTests.swift:501`,
    `Tests/ProseTypographyTests.swift:15`, `Tests/MarkdownAttributedTextTests.swift:15`;
  - ADR-0068 in 37 files under `docs/manifests/`;
  - ADR-0138, ADR-0154, ADR-0158 in `docs/superpowers/plans/*` and `docs/specs/pg-066-*`;
  - ADR-0159 at `PROJECT_BRIEF.md:329`, ADR-0066 at `TODO.md:789`;
  - one **collision** a resolve-only check cannot see. `docs/adr/0040-…:39`, `:653` and
    `docs/adr/0042-…:51`, `:628` cite the retired workflow's ADR-0053 («protected interfaces are
    proposed by the architect and created by the operator»). In this directory 0053 is
    `0053-test-seams-for-the-in-process-merge-gate.md`, a different record.

  Recommended: accept, and record them as the baseline of the Task 8 ledger entry. Widening now is
  Stefano's call.

## Ownership and order

There is no tester step. Nothing is declared and no test is written (SPEC «Test seams»), so the
compiled-language rule about the tester owning signatures does not arise. One coder runs Tasks 1→8.
The reviewer runs the Acceptance block at the review step of `/build`. If the orchestrator wants
parallel batches:

- Tasks 3, 4, 5 and 7 touch disjoint files.
- 6 follows 5, because 0036, 0040 and 0042 take an edit from each (different lines).
- 2 follows 1.
- 8 follows 2, because both edit `CLAUDE.md` and `TODO.md`.

A shared rule for every Swift edit (Tasks 2, 3, 4): comments only. Do not add or remove a
statement. Do not leave two consecutive bare `//` lines, or a bare `//`/`///` immediately before
code. A blank line removed with a deleted paragraph is fine; the diff filter allows it.

---

### Task 1 — The external-deletion ADR becomes 0064 (R-04, R-05)

Files:

- `docs/adr/0061-external-deletion-reaches-the-tabs-and-the-diary.md` →
  `docs/adr/0064-external-deletion-reaches-the-tabs-and-the-diary.md` with `git mv`, committed alone
  (commit gate).
- Then, in the renamed file:
  - line 1: `# ADR-0061:` → `# ADR-0064:`;
  - one new bullet immediately after the existing `- **Numbering note.**` bullet (lines 17–20),
    which stays verbatim;
  - nothing else. The status line (see D5), the Base note and the Path note stay as they are.

  ```markdown
  - **Renumbering note (2026-09-26).** Written, merged and cited as ADR-0061 (PR #530, merge
    `638f5e4`, 2026-09-25). The merge-integrity guard, `0061-merge-integrity-guard.md` (PR #529,
    merge `15a0df7`), landed the same day before it and keeps 0061, because the tooling cites that
    number. This record took the next free number, 0064 (0063 was already ADR-0063), on issue #581.
    Commits, PR bodies and closed tickets from before this date call it ADR-0061. Register:
    `docs/adr/README.md`.
  ```

- `docs/adr/0061-merge-integrity-guard.md`: one new bullet after the `- Date:` bullet (lines 4–9),
  before `- **Reopens nothing.**`. Nothing else changes.

  ```markdown
  - **Renumbering note (2026-09-26).** A second record numbered 0061, the external-deletion ADR
    (PR #530, merged after this one on 2026-09-25), is now ADR-0064
    (`0064-external-deletion-reaches-the-tabs-and-the-diary.md`). This record keeps 0061 because
    `scripts/check-merge-integrity.py`, the pre-push hook, `merge-integrity.yml` and ADR-0062 cite
    it. Issue #581; register: `docs/adr/README.md`.
  ```

Date both notes with the day of the rename commit if it is not 2026-09-26. The PR and merge hashes
were read from `git log --first-parent origin/main`: `15a0df7` is «Merge pull request #529» and
`638f5e4` is «Merge pull request #530», both 2026-09-25.

### Task 2 — Every reference to the external-deletion decision says 0064 (R-06)

Every hit was classified by topic (deletion, tabs, diary, absence marker, conflict banner,
`PG-234`), as the SPEC's Edge cases describe. None of the files in the first two bullets holds a
merge-guard reference, so a mechanical `sed -i '' 's/ADR-0061/ADR-0064/g'` on exactly those 14 Swift
files is safe.

- **Sources, 25 lines in 11 files:** `Sources/App/VaultController+Watching.swift:30`,
  `Sources/App/VaultController+TabFollowUps.swift:5,35`,
  `Sources/App/VaultController+Editing.swift:10,125,146`,
  `Sources/Features/Editor/EditorColumn+Conflict.swift:10`,
  `Sources/Features/Editor/ConflictBannerCopy.swift:3`,
  `Sources/Vault/VaultSession.swift:114,124,138,149,164`, `Sources/Vault/NoteTab.swift:88,94,105`,
  `Sources/Vault/VaultSession+Watching.swift:13,48,81`, `Sources/Vault/VaultDisk.swift:293,450,453`,
  `Sources/Vault/VaultSession+Journal.swift:67,79`, `Sources/Vault/VaultScanner.swift:184`.
- **Tests, 7 lines in 3 files:** `Tests/VaultControllerExternalDeletionTests.swift:5,169`,
  `Tests/ExternalDeletionReconcileTests.swift:5,9,51,95`, `Tests/DiaryWatcherReloadTests.swift:48`.
  The «Red on…» and «already fails» sentences at `DiaryWatcherReloadTests.swift:48` and
  `ExternalDeletionReconcileTests.swift:95` are stale too. Those files do not cite ADR-0155, so the
  sentences are out of scope (SPEC Out of scope, second bullet) and only the number changes.
- **`docs/plans/pg-234-external-deletion.md`, 14 lines:** lines 4, 6, 7 (the path
  `docs/adr/0061-external-deletion-…`), 14, 24, 27, 61, 215, 224, 243, 271, 272, 303, 311 → 0064.
  Add this as the first head bullet:

  ```markdown
  - **Renumbered 2026-09-26:** the ADR this plan implements was ADR-0061 when the plan was written
    and is ADR-0064 since issue #581 (register: `docs/adr/README.md`); every reference below was
    updated to match, nothing else changed.
  ```

- **`CLAUDE.md:504`:** `**ADR-0061**` → `**ADR-0064**`, and the trailing
  `docs/adr/0061-external-deletion-…` → `docs/adr/0064-external-deletion-…`. The entry stays where
  it is (after ADR-0060's), as does the merge guard's at `:500`. Lines 145, 147, 227, 500 and 501
  mean the merge guard and stay.
- **`TODO.md`, closed `PG-234` entry** (line 566 before the merge; find it by id): «implements
  ADR-0061» → «implements ADR-0064», and the marker's `adr:0061` → `adr:0064` (D3). Leave these
  alone: `PG-240`, `PG-241`, `PG-244`, `PG-246`, `PG-251` (merge guard) and `PG-267` (the defect's
  own description).
- **`ROADMAP.md:717`:** `post-ADR-0061.` → `post-ADR-0064.`. Lines 946–947 (chain 14's audit text)
  stay, per SPEC Out of scope.
- **`docs/adr/0063-connector-input-hardening.md:20`:** `0054/0055/0058/0061` →
  `0054/0055/0058/0064` (D3). Lines 14–16, about the duplicate itself, stay.

Untouched on purpose, because they mean the merge guard: `docs/adr/0062-…` (45 lines),
`docs/plans/pg-242-landing-check.md` (18), `docs/plans/connector-input-hardening.md:68` (`:545` is
about the duplicate), `scripts/**`, `.github/workflows/merge-integrity.yml`.

### Task 3 — ADR-0155 leaves the Sources comments (R-07, R-15)

The rule is the SPEC's own. The citation goes, and so does every stale claim. A still-true fact
keeps its sentence, phrased without the number. Three claim classes are in scope anywhere in the 18
files:

- **(a)** a declaration is a stub or placeholder, or returns a wrong-but-safe constant;
- **(b)** a test or batch is red, or is expected to fail until something happens;
- **(c)** a body is still to be filled, wired or implemented «by the coder», or «does not … yet».

Two kinds of text are not claims and stay: attribution with no statement about current state («the
coder's SwiftUI view», «this batch's report»), and feature vocabulary («placeholder» in ADR-0042's
inline-image sense). Before deleting a «not yet» sentence, confirm in the code that it is false. The
dispositions below were checked that way on 2026-09-26.

| File:line | Disposition |
|---|---|
| `Sources/App/CommandActions+CanRun.swift:72-76` | Keep one sentence: `` `vault.root != nil` mirrors `.newNote`/`.newBoard` above: creating a pratica needs somewhere to write it. `` The leading «Plan Task 8 (R-20, R-21):» may stay. Drop «a tester-declared stub arm, added only so the exhaustive switch keeps compiling» and «which the coder may refine once …» (`NuovaPraticaWizard.swift` and `MailSeedPicker.swift` exist). |
| `Sources/Core/Pratiche/DailyNoteMirror.swift:12-13` | Delete the paragraph and the bare `//` above it. `line(for:)` and `appending` are real. |
| `Sources/Core/Pratiche/MembershipRule.swift:31-35` | Keep «One conversation's messages, followed or not (ADR §D22.1).»; «A one-line union of two dictionary lookups.» may stay. Drop «Tester stub (ADR-0155 §D1) … no-op stub» and the sentence «`everyMessage(in:)` does not call this yet - that rewiring is coder work»: the rewiring went to `candidates`, `:70`. |
| `Sources/Core/Pratiche/PraticaEntry.swift:15-17` | Delete the paragraph and the bare `//` above it. |
| `Sources/Core/Pratiche/PraticaTrayModel.swift:13-17` | Replace with «`isHidden(_:)` is exactly `.isEmpty`.» or delete the paragraph. `proposals`, `ignoring` and `following` are real. |
| `Sources/Features/Pratiche/AddToPraticaOrdering.swift:16-17` | Delete both lines (`///` and «Tester-declared boundary …»). `recentFirst` is real. |
| `Sources/Features/Pratiche/AttachmentChip.swift:83` | Drop «(ADR-0155)»; the injection fact stays. |
| `Sources/Features/Pratiche/AttachmentChipModel.swift:11-12` | Drop the parenthetical «(ADR-0155: this declaration is tester-owned, the coder fills gaps)». «Pulled out of the SwiftUI view so those decisions are testable …» stays. |
| `Sources/Features/Pratiche/MailStorePreparation.swift:55` | Drop «(ADR-0155 §D1; the coder fills the detection in `prepare`)». «defaulted empty so every existing construction site keeps compiling» stays. The detection exists: `followed.remap`, `:116`. |
| `Sources/Features/Pratiche/MessageCommand.swift:10-11` | Delete the paragraph and the bare `//` above it. `available` is real, `:78`. |
| `Sources/Features/Pratiche/PraticaCommand.swift:14-16` | Delete the paragraph and the bare `///` above it. |
| `Sources/Features/Pratiche/PraticaLiveSync.swift:10` | «(the tester's signature, ADR-0155)» → «(the signature the tests were written against)». |
| `Sources/Features/Pratiche/PraticaSyncEngine+Payloads.swift:66-67` | Delete both lines and the bare `///` above them. `commit` appends to `bridge` (`PraticaSyncEngine+Messages.swift:864,899`). |
| `Sources/Features/Pratiche/PraticaTimelineModel.swift:15-17` | Delete the paragraph and the bare `//` above it. |
| `Sources/Features/Pratiche/PraticheController.swift:72` | «the tester-declared shape … (ADR-0155)» → «the shape the ordering, filtering and lane rules are written against». |
| `Sources/Features/Pratiche/PraticheController.swift:287` | «is the tester-declared signature (ADR-0155) and widening it would break …» → «is the signature the tests were written against, and widening it would break …». |
| `Sources/Features/Pratiche/PraticheController.swift:305` | Drop «(ADR-0155)». |
| `Sources/Features/Pratiche/PraticheController+Ledger.swift:715-716` | Replace with «Called, through `applyConversationRemap`, from `PraticaLiveSync.runExclusive` before candidates are evaluated (§D23.4).» (`PraticaLiveSync+Run.swift:117,120,215`). |
| `Sources/Features/Pratiche/PraticheSidebarGrouping.swift:15-16` | Delete the paragraph and the bare `//` above it. `grouped` is real, `:76`. |
| `Sources/Features/Pratiche/WizardState.swift:12-13` | Delete the paragraph and the bare `//` above it. `makeDossier` is real, `:149`. |

Then sweep the same 18 files for classes (a)–(c) with the candidate command under R-07 below. On
2026-09-26 the sweep found nothing beyond the rows above except `PraticaTrayModel.swift`'s own
lines 13–17.

### Task 4 — ADR-0155 and the stale red/stub claims leave the Tests comments (R-07, R-15)

The rule and classes (a)–(c) are Task 3's. Header blocks come first; each row says what stays.

| File | Header lines | What stays |
|---|---|---|
| `PraticaSyncAttachmentTests`, `PraticaSyncInlineImageTests`, `PraticaSyncIntegrityTests`, `PraticaSyncPendingTests`, `PraticaSyncPlanTests`, `PraticaSyncRepairTests`, `PraticaSyncRetryTests`, `PraticaSyncThresholdTests`, `PraticaSyncWritePathTests`, `PraticaRegenerationTests` | 9–12, the identical «declared-but-stubbed … red» paragraph | nothing; delete it and one adjacent bare `//` |
| `AttachmentChipTests` | 9–10 | «A temporary directory stands in for `allegati/` and for Mail's own store - never `~/Library/Mail`.» |
| `AttachmentIntegrityTests` | 9–13 | nothing |
| `DossierTests` | 9–10 | «No test here touches `~/Library/Mail`.» |
| `DossierWriterTests` | 8–12 | «This test is written against the contract - call `update`, then read the file back.» |
| `EMLXReaderTests` | 8–10 | «Every fixture is synthetic, built by `Tests/EmailFixtureCorpus.swift` - no test here reads `~/Library/Mail`.» |
| `EmbedResizeTests` | 11–14 | nothing |
| `EmbedResolutionTests` | 15–25 | the Task 4 quote up to «drawn at». Drop «As of this file … already exists on disk» after confirming that `rendition(forSyntax:…)` no longer asks for the constant 720. |
| `MailStoreReaderTests` | 9–15 | «`MailStoreFixture` (`Tests/MailStoreFixture.swift`) builds every fixture; no test here touches `~/Library/Mail`.» |
| `MarkupHidingTests` | 545–550 | «Task 4 of …», «Both properties are plain stored values with system-face defaults» and «What is asserted here is the interface itself …» |
| `MessageAttachmentPatchTests` | 9–12 | nothing |
| `MessageDocumentTests` | 242–245 (in-body) | nothing, or the list of names exercised |
| `NoteStoreReadTests` | 13–20 | optionally «The tests that characterise `read`'s output exist to catch a regression.» |
| `PraticaEntryTests`, `PraticaTimelineTests`, `PraticaTrayTests`, `PraticaWizardTests` | 8–10 / 9–13 / 11–14 / 8–10 | nothing |
| `PraticaLedgerTests` | 9–14 | «`PraticaLedger.PraticaState` carries `notInStore` so a sync can record R-16's outcome and `PraticheController.readTimeline` can read it back into R-26's «non più in Mail» caption.» Confirm `readTimeline` no longer hardcodes `isInMail: true`. |
| `PraticaNamingTests` | 9–11 | «`PraticaNaming.messageFileName` is a protected interface (`.claude/protected-interfaces`).» |
| `PraticheConnectorTests` | 9–18 | the fixture sentence, minus «only the connector functions themselves are stubs» |
| `PraticheControllerTests` | 9–16 | «No test here touches `~/Library/Mail`; `stateReadsEPERMAsNotGranted` and the `PraticheController` tests build their own throwaway, unreadable file instead.» |
| `PraticheSettingsTests` | 9–17 | «`PraticheSettings` round-trip and clamping are kept here as a completeness check, so a regression in the Settings tab is caught by the file that owns its coverage.» |
| `RecordingsViewModelTests` | 9–18 | «Everything here is a value, never a view: only the pure presentation types (…) are exercised.» The views exist now. |
| `TaskMarkerTests` | 12–20 | «Two tests are guards: the backward-compatibility case (`^[[Nota]]`, no `.canvas`) and the plain-link case that mirrors `Tests/TaskTests.swift:37-40`.» |
| `VaultBoundaryCallSiteTests` | 13–20 | «The four `Bool`/`URL?`-returning sites answer `false`/`nil` on a violation.» and «`BoardCardActions.resolvedOpenURL(for:root:)` is a `nonisolated`, pure function extracted from `open(_:)`: there is no other seam that does not drive `NSWorkspace` for real.» |
| `VaultDiskTests` | 9–15 | nothing. This also removes the retired workflow's «ADR-0049» on `:9`. |
| `VaultWalkTests` | 10–15 | nothing. The «Declared signature» copy below it is not a claim and stays. |

In-body worklist found by the candidate sweep on 2026-09-26. Drop the stub or red half, keep the
half that says what the test checks:

- `DossierWriterTests.swift:41`
- `MailStoreReaderTests.swift:23-24, 41, 131-132, 151-152, 180-181, 202-203, 230-231, 246, 273, 337,
  356, 368`
- `MarkupHidingTests.swift:523-529`, and `:1058` after confirming whether the hook's guard now calls
  it
- `NoteStoreReadTests.swift:132` (the `MARK` line: drop «coder implements:»)
- `PraticaLedgerTests.swift:58` (the `MARK`: drop «RED:»), `:89`
- `PraticaRegenerationTests.swift:16-20, 172-175`
- `PraticaSyncAttachmentTests.swift:145-146`
- `PraticaSyncIntegrityTests.swift:24-25`
- `PraticaSyncPendingTests.swift:125-130`
- `PraticaSyncRepairTests.swift:141-146`
- `PraticaSyncRetryTests.swift:23` (and the sentence it opens)
- `PraticaSyncThresholdTests.swift:108-109`
- `PraticheConnectorTests.swift:99, 131`
- `PraticheControllerTests.swift:238, 307, 524`
- `PraticheSettingsTests.swift:75-76`
- `RecordingsViewModelTests.swift:96-97, 107, 171`
- `TaskMarkerTests.swift:172-174`
- `VaultBoundaryCallSiteTests.swift:88, 236, 375`
- `VaultDiskTests.swift:27, 58` (the `MARK` lines), `:132`

These stay: design rationale, or feature vocabulary.

- `PraticaSyncAttachmentTests.swift:31`
- `PraticaSyncIntegrityTests.swift:226`
- every «placeholder» in `PraticaSyncInlineImageTests.swift`
- `VaultWalkTests.swift:92`

A hit the coder cannot classify from the code is kept and listed in the task report. Do not guess.

### Task 5 — The eleven documents qualify their first ADR-0155 mention (R-08)

Only the first mention per file changes. The literal «retired concept-to-code workflow» goes on the
same line as that mention, or on the next line, so the Acceptance check can find it. No other
sentence changes; later mentions stay. Forms, adapted to the grammar:

- «(ADR-0155)» becomes «(ADR-0155 of the retired concept-to-code workflow, not a Pergamenum ADR)»;
- «**ADR-0155** (on a …» becomes «**ADR-0155** (the retired concept-to-code workflow's ADR, not a
  Pergamenum one: on a …»;
- «(ADR-0155 — the declaration is …» becomes «(ADR-0155 of the retired concept-to-code workflow, not
  a Pergamenum ADR — the declaration is …».

The first mentions:

- `docs/adr/0036-pratiche.md:596`
- `docs/adr/0040-pratiche-attachment-reliability-bugs.md:40` (`:244` stays)
- `docs/adr/0042-pratiche-inline-image-placeholders.md:52`
- `docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md:72`
- `docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md:75`
- `docs/superpowers/plans/2026-09-09-pratiche.md:85`
- `docs/superpowers/plans/2026-09-10-pratiche-pg105-pg108.md:84`
- `docs/superpowers/plans/2026-09-11-pratiche-attachment-reliability-bugs.md:103`
- `docs/superpowers/plans/2026-09-12-pratiche-inline-image-placeholders.md:149`
- `docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md:37` (`:101` stays)
- `docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md:58` (`:190` stays)

0036, 0040 and 0042 also take a status-line edit in Task 6. R-08's «no other sentence changes» is
about this task's edit.

### Task 6 — Status lines for the 25 ADRs (R-09, R-10)

The form is kept per file (D2). In each case the old status statement goes: every continuation line
of the bullet, and the whole first paragraph under `## Status`, except 0023's second sentence.

- **Plain bullet** (`- Status: …`): 0017, 0029–0034, 0036, 0040, 0042, 0044, 0050, 0054–0059.
- **Bold bullet** (`- **Status:** …`): 0022, 0026.
- **`## Status` section**, first paragraph: 0023, 0024, 0025, 0027, 0028. For 0023, only
  «Proposed — 2026-08-25.» is replaced; «Supersedes **ADR-0022 §D8** on one point only: …» stays.
  For 0024 and 0025, «To be accepted at Gate 2 of the … chain.» goes too. The «Supersedes …»
  paragraphs below stay.

Landing evidence, read from git on 2026-09-26. Method: the oldest commit that added the file on
`origin/main` (`git log --diff-filter=A`), then the oldest commit of
`git rev-list --first-parent origin/main` that contains it (binary search with
`git merge-base --is-ancestor`). The brief's `--ancestry-path` form returns nothing when combined
with `--first-parent` for 19 of the 25, which is why the ancestor search was used. Every hash below
is on `origin/main`'s first-parent line, and its subject names the PR.

| ADR | File added in | Landed on `main` (first-parent) | Date |
|---|---|---|---|
| 0017 | `5b09c3b` | PR #82, merge `336d8b3` (record only); implementation PR #83, merge `9fe5a45` | 2026-08-21 / 2026-08-22 |
| 0022 | `b477209` | PR #104, merge `cc4c372` | 2026-08-25 |
| 0023 | `3881c1d` | PR #105, merge `71e45ad` | 2026-08-25 |
| 0024 | `ebcec59` | PR #106, merge `f110cdd` | 2026-08-26 |
| 0025 | `efcd5c1` | PR #109, merge `a6648d1` | 2026-08-28 |
| 0026 | `7ada68c` | PR #109, merge `a6648d1` (implementation included) | 2026-08-28 |
| 0027 | `c29f9b3` | PR #111, merge `2ea6a0c` | 2026-08-29 |
| 0028 | `b46427b` | PR #113, merge `6a47ea5` | 2026-08-30 |
| 0029 | `c2f24e7` | PR #164, merge `b171a90` | 2026-09-03 |
| 0030 | `87df7e4` | PR #167, merge `6e5b5f9` (record only, via the Sparkle branch); implementation PR #169, merge `1c254fa` | 2026-09-04 / 2026-09-05 |
| 0031 | `68e1d4c` | PR #167, merge `6e5b5f9` | 2026-09-04 |
| 0032 | `a07707f` | PR #170, merge `07badd5` | 2026-09-06 |
| 0033 | `51066f5` | PR #178, merge `0bec334` | 2026-09-07 |
| 0034 | `eda7903` | PR #179, merge `0c47d3a` | 2026-09-08 |
| 0036 | `8fb5c6b` | PR #196, merge `ab36722` | 2026-09-11 |
| 0040 | `ce7f529` | PR #199, merge `9f6ff14` | 2026-09-11 |
| 0042 | `49b110f` | PR #250, merge `f9dc424` | 2026-09-12 |
| 0044 | `0520807` | PR #261, merge `41939a6`, with `.github/workflows/ci.yml` | 2026-09-14 |
| 0050 | `8d8c997` | PR #310, merge `56c5fdc` | 2026-09-18 |
| 0054 | `c14ac44` | PR #396, merge `cc60ca6` | 2026-09-22 |
| 0055 | `fc44f30` | PR #409, merge `1a0596b` | 2026-09-22 |
| 0056 | `616c5ad` | PR #453, squash commit `616c5ad` (no merge commit) | 2026-09-24 |
| 0057 | `adc7297` | PR #488, merge `242b907` | 2026-09-24 |
| 0058 | `12ccb00` | PR #500, merge `b390000` | 2026-09-25 |
| 0059 | `6f45016` | PR #508, merge `851dcd2` | 2026-09-25 |

The texts. Avoid the word «proposed» anywhere in the new status statement, because the Acceptance
check reads it.

- **Plain bullet:** ``- Status: accepted. Landed on `main` via PR #NNN (merge `sha`, YYYY-MM-DD).``
- **0017:** ``- Status: accepted. This record landed on `main` via PR #82 (merge `336d8b3`,
  2026-08-21); its implementation (`PG-004`) via PR #83 (merge `9fe5a45`, 2026-08-22).``
- **0030:** ``- Status: accepted. This record reached `main` via PR #167 (merge `6e5b5f9`,
  2026-09-04), whose branch carried it; its implementation via PR #169 (merge `1c254fa`,
  2026-09-05).``
- **0044** (Edge case: the line is replaced, §D13 stays): ``- Status: accepted. The workflow it
  decides, `.github/workflows/ci.yml`, landed on `main` with this record via PR #261 (merge
  `41939a6`, 2026-09-14); §D13 is the decision as written before the workflow existed.``
- **0056:** ``- Status: accepted. Landed on `main` via PR #453 (squash commit `616c5ad`,
  2026-09-24).``
- **0022:** ``- **Status:** Accepted. Landed on `main` via PR #104 (merge `cc4c372`,
  2026-08-25).`` Its superseded-in-part notes from ADR-0024 and ADR-0025 stay.
- **0026:** ``- **Status:** Accepted (2026-08-27). Implemented and landed on `main` via PR #109
  (merge `a6648d1`, 2026-08-28); plan:
  `docs/superpowers/plans/2026-08-27-drag-and-drop-board-files-into-workspace.md`.``
- **`## Status` form:**
  - 0023: ``Accepted — dated 2026-08-25; landed on `main` via PR #105 (merge `71e45ad`,
    2026-08-25).``, followed by its unchanged «Supersedes …» sentence;
  - 0024: ``Accepted — dated 2026-08-25; landed on `main` via PR #106 (merge `f110cdd`,
    2026-08-26).``;
  - 0025: ``Accepted — dated 2026-08-27; landed on `main` via PR #109 (merge `a6648d1`,
    2026-08-28).``;
  - 0027: ``Accepted — landed on `main` via PR #111 (merge `2ea6a0c`, 2026-08-29).``;
  - 0028: ``Accepted — landed on `main` via PR #113 (merge `6a47ea5`, 2026-08-30).``.

Nothing else in the 25 files changes in this task. Other accepted ADRs are not normalised (SPEC
Decision).

### Task 7 — ADR-0059 §D10's amendments and the ADR-0038 changelog note (R-01, R-02, R-03, R-12)

- **`docs/20260811_Pergamenum_SpecApp.md:396`** (§9, `note?id=` row). Append inside the «Azione»
  cell, after the original text, in the form `:54` already uses:

  ```markdown
   — *Emendato 2026-09-25 (ADR-0059): l'ID è registrato nel file di registro degli ID del vault, `.pergamenum/note-ids.json`, non nel frontmatter né nell'indice; segue ogni rinomina e spostamento fatti dall'app ed è stabile finché il file non viene rinominato fuori dall'app.*
  ```

- **`docs/20260811_Pergamenum_SpecApp.md:512`** (§14, Frontmatter row). Append inside the
  «Motivazione» cell, after «non nei file»:

  ```markdown
   — *Emendato 2026-09-25 (ADR-0059): l'ID per gli URL è registrato in `.pergamenum/note-ids.json`, il registro degli ID del vault, non nel frontmatter né nell'indice; segue ogni rinomina e spostamento fatti dall'app ed è stabile finché il file non viene rinominato fuori dall'app.*
  ```

  Both original sentences stay readable. §4.1's tree is not touched (ADR-0059 §D10). This is the
  app-spec HITL gate, satisfied by the SPEC's approval and `/ship`'s commit gate.
- **`docs/adr/0001-initial-architecture.md`**:
  - Head: after the three bullets (lines 3–5), add a blank line and then:

    ```markdown
    **Scope note (2026-09-25, ADR-0059):** the id behind `pergamenum://note?id=` no longer lives in
    the index; ADR-0059 moved it to `.pergamenum/note-ids.json`, a registry file in the vault. §D2's
    last paragraph carries the amendment inline. The rest of the decision below stands as taken.
    Body otherwise untouched.
    ```

  - §D2's last paragraph (lines 73–76): after «live in the index» insert
    ``*(amended 2026-09-25, ADR-0059: they live in `.pergamenum/note-ids.json`, the vault's note-id
    registry, not in the index)*``. The rest of the paragraph stays: not in frontmatter, and stable
    only while the file is not renamed outside the app, both still hold per ADR-0059. No other line
    of the file changes.
- **`PROJECT_BRIEF.md:54-55`** (the §14 summary, English). After «than in files» insert
  ``*(amended 2026-09-25, ADR-0059: the ids live in the vault's registry
  `.pergamenum/note-ids.json`, not in the index nor in the frontmatter)*``. Do not reflow the
  neighbouring lines.
- **`PROJECT_BRIEF.md`, 2026-08-13 «Every section has its toolbar» entry** (lines 1189–1198, English).
  Add one continuation line at its end, after «cannot be given one.», indented two spaces:

  ```markdown
    *Note (2026-09-26): the Conformità pane and its «Verifica conformità» command were removed on
    2026-09-11 by ADR-0038 (PR #195, `6a89a9a`); `perg lint` and the MCP `lint_note`/`lint_vault`
    tools remain.*
  ```

  The entry's own sentences do not change. The connector tool list at `:1099` («conformità» there
  means the MCP lint tools) stays. The tool names were read from `Sources/CLI/main.swift:21` and
  `Sources/MCPServer/ToolCatalogue.swift:145,155`. `6a89a9a` is a first-parent squash commit whose
  subject names PR #195.

### Task 8 — The ADR directory README, the CLAUDE.md pointer and the ledger (R-11, R-13, R-14, R-15)

- **New `docs/adr/README.md`**, text to copy:

  ```markdown
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

  - A number this directory holds always means the file here.
  - An ADR this directory does not hold is cited with its origin in the same sentence, for example
    ADR-0155 of the retired concept-to-code workflow, not a Pergamenum ADR.

  ## Renumbering register

  | Old | New | Date | Reason |
  |---|---|---|---|
  | 0061 (`0061-external-deletion-reaches-the-tabs-and-the-diary.md`) | 0064 | 2026-09-26 | Two ADRs took 0061 on 2026-09-25. The merge-integrity guard (PR #529) landed first and keeps 0061, which `scripts/check-merge-integrity.py`, the pre-push hook, `merge-integrity.yml` and ADR-0062 cite. The external-deletion record (PR #530) moved to the next free number; 0063 was already ADR-0063. Issue #581. |
  ```

- **`CLAUDE.md`**: one line, directly under `## Chain decision index` (line 460), followed by a
  blank line: ``ADR conventions (one number per file, the status line, citing an ADR from outside
  this repo) and the renumbering register: `docs/adr/README.md`.`` No chain-index line is added,
  because there is no new ADR.
- **`TODO.md`, `PG-156`** (line 117 before the merge; find it by id). It is closed in place, the way
  PR #591 closed `PG-096`: not moved, and its two sub-bullets stay.
  - `- [ ]` becomes `- [x]`.
  - After the file list, before the marker, append: ``· Closed 2026-09-26: already fixed by
    ADR-0033 (PR #178, merged 2026-09-07), which renders `pergamenum-view` fences live in the editor
    through an `NSHostingView` attachment reusing `RenderedViewBlock`; the «board surface outside
    the text flow» idea lives in `ROADMAP.md` chain 16 item 2. Closed by hand in chain 14 (#581).``
  - The marker becomes `<!-- src:session opened:2026-09-06 kind:roadmap closed:2026-09-26 adr:0033
    pr:178 -->`.
- **`TODO.md`, new entry:** first line under `## Open Issues`, above `PG-272`. The id is `PG-273`,
  or `lastId + 1` after the merge (Before `/build`, item 1). Line 1 becomes
  `<!-- project-tasks: prefix=PG lastId=273 -->`. The `Updated:`/`Open:` line and `PG-267` stay
  untouched (SPEC Edge cases; the post-merge sync does both). Recommended text, which carries D6's
  measured baseline:

  ```markdown
  - [ ] `PG-273` **P4** [chore] ADR reference-check script, the follow-up of Audit Fable chain 14 (#581, `docs/plans/chain-14-docs-consistency.md`): one self-tested command under `scripts/` that fails when two files under `docs/adr/` share a number, when an `ADR-NNNN` cited in `Sources`, `Tests` or `docs` resolves to no file there and carries no origin qualifier, and when a status line reads `proposed` while its implementation is on `main` — the three rules `docs/adr/README.md` writes down, checked by hand in chain 14. Its first run will meet a measured baseline: unqualified ADR-0073 (4 test files), ADR-0068 (37 manifests), ADR-0138/0154/0158 (superpowers plans, `docs/specs/pg-066-*`), ADR-0159 (`PROJECT_BRIEF.md:329`), ADR-0066 (`TODO.md`), and ADR-0053 cited by ADR-0040/0042 in the retired workflow's sense while this directory's 0053 is a different record, a collision a resolve-only check cannot see <!-- src:session kind:chore opened:2026-09-26 -->
  ```

- **Final verification (R-15):** run the whole Acceptance block. The `Stop` hook's
  `.claude/test-cmd` build must be green on the last turn.

---

## Requirement coverage

| R-id | Task(s) |
|---|---|
| R-01 | 7 |
| R-02 | 7 |
| R-03 | 7 |
| R-04 | 1 |
| R-05 | 1 |
| R-06 | 2 |
| R-07 | 3, 4 |
| R-08 | 5 |
| R-09 | 6 |
| R-10 | 6 |
| R-11 | 8 |
| R-12 | 7 |
| R-13 | 8 |
| R-14 | 8 |
| R-15 | 3, 4, 8 |

Every R-id the SPEC declares is cited; the SPEC's `(no-test: …)` markers exempt the test axis only.

## Acceptance (reviewer; bash, from the repo root, after `git fetch origin`)

Run under `bash`, not zsh: several loops rely on word splitting.

```bash
# R-01
grep -n 'note?id=<uuid>' docs/20260811_Pergamenum_SpecApp.md | grep -c 'Emendato 2026-09-25 (ADR-0059)'   # 1
grep -n '^| Frontmatter |' docs/20260811_Pergamenum_SpecApp.md | grep -c 'Emendato 2026-09-25 (ADR-0059)' # 1
grep -c 'registrato nell.indice, non nel frontmatter' docs/20260811_Pergamenum_SpecApp.md                 # 1 (original readable)
grep -c 'vive nell.indice, non nei file' docs/20260811_Pergamenum_SpecApp.md                               # 1 (original readable)

# R-02
sed -n '1,14p' docs/adr/0001-initial-architecture.md | grep -c 'Scope note (2026-09-25, ADR-0059)'        # 1
sed -n '/^### D2/,/^### D3/p' docs/adr/0001-initial-architecture.md | grep -c 'note-ids.json'             # >= 1
git diff -U0 origin/main...HEAD -- docs/adr/0001-initial-architecture.md | grep '^@@'                     # 2 hunks: head (after :5) and the §D2 paragraph (~:73)

# R-03
grep -n -A1 'note IDs living in the index' PROJECT_BRIEF.md | grep -c 'ADR-0059'                           # 1

# R-04
ls docs/adr | grep -E '^[0-9]{4}-' | cut -c1-4 | sort | uniq -d                                            # empty
ls docs/adr/0061-* docs/adr/0064-*                                                                         # 0061-merge-integrity-guard.md, 0064-external-deletion-…md
head -1 docs/adr/0064-external-deletion-reaches-the-tabs-and-the-diary.md | grep -c '^# ADR-0064:'          # 1
git log --follow --format=%h -- docs/adr/0064-external-deletion-reaches-the-tabs-and-the-diary.md | grep -cE '^(319ca32|c2cf19b)'  # 2
git diff -M --name-status origin/main...HEAD | grep '^R'                                                   # exactly the 0061-external → 0064-external rename

# R-05
grep -c 'Renumbering note' docs/adr/0061-merge-integrity-guard.md docs/adr/0064-external-deletion-reaches-the-tabs-and-the-diary.md  # 1 and 1
diff <(git show origin/main:docs/adr/0061-external-deletion-reaches-the-tabs-and-the-diary.md) docs/adr/0064-external-deletion-reaches-the-tabs-and-the-diary.md   # only line 1 changed plus the added note
diff <(git show origin/main:docs/adr/0061-merge-integrity-guard.md) docs/adr/0061-merge-integrity-guard.md    # only the added note

# R-06
grep -rn 'ADR-0061' Sources Tests                                                                          # empty
grep -n '0061' docs/plans/pg-234-external-deletion.md                                                      # 1 line: the head «Renumbered» bullet
grep -n 'ADR-006[14]\*\*' CLAUDE.md                                                                        # :500 ADR-0061 (PG-240), :504 ADR-0064 (PG-234), order unchanged
grep '`PG-234`' TODO.md | grep -c 'adr:0064'                                                               # 1
grep '`PG-234`' TODO.md | grep -c 'ADR-0061\|adr:0061'                                                     # 0
grep -n 'post-ADR-006' ROADMAP.md                                                                          # post-ADR-0064
sed -n '20p' docs/adr/0063-connector-input-hardening.md | grep -c '0054/0055/0058/0064'                    # 1
grep -rn '0061' docs CLAUDE.md TODO.md ROADMAP.md PROJECT_BRIEF.md \
  | grep -v -e 'docs/adr/0062-' -e 'docs/plans/pg-242-landing-check.md' -e 'docs/plans/chain-14-docs-consistency.md'
# every remaining hit is on this allowlist (merge guard, or the duplicate itself):
#   docs/adr/0061-merge-integrity-guard.md (title, renumbering note); docs/adr/0064-… (Numbering note :19-20, renumbering note);
#   docs/adr/0063-…:14,16; docs/adr/README.md (register); docs/plans/connector-input-hardening.md:68,545;
#   docs/plans/pg-234-external-deletion.md (head bullet); CLAUDE.md:145,147,227,500,501;
#   TODO.md PG-267, PG-246, PG-251, PG-244, PG-242, PG-241, PG-240; ROADMAP.md:946-947

# R-07
grep -rn 'ADR-0155' Sources Tests                                                                          # empty
git diff -U0 origin/main...HEAD -- Sources Tests \
  | grep -E '^[-+]' | grep -vE '^(\+\+\+|---) ' | grep -vE '^[-+][[:space:]]*(//|\*|/\*|$)'               # empty: comment or blank lines only
files=$(git grep -l 'ADR-0155' origin/main -- Sources Tests | sed 's#^origin/main:##')                    # the 54 files
grep -nE "^\s*(//|///|\*).*(stub|wrong-but-safe|[^a-z]red[^a-z]|RED|expected to fail|until the coder|fails until|coder (fills|wires|extracts|implements|builds|replaces|may refine)|coder's (Task|job|work|bod|implementation)|does not exist yet|not yet|genuinely red)" $files
# every remaining hit is one of Task 4's «stays» lines, or is listed in the task report with its reason

# R-08
for f in $(grep -rl 'ADR-0155' docs); do grep -m1 -A1 'ADR-0155' "$f" | tr '\n' ' ' | tr -s ' ' | grep -q 'retired concept-to-code workflow' || echo "UNQUALIFIED: $f"; done   # empty
git diff -U0 origin/main...HEAD -- docs/superpowers/plans | grep -c '^@@'                                  # 8 (one hunk per plan)

# R-09
for f in docs/adr/[0-9]*.md; do
  s=$(awk '/^## Status/{h=1;next} h&&NF{print;exit} /^- (\*\*)?Status(:\*\*|\*\*:|:)/{print;exit}' "$f")
  [ -z "$s" ] && { echo "NO STATUS: $f"; continue; }
  printf '%s' "$s" | sed -E 's/^- (\*\*)?Status(:\*\*|\*\*:|:)[[:space:]]*//' | grep -qiE '^(\*\*)?accepted' || echo "NOT ACCEPTED: $f"
  b=$(awk '/^## Status/{h=1;next} h&&NF{p=1} h&&p&&!NF{exit} h&&p{print;next} /^- (\*\*)?Status(:\*\*|\*\*:|:)/{s=1;print;next} s&&/^  /{print;next} s{exit}' "$f")
  printf '%s' "$b" | tr '\n' ' ' | tr -s ' ' | grep -qiE 'pending|not implemented|awaiting|to be accepted|when that branch merges' && echo "STALE: $f"
done; true   # empty; the output is the verdict, not the exit status (a dry run on the pre-chain tree flags exactly the 25)

# R-10 (scoped to the 25 lines this chain writes, D5)
fp=$(git rev-list --first-parent origin/main)
for n in 0017 0022 0023 0024 0025 0026 0027 0028 0029 0030 0031 0032 0033 0034 0036 0040 0042 0044 0050 0054 0055 0056 0057 0058 0059; do
  f=$(ls docs/adr/$n-*.md)
  b=$(awk '/^## Status/{h=1;next} h&&NF{p=1} h&&p&&!NF{exit} h&&p{print;next} /^- (\*\*)?Status(:\*\*|\*\*:|:)/{s=1;print;next} s&&/^  /{print;next} s{exit}' "$f")
  prs=$(printf '%s' "$b" | grep -oE '#[0-9]+' | tr -d '#')
  shas=$(printf '%s' "$b" | grep -oE '`[0-9a-f]{7,40}`' | tr -d '`')
  [ -z "$shas" ] && echo "NO HASH: $n"
  for sha in $shas; do
    full=$(git rev-parse --verify -q "$sha^{commit}") || { echo "UNKNOWN: $n $sha"; continue; }
    printf '%s\n' "$fp" | grep -qx "$full" || echo "NOT FIRST-PARENT: $n $sha"
    subj=$(git log -1 --format=%s "$full"); ok=0
    for pr in $prs; do printf '%s' "$subj" | grep -qE "(pull request #$pr |\(#$pr\)$)" && ok=1; done
    [ $ok = 1 ] || echo "HASH NAMES NO CITED PR: $n $sha"
  done
done; true   # empty; the output is the verdict, not the exit status (the table in Task 6 passes this logic, checked 2026-09-26)

# R-11
grep '`PG-156`' TODO.md | grep -E '^- \[x\]' | grep -c 'ADR-0033.*PR #178.*2026-09-07.*closed:2026-09-26'  # 1
git diff origin/main...HEAD -- TODO.md | grep -E '^[-+]Updated:'                                           # empty (counts untouched)
grep '`PG-267`' TODO.md | grep -c '^- \[ \]'                                                               # 1 (still open)

# R-12
awk '/^- 2026-08-13: \*\*Every section has its toolbar/,/^- 2026-08-13: \*\*Builds are numbered/' PROJECT_BRIEF.md | grep -c 'ADR-0038'  # 1
git diff -U0 origin/main...HEAD -- PROJECT_BRIEF.md | grep -E '^-[^-]'                                     # exactly 1 line: the §14 summary line (R-03); nothing from the changelog
grep -c 'giornata, conformità, statistiche' PROJECT_BRIEF.md                                               # 1 (untouched)

# R-13
test -f docs/adr/README.md && grep -cE '^## (1|2|3)\.|^## Renumbering register' docs/adr/README.md         # 4
grep -E '^\| *0061' docs/adr/README.md | grep -c '0064'                                                    # 1
grep -c 'docs/adr/README.md' CLAUDE.md                                                                     # 1

# R-14
head -1 TODO.md                                                                                            # lastId=273 (or the id actually used)
grep '`PG-273`' TODO.md | grep -c '\*\*P4\*\*.*#581'                                                       # 1

# R-15
git diff --stat origin/main...HEAD -- scripts .github Project.swift Tuist                                   # empty
git diff --name-only origin/main...HEAD | grep -vE '\.(md|swift)$'                                         # empty
scripts/check-merge-integrity.py --landing origin/main HEAD                                                 # exit 0 (ADR-0062)
# and .claude/test-cmd green on the last turn (Stop hook)
```

The R-07 diff filter differs from the one-line form in the brief on purpose. It also accepts blank
lines, because deleting a whole comment paragraph removes its separating blank line, and a blank
line is not a statement.

## Out of scope, measured and left

- Stale «red» sentences in files that do not cite ADR-0155 (`Tests/DiaryWatcherReloadTests.swift:48`,
  `Tests/ExternalDeletionReconcileTests.swift:95`, and any other): SPEC Out of scope, second bullet.
- Every non-ADR-0155 unqualified citation and the ADR-0053 collision (D6): baseline of the new
  ledger entry.
- The renumbered ADR's `c2cf19b` status citation (D5).
- ADR-0049's accepted status line still reads «proposed for the `feat-note-project` branch». It
  starts with `accepted`, it is not in the SPEC's class, and it says nothing false about the
  implementation. Left, per the SPEC's «no normalising».
- ADR-0059's gate E (the `NoteIDRegistry` protected-interface entry): not this chain.

## Risks and HITL gates

- **HITL:**
  - G1 (the departures above);
  - every commit, with the rename committed alone first;
  - the push, where the pre-push hook runs ADR-0061's merge check and ADR-0062's landing check;
  - `/ship`'s diff review, which is also the app-spec gate that ADR-0059 §D10 requires.
  - No deploy, no schema change, no deletion: the rename removes no content.
- **Ledger race.** Another session may take `PG-273` or edit `TODO.md` between the merge in item 1
  and this PR's merge. Re-read `lastId` just before committing Task 8. The post-merge sync owns the
  header counts and `PG-267`, and the PR body should carry `Closes #581` so the sync can close it.
- **ADR-number race.** A parallel chain could land a new ADR-0064 before this PR. Before the merge,
  check `git ls-tree origin/main docs/adr/ | grep ' docs/adr/0064-'`. If it is taken, the register
  entry and every Task 1/2 edit move to the next free number: redo Task 2 with that number, never
  leave two 0064 files.
- **Chain 13 overlap.** `PG-266` (dead code, ADR-0038 residues) may touch the same Pratiche or
  Conformità comments. Merge `origin/main` again before the push if it lands first, and re-run
  R-07's checks.
- **A comment edit that breaks the build.** The main way this happens is an unterminated `/*`, or a
  doc comment left dangling before an attribute. The Stop hook's unit build catches it, and CI
  builds all three targets on the PR (ADR-0044). The shared files (`Sources/Core/**`,
  `Sources/Vault/*`) compile in the app target too, so the unit build covers `perg` and
  `pergamenum-mcp` for comment-only edits.
- **Landing check.** Each edited file gets a blob it never held, and the renamed path is new, so
  `--landing` passes. If it ever flags a path, investigate. Never add `Restore-override` to get past
  it.
- **Judgement in Task 4.** Some «not yet» or «red» sentences need a check against the code
  (`EmbedResolutionTests`, `MarkupHidingTests:1058`, `PraticaLedgerTests`). When a sentence is still
  true it stays, rephrased without workflow words. Anything unclear is kept and reported, never
  deleted on a guess.
- No externally provisioned resource is needed: no API, no console, no env var.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield
