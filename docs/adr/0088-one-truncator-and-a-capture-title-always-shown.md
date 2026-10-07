# ADR-0088: One word-boundary truncator, and a capture title the panel always shows

- Status: **planned**. Lands with the N1 delta PR, Tasks 1 and 2 of
  `docs/plans/note-workflow-n1.md`. Flip to `accepted` as the first docs change after that PR
  merges, naming the PR, its merge hash as `git log --first-parent main` shows it, and the date
  (`docs/adr/README.md` rule 2).
- Date: 2026-10-05. Written against `origin/main` at `5056c61f`, which holds PR #897 (ADR-0080's
  implementation, session 1 of `docs/plans/pg-384-n1-seams.md`).
- Number: `0088` was checked free on every local and remote-tracking ref on 2026-10-05. The
  roadmap's N2 to N5 records hold 0081 to 0087 in this chain's working tree. Check again
  immediately before the merge (`docs/adr/README.md` rule 1).
- Source: the repo-root `SPEC.md` of the note-workflow chain (N1 to N5, Approved 2026-10-04),
  R-02 and its Constraints and Edge cases.
- **Amends ADR-0080** in three places, and nothing else in it:
  - §D4: the free-text cut;
  - §D3's caption clause, «while the destination is «Nota nuova» and the derived title differs
    from the typed line»;
  - §D3 item 5, for the panel only: the sentence a taken title is refused with.

  ADR-0080 §D1, §D2, §D3 items 1 to 4, §D5 and §D6 stand unchanged.
- No on-disk format, schema, setting or protected interface changes. `ImportNaming.recordingNoteTitle`
  and `PraticaNaming.messageFileName` keep their bytes.

## Context

Two SPECs were approved on 2026-10-04 for the same milestone.

- **The N1-only SPEC** is archived as `docs/specs/note-workflow-n1-seams.spec.md`. ADR-0080 and
  PR #897 implement it.
- **The note-workflow SPEC** covers N1 to N5. Its N1 criteria overlap the first SPEC almost
  entirely.

Stefano kept #897's chain as the N1 implementation on 2026-10-05. What the second SPEC asks
beyond it is built as a delta (`docs/plans/note-workflow-n1.md`). Three of those points contradict
sentences ADR-0080 records, so ADR-0080 would describe code that no longer exists unless a record
amends it. This is that record.

**The truncator.** The note-workflow SPEC's Constraints say: «the word-boundary truncator behind
`ImportNaming.recordingNoteTitle` is reused, never forked». ADR-0080 §D4 chose the opposite.
`ImportNaming.truncatedAtSpace(_:toFit:)` was added beside `truncatedAtWordBoundary(_:toFit:)`, and
generalising the latter to take a separator was rejected because two protected names sit behind
it. ADR-0045 §D5 had just made `truncatedAtWordBoundary` "the one word-boundary truncator" after
`PraticaNaming` was found keeping its own identical copy. The fork is the shape that ADR-0045
removed.

On `5056c61f`, `truncatedAtSpace` has one production caller, `CaptureTitle.swift:70`. It is pinned
by four tests in `CaptureTitleTests`. The two functions differ in exactly one case: when the first
word is longer than the budget, `truncatedAtWordBoundary` returns `""`, while `truncatedAtSpace`
cuts at the budget. They also differ on runs of spaces, which `truncatedAtWordBoundary` collapses
while splitting. `CaptureTitle` collapses whitespace before it cuts, so that difference cannot
reach a capture title.

**The caption.** ADR-0080 §D3 shows «Titolo: …» only when the derived title differs from the typed
line. The note-workflow SPEC's UI flow is «a live «Titolo: …» caption under the field». Its edge
case for a taken title is «the caption shows it, Return is refused with the composer's existing
"already exists" sentence». A legal first line that is already taken differs from nothing, so under
§D3 the caption is absent exactly where that edge case needs it.

**The sentence.** On `5056c61f`, a taken capture title reaches the panel as `ConnectorError`'s
«esiste già: 00 Inbox/X.md» (`VaultWrites.swift:85`). The composer, Quick Open and «Documento»
say «Esiste già una nota in 00 Inbox/X.md» (`ConformanceText.creationFailure`).

## Decision

**D1. The capture title is cut by the one word-boundary truncator.**

- **The parameter.** `ImportNaming.truncatedAtWordBoundary(_:toFit:)` gains a defaulted separator:
  `truncatedAtWordBoundary(_ slug: String, toFit budget: Int, separator: Character = "-")`. Its
  body splits and joins on `separator` and is otherwise unchanged. Every existing caller passes
  nothing, so `recordingNoteTitle` and `messageFileName` take the default path byte for byte.
  `ConventionsNamingTests` and `PraticaNamingTests` stay unmodified and green; they are the proof.
- **The wrapper.** `truncatedAtSpace(_:toFit:)` keeps its name, its signature and its contract.
  Its body becomes a call to `truncatedAtWordBoundary(text, toFit: limit, separator: " ")`, plus
  the one thing the slug truncator does not do: when that returns `""` (a first word longer than
  the limit), it returns `String(text.prefix(limit))`. `CaptureTitle` is not touched.
- **The proof of the contract.** The four `truncatedAtSpace` tests in `CaptureTitleTests` stay
  unmodified and green.
- **One cutting loop.** No second loop that walks words remains in `ImportNaming`.

**D2. The panel always shows the title the capture will write.**

- **When it shows.** While the destination is «Nota nuova» and the text is not empty,
  `CaptureController.titleCaption` returns «Titolo: \<title\>», whether or not the title differs
  from the typed line. It stays `nil` for an empty text and for every other destination.
- **Why always.** The person sees which line becomes the title, the rest being the body, and the
  line under the field no longer appears and disappears as they type.
- **A taken title.** When the vault already holds the note that title would create, Return is
  refused in the panel with the composer's sentence (`ConformanceText.creationFailure` on
  `VaultSession.CreationError.alreadyExists(path)`), and nothing is written. The caption keeps
  showing the taken title, so the person edits the first line.

How the refusal works:

- **The check.** `CaptureController.capture(into:)` checks the path before calling
  `VaultAPI.capture`. The path is `(folder ?? session.inboxFolder)/<title>.md`, with the title
  read from the same `CaptureTitle.derive` call.
- **It is a filter, not a guard** (ADR-0043 §D7). The guard stays where it is:
  `VaultSession.createNote` still refuses a taken path inside the write. A note that appears
  between the check and the write is still refused, only in the connector's wording.
- **The connectors are unchanged.** `perg capture` and MCP `capture` keep ADR-0080 §D3 item 5's
  `ConnectorError`, and `CaptureTests` keeps pinning it.

## Not decided here

These are delta items with no ADR. Each follows a pattern the code already has and is cheap to
reverse. They are listed so a reader of the archived N1-only SPEC does not undo them.

- **«Documento»'s confirmation with «Apri».** The N1-only SPEC rejected it: «the sheet closes
  before the write ends, so it needs new UI for no gain». The note-workflow SPEC decided it (R-05).
  The rejection's premise no longer holds: session 2 of `docs/plans/pg-384-n1-seams.md` (its
  Task 7) keeps the sheet open until the write ends. N4's composer in the board sheet keeps the
  confirmation (`docs/plans/note-workflow-n4.md`).
- **The pointer (`PG-219`, R-09).** The N1-only SPEC left it out of scope. The note-workflow SPEC
  takes it into N1. The delta tries SwiftUI's `.pointerStyle` on the text views' hosts, the
  `TimelineBlockBox.swift:105` precedent. If that fails, the `.onContinuousHover` restructure the
  ledger entry describes gets its own ADR.
- **An event note opens with the caret in the editor (R-04).** A one-shot request in the shape of
  `closeRequest`.
- **Every failure in the Workspace creation sheet is shown in the sheet and kept in the problem
  list (R-11).**

## Alternatives considered

- **Keep the fork (ADR-0080 §D4).** Rejected, because it breaks the note-workflow SPEC's constraint
  and reopens ADR-0045 §D5. ADR-0080's reason was that generalising would put two protected names
  behind changed code. Here, a defaulted parameter whose default path is today's loop, pinned by
  both protected names' own unmodified tests, is the smallest change to that code. Two loops that
  cut at word boundaries are the drift ADR-0045 had just removed.
- **Delete `truncatedAtSpace` and call `truncatedAtWordBoundary(…, separator: " ")` from
  `CaptureTitle`.** Not chosen. The hard cut for an over-long word would move into `CaptureTitle`,
  four pinned tests would be rewritten for no behavioural gain, and the wrapper costs four lines.
- **Show the caption only when the title differs (ADR-0080 §D3).** Rejected. The taken-title edge
  case needs a caption for a legal line, and a caption that toggles while typing moves the panel's
  layout under the person's hands. What ADR-0080 avoided is a redundant line for an ordinary
  title. That is the price paid here, accepted because the caption also says which line becomes
  the title.
- **Change the connector's sentence to the composer's for every surface.** Rejected. It changes
  the text `perg note create`, `perg capture`, MCP `create_note` and `capture` return, which
  `CaptureTests` pins (`contains("esiste già")`, lower case). The SPEC asks for the composer's
  sentence in the panel only.
- **Rewrite the panel's message after a refused send** by matching the connector's text. Rejected.
  It parses a sentence to recover a fact the controller can read directly from the vault.

## Consequences

- **Positive.**
  - One word-boundary cutting loop in `ImportNaming`, as ADR-0045 §D5 states.
  - The panel always says which line becomes the title.
  - A taken title is refused with the same sentence on every app surface that creates a note.
- **Negative.**
  - A redundant caption for an ordinary first line.
  - `truncatedAtWordBoundary`, which feeds two protected names, gains a parameter. Its doc comment
    must name the third caller, and a future edit to it now has three readers to keep green, not
    two.
- **Neutral.**
  - The pre-check names the taken path one `await` before the write, so a race still refuses, but
    with the connector's wording.
  - Two fallback captures in the same minute still collide, and the second is refused (ADR-0080
    §D3).
- **ADR-0080's own text.** It gains a scope note at its head pointing here, ADR-0047's way. Its
  body is not edited.

## References

- ADR-0080 §D3, §D4 (amended), §D7; ADR-0045 §D5; ADR-0043 §D7; ADR-0047 (scope-note convention).
- `docs/specs/note-workflow-n1-seams.spec.md` (the N1-only SPEC, on `main` since #897).
- The note-workflow `SPEC.md`: R-02, Constraints (the truncator), UI flows (Capture), Edge cases
  (the taken title).
- `docs/plans/note-workflow-n1.md` (the delta), `docs/plans/pg-384-n1-seams.md` (#897's plan).
- `Sources/Core/Conventions/ImportNaming.swift`, `Sources/Core/Conventions/CaptureTitle.swift`,
  `Sources/Features/Capture/CaptureController.swift`, `Sources/Core/Conventions/ConformanceText.swift`
  on `5056c61f`.
