**Requirement set:** `SPEC.md`

# Note workflow N3, links: the mockup PR

Milestone N3 of the note-workflow chain (`PG-386`, issue #888), mockup half. SPEC (root, Approved
2026-10-04), Decision "Mockups ship first, as their own PR per milestone": the person approves the
DesignGallery mockup on the Debug build, then the code PR (`docs/plans/note-workflow-n3.md`) is
built. ADRs: `docs/adr/0083-links-answer-to-the-pointer-and-the-keyboard.md` and
`docs/adr/0084-backlinks-with-context-unresolved-per-note-mentions-that-link.md`, both proposed.
They land with this PR, so the person reads the decisions beside the screens.

**Assumes merged:** N1 (ADR-0080, PG-219's pointer, the `[[` completion rule of R-03) and N2
(ADR-0081, ADR-0082, the styler). This PR touches nothing either of them changes: DesignGallery
files only, literal content, no controller, no index, no vault. If N1 or N2 added cases to
`MockupGalleryView.Screen`, this PR's two cases go after theirs.

**Written against:** `origin/main` at `48a2d912` (2026-10-04).

**ADR outcome:** the two ADRs above are new, written by this planning pass (status proposed). This
plan writes no further ADR. The mockup's own approval is recorded the way the gallery records it,
with the page's milestone label changing from «N3, da approvare» to «N3, approvato» in the code PR.

**How the person approves.** Build the Debug app, open Impostazioni ▸ Design system ▸ «Mostra i
mockup…», and check the three N3 pages in the light theme and in the dark theme. Every colour and
font goes through a token (CLAUDE.md binding rule), so the dark check is a real check.

## Tasks

### Task 1 — Mock the link preview, the choice of several notes and «Crea «X»» (R-20, R-22, R-23)

Owner: coder
Files: Sources/Features/DesignGallery/LinkPreviewMockup.swift, Sources/Features/DesignGallery/MockupGalleryView.swift
Tests: MockupGalleryLayoutTests.swift
Signatures:
- LinkPreviewMockup — `struct LinkPreviewMockup: View`
- MockupGalleryView.Screen.linkPreview — `case linkPreview`, page `Page("Link", "N3, da approvare", LinkPreviewMockup())`
Red: no

A new page in the gallery, the shape every mockup there has (`MockupPage`, `MockupScene`, sizes
from `MockupGalleryView.rowWidth`/`pairWidth`, never guessed: `MockupGalleryLayoutTests` pins the
arithmetic). Literal content only. What the page shows, each scene captioned with the rule it makes
visible (ADR-0083 §D7, §D5, §D6):

1. **The preview over a note line.** An editor line with `[[Riunione settimanale]]`, the pointer on
   it, Command held (a caption says so), and the preview panel below the line: the target's title,
   then its first twelve body lines, cut with a fade or an ellipsis (the person picks). Width and
   maximum height are the question here; propose 360 pt wide and twelve lines.
2. **The four other states of the same panel,** in a row of `pairWidth` cells: a heading section
   (`[[Riunione settimanale#Decisioni]]`), a missing section («Nessuna sezione «Decisioni»»), a board
   link (the board's name and its glyph, `square.grid.2x2`), several matches («3 note si chiamano
   «Riunione»» with the three folder labels), no match («Nessuna nota si chiama «Bozza»», «Cmd+clic
   per crearla»).
3. **No panel for an external link,** one line with a caption: the SPEC's edge case, drawn so its
   absence is a decision.
4. **The choice at a click.** A menu drawn under a link: a disabled header «Più note si chiamano
   «Riunione»», then one row per note labelled by its folder (`Clienti/Nexion`, `Progetti`,
   «radice del vault»). Drawn with SwiftUI shapes that imitate the system menu, as the other menu
   mockups do: the real one is an `NSMenu` and looks like the system's.
5. **The choice from the keyboard,** `LinkChoiceSheet`: title «Quale «Riunione»?», the same rows,
   Return opens the selected one, «Annulla». And the dangling case: the one row «Crea «Bozza»».
6. **The `[[` popup with no match,** the existing completion panel's look with its one new row,
   «Crea «Bozza»» (`plus.square` glyph), under a caption: shown only when nothing matches and the
   typed text is a valid title.

Cmd+Shift+click and Cmd+Opt+click have nothing to draw; the page's header text names them with the
two Vista items («Apri il link in una nuova tab», «Apri il link nell'altra colonna», no default key)
so the page is the whole of ADR-0083 at a glance. Keyboard shortcuts in the copy are written the
way the app writes them elsewhere in the gallery.

`MockupGalleryView.swift` gains the case and its one `page` line; nothing else in it changes.

### Task 2 — Mock the inspector: backlinks with context, unresolved per note, the structural sheet, «Dove compare» (R-24, R-25, R-27, R-28)

Owner: coder
Files: Sources/Features/DesignGallery/InspectorLinksMockup.swift, Sources/Features/DesignGallery/MockupGalleryView.swift
Tests: MockupGalleryLayoutTests.swift
Signatures:
- InspectorLinksMockup — `struct InspectorLinksMockup: View`
- MockupGalleryView.Screen.inspectorLinks — `case inspectorLinks`, page `Page("Ispettore: link", "N3, da approvare", InspectorLinksMockup())`
Red: no

The inspector at its real width (260 pt, `UnlinkedMentionsMockup.inspectorWidth`'s value and
comment), sections drawn as `TraySection` draws them today (caption title, count, rows), literal
content. Scenes (ADR-0084 §D1, §D2, §D4, §D6):

1. **BACKLINK with context.** Three rows: a title in the accent colour; under it the linking line in
   the secondary text colour, the link itself in the accent, one line, truncated at the tail; a
   count («3 link») only on the row that has more than one; the «strutturale» badge on the row whose
   `related` names the note. The badge's form (a word in a capsule, or a glyph with a tooltip) is the
   person's choice; propose the word.
2. **The row menu,** drawn open on a plain row (Apri, Apri nell'altra colonna, Rendi strutturale)
   and on the structural row (Apri, Apri nell'altra colonna, Scollega), so the two catalogues are
   seen side by side.
3. **«Scollega» asking first:** the confirmation «Scollegare «A» e «B»?», «Scollega» destructive,
   «Annulla».
4. **LINK NON RISOLTI for this note.** Two rows, each the target name with «Crea nota» and «Vai al
   link» as small trailing buttons; a third row for `[[Piano.md]]`, which is not a valid title,
   with «Vai al link» only. The empty state: «nessun link non risolto in questa nota».
5. **The structural sheet.** Target list with two «Riunione» rows told apart by their folder
   labels, one preselected (as «Rendi strutturale» opens it); the forward reason typed, the reverse
   reason mirroring it in the field's normal text, and a second cell showing the reverse field after
   the person edited it (no longer following). Whether the mirrored text looks different from typed
   text until it is edited (for example the placeholder colour) is a question for the person.
6. **DOVE COMPARE.** The resting state («Cerca dove compare», one sentence saying it reads boards and
   pratiche), the scanning state, the results (BOARD: two board names with their glyph; PRATICHE: a
   pratica that links the note, and one message row under a pratica), the empty result («non compare
   in nessuna board né pratica»), «Cerca di nuovo». Beside it, one cell drawing the automatic
   alternative (results already there on opening), captioned as the open question: on request
   (ADR-0084 §D6's recommendation, ADR-0012 §D9's shape) or automatic.

### Task 3 — Mock «Collega» on an unlinked mention and its diff confirmation (R-26)

Owner: coder
Files: Sources/Features/DesignGallery/UnlinkedMentionsMockup.swift
Tests: MockupGalleryLayoutTests.swift
Signatures:
- UnlinkedMentionsMockup — `struct UnlinkedMentionsMockup: View`, existing; gains a «Collega» scene, no new type
Red: no

The existing «Menzioni» page gains its N3 half (ADR-0084 §D3):

1. **The row with «Collega».** The approved row (title, the line, the mention in the accent) gains a
   trailing «Collega» button. The existing «Apri» gesture (the row) stays.
2. **The confirmation sheet.** Title «Collegare «Curva di trasmissibilità» in «Prova banco»?», the
   diff drawn as `DiffView` draws it (one removed line, one added line with `[[…]]`), «Collega»
   default, «Annulla».
3. **The alias case.** The same sheet for a mention that matched an alias: the added line reads
   `[[Curva di trasmissibilità|curva T]]`, so the prose reads as before, with a caption saying why.
4. **The note moved on.** The sheet with its notice «La nota è cambiata: il confronto è stato
   aggiornato» above a recomputed diff.
5. **Nothing left to link.** The row's replacement sentence when the name went or a link arrived.

The page's doc comment changes with it: its third decision («A row opens the note and nothing
else») is marked amended by ADR-0084 §D3, with one sentence of the reason (the diff is the
guardrail the refusal asked for), the original text kept above the note so the history of the
decision reads in place. The page's milestone label goes from «M10» to «M10, N3 da approvare».

## Risks and HITL gates

- **HITL: mockup approval.** No view code of the N3 code PR starts until the person has approved the
  three pages on the Debug build, light and dark. The open questions the pages put: preview size and
  cut; badge form; mirrored text's look; «Dove compare» on request or automatic.
- **HITL: commit and push.** Branch `feature/note-workflow-n3-mockup` (or the chain's own naming),
  one commit for the two ADRs and the three pages, PR against `main`. Never on `main` directly.
- **Merge order.** N1's and N2's mockup PRs may each add a `Screen` case; a textual conflict in
  `MockupGalleryView.swift` is expected and resolved by keeping every case. The merge-integrity
  hook (ADR-0061/0062) refuses a resolution that drops one.
- **ADR numbering.** 0083 and 0084 were reserved by the dispatch and free on every ref on
  2026-10-04; rerun `git log --all -- 'docs/adr/0083*' 'docs/adr/0084*'` and
  `scripts/check-adr-references.py` (after `git fetch origin`) before the merge. Both ADRs cite
  ADR-0080..0082, which land with N1 and N2; the checker passes only once those are on `main`,
  which the milestone order guarantees.
- **No test is red-first here.** The gallery is checked by eye; the one test that touches it,
  `MockupGalleryLayoutTests`, pins the row arithmetic and stays green as long as the new pages size
  their cells from the gallery's constants.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE

No static check is declared that passes on `main`: SwiftLint fails there by design on seven types
(`.swiftlint.yml`, `.github/workflows/ci.yml`'s header), so any `swiftlint lint` form would make the
stop-gate red before the suite runs. The type check is the build inside the test command.
