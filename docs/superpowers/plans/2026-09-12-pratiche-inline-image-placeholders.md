# Plan — Pratiche: an inline image Mail has not sent yet is a hole in the prose, not an attachment

- **ADR:** `docs/adr/0042-pratiche-inline-image-placeholders.md`. **That file is not in `docs/adr/`
  yet**: it was written to `docs/architecture/ADR-0042-pratiche-inline-image-placeholders.md`
  because the architect's write scope excludes `docs/adr/**`. The orchestrator relocates it before
  the coder starts. Everything below cites it as **ADR-0042 §D1…§D10**.
- **Numbering:** the request said «ADR-0041». That number was taken earlier the same day by
  `docs/adr/0041-vault-layer-consistency-and-security-cha.md` (a different, in-flight chain). This
  decision is **ADR-0042** everywhere — ADR header, plan, commit messages, CLAUDE.md index bullet.
- **Also to be applied by the orchestrator (Task 8):** ADR-0042 §D9 replaces two of the three items
  of `docs/adr/0040-pratiche-attachment-reliability-bugs.md` §D9, and §D7 adds a fourth clause to
  the exception list that ADR-0040 §D5 added a third one to. Both are cross-references appended to
  ADR-0040, not rewrites of its text (R-12).
- **Requirement ids.** This chain entered at Step 2 with **no `SPEC.md` of its own** — the repo's
  root `SPEC.md` currently holds the unrelated vault-layer chain, and `docs/specs/` has no file for
  this feature. The ids `R-01`…`R-12` are therefore **declared in this plan** (below) rather than
  read out of a SPEC, and every one of them is cited by at least one task. If a SPEC is generated
  for this chain, it must declare exactly this set and no other. ADR-0036's and ADR-0040's own
  `R-*` numbers are different, unrelated sets and are never used here; `§D*` numbers appear only as
  cross-references.
- **Harness:** none created. The gate is the project's existing `.claude/test-cmd`
  (`-only-testing:PergamenumTests`), which picks up new Swift Testing cases with no edit, plus
  `scripts/uitests.sh` before the merge to `main`, per CLAUDE.md. No new script, no new anchor.
- **Branch:** `fix/pratiche-inline-image-placeholders` off `main`. Never on `main` directly.

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test`
TEST-CMD MODE: brownfield

> Copied byte-for-byte from `.claude/test-cmd`, which was read for this plan. Every test below is a
> Swift Testing case in `Tests/`, compiled into `PergamenumTests`, picked up with no edit to that
> file. Do not widen it to the whole scheme: CLAUDE.md's «the UI suite is not in `test-cmd`» rule is
> load-bearing and was paid for once already. **One caveat for the coder:** Tasks 1, 2 and 8 add new
> files under `Sources/Core/Pratiche/`; `tuist generate --no-open` must run before the first build
> that includes them, or the compiler will name a missing symbol rather than a missing file.

EXTERNAL DEPENDENCY: ~/Library/Mail/V10 | file | provisioned: unknown
EXTERNAL DEPENDENCY: Full Disk Access for the app and the test host | tcc-consent | provisioned: true

> **No new dependency is added by this fix** — no SPM package, no framework, no service, no network
> call (ADR-0042 header, CLAUDE.md principle 2). The two lines above are ADR-0036's, restated
> because Task 7's hand-check reads the person's real pratiche and therefore needs both; **every
> automated test in this plan resolves to a fixture through `MailStoreLocation.resolve()` and must
> never reach the real store** (ADR-0036 §D7).

CODER-MODEL CANDIDATE: opus

> `PraticaSyncEngine` is an `actor` under Swift 6 strict concurrency and this work changes its
> decode loop, its rewrite guard and the write-mode fork inside `commit`. It performs surgery on
> the body text of notes already in somebody's vault, adds a key to an on-disk format, and its
> correctness rests on an ordering argument (ADR-0042 §D6) that is wrong in a way no compiler
> catches. Not a Sonnet job.

---

## Requirement ids declared by this plan

- **R-01** — A not-yet-available inline image never appears in `pergamenum-mail-attachments`, in
  either the `[[…]]` or the bare form. No inline image, in any state, produces an attachment chip.
- **R-02** — Each `cid:` reference to a not-yet-available inline image in the note's body is
  replaced by one visible placeholder, at that position.
- **R-03** — A not-yet-available inline image the body does not reference at all produces no
  placeholder, no frontmatter entry and no retry.
- **R-04** — The content ids still waited for are recorded in `pergamenum-mail-inline-pending`, one
  entry per placeholder, in the order the placeholders appear in the rendered file; the key is
  omitted when empty; `pergamenum-mail` stays at schema 1 and notes written before this fix parse
  unchanged.
- **R-05** — Every sync revisits a `.complete` message whose `pergamenum-mail-inline-pending` is
  non-empty — for ever, with no attempt cap, no cooldown and no terminal state.
- **R-06** — On the sync where the bytes arrive: a usable, non-decorative image replaces its own
  placeholder with `![[<placed name>]]`; a usable, decorative one has its placeholder removed; a
  still-unusable one keeps it. The note is amended in its placeholders and in one frontmatter line,
  never re-rendered, and an amendment identical to the file on disk is not written at all.
- **R-07** — When the number of placeholders in the file and the number of recorded content ids
  disagree, no placeholder is touched; a resolved image is linked as an ordinary attachment instead
  of being placed at a guessed position.
- **R-08** — All three inline branches (placed, decorative, deferred) replace a `cid:` reference
  through one rule that removes the whole `![alt](cid:…)` construct where there is one and the bare
  reference elsewhere; no `![alt]()` remnant survives into a note.
- **R-09** — No timeline pill, no accessibility «N allegati» count and no connector JSON entry ever
  names an inline image, in any state.
- **R-10** — A note written by the ADR-0040 build loses its phantom pending entries at the next
  sync of its pratica, gains no `pergamenum-mail-inline-pending` key, and «Rigenera» remains the
  one manual path that restores its inline-image positions.
- **R-11** — The fixture corpus gains the cases this behaviour needs: an HTML body with two inline
  images of which one has no bytes, a plain-text body that references nothing, and a two-sync
  arrival.
- **R-12** — The decision is recorded where the next reader looks: the ADR is relocated to
  `docs/adr/`, ADR-0040 §D9 and ADR-0036 §D6 carry the cross-references, and CLAUDE.md's Chain
  decision index gains its bullet — under the number 0042, not 0041.

---

## Order, and why it is this order

1. **Task 1 (the pure text rules) first.** Everything else calls it, it has no dependency of its
   own, and its tests need no `.emlx`, no fixture store and no vault.
2. **Task 2 (the note's representation and the two patches) before any engine work.** The engine
   cannot record a state that has no spelling, and `commit` cannot compose two patches that do not
   exist.
3. **Task 3 (fixtures) before Task 4**, for ADR-0040's own reason: landing fixtures separately
   means Task 4 turns the suite red for one reason — the behaviour it adds — rather than two.
4. **Task 4 (the decode loop) before Task 5 (retry and commit)**: the retry re-reads what the
   decode loop wrote.
5. **Task 6 (the UI and connector claim) after Task 5**, because it asserts the *absence* of pills
   on notes the engine has just stopped producing them for.
6. **Task 7** is the contract-staleness sweep, the full suite, the offline check and the one
   hand-check that needs a person at the keyboard.
7. **Task 8** is the documentation obligation and the ADR relocation.

Batching suggestion for the orchestrator: {1} · {2} · {3} · {4} · {5} · {6} · {7} · {8}. Tasks 4
and 5 touch the same function and must never be fanned out into parallel worktrees.

---

## What changes an observable contract, and every call-site found

Grepped across `Sources/`, `Tests/` and `UITests/` before this plan was written. The coder does not
have to discover these.

| Symbol | Change | Call-sites that must move with it |
| --- | --- | --- |
| `MessageDocument.MailFrontmatter` | gains `pendingInlineImages: [String] = []`, declared **immediately after `storeReferences`** (ADR-0042 §D3) | six construction sites, all keep compiling because the field is defaulted: `Sources/Core/Pratiche/MessageDocument.swift:221` (the parser — **must be taught the new key**), `Sources/Features/Pratiche/PraticaSyncEngine.swift:627` (the writer — **must pass the new value**), `Tests/PraticheControllerTests.swift:415`, `Tests/PraticaTimelineTests.swift:190`, `Tests/PraticaLedgerTests.swift:70`. The type is `Equatable` and is compared by whole value in at least one place — **verify, do not assume**. |
| `MessageDocument.foreignKeys(of:)` | writes one more key line | every render/parse round-trip test: `Tests/MessageDocumentTests.swift:36`, `:48`, `:56`, `:66`, `:72`; `Tests/MessageAttachmentPatchTests.swift:56`, `:84`, `:103`, `:122`; `Tests/PraticheConnectorTests.swift:66`. All should pass unchanged (the key is omitted when empty) — **run them, do not reason about them**. |
| `MessageAttachmentPatch.applying(entries:to:)` | **signature and behaviour unchanged**; body delegates to the new `MessageFrontmatterPatch` | `Sources/Features/Pratiche/PraticaSyncEngine.swift:382`, `:835`; the whole of `Tests/MessageAttachmentPatchTests.swift`. Nothing moves. If any of those assertions goes red, the extraction is wrong — do not adjust the assertion. |
| `PraticaSyncEngine.prepare`'s `.inlineImage` branch (`:547-594`) | a deferred image no longer appends to `pendingAttachmentNames` (R-01) | **`Tests/PraticaSyncTests.swift:736` asserts exactly the removed behaviour** (`pendingAttachmentNames == ["20260610_logo.png"]`, inside `aZeroByteInlineImageIsNeverPlacedAndLeavesNoDanglingCidOrEmbedReference`). It moves in Task 5. Its two neighbours, `:733` (`!newText.contains("cid:")`) and `:734` (`!newText.contains("![[")`), stay true and must stay in place. |
| `PraticaSyncEngine.prepare`'s decorative branch (`:565-570`) | removes the whole `![alt](cid:…)` construct, not just the reference (R-08) | `Tests/PraticaSyncTests.swift:495`, `:522` (the «heavy inline image must still be kept» pair) use a **plain-text** body, so they exercise the bare-reference path only — they must stay green and they do not prove the construct path. Task 3 adds the fixture that does. |
| `PraticaSyncEngine.PreparedMessage` | gains `inlineResolutions` | `private`/`fileprivate` nested type; no call site outside `PraticaSyncEngine.swift`. |
| `PraticaSyncEngine.SyncOutcome` | **no new field**; `resolvedAttachmentFiles`'s doc comment widens | `PraticheController.swift:486-525`, `Tests/PraticaLiveSyncRecordOutcomeTests.swift:64`, `:104`, `:116`, `Tests/PraticheControllerTests.swift:189`, `:211`, `:229` — none changes. |
| `PraticaRowDetail.pendingAttachments` / the chip row | **no code change**; its *contents* stop including inline images (R-09) | `PraticheController.swift:796` (producer), `PraticaMessageRow.swift:121`, `:138-145` (consumer), `PraticaMessageRow.swift:233-234` (the «N allegati» label). `Tests/PraticheControllerTests.swift:403-440` asserts the split with a real `.docx` attachment and is **unaffected** — do not touch it. |
| `Sources/Connector/VaultPratiche.swift:216` | **no code change**; the JSON's `attachments` array stops naming inline images (R-09) | `Tests/PraticheConnectorTests.swift:58` asserts `attachments: []` and is unaffected. `VaultAPI.PraticaSummary` (protected) is untouched. |
| `pergamenum-mail` frontmatter on disk | gains an optional key | no migration, no schema bump, no index change. `IndexCache.schemaVersion` stays 3 (protected interface — **do not touch it**). |

**After these changes run the full unit suite, not just the Pratiche tests.** `MessageDocument` and
the three new files live under `Sources/Core/**`, which both command-line targets compile; a
frontmatter key that renders wrong shows up in `MessageDocumentTests`, `MessageAttachmentPatchTests`
and `PraticheConnectorTests` long before it shows up in `PraticaSyncTests`. A green
`PraticaSyncTests` proves nothing about the other three.

---

## Task 1 — one placeholder, one reference rule, one ordering (R-02, R-03, R-08)

Cross-refs: ADR-0042 §D2, §D4, §D6; `PraticaSyncEngine.swift:583-594` (the regex being moved),
`:1062-1063` (the italic-placeholder precedent); `Sources/Core/Email/InlineImageClassifier.swift`
for the file's shape and comment style.
Budget: `Sources/Core/Pratiche/MessageInlineImage.swift`, `Tests/MessageInlineImageTests.swift`
(~230 lines)

**Tester declares** (ADR-0155 of the retired concept-to-code workflow, not a Pergamenum ADR — the declaration is the tester's, the body is the coder's):

```swift
enum MessageInlineImage {
    static let placeholder: String
    static func replacingReferences(
        to contentID: String, in body: String, with replacement: String
    ) -> String
    static func referencesContentID(_ contentID: String, in body: String) -> Bool
    static func deferralToken(forPart ordinal: Int) -> String
    static func resolvingDeferralTokens(
        in texts: [String], contentIDByOrdinal: [Int: String]
    ) -> (texts: [String], pending: [String])
}
```

**Coder implements.** Foundation only — a file under `Sources/Core/**` that imports AppKit, SwiftUI
or ImageIO breaks both connector builds (ADR-0001 §D1, CLAUDE.md). The construct regex is the one
already at `PraticaSyncEngine.swift:583-589`, moved verbatim including
`NSRegularExpression.escapedPattern(for:)`; the bare-reference replacement is the line at `:594`.
Order inside `replacingReferences` matters: constructs first, then bare references, or the bare
pass eats the construct's insides and leaves `![alt]()` behind — which is the bug being fixed.
`placeholder` is `"*[immagine non ancora caricata]*"` exactly: no emoji, no glyph (CLAUDE.md design
system). `deferralToken` must be a string that cannot occur in mail and cannot be confused with
markdown; it never reaches disk.

**Tests (red first):**

- `placeholder` contains neither `cid:` nor `![[`, is not a wikilink and is not a markdown link —
  three assertions, because three renderers depend on it being none of those.
- `replacingReferences` on `"testo ![Logo](cid:abc) coda"` with `"X"` → `"testo X coda"`; the whole
  construct goes, brackets and parens included (R-08).
- The same body with `replacement: ""` → `"testo  coda"` and **no `![Logo]()` remnant** — this is
  the decorative branch's defect, asserted directly.
- `replacingReferences` on a plain-text body `"vedi immagine cid:abc"` → the bare form is replaced
  (this is `EmailFixtureCorpus.singleInlineImageMessageRFC822`'s real shape).
- A body carrying both forms of the same id → both replaced, two occurrences.
- A content id containing regex metacharacters (`image001.png@01DA5C3E.9F2B1C40`, a real Outlook
  shape, with `.` and `@`) → replaced literally, not as a pattern.
- `referencesContentID` false for a body that never mentions it, true for either form (R-03).
- `resolvingDeferralTokens` over three texts where the token for part 7 sits in the third text and
  the token for part 2 in the first → `pending == [id7? no: id2, id7]`, i.e. **the order is the
  order of the texts as passed**, not the ordinal order. Write this assertion explicitly with
  reversed ordinals; it is the one ADR-0042 §D6 exists for.
- Two tokens for the same part in one text → two placeholders, the id twice in `pending`.
- No tokens → texts returned unchanged, `pending` empty.

---

## Task 2 — the key, and two patches that share one line surgeon (R-04, R-06, R-07)

Cross-refs: ADR-0042 §D3, §D8; `MessageDocument.swift:113-164`, `:212-248`;
`MessageAttachmentPatch.swift:16-57`.
Budget: `Sources/Core/Pratiche/MessageDocument.swift`,
`Sources/Core/Pratiche/MessageFrontmatterPatch.swift`,
`Sources/Core/Pratiche/MessageInlineImagePatch.swift`,
`Sources/Core/Pratiche/MessageAttachmentPatch.swift`, `Tests/MessageDocumentTests.swift`,
`Tests/MessageInlineImagePatchTests.swift` (~420 lines)

**Tester declares:**

```swift
extension MessageDocument.MailFrontmatter {
    var pendingInlineImages: [String] { get set }   // stored, defaulted [], after storeReferences
}
extension MessageDocument {
    static let inlinePendingKey = "pergamenum-mail-inline-pending"
    static func inlinePendingLine(for contentIDs: [String]) -> String
}

enum MessageFrontmatterPatch {
    static func applying(line: String?, forKey key: String, before: [String], to text: String) -> String?
}

enum MessageInlineImagePatch {
    enum Resolution: Equatable, Sendable {
        case embedded(fileName: String)
        case dropped
    }
    struct Outcome: Equatable, Sendable {
        var text: String
        var remaining: [String]
        var unplaceable: [String]
    }
    static func applying(
        resolved: [String: Resolution], pending: [String], to text: String
    ) -> Outcome?
}
```

**Coder implements.** `foreignKeys(of:)` writes the new key **after `pergamenum-mail-attachments`
and before `pergamenum-mail-store-references`**, omitted when empty, quoted through the same
`inlineList` the other list keys use; `parse` reads it through the existing `list(_:_:)`.
`MessageFrontmatterPatch` is `MessageAttachmentPatch`'s body with the key and the insertion order as
arguments; `MessageAttachmentPatch.applying(entries:to:)` becomes a delegation and **keeps its exact
signature** (its tests must not move). `MessageInlineImagePatch.applying` counts placeholder
occurrences **in the body region only** (after the closing `---`), guards
`count == pending.count`, walks in order, and rewrites the key line from `remaining` through
`MessageFrontmatterPatch`. On a count mismatch it touches no placeholder, puts every `.embedded`
file name into `unplaceable` in order, and still drops the resolved ids from `remaining`.

**Tests (red first):**

- Round-trip: a `MailFrontmatter` with two `pendingInlineImages` renders, parses back equal, and the
  key line sits between `attachments` and `store-references` (R-04).
- The key is absent from the rendered text when the list is empty; a note written before this fix
  parses with `pendingInlineImages == []` (R-04, the compatibility half — assert on a literal
  pre-fix note text, not on a re-render).
- A content id containing a `"` round-trips (the quoting rule `MessageDocumentTests:205` already
  exercises for attachment names).
- `MessageFrontmatterPatch`: replace an existing line; insert before `store-references`; insert
  before `body` when `store-references` is absent; remove when `line` is `nil`; `nil` for a text
  with no frontmatter, for an unterminated block, and for a block with no `pergamenum-mail` key.
- `MessageInlineImagePatch`, counts matching: two placeholders, one resolved `.embedded` → that
  placeholder becomes `![[name]]`, the other is untouched, `remaining` holds the second id, the key
  line is rewritten, **every other byte of the file is identical** (assert on the whole string).
- `.dropped` → the placeholder disappears and nothing replaces it (R-06).
- Both resolved → the key line is **removed**, not written empty.
- Nothing resolved → `Outcome.text == text` exactly, so `commit`'s no-op rule fires (R-06).
- Count mismatch (a person deleted one placeholder): no placeholder changes, `unplaceable` holds the
  resolved file name, `remaining` drops the resolved id, and the key line is still rewritten (R-07).
- A placeholder inside the `<details>` blocks resolves like any other (the signature case, which is
  the reported one).
- Prose added by a person **below** the quoted-history block survives every patch above (the whole
  reason a patch exists rather than a re-render).

---

## Task 3 — the fixtures this behaviour actually needs (R-11)

Cross-refs: ADR-0042 finding 1 and finding 7; `Tests/EmailFixtureCorpus.swift:94-130`, `:260-292`.
Budget: `Tests/EmailFixtureCorpus.swift` (~150 lines)

**This task must land green and wire no behaviour.** It only adds fixtures.

**Tester declares and implements:**

1. `htmlInlineImagesMessageRFC822(messageID:images:)` — a `multipart/alternative` whose HTML part
   embeds several `cid:` images through `<img src="cid:…">` **and whose plain-text part is empty**,
   so `bodyText` reduces the HTML and the body really carries `![alt](cid:…)` constructs. Each image
   is `(contentID:, filename:, bytes:)`, so a caller can make one empty and one a real PNG.
2. `htmlInlineImagesWithPlainAlternativeRFC822(messageID:images:)` — the same, **with** a non-empty
   plain-text part that never mentions the ids. This is finding 1's case: the one that produced most
   of the reported pills, and the one R-03 must silence.
3. `signatureInlineImagesReplyRFC822(messageID:)` — a reply whose new text, signature and quoted
   history each carry one inline image reference, so the render-order rule of ADR-0042 §D6 is
   exercised end to end rather than only in Task 1's unit test.
4. A helper that rebuilds one of the above with the previously-empty part's bytes filled in, keeping
   every other byte identical — Task 5's two-sync arrival needs the second `.emlx` to differ from
   the first only in that.

**Tests:** the suite stays green; the new fixtures are unused until Task 4. Do not add placeholder
assertions to make them look used.

---

## Task 4 — the decode loop stops calling an image an attachment (R-01, R-02, R-03, R-08)

Cross-refs: ADR-0042 §D1, §D4, §D5, §D6; `PraticaSyncEngine.swift:509-599`, `:600-603`, `:626-651`.
Budget: `Sources/Features/Pratiche/PraticaSyncEngine.swift`, `Tests/PraticaSyncTests.swift`
(~260 lines)

**Coder implements**, in `prepare`:

- The `.inlineImage` case's three branches all replace references through
  `MessageInlineImage.replacingReferences` (R-08). Integrity first, `isDecorative` second — ADR-0040
  §D9 item 1, unchanged.
- The deferred branch: **if `referencesContentID` is false, `continue` with no state at all**
  (R-03); otherwise replace with `MessageInlineImage.deferralToken(forPart: ordinal)` and record
  `ordinal → contentID`. **Nothing is appended to `pendingAttachmentNames`** (R-01).
- After `QuoteSplitter.split`, one call to `resolvingDeferralTokens` over
  `[newText, quotedHistory ?? "", signature ?? ""]` **in that order** (ADR-0042 §D6), feeding
  `pendingInlineImages` into the `MailFrontmatter` at `:627` and the three texts back into the
  document. Empty results map back to `nil` for the two optionals, or a note gains an empty
  `<details>` block.
- `PreparedMessage` gains `inlineResolutions`, filled for every inline part this decode judged:
  `.embedded(fileName:)` for a placed one, `.dropped` for a decorative one, nothing at all for one
  still unusable.

**Tests (red first), in `Tests/PraticaSyncTests.swift`:**

- An HTML message with two inline images, one with no bytes: the note's body carries exactly one
  placeholder where that image was, the other is embedded as `![[…]]`,
  `pendingInlineImages == [<id>]`, **`pendingAttachmentNames` is empty**, and `allegati/` holds
  exactly one file (R-01, R-02).
- The same message with a plain-text alternative that mentions nothing: no placeholder, no
  `pendingInlineImages`, no pending attachment, and `allegati/` holds exactly one file (R-03). This
  is the reported defect; name the test after it.
- A decorative (small, light) inline image with bytes: no placeholder, no entry, **and no `![…]()`
  remnant in the body** (R-08).
- The reply fixture: three placeholders, and `pendingInlineImages` in **file order** — new text,
  quoted, signature — asserted against the rendered note's own text, not against the MIME order.
- A message with a real attachment that is not yet available **and** an inline image that is not yet
  available: the attachment is a bare entry in `pergamenum-mail-attachments` (ADR-0040 §D3, intact),
  the image is not (R-01).
- No deferral token survives into any rendered note (grep the written file for the token's stem).

---

## Task 5 — the retry puts the picture back where it was (R-05, R-06, R-07)

Cross-refs: ADR-0042 §D7, §D8, §D9; ADR-0040 §D4's write-mode table, §D6's no-op rule;
`PraticaSyncEngine.swift:467-479`, `:786-885`, `:892-912`.
Budget: `Sources/Features/Pratiche/PraticaSyncEngine.swift`, `Tests/PraticaSyncTests.swift`
(~280 lines)

**Coder implements:**

- `prepare`'s §D6 guard and `regeneratePending`'s selection each gain one clause:
  `!frontmatter.pendingInlineImages.isEmpty` (R-05). No counter, no cooldown, no terminal state.
- `commit`'s patch mode composes the two patches and writes once (ADR-0042 §D8's four steps):
  inline patch on the on-disk text, then the attachment patch with
  `prepared…attachments + unplaceable.map(MessageDocument.attachmentEntry(linking:))`, then
  **ADR-0040 §D6's identity check**, then one `write` and
  `outcome.resolvedAttachmentFiles.append(notePath)`. Widen that field's doc comment; add no field.
- `mustFullyRender` is **not** given a new row: an inline image can never become a
  `StoreReference`.

**The stale assertion, to be moved in this task and nowhere else:**
`Tests/PraticaSyncTests.swift:736` —
`#expect(doc.frontmatter.pendingAttachmentNames == ["20260610_logo.png"])` becomes
`#expect(doc.frontmatter.pendingAttachmentNames.isEmpty)` plus
`#expect(doc.frontmatter.pendingInlineImages == ["zeroinline"])` plus an assertion that the body
carries the placeholder. `:733` and `:734` stay exactly as they are.

**Tests (red first):**

- Two-sync arrival: sync 1 against the fixture with empty bytes, sync 2 against the filled one →
  the placeholder is gone, `![[20260610_…]]` stands in its place **at the same offset in the same
  paragraph**, `pendingInlineImages` is empty, the key line is gone, `allegati/` has the file
  (R-06).
- Two-sync arrival where the filled image is decorative → the placeholder is gone, nothing replaces
  it, no file is placed, no chip appears (R-06).
- Partial arrival: two deferred images, one arrives → exactly one placeholder replaced, the other
  untouched, `pendingInlineImages` holds only the second id (R-06).
- **The no-op rule:** three consecutive syncs with the bytes never arriving → the note's text and
  its modification date are byte-identical after each, `resolvedAttachmentFiles` is empty, and
  nothing is appended to `regeneratedPendingFiles` (R-05, R-06).
- **Prose survives:** append a paragraph by hand to the note between sync 1 and sync 2; after sync 2
  the paragraph is still there and the image has arrived (R-06 — the reason for a patch).
- **The mismatch fallback:** delete one of two placeholders by hand between syncs, then resolve both
  → no placeholder is touched, the resolved image appears as a `[[…]]` entry in
  `pergamenum-mail-attachments`, and the file is in `allegati/` (R-07).
- A message with a pending inline image and a `pending` body: the body's arrival still takes the
  full-render path (ADR-0036 §D6's first exception, unchanged) and the placeholders are re-derived
  from the fresh decode, not patched.
- Cancellation mid-run still leaves every written file complete (ADR-0036 R-11 — assert it once
  here, because `commit` changed).

---

## Task 6 — the row stops claiming attachments it never had (R-09, R-10)

Cross-refs: ADR-0042 §D10; `PraticheController.swift:746-799`, `PraticaMessageRow.swift:118-148`,
`:226-238`, `Sources/Connector/VaultPratiche.swift:193-221`.
Budget: `Tests/PraticheControllerTests.swift`, `Tests/PraticheConnectorTests.swift`,
`Tests/PraticaSyncTests.swift` (~140 lines)

**This task should change no production code.** If it turns out to need any, stop and say so: it
means §D10's claim — that five surfaces are corrected by one upstream rule — is wrong, and the ADR
is what has to change, not the views.

**Tests (red first):**

- `PraticheController.readMessages` over a note written by Task 4 with one deferred inline image →
  `detail.pendingAttachments.isEmpty`, `detail.attachments.isEmpty`, and `detail.body` contains the
  placeholder (R-09).
- The accessibility label of such a row names **no** «allegati» count
  (`PraticaMessageRow.accessibilityText` is reachable from a test through the row's own static
  helpers; if it is not, assert on `PraticaRowDetail` instead and say so in the test's comment).
- `VaultPratiche.messageRows` over the same note → `entry.attachments` is empty (R-09).
- **The migration (R-10):** hand-write a note in the ADR-0040 shape — bare inline names in
  `pergamenum-mail-attachments`, no placeholders, no new key — run a sync whose message is the same
  id, then assert: the bare entries are gone, `pendingInlineImages` is empty (the key was **not**
  added), the body is otherwise byte-identical, and `detail.pendingAttachments` is empty.

---

## Task 7 — the sweep (no requirement id: this task verifies, it adds no behaviour)

Budget: none — this task writes no production code. It may write one test.

1. **Full unit suite green**, not only the Pratiche files: `.claude/test-cmd` verbatim.
2. **Protected interfaces intact**: `IndexCache.schemaVersion` still 3;
   `VaultAPI.LintFinding`, `VaultAPI.PraticaSummary`, `PraticaNaming.messageFileName`,
   `Dossier.render`, `ImportNaming.recordingNoteTitle`,
   `MessageDocument.isPendingAttachmentEntry`, `CompletingTextView+Pasteboard.swift` — all
   untouched. `git diff` the five files that hold them and confirm empty.
3. **Offline**: `grep -rn "URLSession\|NWConnection\|Network\." Sources/Core/Pratiche/` returns
   nothing new. Principle 2 is unchanged by this fix.
4. **Both connectors still build**: `xcodebuild … -scheme perg` and `-scheme pergamenum-mcp`. Three
   new files landed under `Sources/Core/**`; a stray `import AppKit` in any of them breaks both and
   the app suite would not have caught it.
5. **`scripts/mcp-smoke.py`** if `Sources/MCPServer` was touched (it should not have been).
6. **`scripts/uitests.sh`** in full before the merge to `main`, per CLAUDE.md. Kill stale instances
   first; read the per-test seconds before believing a red.
7. **Hand-check, needs a person**: open the app on the real vault, sync a pratica that holds one of
   the reported messages, and confirm — the pills are gone, the body reads sensibly, and nothing
   else in that note changed (`git diff` the note file, or compare against a copy taken first).
   **Take a copy of the pratica folder before this step.**

---

## Task 8 — the decision is recorded where the next reader looks (R-12)

Budget: `docs/adr/0042-pratiche-inline-image-placeholders.md`,
`docs/adr/0040-pratiche-attachment-reliability-bugs.md`, `docs/adr/0036-pratiche.md`, `CLAUDE.md`
(~70 lines)

1. Relocate `docs/architecture/ADR-0042-pratiche-inline-image-placeholders.md` to
   `docs/adr/0042-pratiche-inline-image-placeholders.md` and delete the now-empty staging directory
   entry. **Check first that `docs/adr/0042-*` does not already exist** — 0041 was taken by another
   chain the same day, which is why this one is 0042.
2. Append to ADR-0040 §D9: «Items 2 and 3 are replaced by ADR-0042 §D1/§D9 (2026-09-12): a
   not-yet-available inline image is a placeholder in the body plus a `pergamenum-mail-inline-pending`
   entry, never a pending attachment, and a late arrival returns to its own position.»
3. Append to ADR-0036 §D6's exception list the fourth clause, quoted from ADR-0042 §D7.
4. CLAUDE.md — **two** edits: a bullet in the Chain decision index, and a paragraph in «Decisions
   from later chains». Suggested index line: «**ADR-0042** — a not-yet-available inline image is a
   placeholder in the prose plus a `pergamenum-mail-inline-pending` content id, never an attachment
   chip; a late arrival returns to its own position through a two-part patch; amends ADR-0040 §D9 →
   `docs/adr/0042-pratiche-inline-image-placeholders.md`».
5. `PROJECT_BRIEF.md` status is **not** touched: this is a defect fix inside M3, not a milestone.

---

## Risks, dependencies, and the HITL gates

- **This fix edits the body text of notes already in the person's vault.** It is the first thing in
  Pratiche that does. The patch is line-surgical and Task 5 has a test for prose survival, but the
  blast radius is real files. **Back up the pratiche folders before the Task 7 hand-check**, and
  never run the hand-check against the vault the person is using while they are using it.
- **The ordering argument (ADR-0042 §D6) is the one thing no compiler checks.** If the three texts
  are passed in decode order rather than render order, resolved images will land in the wrong region
  of replies specifically — a defect that only appears on a two-sync arrival in a reply with a
  signature. Task 1's reversed-ordinal test and Task 4's reply fixture are both there for this.
- **Two chains are in flight in this repository today** (`vault-layer-consistency-and-security-cha`
  holds ADR-0041 and touches `PraticheController.swift` and `PraticaSyncEngine.swift` for the
  path-traversal guard). Rebase before starting, and expect a conflict in those two files. Do not
  fan out work from both chains into parallel worktrees.
- **Dependency on ADR-0040 being implemented and merged.** Its chain memory says
  `step_5_implementation, in_progress`. If any of `AttachmentIntegrity`,
  `MessageDocument.attachmentEntry(pending:)`, `MessageAttachmentPatch` or the `hasPendingAttachments`
  guard is not on `main` yet, **stop**: this plan amends code that must exist first.
- **The plain-text-alternative limitation is not a bug to be fixed later by surprise** (ADR-0042
  §D5). If the person expects a marker on every missing image regardless of which alternative the
  body came from, that is a separate decision that reopens ADR-0036's body-selection rule. Say so
  before implementing anything beyond R-03.
- **HITL gates:** the branch cut; the commit; the push; the PR merge to `main` (after
  `scripts/uitests.sh`); the Task 7 hand-check on real data; and the operator's decision on the
  protected-interface and audit-profile proposals below. No deletion, no schema migration and no
  destructive command is required by this plan — `FileManager.trashItem` is not reached by any new
  code path.

---

## PROPOSED PROTECTED INTERFACES

```
Sources/Core/Pratiche/MessageInlineImage.swift:MessageInlineImage.placeholder — added 2026-09-12 per ADR-0042 §D2; this exact string is written into the body of every message note on disk and is the only anchor the retry has for putting a late inline image back where it belongs. A silent change strands every placeholder already written: the count guard then refuses to patch and every image that arrives afterwards becomes an attachment chip instead of an embed.
```

One candidate only. Deliberately not proposed: `MessageInlineImagePatch.applying` (pure logic,
expected to be tuned) and `MessageInlineImage.replacingReferences` (a rule, not a format).

## PROPOSED AUDIT PROFILE

```
risk: high — the change performs text surgery on files already in the person's vault, and the only
recovery for a wrong patch is the person's own backup: there is no journal on message notes
(ADR-0036 §D14) and no undo.
task_type: legacy-integration — Apple Mail's `.emlx`/MIME shapes plus a 1068-line Swift 6 actor and
an on-disk note format three ADRs already constrain; the failure modes are other people's data, not
this repo's logic.
```
