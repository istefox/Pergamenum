# ADR-0042: An inline image Mail has not sent yet is a hole in the prose, not an attachment

- Status: accepted. Landed on `main` via PR #250 (merge `f9dc424`, 2026-09-12).
- Date: 2026-09-12. Written after reading every file it names, at the line, on the working tree at
  `71f6664` (`main`, marketing version 1.4). Every claim below about this repo's code was read out
  of `Sources/`, `Tests/` and `UITests/`, not out of an ADR.

- **Numbering note, read this first.** The request named this decision «ADR-0041». That number was
  taken earlier the same day by `docs/adr/0041-vault-layer-consistency-and-security-cha.md`
  (status `accepted`, written 2026-09-12, currently untracked in git). This file is therefore
  **ADR-0042**, and every reference to it — CLAUDE.md's Chain decision index, the plan, the commit
  message — must say 0042. Nothing else about the request changes.
- **Relocation note:** this file is written at
  `docs/architecture/ADR-0042-pratiche-inline-image-placeholders.md` because that is the
  architect's enforced write scope (`test-write-scope.sh`); the orchestrator relocates it to
  `docs/adr/0042-pratiche-inline-image-placeholders.md`, which is where this repo's ADRs live
  (`0001`…`0041`) and which is the path the plan and every reference below assume. Same convention
  ADR-0029…ADR-0041 carry in their own headers.

- **Amends ADR-0040 §D9** — «an inline image is checked like any other part, but a late arrival
  becomes a chip and never re-enters the body». Item 1 (integrity before `isDecorative`) stands
  untouched. Item 2 is replaced: a not-yet-available inline image no longer records a pending
  *attachment* entry; it leaves a visible placeholder where its reference was and records its
  content id under a new key (§D1, §D2, §D3). Item 3 is replaced: a late arrival re-enters the body
  at its own placeholder (§D9). **Nothing else of ADR-0040 changes** — §D1/§D2 (the verdict), §D3
  (the pending-attachment codec, for real attachments), §D6 (the no-op rule), §D7 (the repair pass),
  §D8 (the chip's three-state probe) and §D10 (`SyncOutcome`) are all reused as they are.
- **Widens ADR-0040 §D5's amendment to ADR-0036 §D6 by one clause**, exactly as §D5 itself widened
  it: the automatic-rewrite exception list gains a fourth entry, stated verbatim in §D7. A sync
  still never rewrites a `.complete` message that is not waiting for something, and «Rigenera»
  (ADR-0036 §D21) is still the only path that re-renders one wholesale, still behind its diff.
- **Reopens nothing else of ADR-0036.** §D1, §D2, §D3, §D4, §D5, §D7, §D12, §D14, §D15, §D18,
  §D19, §D21 are untouched. The «text/plain preferred, else HTML→markdown» body rule is untouched
  too, and §D5 below records exactly what that costs this fix.
- **Adds no exception to CLAUDE.md principle 2.** No network call, no socket, no loopback. Every
  new decision is a pure function over bytes already in memory or text already on disk.
- **Extends the closed frontmatter schema by exactly one prefixed key**,
  `pergamenum-mail-inline-pending` (§D3), which is the sanctioned mechanism (ADR-0020's precedent,
  spent again here for the first time since ADR-0036 — §"Alternatives considered" A1 argues why the
  alternative of reusing `pergamenum-mail-attachments` is the wrong shape). The closed four-key note
  schema (`date`, `tags`, `related`, `aliases`) is not touched. `IndexCache.schemaVersion` stays 3.
  `MessageDocument`'s own `pergamenum-mail` schema version **stays 1** (§D3's compatibility note,
  A7's rejection).
- **Touches none of the five protected interfaces** this repo declares for Pratiche.
  `PraticaNaming.messageFileName`, `Dossier.render`, `VaultAPI.PraticaSummary` and
  `MessageDocument.isPendingAttachmentEntry` keep their signature and their behaviour; the last of
  them keeps its meaning too, because after this ADR the only entries it ever judges are real
  attachments. One *new* protected-interface entry is proposed to the operator, not written
  (§"Protected-interface proposal").
- Depends on: **ADR-0036** in full, **ADR-0040** in full (this is a defect fix inside that fix),
  **ADR-0020** (a prefixed key is how this repo extends a closed schema), **ADR-0053** (protected
  interfaces are proposed by the architect and created by the operator), **ADR-0155** (the
  retired concept-to-code workflow's ADR, not a Pergamenum one: on a compiled language the tester
  owns the declaration, the coder owns the body).

---

## Context

An email with a rich HTML signature — a company logo, five social icons, a banner — carries those
pictures as MIME parts with a `Content-ID`, referenced from the HTML by `cid:<id>`. Mail downloads
them from IMAP lazily. On the day Pergamenum syncs, some of them are headers with no bytes behind
them yet.

ADR-0040 taught the sync to recognise bytes that are not the file, and routed **every** such part —
attachment or inline image — into one representation: a bare name in
`pergamenum-mail-attachments`, drawn as an «In attesa» chip. For a real attachment that is right.
For an inline image it produces three wrong things at once, and a person reported all three
on 2026-09-12:

1. **Eight to ten «In attesa» pills on one message row.** They read as «this email had ten
   attachments and Pergamenum lost them all». None of them is an attachment; they are the icons in
   somebody's signature. In a Vibrofer-facing vault — where most correspondence comes from
   companies with branded signatures — this is the *common* case, not an edge case. The person
   filed it as a suspected regression of ADR-0040, which is the honest reading of what the UI says.
2. **They never resolve, and nothing says why.** Pergamenum mirrors Mail's local `.emlx` files and
   can never fetch a byte Mail does not have (ADR-0036, principle 2). ADR-0040 §D5 chose no cap and
   no terminal state deliberately, and that choice is right — but a chip that will very likely
   never clear, multiplied by ten, on a message whose real attachments are all fine, is not the
   state that choice was designed for.
3. **The picture is gone from the prose with no marker at all.** `prepare`'s pending branch strips
   the `cid:` reference out of the body (`PraticaSyncEngine.swift:562`). A long message whose
   illustrations were inline reads as unbroken text with holes nobody can see. The person sent a
   screenshot of exactly this.

### Is this worth fixing, and how much of it

Yes, and all of it. The three symptoms are one defect with two halves: an inline image is being
described by a vocabulary built for attachments (halves 1 and 2), and the one place it actually
belongs — its position in the prose — is being erased (half 3). Fixing only the pills would leave
the vault's message notes silently lossy; fixing only the body would leave the row still claiming
ten missing attachments. The data a person keeps in this vault is the point of the app
(principle 1, «file over app»), and a note that quietly drops the picture the sentence refers to is
a note that has lost content. ADR-0040's silence on inline-image UX is not a reason to scope this
down: §D9 was written in one paragraph, at the end of an ADR about attachments, and it explicitly
called its own item 3 «a stated, deliberate cost». This is the ADR that pays it back.

### What was read in this repository, at the line, before deciding

Eight findings. Three of them change the design; two of them are pre-existing defects in the
adjacent lines that this fix would otherwise step over.

1. **Most of the person's ten pills are for images that were never in the note at all.**
   `PraticaSyncEngine.bodyText(of:)` (`:991-1000`) prefers `text/plain` and reduces the HTML only
   when the plain part is empty. A business email virtually always carries both. So for the
   reported message the body was the plain-text alternative, which references no `cid:` at all —
   yet `prepare`'s pending branch (`:556-563`) appends a pending name **unconditionally**, whether
   or not the body ever referred to that part. Rule §D5 — no reference, no state — removes those
   pills on its own, and is the single highest-value line in this ADR.
2. **The pending branch leaves a broken markdown construct behind.** It strips only the reference
   (`body.replacingOccurrences(of: "cid:\(contentID)", with: "")`, `:562`), so an HTML-derived body
   keeps `![Logo]()` where the picture was. The placement branch three lines below already knows
   this and removes the *whole* `![alt](cid:…)` construct with a regex (`:583-589`), with a comment
   explaining the exact bug. The decorative branch (`:565-570`) has the same defect as the pending
   one. §D4 gives all three one rule.
3. **`MarkdownInline.link(at:)` treats `![alt](target)` exactly like `[alt](target)`**
   (`MarkdownInline.swift:90-99`) — it renders the *label* and hangs a link on it, and
   `MarkdownBlocksView` then sets `piece.link = URL(string: target)` (`:250-252`). That kills
   A5's tempting idea of keeping `![segnaposto](cid:…)` in the body as the anchor: it would draw a
   link to a `cid:` URL that macOS answers with «no application can open this», in the timeline and
   in the editor alike.
4. **The precedent for this kind of marker already exists and is italic Italian prose.**
   `PraticaSyncEngine.pendingPlaceholder` (`:1062-1063`) is
   `"*Il corpo di questo messaggio non è ancora stato scaricato da Mail.*"`. §D2 follows it exactly
   — no emoji, no glyph, no HTML comment, per CLAUDE.md's «no emoji in the interface» rule and its
   design-system section.
5. **`QuoteSplitter.split` runs *after* the part loop** (`:600-603`), and the file is rendered in
   the order `newText`, quoted `<details>`, signature `<details>` (`MessageDocument.render:89-97`)
   — which is **not** the order those three pieces appear in the source body of a reply, where the
   signature precedes the quoted history. A signature logo's placeholder therefore lands in the
   third region of the file while sitting in the second region of the decoded body. Any ordering
   the frontmatter records must be taken *after* the split, in render order (§D6). Getting this
   backwards silently mis-places a resolved image.
6. **`MessageAttachmentPatch` is a one-key surgeon** (`MessageAttachmentPatch.swift:16-42`): it
   finds the frontmatter block, then replaces, inserts or removes exactly
   `pergamenum-mail-attachments`. Its insertion-order helper (`:49-57`) mirrors
   `MessageDocument.foreignKeys(of:)`'s own order. A second key needs the same surgery, and a
   second copy of it is how the two key orders drift (§D8 extracts it instead).
7. **One existing test asserts precisely the contract this ADR changes.**
   `Tests/PraticaSyncTests.swift:736` —
   `#expect(doc.frontmatter.pendingAttachmentNames == ["20260610_logo.png"])`, inside
   `aZeroByteInlineImageIsNeverPlacedAndLeavesNoDanglingCidOrEmbedReference`. It is not a wrong
   test; it asserts ADR-0040 §D9 item 2, which this ADR replaces. It moves (plan Task 5). Its
   fixture, `EmailFixtureCorpus.singleInlineImageMessageRFC822` (`:260-292`), puts the reference in
   the **plain-text** body as a bare `cid:…` — so the bare form is real, is covered, and §D4 must
   handle it, not only the markdown-image form.
8. **The connector leaks the phantom names into JSON today.**
   `Sources/Connector/VaultPratiche.swift:216` maps every entry of `mail.attachments`, pending ones
   included, into `PraticaTimelinePayload.Entry.attachments`. So `perg pratiche --json` currently
   lists ten attachments that do not exist either. This fix removes them with no connector edit and
   no payload-shape change (`VaultAPI.PraticaSummary` is untouched, R-13 of ADR-0040 still holds).

---

## Decision

### §D1 — An inline image gets two representations, one per question, and leaves the attachment list entirely

The two questions are different and must not share a field:

| Question | Answer lives in | Why there |
|---|---|---|
| *Where does the picture go?* | a placeholder in the body, at the reference it replaced (§D2) | it is the only place that carries position, and position is the thing being lost |
| *Should the next sync look again?* | `pergamenum-mail-inline-pending` in the frontmatter (§D3) | a guard must answer it without parsing prose, and the person must be able to see the state on disk |

**An inline image never appears in `pergamenum-mail-attachments` again**, in either form. It is not
an attachment: it has no chip today when it works, and it must have none when it does not. That one
sentence is what removes the pills — from `PraticaMessageRow`'s chip row, from
`PraticaRowDetail.pendingAttachments`, from the accessibility label's «N allegati», and from the
connector's JSON — without a line changing in any of those four places (§D10).

### §D2 — The placeholder is one italic Italian sentence, spelled in exactly one place

```swift
enum MessageInlineImage {
    /// `*[immagine non ancora caricata]*` - what stands where an inline image will go
    /// until Mail has its bytes (ADR-0042 §D2).
    static let placeholder = "*[immagine non ancora caricata]*"
}
```

`Sources/Core/Pratiche/MessageInlineImage.swift`, Foundation only, picked up by `Sources/Core/**`
with no manifest edit — though a *new file* still needs `tuist generate` before it compiles
(CLAUDE.md).

Four constraints decided it, and it is the only form that meets all four:

- **It must be legible as text in three renderers and in a plain editor.** Italic markdown is:
  `MarkdownInline.emphasis` styles it in the timeline, `MarkdownStyler` styles it in the editor,
  Obsidian styles it, `cat` shows it. A wikilink, a markdown image or a markdown link would each be
  drawn as a *broken affordance* in at least one of them (finding 3, A4, A5).
- **No emoji, no glyph.** CLAUDE.md's design system says so, and the app's own
  `pendingPlaceholder` (finding 4) is the precedent being followed rather than a new style being
  invented.
- **It must not enter the vault's link graph.** Square brackets around plain words are not a
  wikilink and not a markdown link; nothing indexes it, nothing reports it broken, nothing
  backlinks it.
- **It must be findable by exact string match**, because §D8's patch anchors on it. A sentence in
  Italian inside square brackets inside asterisks does not occur by accident in somebody's mail.

**One placeholder per reference**, not per part: a body that mentions the same `cid:` twice — which
`HTMLTextReducer` can emit, and which the placement branch at `:590-594` already handles as two
embeds — gets two placeholders and two entries in the key (§D3). That is what keeps the two
representations countable against each other (§D8's guard).

### §D3 — `pergamenum-mail-inline-pending`: the content ids, one per placeholder, in the order the placeholders appear in the file

```yaml
pergamenum-mail-subject: "Richiesta offerta"
pergamenum-mail-attachments: ["[[20260610_offerta.pdf]]"]
pergamenum-mail-inline-pending: ["image001.png@01DA5C3E.9F2B1C40", "social-li@01DA5C3E.9F2B1C40"]
pergamenum-mail-body: complete
```

- **Position in the key order:** after `pergamenum-mail-attachments`, before
  `pergamenum-mail-store-references` — added to `MessageDocument.foreignKeys(of:)` and mirrored in
  §D8's insertion rule, so a full render and a patch put the line in the same place.
- **Omitted entirely when empty**, the rule every list key in that function already follows
  (`MessageDocument.swift:139-147`).
- **The value is the raw `Content-ID` with its angle brackets already stripped** — exactly the
  string `MIMEPart.Kind.inlineImage(contentID:)` carries (`MIMEDecoder.swift:58-68`) and exactly
  what `cid:` references in the body match on. Not a file name: a file name is a thing this app
  invents at placement time, and the part has not been placed.
- **Duplicates are legal and meaningful** (§D2): two placeholders for one content id are two
  entries.
- **The frontmatter field:**

```swift
extension MessageDocument.MailFrontmatter {
    /// `pergamenum-mail-inline-pending` (ADR-0042 §D3): the content ids of inline images
    /// this note is still waiting for, one per placeholder, in the order the
    /// placeholders appear in the rendered file. Defaulted empty, so every existing
    /// construction site keeps compiling and every note written before this fix reads
    /// back as "waiting for nothing".
    var pendingInlineImages: [String] = []
}
```

Declared **immediately after `storeReferences`** in `MailFrontmatter`, which is where its key sits
and which keeps every existing memberwise-init call site compiling unchanged (a defaulted parameter
in the middle is legal to omit; `storeReferences` already proves it in this exact type).

**Compatibility runs both ways, and neither direction needs a schema bump.** A note written before
this fix has no such key, so the list reads back empty and nothing about it changes. A note written
after it, read by a build from before it, parses exactly as it does today — `MessageDocument.parse`
reads keys by name and ignores what it does not know. The one asymmetry worth naming: a *pre-fix
build* that fully re-renders a post-fix note (a «Rigenera», or a pending body arriving) drops the
key while leaving the placeholders in the text, which strands them. That is a downgrade scenario,
it loses no content, and «Rigenera» on the new build repairs it.

### §D4 — One rule replaces a `cid:` reference, and all three inline branches use it

```swift
extension MessageInlineImage {
    /// Every reference to `contentID` in `body` replaced by `replacement`: the whole
    /// `![alt](cid:…)` construct where the reducer wrote one, the bare `cid:…` token
    /// elsewhere (a plain-text body mentions it without markdown -
    /// `EmailFixtureCorpus.singleInlineImageMessageRFC822` is exactly that shape).
    static func replacingReferences(
        to contentID: String, in body: String, with replacement: String
    ) -> String
    /// Whether `body` refers to `contentID` at all - §D5's whole question.
    static func referencesContentID(_ contentID: String, in body: String) -> Bool
}
```

The construct regex is the one already at `PraticaSyncEngine.swift:583-589`, moved rather than
rewritten, `NSRegularExpression.escapedPattern(for:)` included. The three call sites become:

| Branch | Replacement | Change |
|---|---|---|
| placed (`:571-594`) | `![[<placed name>]]` | behaviour identical; the duplicated regex + bare-reference pair becomes one call |
| decorative (`:565-570`) | `""` | **fixes finding 2**: the `![Logo]()` remnant it leaves today disappears |
| not yet available (`:556-563`) | §D6's deferral token | the new behaviour |

Fixing the decorative branch is inside this ADR's scope rather than beside it: it is the same
line, the same defect and the same symptom the person reported («no inline images visible where
they should be»), and leaving it would mean shipping a fix that repairs the rarer half of what they
saw.

### §D5 — A part the body never referenced is not waiting for anything

If `referencesContentID` is false — the overwhelmingly common case, because the body came from the
`text/plain` alternative (finding 1) — the not-yet-available inline part produces **no placeholder,
no frontmatter entry, and no retry**. There is no position to mark and nothing the note is missing:
that picture was never in this note and would not be there if Mail had every byte of it.

This is the rule that removes most of the reported pills, and it is also this ADR's honest limit,
stated rather than hidden: **when the body is the plain-text alternative, an inline image that is
missing gets no marker, because the alternative that contains it is not what the note is made of.**
Changing which alternative the body comes from is an ADR-0036 decision («text/plain preferred»)
with consequences far outside this defect, and it is not reopened here. A follow-up worth
considering on its own merits, and deliberately not bundled: prefer the HTML alternative when it
embeds inline images and the plain one does not mention them.

The `.usable` inline branch is **not** made conditional on a reference. It still places an
unreferenced inline image into `allegati/` exactly as today. That is arguably an orphan file, but
changing it deletes a behaviour three green tests rest on for no gain to this defect.

### §D6 — The order is taken after the split, in render order, through a deferral token

`prepare` cannot record the key's order as it goes: it walks MIME parts, and the file's order is
the order of the *placeholders*, which is decided by the body text and then rearranged by
`QuoteSplitter` (finding 5). So:

1. In the part loop, a deferred inline image's references are replaced by
   `MessageInlineImage.deferralToken(forPart: ordinal)` — a unique, non-prose token per part.
2. `QuoteSplitter.split` runs as it does today.
3. One pass, over the three pieces **in `MessageDocument.render`'s own order** — `newText`, then
   `quotedHistory`, then `signature` — turns every token into the placeholder and reports the
   content ids in the order encountered:

```swift
extension MessageInlineImage {
    static func deferralToken(forPart ordinal: Int) -> String
    /// `texts` in the order the file will carry them. Returns the same count of texts,
    /// tokens replaced by `placeholder`, plus the content ids in placeholder order -
    /// which is what `pergamenum-mail-inline-pending` records (§D3).
    static func resolvingDeferralTokens(
        in texts: [String], contentIDByOrdinal: [Int: String]
    ) -> (texts: [String], pending: [String])
}
```

A token rather than sorting by offset because offsets move as each replacement is made, and because
the token also survives `QuoteSplitter`'s slicing untouched. It never reaches disk: a token left in
a rendered note would be a bug the round-trip test in plan Task 2 fails on.

### §D7 — The retry is one more clause in the two places ADR-0040 already widened — this is the amendment to ADR-0036 §D6

ADR-0036 §D6, as amended by ADR-0040 §D5, lists three automatic exceptions to «a sync never
rewrites a message file». **It gains a fourth, and only this:**

> — a `.complete` message whose `pergamenum-mail-inline-pending` carries at least one content id
> (ADR-0042 §D3), whose note is then amended in its placeholders and that one key line, and never
> re-rendered (ADR-0042 §D8).

Mechanically, one clause in each of the two selections ADR-0040 already touched:

```swift
// PraticaSyncEngine.prepare, the §D6 guard at :467-479
let hasPendingInlineImages = !existing.document.frontmatter.pendingInlineImages.isEmpty
guard isRequestedRegeneration
    || (existing.document.frontmatter.body == .pending && !isPending)
    || hasPendingAttachments
    || hasPendingInlineImages
else { return nil }

// PraticaSyncEngine.regeneratePending, the selection at :900-902
```

**No cap, no cooldown, no terminal state**, for ADR-0040 §D5's reason unchanged: the app cannot
tell «still downloading» from «never coming», and a cap turns the first into a silent permanent
loss. The cost stays zero because ADR-0040 §D6's no-op rule governs the write: a retry that
resolves nothing produces text identical to what is on disk and writes nothing at all.

### §D8 — Two patches, one write: the body's placeholders and one frontmatter line, never a re-render

Three pure types, all `Sources/Core/Pratiche/`, all Foundation only:

```swift
/// The line surgery `MessageAttachmentPatch` already performs, with the key as an
/// argument - extracted so the second key cannot drift from the first (finding 6).
/// `MessageAttachmentPatch.applying(entries:to:)` keeps its exact signature and
/// delegates here; its 60-odd existing assertions do not move.
enum MessageFrontmatterPatch {
    /// `nil` when `text` carries no `pergamenum-mail` frontmatter to patch. `line` is
    /// `nil` to remove the key. `before` is the key order to insert in front of, first
    /// match wins, `MessageDocument.foreignKeys(of:)`'s own order.
    static func applying(line: String?, forKey key: String, before: [String], to text: String) -> String?
}

enum MessageInlineImagePatch {
    /// What a fresh decode found for an inline image the note is waiting for.
    enum Resolution: Equatable, Sendable {
        /// Placed in `allegati/`; its placeholder becomes `![[fileName]]`.
        case embedded(fileName: String)
        /// Usable and decorative (ADR-0040 §D9 item 1 order preserved): the placeholder
        /// goes, nothing replaces it.
        case dropped
    }
    struct Outcome: Equatable, Sendable {
        var text: String
        /// What `pergamenum-mail-inline-pending` becomes: the ids still waiting, in
        /// placeholder order.
        var remaining: [String]
        /// Resolved images whose placeholder is no longer in the file, so they are
        /// linked as ordinary attachments instead of losing the picture (see below).
        var unplaceable: [String]
    }
    /// `pending` is the note's own recorded list, in placeholder order; `resolved` maps
    /// a content id to what this sync found for it. Total: `nil` only when `text`
    /// carries no `pergamenum-mail` frontmatter.
    static func applying(
        resolved: [String: Resolution], pending: [String], to text: String
    ) -> Outcome?
}
```

**The count guard is the whole safety argument.** The patch counts placeholder occurrences in the
file's body region. If that count equals `pending.count`, the k-th placeholder *is* the k-th
recorded id — by construction, because §D6 wrote them together in one order — and the patch
replaces in place. If the counts differ, somebody has edited the prose: **no placeholder is touched
at all**, every `.embedded` resolution is reported in `unplaceable`, and `commit` links those as
ordinary `[[…]]` attachment entries. A picture in the wrong paragraph is a content error this repo
does not accept on a probability argument; a picture as a chip is merely a lesser answer.

`commit`'s patch mode (ADR-0040 §D4's fourth row, `PraticaSyncEngine.swift:823-855`) composes the
two patches and still writes once:

1. `MessageInlineImagePatch.applying(...)` on the on-disk text → text and `remaining` (the key line
   is rewritten inside it, through `MessageFrontmatterPatch`).
2. `MessageAttachmentPatch.applying(entries:)` on that result, with `entries` =
   `prepared.document.frontmatter.attachments` + `unplaceable.map(attachmentEntry(linking:))`.
3. **ADR-0040 §D6's no-op rule, unchanged**: identical to what is on disk → nothing is written,
   nothing is appended to the outcome.
4. Otherwise one `write`, `outcome.resolvedAttachmentFiles.append(notePath)` — whose doc comment
   widens from «attachment list» to «attachment list or inline-image placeholders». **No new
   `SyncOutcome` field**: the pane's existing signal is the right one and ADR-0040 §D10's
   `regeneratedPendingFiles` still means only what it meant.

The `.eml` sidecar is not rewritten in patch mode (ADR-0036 §D18, unchanged). `mustFullyRender`
gains no row: an inline image can never become a `StoreReference` (the threshold branch belongs to
`.attachment` parts alone), so the one case ADR-0040 had to fall back to a full render for cannot
arise here.

`PreparedMessage` carries the resolutions across:

```swift
/// ADR-0042 §D8: what this decode found for each inline image, by content id - the
/// input to the patch. Empty on a fresh import: nothing is waiting yet.
var inlineResolutions: [String: MessageInlineImagePatch.Resolution]
```

### §D9 — A late inline image goes back where it was; a late *decorative* one leaves no trace — this replaces ADR-0040 §D9 item 3

ADR-0040 §D9 item 1's order — integrity first, `isDecorative` second — is unchanged and is what
makes this work: a corrupt image's dimensions are unreadable, so `isDecorative` answers «keep it»
for a guess, and only bytes that passed `AttachmentIntegrity` are ever judged decorative.

On the sync where Mail finally has the bytes:

- usable and not decorative → placed through the existing `place(...)` (same dedup, same `-2`
  collision rule) → its placeholder becomes `![[<name>]]`, **in the position the sender put it**;
- usable and decorative → its placeholder is removed, because a signature logo is not content and
  ADR-0036's rule about that has not changed;
- still not usable → its placeholder and its entry stay, and the next sync asks again.

The cost ADR-0040 §D9 item 3 accepted — «a late inline image loses its position in the prose» — is
hereby repaid, and the chip it produced instead is gone.

### §D10 — No chip, no new field, no controller change; the migration is one sync, and «Rigenera» is the only manual path

**`PraticheController` and `PraticaMessageRow` change by nothing at all**, and that is the design
rather than an omission. `PraticaRowDetail.pendingAttachments` (`PraticheController.swift:796`) is
fed by `MailFrontmatter.pendingAttachmentNames`, which after §D1 only ever contains real
attachments; the pills stop because the entries stop being written, not because a view learned a
new case. The same holds for `hasAttachments` (`:772`), the accessibility label's «N allegati»
(`PraticaMessageRow.swift:233-234`) and the connector's JSON (finding 8). Five surfaces corrected
by one upstream rule, with no drift surface added.

**A pending inline image gets no chip of any kind** — not one per image, not one summary pill
(A3). The placeholder is the surface; the collapsed row must not claim attachments a message does
not have, which is the exact misreading that started this.

**Migration is free for the pills and partial for the positions.** A note already written by the
ADR-0040 build carries bare inline names in `pergamenum-mail-attachments`, so ADR-0040 §D5's own
guard already revisits it at the next sync; `prepare` re-decodes, produces an attachment list
without them, and the one-line patch removes them. The pills disappear on the first sync after the
upgrade, per pratica, with no command to run. **The positions cannot be recovered automatically**:
that build stripped the `cid:` references and recorded nowhere that they had existed, so patch mode
has no place to insert a placeholder. Such a note is therefore *not* given a
`pergamenum-mail-inline-pending` key either — adding one would resurrect the chips through
`unplaceable` for exactly the images whose chips this ADR removes. The consented, diffed path
exists and is unchanged: «Rigenera» on that message re-renders it with correct placeholders
(ADR-0036 §D21).

---

## Alternatives considered

**A1 — Keep everything inside `pergamenum-mail-attachments` with a third entry form** (say
`(cid:…)`-wrapped, or a `!`-prefixed bare name). Rejected. ADR-0040 §A1's argument — one list
cannot desynchronise with itself — is about one *set*; this is a second set, with different
semantics, a different renderer and a different lifecycle. A third form would have to be learned by
`isPendingAttachmentEntry` (a protected interface), by `linkedAttachmentNames`, by
`PraticheController.readMessages`, by `VaultPratiche.messageRows` and by
`PraticheController.attachmentFileName(fromWikilink:)` — five readers, each of which draws a chip
today and would draw a wrong one until it was taught otherwise. The whole point of the fix is that
an inline image is *not* an attachment; encoding it in the attachment list keeps the confusion and
adds a dialect. A prefixed key is the mechanism this repo has for exactly this
(ADR-0020, ADR-0036), and it costs one line in `foreignKeys(of:)` and one in `parse`.

**A2 — No frontmatter key: find pending inline images by scanning the body for the placeholder.**
Rejected, though it is cheaper than it looks (`folderContext` already reads every message file, so
the scan is free). Two reasons. It makes a prose string the schema: a person who edits the sentence
— or translates it, or removes the asterisks — silently switches off the retry with no way to tell
that it happened. And the join it would leave is *order against order*, the fresh decode's against
the body's, with nothing recorded to cross-check; §D8's count guard exists precisely because the
recorded list makes that check possible. A key that can be `grep`-ed is also how a person, or a
future reader of a vault, can see what the app is waiting for.

**A3 — One summary chip per message: «3 immagini non ancora caricate».** Rejected for this ADR,
and worth reconsidering later on its own merits. It is a smaller lie than ten pills but it is the
same shape of lie: a chip in the attachment row of a collapsed message says «this message has
things attached to it», and the person's report began with exactly that reading. The information
belongs where the picture belongs. Cost of adding it later: one `PraticaRowDetail` field and one
`AttachmentChip.Content` case, no format change — the key this ADR adds is already the data source.

**A4 — Write the eventual embed immediately: `![[20260610_logo.png]]`, and let it resolve when the
file appears.** Rejected, and it is the most elegant-looking option. Three defects. The eventual
name is not predictable: `place` appends `-2`, `-3` on a collision (`:950-960`), so the embed can
be permanently broken by an unrelated attachment landing first. A decorative verdict on arrival
still requires a body edit, so it does not even remove the need for a patch. And it puts a broken
embed into the vault's own link graph and into Obsidian's broken-link list, with no text saying
why — which is symptom 3 with an error badge instead of an explanation.

**A5 — Keep the reference as the anchor: `![immagine non ancora caricata](cid:…)`.** Rejected on
evidence, not taste. It is genuinely the tidiest join (the existing regex finds it, the content id
is right there), but finding 3 shows what it renders as: `MarkdownInline` treats `![…](…)` as a
link and `MarkdownBlocksView` hangs `URL(string: "cid:…")` on it, so the timeline and the editor
both offer a click that macOS answers with «no application can open this URL», and Obsidian draws a
broken image. A marker whose purpose is to explain an absence must not itself be a broken
affordance.

**A6 — Re-render the whole note when an inline image arrives, reusing the «Rigenera» path.**
Rejected, for ADR-0040 §A3's three reasons verbatim and unchanged: it discards prose a person added
outside the three regions `splitBody` models, it rewrites the file (and its modification date) on
every sync for an image that never arrives — feeding `lastActivity`, `messagesSinceLastOpen` and
the watcher — and it re-enters the class of defect this repo has documented four times. §D8's patch
costs two pure functions and their tests.

**A7 — Bump `pergamenum-mail` from 1 to 2.** Rejected. The key is additive and optional in both
directions (§D3), so no reader needs to branch on a version, and a version nothing branches on is a
number that goes stale. The one thing a bump could have discriminated — a pre-fix body whose
placeholder positions are unknowable — is answered directly and more honestly by counting
placeholders (§D8), which is a fact about the file rather than a claim about the build that wrote
it.

**A8 — Give pre-fix notes a `pergamenum-mail-inline-pending` key anyway, so their inline images at
least arrive as chips.** Rejected. It reintroduces a pill for precisely the class of image this ADR
exists to stop putting pills on, and it does so on the notes the person is already looking at. The
content is not lost either way — the bytes stay in Mail, and «Rigenera» produces a correct note on
demand, with a diff, on that one message.

**A9 — Put the placeholder and the patch in `Sources/Features/Pratiche/`.** Rejected, for ADR-0040
§A9's argument: they are pure functions over text with no UI, no actor and no vault knowledge, and
their siblings (`MessageDocument`, `MessageAttachmentPatch`) are in `Sources/Core/Pratiche/`.
`MessageDocument.parse` must read the new key for the connectors too, and `Sources/Core` is what
both command-line targets compile.

**A10 — A per-placeholder visible ordinal, `*[immagine non ancora caricata (2)]*`, so the join
survives any edit.** Rejected. It makes the join exact against a reordering of paragraphs between
two syncs — a case §D8's count guard does not catch — at the price of a number in somebody's prose
on every one of eight signature icons, forever, including the images that never arrive. The guard
catches the realistic edit (a deletion); the unrealistic one (reordering paragraphs that contain
placeholders, between syncs, without changing their number) is recorded in the negative
consequences rather than paid for in every note.

---

## Consequences

### Positive

- The reported symptom disappears twice over: §D5 removes the pills for parts the body never
  referenced (the common case, finding 1), and §D1 removes them for the parts it did.
- An inline image that is not there yet *says so*, in Italian, in the place it will appear — the
  only place where that sentence answers the question the person actually has.
- When Mail catches up, the picture lands back in the sentence it belonged to, with nobody doing
  anything and nothing else in the note changing. ADR-0040 §D9's stated cost is repaid.
- A decorative signature logo that arrives late leaves no trace at all — no chip, no placeholder,
  no file in `allegati/` — which is what ADR-0036 always wanted for signature furniture.
- The `![Logo]()` remnant the decorative and pending branches leave in every HTML-derived body
  today is gone (finding 2), and all three inline branches now share one replacement rule that can
  only be wrong in one place.
- Five surfaces — the chip row, `hasAttachments`, the accessibility label, `perg pratiche --json`
  and the MCP timeline — are corrected without a line changing in any of them.
- Existing vaults heal their pills on the first sync after the upgrade, per pratica, with no
  migration to run and no flag to persist.
- No new dependency, no framework, no index field, no manifest edit, no schema bump, no network.
  Three new Foundation-only files under a glob that already exists.

### Negative

- **An inline image missing from a message whose body came from the `text/plain` alternative gets
  no placeholder** (§D5). The note is no worse than today and the phantom chips are gone, but the
  person is told nothing, because the note is not made of the part that contained the picture.
  Named, bounded, and left to a follow-up that would have to reopen ADR-0036's body-selection rule.
- **A note written by the ADR-0040 build never regains its inline-image positions automatically**
  (§D10). Its pills go; its pictures come back only through «Rigenera», by hand, one message at a
  time.
- **If a person deletes some but not all placeholders from a message note, every image that later
  arrives for that message becomes an attachment chip instead of an embed** (§D8's guard). Content
  preserved, position lost, silently.
- **If a person reorders paragraphs containing placeholders between two syncs without changing
  their number, a resolved image can land at the wrong placeholder.** The guard cannot see it
  (A10). Judged far-fetched, recorded rather than engineered against.
- **A resolved image inside the quoted history or the signature renders as literal `![[…]]` text in
  the timeline**, because `PraticaMessageRow` draws those two regions with `Text`, not
  `MarkdownBlocksView` (`:166-169`, `:189-191`). It renders correctly in the editor and in
  Obsidian. Mostly theoretical: a signature image large enough to survive `isDecorative` is rare.
- **`Tests/PraticaSyncTests.swift:736` asserts the contract this ADR replaces** and must move. It
  is enumerated in the plan's staleness table so the coder does not discover it.
- **`MailFrontmatter` grows a field and `foreignKeys(of:)` a key**, so every round-trip test of
  that type is in the blast radius even though all of them should pass unchanged.
- The sync does marginally more work per deferred inline part: one token substitution and one
  ordered scan of three strings, on text already in memory.

### Neutral

- `pergamenum-mail` stays at schema 1; `IndexCache.schemaVersion` stays 3.
- `MessageAttachmentPatch.applying(entries:to:)` keeps its signature exactly and delegates; its
  tests do not move.
- `SyncOutcome` gains no field. `resolvedAttachmentFiles` widens in meaning by one sentence of doc
  comment; `regeneratedPendingFiles` keeps its ADR-0036 meaning untouched.
- `AttachmentChip`, `AttachmentChipModel` and their 21 assertions are not touched by this ADR at
  all.
- The connectors compile the three new Core files and gain no capability: a pending inline image is
  invisible to `perg` and `pergamenum-mcp`, by the structural rule ADR-0036 §D19 already enforces.
- The UI suite is unaffected: no accessibility identifier changes and no new launch argument. The
  four flags every UI-test file passes (`-disableCalendar`, `-disableUpdater`, `-mailStoreRoot`,
  `-recentVaults`) are unchanged.
- A new file under `Sources/Core/**` needs no `Project.swift` edit but does need
  `tuist generate --no-open` before it builds.

---

## Protected-interface proposal (ADR-0053 — proposed, not written)

One candidate. The architect cannot create `.claude/protected-interfaces`; the operator does, at
Gate 2, if they want the protection — and it BLOCKS once it exists.

```
Sources/Core/Pratiche/MessageInlineImage.swift:MessageInlineImage.placeholder — added 2026-09-12 per ADR-0042 §D2; this exact string is written into the body of every message note on disk and is the only anchor the retry has for putting a late inline image back where it belongs. A silent change strands every placeholder already written: the count guard then refuses to patch, and every image that arrives afterwards becomes a chip instead of an embed.
```

Deliberately *not* proposed: `MessageInlineImagePatch.applying` (pure logic, expected to be tuned)
and the `pergamenum-mail-inline-pending` key name (already guarded by the note format's own
round-trip tests).

---

## References

- `docs/adr/0040-pratiche-attachment-reliability-bugs.md` — §D9 (amended here), §D3, §D4, §D5, §D6,
  §D7, §D8, §D10 and A1/A3/A9 (arguments reused).
- `docs/adr/0036-pratiche.md` — §D6 (widened by one clause, §D7 here), §D18, §D19, §D21.
- `docs/adr/0020-image-card-crop.md` — the prefixed-key precedent, spent here.
- `Sources/Features/Pratiche/PraticaSyncEngine.swift` — `:467-479` (the guard), `:509-599` (the part
  loop), `:547-594` (the three inline branches), `:600-603` (the split), `:786-885` (`commit`),
  `:892-912` (`regeneratePending`), `:991-1000` (`bodyText`), `:1062-1063` (the italic-placeholder
  precedent).
- `Sources/Core/Pratiche/MessageDocument.swift` — `:59`, `:113-164`, `:212-248`, `:459-506`.
- `Sources/Core/Pratiche/MessageAttachmentPatch.swift` — `:16-57`.
- `Sources/Core/Email/MIMEDecoder.swift:58-68`, `Sources/Core/Email/MIMEPart.swift:12-14`,
  `Sources/Core/Email/HTMLTextReducer.swift:311-318`,
  `Sources/Core/Email/InlineImageClassifier.swift`.
- `Sources/Core/Markdown/MarkdownInline.swift:90-99`,
  `Sources/Features/Editor/MarkdownBlocksView.swift:245-252`.
- `Sources/Features/Pratiche/PraticheController.swift:746-799`, `:880-886`;
  `Sources/Features/Pratiche/PraticaMessageRow.swift:118-148`, `:166-191`, `:226-238`.
- `Sources/Connector/VaultPratiche.swift:193-221`.
- `Tests/PraticaSyncTests.swift:708-737`, `Tests/EmailFixtureCorpus.swift:260-292`,
  `Tests/MessageDocumentTests.swift:151-211`, `Tests/MessageAttachmentPatchTests.swift`,
  `Tests/PraticheControllerTests.swift:403-440`.
