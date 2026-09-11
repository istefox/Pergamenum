# Plan — Pratiche: an attachment Mail has not finished writing is a state, not a file

- **ADR:** `docs/adr/0040-pratiche-attachment-reliability-bugs.md`. **That file is not in
  `docs/adr/` yet**: it was written to
  `docs/architecture/ADR-0040-pratiche-attachment-reliability-bugs.md` because the architect's
  write scope excludes `docs/adr/**`. The orchestrator relocates it before the coder starts.
  Everything below cites it as **ADR-0040 §D1…§D10**.
- **Also to be applied by the orchestrator (Task 10):** ADR-0040 §D5 and §D7 amend two sentences of
  `docs/adr/0036-pratiche.md` §D6. The amendment is a cross-reference appended to ADR-0036, not a
  rewrite of its text (R-16).
- **Requirement ids.** `SPEC.md`, this chain: `R-01`…`R-16`. Every one is cited by at least one
  task below, and no id outside that set is cited. ADR-0036's own `R-*` numbers are a different,
  unrelated set and are never used here; ADR-0040's `§D*` numbers appear only as cross-references.
- **Harness:** none created. The gate is the project's existing `.claude/test-cmd`
  (`-only-testing:PergamenumTests`), which picks up new Swift Testing cases with no edit, plus
  `scripts/uitests.sh` before the merge to `main`, per CLAUDE.md. No new script, no new anchor.
- **Branch:** `fix/pratiche-attachment-reliability` off `main`. Never on `main` directly.

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test`
TEST-CMD MODE: brownfield

> Unchanged from `.claude/test-cmd`, verified byte-for-byte against it. Every test this plan adds
> is a Swift Testing case in `Tests/`, compiled into `PergamenumTests`, and is picked up with no
> edit to that file. Do not widen it to the whole scheme: CLAUDE.md's «the UI suite is not in
> `test-cmd`» rule is load-bearing and was paid for once already.

EXTERNAL DEPENDENCY: ~/Library/Mail/V10 | file | provisioned: unknown
EXTERNAL DEPENDENCY: Full Disk Access for the app and the test host | tcc-consent | provisioned: true

> **No new dependency is added by this fix** — no SPM package, no framework, no service. Magic-byte
> detection is literal byte-prefix comparison in pure Swift over `Data` (ADR-0040 §D2). The two
> lines above are ADR-0036's, restated because Task 9's hand-check reads the person's real pratiche
> and therefore needs both; **every automated test in this plan resolves to a fixture through
> `MailStoreLocation.resolve()` and must never reach the real store** (ADR-0036 §D7).

CODER-MODEL CANDIDATE: opus

> `PraticaSyncEngine` is an `actor` under Swift 6 strict concurrency, and this work adds a new
> `Sendable` value type crossing its boundary, a new `async` step between the folder scan and the
> main loop, and a write-mode fork inside `commit`. It also moves files in somebody's vault to the
> Trash and amends the on-disk format of every message note. The `Content` enum change breaks four
> `switch`es on purpose. Not a Sonnet job.

---

## Order, and why it is this order

1. **Task 1 (the pure verdict) first.** Everything else calls it. It has no dependency of its own
   and its tests need no `.emlx`, no fixture store and no vault.
2. **Task 2 (fixtures) before any wiring.** It both adds the three new `.emlx` fixtures R-15 asks
   for *and* corrects the two existing tests whose attachments are named `.pdf` but are not PDFs
   (staleness table below). Landing it before Task 4 means Task 4 turns a green suite red for one
   reason only — the behaviour it is adding — instead of for two.
3. **Task 3 (the note's representation) before Task 4 (the engine that writes it).** The engine
   cannot record a pending entry before there is a spelling for one.
4. **Tasks 4, 5 (write paths)** before **Task 6 (retry)**: the retry re-reads what the write path
   produced. Before **Task 7 (repair)**: the repair downgrades into the same representation the
   retry consumes, and a repair with no retry behind it is a deletion with no recovery.
5. **Task 8 (UI) after Task 3**, not after Task 7: the chip only needs the representation. Running
   it late keeps the AppKit/SwiftUI churn out of the batches that touch the actor.
6. **Task 9** is the contract-staleness sweep, the protected-interface and offline verification,
   the full suite, and the one hand-check that needs a person.
7. **Task 10** is the documentation obligation and the ADR relocation.

Batching suggestion for the orchestrator: {1, 2} · {3} · {4, 5} · {6} · {7} · {8} · {9} · {10}.
Tasks 4 and 5 touch the same function and must not be fanned out in parallel worktrees.

---

## What changes an observable contract, and every call-site found

Grepped across `Sources/`, `Tests/` and `UITests/` before this plan was written. The coder does
not have to discover these.

| Symbol | Change | Call-sites that must move with it |
| --- | --- | --- |
| `AttachmentChipModel.symbol/previewURL/openURL/revealURL/copyItems` | `fileExists: (URL) -> Bool` → `state: (URL) -> FileState` (ADR-0040 §D8) | `Sources/Features/Pratiche/AttachmentChip.swift:78`, `:82`, `:85`, `:95`, `:139` (the only production callers); **`Tests/AttachmentChipTests.swift` — 21 assertions across `:35-97`, plus the `Self.fileExists` helper at the top of the suite.** Every one is a mechanical rewrite; read them before editing. |
| `AttachmentChip.Content` | gains `case pending(name: String)` | the enum is `switch`ed in four places in `AttachmentChipModel.swift` (`:21`, `:33`, `:59`) and three in `AttachmentChip.swift` (`:63`, `:98`, `:108`) — all become non-exhaustive and **will not compile** until handled. That is the design (ADR-0040 A8), not an accident. Constructed at `PraticaMessageRow.swift:124`, `:131`. |
| `MessageDocument.MailFrontmatter.attachments` | **signature unchanged**, contents gain a second form (bare name = pending, ADR-0040 §D3) | every reader of it changes meaning, not type: `PraticheController.swift:756` (`hasAttachments` — leave as is, a pending attachment still means the message has one) and `:771-777` (**must split linked from pending, or a pending entry renders as a chip pointing at a missing file**); `PraticaSyncEngine.swift:491` (writer). `Tests/MessageDocumentTests.swift:25` constructs one — verify it still round-trips. |
| `PraticheController.attachmentFileName(fromWikilink:)` (`:865`) | behaviour unchanged; it must stop being the *only* filter | called once, `PraticheController.swift:772`. It strips brackets when present and returns the string otherwise — so it cannot tell the two forms apart. The classification belongs to `MessageDocument.isPendingAttachmentEntry` (Task 3), not here. |
| `PraticaRowDetail` | gains `pendingAttachments: [String] = []`, **declared last** | `PraticheController.swift:766` and `:817` keep compiling because the field is defaulted and last. `Tests/PraticaTimelineTests.swift:201` constructs one — verify, do not assume. |
| `PraticaSyncEngine.SyncOutcome` | gains `resolvedAttachmentFiles: [String] = []` and `attachmentProblems: [String] = []`, **both declared last**; `.empty` updated (`:82`) | `PraticheController.swift:486-525` (`recordSyncOutcome`); `Tests/PraticaLiveSyncRecordOutcomeTests.swift:64`, `:104`, `:116`; `Tests/PraticheControllerTests.swift:189`, `:211`, `:229`. All construct with labels and keep compiling — **verify, do not assume**, the type is `Equatable` and is asserted by whole value in at least one place. |
| `PraticaSyncEngine.SyncOutcome.regeneratedPendingFiles` | **meaning unchanged** — nothing from this fix is ever appended to it | `Tests/PraticaSyncTests.swift:481` and `:628` assert `count == 1`. If either goes red, the write-mode table of ADR-0040 §D4 has been implemented wrong; do not adjust the assertion. |
| `PraticaSyncEngine.FolderContext` / `.ExistingMessage` | gain `corruptAttachmentNames: Set<String>` / `text: String` | both are `private` nested types — no call site outside `PraticaSyncEngine.swift`. |
| `EmailFixtureCorpus.mixedMultipartMessageRFC822` attachment bytes (`:129`, `cGRmLWJ5dGVz` = `pdf-bytes`, declared `application/pdf`) | becomes real PDF-shaped bytes | `Tests/MIMEDecoderTests.swift:70` asserts on the decoded parts — check whether it asserts on the bytes' *value*; if it does, it moves with the fixture. |
| `Tests/PraticaSyncTests.swift:254` and `:293` | attachments named `offerta.pdf` whose bytes are Italian prose | **both go red the moment Task 4 lands** unless Task 2 has already given them PDF-shaped bytes. `:333`'s `.dwg` fixture is safe (no signature entry, R-03). |

**After the contract changes: run the full unit suite, not just the Pratiche tests.**
`MessageDocument` and the new `AttachmentIntegrity` live under `Sources/Core/**`, which both
command-line targets compile; `SyncOutcome` and `PraticaRowDetail` are `Equatable` value types
asserted on by whole-value comparison in three test files. A green `PraticaSyncTests` proves
nothing about `MessageDocumentTests`, `MIMEDecoderTests` or `PraticheControllerTests`.

---

## Task 1 — one pure verdict over bytes, and a file probe that never reads the whole file (R-01, R-02, R-03)

Cross-refs: ADR-0040 §D1, §D2; `Sources/Core/Email/InlineImageClassifier.swift` for the file's
shape and its «never drop on a guess» comment style.
Budget: `Sources/Core/Email/AttachmentIntegrity.swift`, `Tests/AttachmentIntegrityTests.swift`
(~220 lines)

**Tester declares** (ADR-0155 — the declaration is the tester's, the body is the coder's):

```swift
enum AttachmentIntegrity {
    enum Verdict: Equatable, Sendable { case usable, empty, signatureMismatch, truncated }
    static func verdict(of bytes: Data, named name: String?, contentType: String?) -> Verdict
    static func verdict(ofFileAt url: URL, named name: String?) -> Verdict
}
```

**Coder implements** ADR-0040 §D2's table and its six ordered rules. Foundation only — no ImageIO,
no UTType, no `NSWorkspace`: a file under `Sources/Core/**` that imports AppKit or SwiftUI breaks
both connector builds (ADR-0001 §D1, CLAUDE.md). `verdict(ofFileAt:)` reads the size through
`URL.resourceValues(forKeys: [.fileSizeKey])` and two windows through a `FileHandle`
(`read(upToCount:)` from the start, `seek(toOffset:)` + `readToEnd()` for the tail) — **never
`Data(contentsOf:)`**, which would slurp a 400 MB store reference to draw a chip.

**Tests (red first):**

- Empty `Data` → `.empty`, for every combination of known type, unknown type, and `nil` name
  (R-01).
- `%PDF-1.7\n…\n%%EOF` bytes → `.usable` when declared `application/pdf`, when declared
  `application/octet-stream` with name `x.pdf`, and when declared with neither (R-02, R-03).
- `Data("contenuto".utf8)` named `x.pdf` → `.signatureMismatch`; the same bytes named `x.dwg` or
  with no name at all → `.usable` (R-02 and R-03 in one pair — this pair is the whole of the
  design's conservatism).
- `%PDF-1.7` + filler with no `%%EOF` → `.truncated`; the same with `%%EOF` followed by 40 bytes of
  trailing whitespace → `.usable` (the window is searched, not suffix-compared).
- PNG: `EmailFixtureCorpus.solidColorPNG(width: 8, height: 8)` → `.usable`; the same bytes with the
  last 20 dropped → `.truncated`; the same with the first byte flipped → `.signatureMismatch`.
- JPEG and ZIP: one `.usable`, one `.truncated`, one `.signatureMismatch` each. A four-byte ZIP
  header alone → `.truncated`, not a crash (the tail window is longer than the file).
- A file shorter than its own head signature, declared `application/pdf` → `.signatureMismatch`.
- `verdict(ofFileAt:)` on a file that does not exist → `.empty`. On a 3 MB file whose head and tail
  are valid → `.usable`, asserted alongside a check that the whole file was not read (assert on the
  result plus a comment naming the mechanism; there is no hook to count bytes here, so the
  guarantee is structural: grep the implementation for `Data(contentsOf:` and assert zero hits from
  `Tests/SharedSourcesPurityTests.swift`'s own file-walking precedent if the coder wants it
  enforced rather than reviewed).

---

## Task 2 — the fixture corpus grows three cases, and two existing tests stop pretending prose is a PDF (R-15)

Cross-refs: ADR-0040 finding 1; `Tests/EmailFixtureCorpus.swift:230-292`.
Budget: `Tests/EmailFixtureCorpus.swift`, `Tests/PraticaSyncTests.swift`,
`Tests/MIMEDecoderTests.swift` (~140 lines)

**This task must land before Task 4 and must leave the suite green.** It changes fixtures and the
assertions that depend on them; it wires no behaviour.

**Tester declares and implements** (this task is entirely test-side):

1. `EmailFixtureCorpus.pdfBytes(pages:)` — real PDF-shaped bytes: `%PDF-1.7`, some filler, `%%EOF`.
   Not a real PDF document; a byte sequence with the right head and tail, which is all §D2 reads.
2. `EmailFixtureCorpus.truncatedPDFBytes()` — the same head, the same filler, **no `%%EOF`**.
3. `EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(messageID:filename:)` — R-15's first case:
   one `multipart/mixed` with an attachment part whose body is empty. Build it from
   `singleAttachmentMessageRFC822` with `attachmentBytes: Data()` if that produces a genuinely
   empty part; if the base64 line collapses the boundary walk, write it out explicitly rather than
   forcing the helper.
4. `EmailFixtureCorpus.truncatedAttachmentMessageRFC822(messageID:filename:)` — R-15's second case:
   non-empty bytes that fail the check for their declared type.
5. `EmailFixtureCorpus.mixedValidAndTruncatedAttachmentsRFC822(messageID:)` — R-15's third case:
   two attachment parts, one `pdfBytes`, one `truncatedPDFBytes`, distinct filenames.
6. `mixedMultipartMessageRFC822:129` — `cGRmLWJ5dGVz` becomes `pdfBytes()` base64-encoded. Check
   `Tests/MIMEDecoderTests.swift:70` first: if it asserts on the decoded attachment's byte *value*,
   move the assertion with the fixture; if it asserts only on part classification and count, it
   does not change.
7. `Tests/PraticaSyncTests.swift:254` and `:293` — the `offerta.pdf` attachments become
   `pdfBytes()`-derived bytes. `:254` needs the two messages to carry *identical* bytes (its whole
   point is one copy linked twice) and `:293` needs them *different* (its point is the `-2`
   collision), so parameterise: `pdfBytes(pages: 1)` vs `pdfBytes(pages: 2)`.

**Tests (green throughout):** the suite must be green at the end of this task with no behaviour
change. The three new fixtures are unused until Task 4 — that is expected; do not add placeholder
assertions to make them look used.

---

## Task 3 — a pending attachment is a bare name in the list the note already has, and one line of the file is patchable (R-04)

Cross-refs: ADR-0040 §D3, §D4; `Sources/Core/Pratiche/MessageDocument.swift:59`, `:113-153`,
`:229`.
Budget: `Sources/Core/Pratiche/MessageDocument.swift`,
`Sources/Core/Pratiche/MessageAttachmentPatch.swift`, `Tests/MessageDocumentTests.swift`,
`Tests/MessageAttachmentPatchTests.swift` (~260 lines)

**Tester declares:**

```swift
extension MessageDocument {
    static func attachmentEntry(linking fileName: String) -> String
    static func attachmentEntry(pending fileName: String) -> String
    static func isPendingAttachmentEntry(_ entry: String) -> Bool
}

extension MessageDocument.MailFrontmatter {
    var linkedAttachmentNames: [String] { get }
    var pendingAttachmentNames: [String] { get }
}

enum MessageAttachmentPatch {
    /// `nil` when the text carries no `pergamenum-mail` frontmatter to patch.
    static func applying(entries: [String], to text: String) -> String?
}
```

**Coder implements:**

1. The codec per ADR-0040 §D3: `"[[name]]"` for linked, the bare name for pending,
   `hasPrefix("[[") && hasSuffix("]]")` as the discriminator. `linkedAttachmentNames` unwraps and
   drops the alias half after `|`, matching `PraticheController.attachmentFileName(fromWikilink:)`
   exactly — the two must agree, and the one in `PraticheController` is the one that is about to
   stop being used for classification.
2. `MessageAttachmentPatch.applying` per §D4: find the frontmatter block, find the
   `pergamenum-mail-attachments:` line (a top-level line, not an indented continuation — reuse the
   `!hasPrefix(" ") && !hasPrefix("\t")` rule `MessageDocument.scalar` already applies at `:244`),
   replace it, insert it in `foreignKeys(of:)`'s own position when absent, remove it when `entries`
   is empty. The line's text comes from the same quoting `MessageDocument` already uses — expose
   what is needed rather than writing a second speller.
3. `PraticaSyncEngine.swift:491`'s `links.map { "[[\($0)]]" }` is replaced by
   `MessageDocument.attachmentEntry(linking:)`. No behaviour change; one speller.

**Tests (red first):**

- Round trip: a frontmatter carrying `["[[20260610_a.pdf]]", "20260610_b.dwg"]` renders, parses
  back identical, and splits into exactly one linked and one pending name (R-04).
- A note written before this fix (only `[[…]]` entries) has an **empty** `pendingAttachmentNames` —
  the backward-compatibility guarantee the whole retry rule rests on.
- `applying` replaces the line and leaves **every other byte** of a realistic note identical,
  asserted by comparing the full text minus that one line. Include a note whose body carries a
  `<details>` block and prose after it — the case a re-render would destroy.
- `applying` inserts the key in the right place when absent (before
  `pergamenum-mail-store-references`, and before `pergamenum-mail-body` when there is none), and
  removes it when `entries` is empty.
- `applying` returns `nil` for a note with no `pergamenum-mail` frontmatter and for a note that is
  not YAML at all.
- A file name containing a `,` and one containing a `"` survive the round trip (the list is
  comma-separated and quoted — `splitTopLevel` already handles this; assert it still does).

---

## Task 4 — the write path refuses bytes that are not the file, and a partly-ready message is still `.complete` (R-01, R-02, R-04, R-12)

Cross-refs: ADR-0040 §D2, §D3, §D9; `PraticaSyncEngine.swift:386-452`, `:479-499`, `:719-737`.
Budget: `Sources/Features/Pratiche/PraticaSyncEngine.swift`, `Tests/PraticaSyncTests.swift`
(~240 lines)

**Tester declares:** `PraticaSyncEngine.SyncOutcome.resolvedAttachmentFiles` and
`.attachmentProblems`, both `= []` and **declared last**, with `.empty` (`:82`) updated.

**Coder implements**, inside `prepare`'s part loop:

1. `.attachment` branch (`:395-415`): take
   `AttachmentIntegrity.verdict(of: bytes, named: name, contentType: part.contentType)` **before
   the threshold comparison** and before `place`. On anything other than `.usable`, append
   `MessageDocument.attachmentEntry(pending: PraticaNaming.attachmentFileName(date: calendarDate, name: name))`
   to the entry list and `continue` — never `place`, never `digest`, never a write (R-01, R-02,
   R-12).
2. `.inlineImage` branch (`:416-448`): the same verdict **before**
   `InlineImageClassifier.isDecorative` (ADR-0040 §D9). On non-`.usable`, record the pending entry
   and strip the `![alt](cid:…)` construct and the bare `cid:` reference exactly as the decorative
   branch already does, so the body never holds an embed pointing nowhere.
3. `:491` becomes the merged list: linked entries in their existing order, then pending entries.
   `body` stays `isPending ? .pending : .complete` — **unchanged**. A message with some usable and
   some not is `.complete` (R-04); that distinction is `bodyState`'s and this fix does not touch
   it.
4. The name recorded for a pending entry is the **placed** name, not the raw MIME filename
   (ADR-0040 §D3) — `PraticaNaming.attachmentFileName(date:name:)` with the message's own calendar
   day, the same call `place` makes.

**Tests (red first), using Task 2's fixtures through `MailStoreFixture`:**

- A message with one zero-byte attachment: `allegati/` is empty, the note is `.complete`, its
  `pendingAttachmentNames` is exactly `["20260610_<name>"]`, and `linkedAttachmentNames` is empty
  (R-01, R-04).
- A message with one truncated PDF: identical outcome (R-02).
- A message whose attachment is `disegno.dwg` filled with `0x41`: placed normally (R-03's
  consequence at the engine level — an unknown format is never rejected).
- **The mixed message**: one file in `allegati/`, one pending entry, one note, `.complete` (R-04).
- **R-12's regression**: two *different* messages each carrying a *different* zero-byte attachment
  produce two distinct pending entries and **no file at all** — before this fix they shared one
  SHA-256 and one file name. Assert `allegati/` is empty and the two notes name different pending
  entries.
- An inline image with zero bytes: no file placed, a pending entry recorded, and the body contains
  neither `cid:` nor `![[`.

---

## Task 5 — the over-threshold path is checked too, before the reference is recorded (R-07)

Cross-refs: ADR-0040 finding 3, §D2; `PraticaSyncEngine.swift:398-408`, `:758-764`.
Budget: `Sources/Features/Pratiche/PraticaSyncEngine.swift`, `Tests/PraticaSyncTests.swift`
(~90 lines)

**Read finding 3 of ADR-0040 before writing a line of this.** A zero-byte part can never reach the
store-reference branch, because the branch is chosen by `bytes.count > thresholdBytes(...)`. R-07
is about a *large* attachment whose bytes are present and wrong, and about the path recorded for
it. An implementation that only guards the copy branch satisfies nothing and will still pass a
carelessly written test.

**Coder implements:** the verdict of Task 4 step 1 is taken once, before the threshold comparison,
and governs both branches. A non-`.usable` over-threshold part records a pending entry and **no
`MessageDocument.StoreReference`** — a reference is a promise that the file is there.

**Tests (red first):**

- An over-threshold attachment with valid head and tail: one `StoreReference`, no file copied
  (this is `Tests/PraticaSyncTests.swift:333`'s existing assertion — it must stay green; its `.dwg`
  fixture has no signature entry, so give the *new* test a `.pdf` to exercise the check).
- An over-threshold attachment named `.pdf` whose bytes are 2 MB of `0x41`: **no** `StoreReference`
  in the frontmatter, one pending entry instead (R-07).
- The same attachment once its bytes are valid: a `StoreReference` appears and the pending entry
  goes — reached through Task 6's retry, so this assertion may have to land in Task 6's batch if
  Task 5 ships first. Say so in the commit message rather than weakening it.

---

## Task 6 — every sync revisits a message that is still waiting, and amends one line when it resolves (R-05, R-06)

Cross-refs: ADR-0040 §D4, §D5, §D6, §D10 — **this is the task that amends ADR-0036 §D6**;
`PraticaSyncEngine.swift:356-364`, `:634-680`, `:686-704`.
Budget: `Sources/Features/Pratiche/PraticaSyncEngine.swift`,
`Sources/Features/Pratiche/PraticheController.swift`, `Tests/PraticaSyncTests.swift` (~280 lines)

**Tester declares:** `PraticaSyncEngine.FolderContext.ExistingMessage.text: String` (a `private`
nested type — the declaration is still the tester's).

**Coder implements:**

1. **The guard** at `:356-364` gains exactly one clause, spelled as in ADR-0040 §D5. Nothing is
   removed from it.
2. **The selection** in `regeneratePending` at `:694` gains the pending-attachment clause, spelled
   as in ADR-0040 §D5. The method keeps its name.
3. **The write-mode fork** in `commit`, per ADR-0040 §D4's four-row table, evaluated in order. The
   fork lives in `commit` and nowhere else — **not** in the guard, which is reached from two
   callers. In patch mode: write the attachment bytes (`prepared.attachments`) first as today,
   **skip the `.eml` rewrite**, then apply `MessageAttachmentPatch.applying` to
   `existing.text` and write the result through the same `write` hop.
4. **The no-op rule** (§D6): if the patched text equals `existing.text`, return without calling
   `write` and without appending anything to the outcome. This is what makes an unresolved retry
   free; without it every pratica with one permanently-stuck attachment rewrites a file on every
   sync forever.
5. `outcome.resolvedAttachmentFiles.append(notePath)` on a patch that actually wrote. **Nothing is
   ever appended to `regeneratedPendingFiles`** by this path — `Tests/PraticaSyncTests.swift:481`
   and `:628` are the guard on that and must not be adjusted.
6. `PraticheController.recordSyncOutcome` surfaces `outcome.attachmentProblems` through the
   existing `problem` property (joined by a newline when there is more than one).

**Tests (red first):**

- Sync a message whose attachment is truncated; sync again with the same fixture: the note is
  **byte-identical** after the second run (compare the whole file, and its modification date),
  `resolvedAttachmentFiles` is empty, `regeneratedPendingFiles` is empty (R-05's no-cost half,
  §D6).
- Sync with the truncated fixture, rebuild the fixture with valid bytes for the same `Message-ID`,
  sync again: the file appears in `allegati/`, the note's entry becomes a wikilink, its pending
  entry is gone, and **every other byte of the note is unchanged** — assert against a note whose
  body was hand-edited between the two syncs, which is the whole reason §D4 exists (R-06).
- A message with two pending attachments, one of which resolves: exactly that one moves, the other
  stays pending, and a third already-linked attachment is untouched (R-06's second sentence).
- Ten consecutive syncs over a never-resolving fixture: ten runs, no write, no growth in any
  outcome array — the no-cap rule is not a leak (R-05).
- A `.complete` message with **no** pending entries is never re-prepared and never rewritten, in
  either loop — ADR-0036 §D6's rule as it stands for everything else. Assert on the modification
  date.
- «Rigenera» on a message with a pending entry still produces a full re-render and a
  `UnifiedDiff` (ADR-0036 §D21 is not reopened): assert `regenerationPreview` returns a plan whose
  `replacementText` is a whole note, not a patched line.

---

## Task 7 — a corrupt file already in the vault is trashed and its message re-enters the cycle (R-10, R-11, R-12)

Cross-refs: ADR-0040 §D7 — **this is the task that narrows «a sync never deletes a file»**;
ADR-0022 §D6 (the Trash is this repo's only deletion convention);
`PraticaSyncEngine.swift:257-287`, `:129-169`.
Budget: `Sources/Features/Pratiche/PraticaSyncEngine.swift`, `Tests/PraticaSyncTests.swift`
(~200 lines)

**Tester declares:** `PraticaSyncEngine.FolderContext.corruptAttachmentNames: Set<String>` (a
`private` nested type).

**Coder implements:**

1. In `folderContext`'s `allegati/` loop (`:272-285`): take
   `AttachmentIntegrity.verdict(of: data, named: name, contentType: nil)` **before**
   `Self.digest(of: data)`. On `.usable`, proceed exactly as today. Otherwise:
   `FileManager.default.trashItem(at:resultingItemURL:)`, and on success record the name in
   `corruptAttachmentNames` and **do not** insert it into `takenAttachmentNames` (the name must be
   free for the retry to reuse) and **do not** compute its digest (R-11, R-12).
2. On a trash **failure**: leave the file, insert the name into `takenAttachmentNames` as today,
   do **not** record it as corrupt, and append a sentence to `outcome.attachmentProblems`. A link
   removed while the file stays would be an orphan nobody can find (§D7.3).
3. A new `async` step between `folderContext(of:)` and the main loop (`:140-143`, declare
   `outcome` before `folder`): for each message in `folder.messagesByID` whose
   `linkedAttachmentNames` intersect `corruptAttachmentNames`, move exactly those entries to the
   pending form, apply `MessageAttachmentPatch`, write, update the in-memory
   `folder.messagesByID[...]` so the rest of the same run sees the new state, and append the note
   path to `outcome.resolvedAttachmentFiles`.
4. Cancellation is observed at the same boundary as everywhere else — one `await Task.yield()` and
   the `cancelled` check per message, matching `regeneratePending`'s shape (ADR-0036 §D14).

**Tests (red first):**

- Seed an `allegati/` with one zero-byte file and one valid file, and a message note linking both.
  After one sync: the zero-byte file is gone from `allegati/`, the valid file is **still there,
  byte-identical**, the note links the valid one and carries a pending entry for the other
  (R-10, R-11).
- The same, where the corrupt file is linked by message A and an identical-name-different-content
  valid file is linked by message B in another pratica folder: B is untouched (R-11's
  «or a different `allegati/` folder»).
- The dedup map after the repair contains the valid file's digest and **not** the corrupt one's —
  assert indirectly by importing a new attachment whose bytes are also empty and checking it is not
  linked to the trashed name (R-12).
- Repair then resolve in **one** sync: seed the corrupt file, build the fixture so Mail now has the
  real bytes, run once — the file in `allegati/` is the good one and the note links it. This is why
  step 3 updates the in-memory context.
- A second sync after a completed repair finds nothing to repair: no write, no outcome growth
  (§D7.2's «no flag needed» claim, asserted rather than argued).
- Trash failure path: if it cannot be provoked on the test volume, assert the branch through a
  seam the coder introduces for it rather than skipping it — and if no seam is affordable, say so
  in the report instead of leaving an untested deletion path.

---

## Task 8 — the chip says «in attesa», opens nothing, and re-checks a file before previewing it (R-08, R-09)

Cross-refs: ADR-0040 §D8; `AttachmentChipModel.swift:21-67`, `AttachmentChip.swift:63-150`,
`PraticaMessageRow.swift:118-139`, `PraticheController.swift:588-605`, `:766-781`.
Budget: `Sources/Features/Pratiche/AttachmentChipModel.swift`,
`Sources/Features/Pratiche/AttachmentChip.swift`,
`Sources/Features/Pratiche/PraticaMessageRow.swift`,
`Sources/Features/Pratiche/PraticheController.swift`, `Tests/AttachmentChipTests.swift`,
`Tests/PraticheControllerTests.swift` (~300 lines)

**Tester declares:** `AttachmentChipModel.FileState`, the five `state:`-taking signatures, and
`AttachmentChip.Content.pending(name:)` — all exactly as ADR-0040 §D8 spells them. Declaring the
enum case is what turns the four `switch`es red, which is this task's RED state.

**Coder implements:**

1. `AttachmentChipModel`: `.pending` returns `nil`/`[]` from every URL function **without calling
   `state`**, and `clock.badge.questionmark` as its symbol. `.usable` behaves as
   `fileExists == true` did; `.missing` and `.unusable` both behave as `false` did, with
   `exclamationmark.triangle` for `.unusable` so a damaged file reads differently from an absent
   one.
2. `AttachmentChip`: the production probe becomes
   `FileManager.fileExists` → `.missing`, else `AttachmentIntegrity.verdict(ofFileAt:named:) == .usable`
   → `.usable` / `.unusable` (R-09, and R-07's «handed to the UI» half for a store reference).
   Label `In attesa` for `.pending`, the file name in `.help(...)`, accessibility label
   `"Allegato \(name), in attesa"`.
3. A click on a `.pending` chip toggles a local `@State` `.popover` carrying one sentence
   («L'allegato non è ancora disponibile in Mail. Verrà riprovato alla prossima
   sincronizzazione.») and calls neither `onQuickLook` nor `NSWorkspace` (R-08). Italian UI,
   English code and comments, per CLAUDE.md.
4. `PraticaRowDetail` gains `pendingAttachments: [String] = []`, declared **last**;
   `PraticheController.readMessages` (`:771`) splits the frontmatter list through
   `linkedAttachmentNames` / `pendingAttachmentNames` instead of mapping the whole list through
   `attachmentFileName(fromWikilink:)`.
5. `PraticaMessageRow.attachments` renders pending chips **after** the store-reference chips, with
   the index base `detail.attachments.count + detail.storeReferences.count`, so the existing
   `pratiche-attachment-<hash>-<n>` identifiers keep their values.

**Tests (red first):**

- All 21 existing assertions in `Tests/AttachmentChipTests.swift` rewritten to the `state:` closure,
  asserting the **same** results — this is the staleness rewrite, not a behaviour change.
- `.pending` content: symbol is the new one, `previewURL`/`openURL`/`revealURL` are `nil`,
  `copyItems` is empty, and the injected `state` closure is **never called** (assert with a closure
  that records its invocations and expect zero) — R-08's «performs no open/preview action» stated
  as a mechanism rather than an outcome.
- `.file` content whose probe answers `.unusable`: same `nil`s as `.missing`, different symbol
  (R-09).
- `.storeReference` whose probe answers `.unusable`: `openURL` and `revealURL` are `nil` (R-07).
- `readTimeline` over a folder whose note carries one linked and one pending entry produces one
  `PraticaAttachmentRef` and one `pendingAttachments` string — the call site from the staleness
  table, asserted directly.

---

## Task 9 — the sweep: protected interfaces intact, nothing new reaches the network, and the whole suite green (R-13, R-14)

Cross-refs: ADR-0040's header claims about R-13 and R-14; `.claude/protected-interfaces`;
CLAUDE.md principle 2.
Budget: none — this task writes no production code. It may write one test.

1. **R-13, mechanically.** Run `interface-check.sh` (Step 6's own gate) against
   `.claude/protected-interfaces`. Confirm by hand that
   `Sources/Core/Pratiche/PraticaNaming.swift:messageFileName`,
   `Sources/Core/Pratiche/Dossier.swift:Dossier.render` and
   `Sources/Connector/VaultPayloads.swift:VaultAPI.PraticaSummary` appear in **zero** hunks of
   `git diff main...HEAD`. If any of the three is touched, stop and report — do not adjust the
   protected-interfaces file. *(no-test: `interface-check.sh` verifies this against the file
   mechanically; there is no Swift Testing assertion for it.)*
2. **R-14, by grep and by review.** `git diff main...HEAD` must contain no `URLSession`, no
   `Network.`, no `NWConnection`, no `NSURLConnection`, no `socket(`, no `http`. The two new Core
   files import Foundation only. State the grep and its zero result in the report.
   *(no-test: the absence of an API cannot be asserted at runtime; it is verified by review and by
   the diff.)*
3. **The full unit suite**, not the Pratiche subset: `.claude/test-cmd` as written. Three
   `Equatable` value types changed shape and two new files landed under `Sources/Core/**`, which
   both command-line targets compile — a green `PraticaSyncTests` proves nothing about
   `MessageDocumentTests` or `MIMEDecoderTests`.
4. **Both connector builds**, because `Sources/Core/**` grew two files:
   `xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build`
   and the same for `pergamenum-mcp`. A `Sources/Core` file that imports AppKit breaks both, and
   the break is reported as a compiler error naming something else (CLAUDE.md).
5. **`scripts/uitests.sh`** before the merge to `main`, per CLAUDE.md's standing rule. Kill stale
   instances first and read the per-test seconds before believing a red.
6. **The hand-check, with Stefano at the keyboard** — this is the only step that touches real mail.
   Open a pratica known to have a broken attachment, sync, and confirm: the corrupt file is in the
   Trash, the chip reads «In attesa», clicking it opens a popover and nothing else, and a second
   sync changes no file's modification date. This is the acceptance criterion for the whole chain;
   the suite cannot produce it.

---

## Task 10 — the amendment is recorded where the next reader will look (R-16)

Cross-refs: ADR-0040 §D5, §D7; ADR-0036 §D6.
Budget: `docs/adr/0040-pratiche-attachment-reliability-bugs.md`, `docs/adr/0036-pratiche.md`,
`CLAUDE.md` (~60 lines)

**Orchestrator, not the coder.**

1. Relocate `docs/architecture/ADR-0040-pratiche-attachment-reliability-bugs.md` to
   `docs/adr/0040-pratiche-attachment-reliability-bugs.md` and delete the staging file.
2. Append to `docs/adr/0036-pratiche.md`, as a follow-up section in the style of its existing ones,
   a short block: «**§D6 amended 2026-09-11 by ADR-0040 §D5/§D7** — a third automatic rewrite
   trigger (a `.complete` message carrying a pending attachment entry, amended in one line, never
   re-rendered) and one narrowing of "a sync never deletes a file" (a file in `allegati/` that
   fails `AttachmentIntegrity` is moved to the Trash). Everything else of §D6 stands; §D21 is not
   reopened.» **Do not rewrite §D6's original text** — R-16 asks for a cross-reference, and this
   repo's ADRs are a record of what was decided when (ADR-0025 and ADR-0037 amend the same way).
3. Add ADR-0040 to CLAUDE.md's «Chain decision index», one line, in the existing form.
4. Add the three-to-five-line «Decisions from the … chain» block for ADR-0040 to CLAUDE.md, matching
   the shape of the ADR-0039 block above it. Keep it to the decisions a future reader must not
   rediscover: §D3's encoding, §D4's patch-not-render rule, §D5/§D7's amendments to ADR-0036 §D6,
   and §D2's «never rejected for want of a signature».
5. Update `PROJECT_BRIEF.md`'s Status section only if this closes a milestone — it does not, so
   most likely: no change. Check rather than assume.

*(no-test: a documentation obligation. Verified by review that the ADR exists at the relocated
path, that ADR-0036 carries the cross-reference, and that CLAUDE.md names ADR-0040.)*

---

## Risks, dependencies, and the HITL gates

- **A valid file wrongly judged corrupt is moved to the Trash** (Task 7). This is the one path that
  touches a file nobody asked it to touch. Mitigations in the design: the Trash rather than
  `removeItem`, a check that only fires on positive evidence (ADR-0040 §D2 rule 3), and the repair
  running only on files this app itself wrote. The residual risk is real and is why the hand-check
  in Task 9 exists.
- **The two `offerta.pdf` tests will go red if Task 2 is skipped or reordered after Task 4.** They
  are correct tests with unrealistic fixtures; the failure will look like a bug in Task 4.
- **`regeneratedPendingFiles` must not grow.** Two assertions (`PraticaSyncTests.swift:481`, `:628`)
  depend on it. If either goes red, the write-mode table was implemented in the guard instead of in
  `commit` — fix the implementation, not the assertion. Never disable a test to make a suite pass
  (CLAUDE.md).
- **Swift 6 isolation.** The new `async` repair step runs inside the `actor` and must not hold a
  non-`Sendable` value across a suspension. `FileManager` calls are fine; the `write` hop is the
  existing `@MainActor` closure and is the only crossing.
- **An attachment that never resolves is a permanent «in attesa» chip** with no way to dismiss it.
  This is the SPEC's explicit choice; if Stefano finds it noisy in practice, the follow-up is a
  «Ignora questo allegato» command, not a retry cap — write it as a backlog item, do not add it
  here.
- **Two new files land under `Sources/Core/**`**, which both command-line targets compile. No
  manifest edit is needed (the glob covers them) but a stray `import AppKit` breaks both builds
  with an error that names the compiler, not the cause.
- **HITL gates**: the commit and the push (every batch); the branch creation; the merge to `main`,
  gated behind `scripts/uitests.sh`; Task 7's first run against a real vault (it deletes files);
  Task 9's hand-check; and the operator's decision on the protected-interface proposal below, which
  BLOCKS once it exists.

## PROPOSED PROTECTED INTERFACES

```
Sources/Core/Pratiche/MessageDocument.swift:MessageDocument.isPendingAttachmentEntry — added 2026-09-11 per ADR-0040 §D3; the only thing that tells an attachment already in `allegati/` from one Mail has not finished writing, on every message note already on disk. A silent change re-links every pending entry to a file that does not exist.
```

Propose only. The architect cannot write `.claude/protected-interfaces`; the operator creates the
entry by hand at Gate 2 if they want it, and it BLOCKS from then on. `AttachmentIntegrity.verdict`
is deliberately **not** proposed: it is tuning policy, not an on-disk format.

## PROPOSED AUDIT PROFILE

```
risk: high — the fix trashes files inside the person's vault and amends the on-disk format of every message note already written. Irreversible in the sense that matters: a wrongly-trashed attachment is recoverable only if the person notices.
task_type: legacy-integration — a defect fix inside an existing eleven-file feature that reads Apple Mail's undocumented local store, across an actor boundary, with four interacting write paths that already exist.
```
