**Requirement set:** `SPEC.md`

# Plan: N4 mockup, the birth of a note in the DesignGallery

- **SPEC:** root `SPEC.md` (Approved 2026-10-04), milestone N4 (issue #889, ledger `PG-387`). The
  Decisions bullet "Mockups ship first, as their own PR per milestone" makes this its own PR, and
  the person approves it on the Debug build before any N4 code is written (R-44).
- **ADRs:** `docs/adr/0085-a-da-classificare-pane-for-notes-and-one-composer.md` and
  `docs/adr/0086-templates-where-notes-are-born.md`, both `proposed`. The mockup draws what they
  decide, and the variants below are what they leave to the person.
- **Depends on:**
  - N1's rule, ADR-0080 §D1, planned in `docs/plans/note-workflow-n1.md`: every note born with no
    `topic-*` carries `status-inbox`. It is what fills the pane drawn here.
  - N1's inbox-folder setting, `VaultSettings.inboxFolder`, ADR-0080 §D6, default `00 Inbox`.
  - The mockup is static and reads neither of them. Its sample rows assume both: captures sit in
    `00 Inbox` and wear `status-inbox`.
- **Base:** `48a2d912`. Code plan: `docs/plans/note-workflow-n4.md`.
- **Scope:** DesignGallery only. No controller, no session, no production view is touched. Every
  colour, font and spacing goes through a token (CLAUDE.md design-system rule). The sheet frame is
  780 pt, so each scene fits `MockupGalleryView.contentWidth` (720 pt).

## Tasks

### Task 1 — The «Da classificare» pane and the creation toast (R-29, R-34)
Owner: coder
Files: Sources/Features/DesignGallery/NoteBirthMockup.swift, Sources/Features/DesignGallery/NoteBirthMockupPieces.swift, Sources/Features/DesignGallery/MockupGalleryView.swift
Tests: MockupGalleryLayoutTests.swift
Signatures:
- NoteBirthMockup — struct NoteBirthMockup: View
- MockupGalleryView.Screen.noteBirth — case noteBirth, page Page("Nascita di una nota", "N4, da approvare", NoteBirthMockup())
Red: no

Add the page and its first two groups of scenes, each a `MockupScene` on a `MockupPage`.

- **4a, the sidebar.** The LAVORO group, light and dark, with «Da classificare» after «Attività».
  - Variant A: no count.
  - Variant B: a count badge. If B is chosen, the production row puts `.badge` before `.tag`, the
    `RootView.swift` trap ADR-0085 §D2 names.
  - A third picture shows the row first in LAVORO, so the person can choose the position.
- **4b, the pane.**
  - The header «Da classificare · 6» and the folder filter («Tutte le cartelle», `00 Inbox · 4`,
    `Calendar · 1`, `Contenitore/2026 · 1`).
  - Six flat rows: title, folder in secondary text, date. One row is a Contenitore scheda with its
    document glyph, per ADR-0085 gate G1.
  - One selected row, and the row menu drawn beside it: «Classifica…», «Apri», «Apri in una nuova
    tab», «Mostra nel Finder», plus «Mostra nel Contenitore» on the scheda row.
  - The empty state «Niente da classificare.»
  - Two layouts for the person to choose: Variant A is the list alone, and Variant B is the list
    plus a read-only preview of the selected note's opening lines.
  - The rows are ordered newest first (ADR-0085 §D2). A caption asks whether oldest first reads
    better as a queue.
- **4e, the toast.**
  - «Nota creata · Annulla» over the bottom edge of an editor page, light and dark.
  - The refused state: «La nota ha modifiche non salvate: resta dove è.»
  - The same strip at the same height in both states. ADR-0085 §D9 forbids a height change, after
    ADR-0075's `HSplitView` crash.

Add `noteBirth` to `MockupGalleryView.Screen`, in both the `case` list and the `page` switch. The
other milestones' mockup PRs add their own cases to the same enum, so a conflict there is expected.
Resolve it by keeping every case.

### Task 2 — The «Classifica» sheet and the composer as a sheet (R-30, R-32, R-33, R-44)
Owner: coder
Files: Sources/Features/DesignGallery/NoteBirthMockup.swift, Sources/Features/DesignGallery/NoteBirthMockupPieces.swift
Tests: MockupGalleryLayoutTests.swift
Signatures:
- NoteBirthMockup — struct NoteBirthMockup: View (scenes 4c and 4d added)
Red: no

- **4c, «Classifica», note subject.**
  - Topic chips (`topic-materiali`, `topic-fornitori`) and a completion list of used topics with
    their counts.
  - A typed value refused in place: «area-xyz non è nel vocabolario», and «Classifica» disabled.
  - The folder picker set to `03 Risorse`.
  - A frontmatter preview with `status-inbox` struck through, and «4 di 7 tag».
  - The dirty-note variant, whose confirm reads «Salva e classifica» with a one-line explanation
    (ADR-0085 gate G2).
  - Beside it, the scheda subject as it is today, with topics, the content-type picker and no
    folder, so the person sees the two forms side by side.
- **4d, the composer as a sheet.**
  - The Workspace «Documento» host: title field, the folder shown as a fixed label «In:
    Progetti/Alfa», the tag field with `topic-`, `client-` and `project-` chips and a completion
    list, a blocked closed-family value («type-…» non si sceglie qui), the template menu, and
    «Crea».
  - The «Estrai» host: the title prefilled from the selection's first line, the selection previewed
    in a quiet box, no template menu, and «Salva ed estrai» when the source is dirty.
  - The half-done state, in place: «Nota «X» creata, ma il collegamento in «Y» non è stato scritto:
    …», with «Chiudi».
  - The in-pane host is not redrawn: it stays exactly as it is today, apart from the tag field,
    which 4d shows.
- **Not mocked, named so the person can ask for them:**
  - The capture panel's template menu under «Nota nuova». It follows the panel's existing folder
    popover (`capture-folder`).
  - The «Modello della nota del giorno» picker in Impostazioni › Convenzioni, an ordinary `Form`
    row beside «Cartella daily».

**Gate M (HITL).** Stefano opens Impostazioni › Design system › «Mockup delle schermate», page
«Nascita di una nota», on a Debug build of this branch. He chooses:

- the LAVORO position (4a);
- the badge, yes or no (4a);
- the pane layout, A or B (4b);
- the order direction (4b).

He then approves or asks for changes. The choices are recorded in ADR-0085's implementation notes
when the code PR lands, and the page's milestone label becomes «N4, approvato». Only then does
`docs/plans/note-workflow-n4.md` start (R-44). Find the Debug build by `WorkspacePath`, never by
newest mtime (CLAUDE.md).

## Risks & HITL gates

- **Merge conflict in `MockupGalleryView.Screen`.** N2, N3 and N5 add cases in their own mockup PRs.
  Resolve by keeping every case, and never by taking one side.
  `scripts/check-merge-integrity.py` refuses a side-pick.
- **Mockup drift.** A mockup that uses a literal colour fails review. Use the tokens that exist.
  N4's mockup needs no new token. If one becomes necessary, it goes in both theme files and in
  `Theme.emergency` (PG-225), and that is a scope change to report.
- **HITL.** Gate M above. Commit and push of the mockup PR are the person's.
- The mockup PR must still build `perg` and `pergamenum-mcp` (R-45). DesignGallery is app-only, so
  nothing reaches them.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE
