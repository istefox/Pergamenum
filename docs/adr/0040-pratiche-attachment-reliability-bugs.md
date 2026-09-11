# ADR-0040: An attachment Mail has not finished writing is a state, not a file

- Status: proposed
- Date: 2026-09-11. Written after reading every file it names, at the line, on the working tree at
  `7381877` (`main`, marketing version 1.4). Every claim below about this repo's code was read out
  of `Sources/` and `Tests/`, not out of the SPEC; the two fixture collisions in §"What was read"
  were found by grep, not predicted.
- **Relocation note:** this file is written at
  `docs/architecture/ADR-0040-pratiche-attachment-reliability-bugs.md` because that is the
  architect's enforced write scope (`test-write-scope.sh`); the orchestrator relocates it to
  `docs/adr/0040-pratiche-attachment-reliability-bugs.md`, which is where this repo's ADRs live
  (`0001`…`0039`) and which is the path the plan and every reference below assume. Same convention
  ADR-0029…ADR-0036 carry in their own headers.
- **Amends ADR-0036 §D6** — «a sync never rewrites a message file, with exactly two exceptions» —
  by adding a third, and by narrowing its companion sentence «a sync never deletes a file». Both
  amendments are stated exactly, in §D5 and §D7 below. **Nothing else of §D6 changes**, and
  **§D21 («Rigenera» acquires the replacement before it destroys anything) is not reopened**: the
  third exception is mechanically disjoint from it (§D4's write-mode table), so the bytes a
  «Rigenera» diff shows are still the bytes it writes.
- **Reopens nothing else of ADR-0036.** §D1 (SQLite in one file), §D2 (the published generation
  copy), §D3 (the ledger bridge), §D4 (the locator), §D5 (`pratica.md` has one editor), §D7
  (`MailStoreLocation` is test-aware), §D12 (the dossier line codec), §D14 (one actor, one write
  hop), §D15 (duplicate resolution), §D19 (the connectors cannot open the store) are all untouched.
- **Adds no exception to CLAUDE.md principle 2.** No network call, no socket, no loopback, no new
  framework that could make one. The whole fix is byte comparison on data already in memory or
  already on disk.
- **Does not reopen the closed frontmatter schema, and adds no key to it.** The new state is
  expressed inside the `pergamenum-mail-attachments` key ADR-0036 already writes (§D3).
  `IndexCache.schemaVersion` stays 3. `MessageDocument`'s own
  `pergamenum-mail` schema version stays 1 — a file written before this fix parses unchanged, and
  a file written after it parses correctly in a build from before it (§D3's compatibility note).
- **Touches none of the three protected interfaces ADR-0036 declared.**
  `PraticaNaming.messageFileName`, `Dossier.render` and `VaultAPI.PraticaSummary` keep their
  signature and their behaviour (R-13). One *new* protected-interface entry is proposed to the
  operator, not written (§"Protected-interface proposal").
- Depends on: **ADR-0036** in full (this is a defect fix inside that feature), **ADR-0020** (a
  prefixed key is how this repo extends a closed schema — cited here only to say the precedent is
  *not* spent again), **ADR-0022 §D6** (a deletion in this repo goes to the Trash through
  `FileManager.trashItem`, never `removeItem`), **ADR-0053** (protected interfaces are proposed by
  the architect and created by the operator), **ADR-0155** (on a compiled language the tester owns
  the declaration, the coder owns the body).

---

## Context

Pratiche copies an email's attachments into `<pratica>/allegati/` and links them from the message
note by wikilink. In use, three things go wrong, and they are one thing:

1. A file lands in `allegati/` with zero bytes, or with bytes that are not the file the sender
   attached. Finder cannot open it («il file è vuoto»); the timeline chip hands the same URL to
   Quick Look and fails the same way.
2. A message whose attachments Mail has not yet materialised on this Mac produces a note with no
   attachment at all — the email visibly has one in Mail, the note has none.
3. Whichever of the two happened, it is permanent. ADR-0036 §D6 says a sync never rewrites a
   message file; the one automatic exception is a `pergamenum-mail-body: pending` note whose body
   has since arrived. A `.complete` note written at an unlucky instant is never revisited, so the
   damage survives every subsequent sync until a person notices and runs «Rigenera» by hand.

The cause is one line. `PraticaSyncEngine.prepare` reads

```swift
let bytes = part.decodedData ?? Data()
```

(`PraticaSyncEngine.swift:397`, and again at `:417` for an inline image) and then hands those
bytes, unexamined, to `place(_:named:date:nameByDigest:taken:)`, which SHA-256s them, reserves a
file name and schedules the write. Empty is a value like any other: it hashes, it gets a name, it
is written. Worse, it hashes *the same way every time* — two unrelated attachments that both came
back empty share a digest, so the second is «already in this pratica» and is linked to the first
one's name (`:729`). The dedup is not wrong; it is being fed bytes that mean «not here yet».

Nothing in this app can make Mail finish downloading an attachment. There is no channel to ask,
and principle 2 forbids opening one. What the app *can* do is notice that the bytes are not the
file yet, refuse to write them, say so on the chip, and look again at the next sync — forever, at
no cost, because a sync already reads every one of those bytes.

### What was read in this repository, at the line, before deciding

Seven findings. The first three would each produce a shipped defect if the SPEC were implemented
literally.

1. **Two existing tests assert the behaviour this fix removes, and a third fixture is complicit.**
   `Tests/PraticaSyncTests.swift:254` and `:293` build attachments named `offerta.pdf` whose bytes
   are `Data("contenuto-identico".utf8)` / `"versione 1"` / `"versione 2, diversa"`, and assert the
   files land in `allegati/`. `EmailFixtureCorpus.mixedMultipartMessageRFC822:129` carries
   `cGRmLWJ5dGVz` — base64 for `pdf-bytes` — as an `application/pdf` part. Under any rule that
   consults the `.pdf` extension, all three are «not a PDF» and the two sync tests go red. They are
   not wrong tests; their fixtures were never meant to be PDFs. They move with the change (plan
   Task 2), and the move makes them more realistic, not less.
2. **`Tests/PraticaSyncTests.swift:333`'s over-threshold fixture is safe by luck.** Its attachment
   is `disegno-staffa.dwg` filled with `0x41`. `.dwg` has no signature entry in this design, so it
   passes on non-emptiness alone (R-03) and the test stays green. Had it been named `.pdf`, R-07
   would have silently broken the threshold test too.
3. **The store-reference branch can never see empty bytes, and that is a trap, not a relief.**
   `prepare` decides «over threshold» with `bytes.count > thresholdBytes(...)`
   (`PraticaSyncEngine.swift:398`), so a zero-byte part always takes the *copy* branch. R-07 is
   therefore not about the empty case at all: it is about a large attachment whose decoded bytes
   are present but wrong, and about the chip that opens the path recorded for it. Both halves are
   designed (§D2, §D8); an implementation that only guards the copy branch satisfies nothing.
4. **`MailFrontmatter.attachments` is already `[String]` of raw wikilink text**
   (`MessageDocument.swift:59`, written at `PraticaSyncEngine.swift:491` as `links.map { "[[\($0)]]" }`,
   read back by `list("pergamenum-mail-attachments", lines)` at `:229`). It is a list of opaque
   strings that already round-trips anything. A second state fits inside it without a new key, a
   new parser or a schema bump (§D3).
5. **`PraticheController.attachmentFileName(fromWikilink:)` (`:865`) strips `[[`/`]]` if present
   and returns the string otherwise unchanged.** It cannot tell a linked entry from a bare one —
   so a pending entry reaching it silently becomes a normal chip pointing at a file that is not
   there. `readMessages` (`:771`) is the call site, and it is in this fix's scope.
6. **`AttachmentChipModel`'s six static functions all take `fileExists: (URL) -> Bool`**
   (`AttachmentChipModel.swift:21-59`), injected from `AttachmentChip.swift:72` and exercised by
   21 assertions in `Tests/AttachmentChipTests.swift`. R-09 needs a third answer («the file is
   there and is not usable»), which a `Bool` cannot carry. Every one of those 21 assertions moves
   (§D8, plan Task 7).
7. **`folderContext(of:)` already reads and hashes every byte of every file in `allegati/`**
   (`PraticaSyncEngine.swift:272-285`), on every sync, before any decision is made. The one-time
   repair pass R-10 asks for costs nothing beyond what is already read — which is what makes §D7's
   «run it every sync and drop the migration flag» affordable rather than wasteful.

### What a magic-byte check can and cannot prove

Stated plainly because the SPEC's objective says «empty or truncated» and only one of those two
words is fully answered here.

- **Empty is decided exactly.** `bytes.isEmpty` is not a heuristic.
- **A head signature catches a part whose bytes are a placeholder, an error page, an
  `X-Apple-Content-Length` stub, or another file entirely.** It does not catch a file that begins
  correctly and stops early.
- **A terminator check catches most of the rest**, and costs four more byte comparisons on data
  already in memory: a PDF ends with `%%EOF`, a PNG with an `IEND` chunk, a JPEG with `FF D9`, a
  ZIP with an end-of-central-directory record. §D2 adopts it, **but only for a part whose head
  signature already matched**, so it can never reject a format this app does not recognise.
- **A file that is truncated inside a valid head and a valid tail is not detectable without
  parsing the format.** §"Alternatives considered" A5 records why that parsing is not done. The
  residue is a real, named limitation, not an oversight.

---

## Decision

### §D1 — Integrity is one pure Foundation type, it answers a verdict rather than a `Bool`, and it lives beside `InlineImageClassifier`

`Sources/Core/Email/AttachmentIntegrity.swift`, Foundation only. It joins the file family
`EMLXReader`/`MIMEDecoder`/`EMLXLocator`/`InlineImageClassifier` already form, is picked up by
`Project.swift`'s `Sources/Core/**` glob with **no manifest edit** (ADR-0036 finding 7), and is
compiled into `perg` and `pergamenum-mcp` without either of them gaining a way to call it — the
same structural silence ADR-0036 §D19 already enforces for `MailStore*`.

```swift
enum AttachmentIntegrity {
    /// Why an attachment's bytes are not the file the sender attached. `.usable` is the
    /// only verdict that may be hashed, placed or opened.
    enum Verdict: Equatable, Sendable {
        case usable
        /// Nothing at all: Mail has the part's headers and none of its bytes.
        case empty
        /// A signature is known for this part's declared type or extension and the
        /// leading bytes are not it.
        case signatureMismatch
        /// The head signature matched and the format's own terminator is missing -
        /// the download stopped part way (§D2).
        case truncated
    }

    /// Decides on bytes already in memory. `contentType` is the part's declared
    /// `Content-Type` base form (`"application/pdf"`), `name` its declared filename -
    /// either may be `nil`, and a part that offers neither is judged on emptiness alone.
    static func verdict(of bytes: Data, named name: String?, contentType: String?) -> Verdict

    /// Decides on a file already on disk without reading it whole: the size, the first
    /// `signatureWindow` bytes and the last `terminatorWindow` bytes. A 400 MB store
    /// reference must not be slurped to draw a chip (§D8, R-07, R-09).
    static func verdict(ofFileAt url: URL, named name: String?) -> Verdict
}
```

A verdict, not a `Bool`, for one reason: the chip's help text and the sync's diagnostic both have
to say *which* of the four it is, and a `Bool` forces each caller to re-derive that from scratch.
The four cases are also what makes the UI's «in attesa» wording honest — the same word covers all
four because the app genuinely cannot tell «still arriving» from «will never arrive» (R-05's
no-cap rule is the consequence, not the cause).

`isDecorative`'s shape is the precedent being followed here, deliberately: it returns `false` —
«keep it» — when it cannot read the image's dimensions, because *absence of evidence is not
evidence of corruption*. Every branch of `verdict` follows the same rule.

### §D2 — The signature table is keyed by declared content type first and by filename extension second, and the terminator is only checked once the head has matched

Four families, chosen because they are what business mail carries and because each has an
unambiguous, documented head and tail:

| Family | Content types | Extensions | Head | Terminator, searched in the last N bytes |
|---|---|---|---|---|
| PDF | `application/pdf` | `pdf` | `%PDF` | `%%EOF` in the last 2048 |
| PNG | `image/png` | `png` | `89 50 4E 47 0D 0A 1A 0A` | `IEND` in the last 16 |
| JPEG | `image/jpeg` | `jpg`, `jpeg` | `FF D8 FF` | `FF D9` in the last 32 |
| ZIP container | `application/zip`, the three OOXML types, `application/vnd.oasis.opendocument.*` | `zip`, `docx`, `xlsx`, `pptx`, `odt`, `ods`, `odp` | `50 4B 03 04` | `50 4B 05 06` in the last 66_000 |

The rules, in order:

1. `bytes.isEmpty` → `.empty`. Nothing else is consulted. This is the case that actually fires in
   production (R-01).
2. The declared content type is looked up first. `application/octet-stream` — what a great many
   senders and `EmailFixtureCorpus.singleAttachmentMessageRFC822` alike declare — resolves to
   nothing, so the filename extension is consulted next. Keying on the content type alone would
   have missed the most common real shape; keying on the extension alone would misjudge a file
   renamed by a sender.
3. No entry for either → `.usable` (R-03). **Never rejected for want of a signature.**
4. Head mismatch → `.signatureMismatch` (R-02).
5. Head match, terminator absent within its window → `.truncated`. The window is searched, not
   compared to the exact last bytes: a PDF routinely carries whitespace or a linearisation
   remnant after `%%EOF`, and a JPEG may be padded.
6. A file shorter than its own head signature, with a known entry → `.signatureMismatch`.

The ZIP window is 66_000 because a ZIP end-of-central-directory record may be followed by a
comment of up to 65_535 bytes. The JPEG and PNG windows are the smallest that can be correct.

**The terminator check is an addition to what the SPEC asks for**, and is recorded as such: R-02
names only the leading bytes. It is adopted because «truncated» is half of the sentence that
opens the SPEC's own objective and the head check alone cannot answer it, and it is bounded by
rule 5's precondition so that it can never turn a format this app does not know into a rejection.
A reader who disagrees can delete rule 5 without touching anything else in this ADR.

### §D3 — A not-yet-available attachment is a bare file name in the `pergamenum-mail-attachments` list the note already has; the wikilink brackets are the marker

No new frontmatter key, no new file, no schema bump, no migration (the SPEC's Data model is
followed here, not amended).

```yaml
pergamenum-mail-attachments: ["[[20260610_offerta.pdf]]", "20260610_disegno.dwg"]
```

The first entry is placed and linked; the second is known by name and not yet on disk. The
distinction is exactly `hasPrefix("[[") && hasSuffix("]]")` — the form
`PraticaSyncEngine.swift:491` already writes for a resolved attachment.

`MessageDocument` gains the codec and is the only speller of it (tester-declared, ADR-0155):

```swift
extension MessageDocument {
    /// `"[[20260610_offerta.pdf]]"` - the form a placed attachment has carried since
    /// ADR-0036.
    static func attachmentEntry(linking fileName: String) -> String
    /// `"20260610_disegno.dwg"` - a name known, bytes not yet usable (ADR-0040 §D3).
    static func attachmentEntry(pending fileName: String) -> String
    static func isPendingAttachmentEntry(_ entry: String) -> Bool
}

extension MessageDocument.MailFrontmatter {
    /// The `[[…]]` entries, unwrapped: the files really in `allegati/`.
    var linkedAttachmentNames: [String] { get }
    /// The bare entries: what Mail had not finished writing when this note was made.
    var pendingAttachmentNames: [String] { get }
}
```

**The name recorded for a pending entry is the name the file will have once it is placed** —
`PraticaNaming.attachmentFileName(date: <the message's own calendar day>, name: <the MIME
filename>)`, the same call `place` makes — not the raw MIME filename. That function is
deterministic in those two arguments, so the label on the «in attesa» chip is byte-identical to
the file name that eventually appears, and the repair pass of §D7 (which only knows the placed
name) and a fresh capture (which only knows the MIME name) produce the same string for the same
attachment. Two pending attachments of one message that would derive the same name share one
label until they resolve, at which point `uniqueAttachmentName` separates them with `-2`; this is
the same collision `allegati/` has always had, one step earlier.

**Compatibility runs both ways.** A note written before this fix has only `[[…]]` entries, so
`pendingAttachmentNames` is empty and nothing about it changes — that is what makes R-05's
selection rule cost nothing on an existing vault. A note written after it, read by a build from
before it, yields a bare string from `list(...)`, which `attachmentFileName(fromWikilink:)`
returns unchanged: an older build draws a chip for a file that is not there, which is precisely
what that path was already built to survive (`PraticheController.swift:607-609`'s own comment).

### §D4 — One table decides how a message is written, and it is consulted in `commit`, never in the guard

`prepare` answers *what* the note should say. `commit` decides *how much of the file to touch*.
Four rows, exhaustive, evaluated in order:

| Condition | Write mode |
|---|---|
| no file on disk for this `Message-ID` | full render (a fresh import) |
| `request.regenerating == messageID` | full render (ADR-0036 §D21, unchanged) |
| the existing note's `pergamenum-mail-body` is `pending` | full render (ADR-0036 §D6's first exception, unchanged) |
| otherwise | **attachment-line patch only** (this ADR's new third exception) |

The fourth row is the whole of the new behaviour, and it is deliberately *not* expressed as a
condition on the guard in `prepare`: the guard is reached from two callers (the main loop and
`regeneratePending`) and a mode chosen there would differ between them. Chosen in `commit`, it
cannot.

**Why a patch and not a re-render.** A message note is a file a person may annotate — that is the
point of putting mail in a vault. Re-rendering it on every sync would (a) discard any prose added
outside the three regions `MessageDocument.splitBody` models, (b) rewrite the file, and therefore
its modification date, on every sync for an attachment that never arrives, which feeds
`PraticaListItem.lastActivity` and `messagesSinceLastOpen` and makes the pratica permanently
announce news it does not have, and (c) reopen exactly the class of defect this repo has paid for
repeatedly and that ADR-0036 §D5 rejected an entire UI design over. The patch is a pure function
over the file's own text:

```swift
/// Replaces - or inserts, or removes - the single `pergamenum-mail-attachments:` line of
/// an already-written message note, leaving every other byte of the file untouched.
/// `nil` when the text carries no `pergamenum-mail` frontmatter to patch, which is the
/// caller's signal to leave the file alone rather than to write a new one.
enum MessageAttachmentPatch {
    static func applying(entries: [String], to text: String) -> String?
}
```

`Sources/Core/Pratiche/MessageAttachmentPatch.swift`, Foundation only, picked up by the same glob.
Insertion position, when the key is absent, is the one `MessageDocument.foreignKeys(of:)` already
writes: after `pergamenum-mail-subject`, before `pergamenum-mail-store-references` if present and
before `pergamenum-mail-body` otherwise. The line is spelled by
`MessageDocument`'s own quoting, reached through the codec in §D3 — there is one speller of this
line in the codebase, not two.

In patch mode the `.eml` sidecar is not rewritten: its bytes have not changed, and ADR-0036 §D18
ties it to the note's own render.

### §D5 — The retry is `regeneratePending`'s existing selection widened by one clause, with no counter and no cooldown — this is the amendment to ADR-0036 §D6

ADR-0036 §D6 currently reads: «A sync never rewrites a message file, with exactly two exceptions».
**It gains a third, and only this:**

> — a `.complete` message whose `pergamenum-mail-attachments` carries at least one pending entry
> (ADR-0040 §D3), whose note is then amended in one line and never re-rendered (ADR-0040 §D4).

Everything else in §D6 stands. In particular: a sync still never rewrites a `.complete` message
that has no pending attachment entry, and «Rigenera» is still the only path that rewrites one
wholesale, still behind the diff §D21 requires.

Mechanically, two clauses:

```swift
// PraticaSyncEngine.prepare, the §D6 guard at :356-364
if let existing {
    let isRequestedRegeneration = request.regenerating == messageID
    let hasPendingAttachments = !existing.document.frontmatter.pendingAttachmentNames.isEmpty
    guard isRequestedRegeneration
        || (existing.document.frontmatter.body == .pending && !isPending)
        || hasPendingAttachments
    else { return nil }
}

// PraticaSyncEngine.regeneratePending, the selection at :694
let frontmatter = folder.messagesByID[messageID]?.document.frontmatter
guard frontmatter?.body == .pending || !(frontmatter?.pendingAttachmentNames.isEmpty ?? true)
else { continue }
```

No attempt counter, no cooldown, no backoff, and no terminal-failure state (R-05, and the SPEC's
own edge case). The reason is not optimism: it is that the app cannot distinguish «Mail is still
downloading» from «Mail will never have this», and a cap would turn the first into a permanent
silent loss the moment the difference mattered. The cost of being wrong is bounded by §D6's
no-op rule — a retry that resolves nothing writes nothing at all.

The method keeps its name. `regeneratePending` now means «revisit what is not finished», which is
what its own doc comment already says; renaming it would churn two test files for a word.

### §D6 — A patch identical to the file on disk is not written

`commit`, in patch mode, compares the patched text to the text `folderContext` already read for
that file and returns without calling `write` when they are equal. Nothing is appended to the
outcome either.

This is what makes §D5's unlimited retry free rather than corrosive: a message with one attachment
that Mail never materialises is re-decoded on every sync — which costs one `.emlx` read the sync
was doing anyway — and touches nothing. Without this rule the same message would rewrite its own
note on every sync forever, and every derived signal in the pane (last activity, unread count,
the watcher's own change notification) would fire on it.

`FolderContext.ExistingMessage` gains a `text: String` so the comparison needs no second read; it
is a `private` nested type, so this costs no call site.

### §D7 — The repair pass is part of the folder scan, runs every sync, and trashes rather than deletes — this is the narrowing of «a sync never deletes a file»

ADR-0036 §D6's companion sentence, «A sync **never deletes a file** (R-16): a message gone from
Mail loses its link, not its file», is narrowed to:

> — except a file in `allegati/` that fails `AttachmentIntegrity` (ADR-0040 §D2), which is moved
> to the Trash and whose owning message's link becomes a pending entry. No message file and no
> `.eml` is ever deleted, and no valid attachment is ever deleted.

Three decisions inside it:

1. **It is part of `folderContext(of:)`, which already reads and digests every byte of every file
   in `allegati/` (finding 7).** The verdict is taken *before* `digest(of:)` is called, so a
   corrupt file's SHA-256 never enters `attachmentNameByDigest` — which is R-12's other half, and
   the reason two unrelated empty attachments can no longer be treated as the same file.
2. **There is no «first sync» flag.** The SPEC describes a one-time migration; this implements the
   same observable behaviour without persisting a migration marker, because after the first
   post-fix sync there is nothing left for the pass to find — every file written since has passed
   the check at write time. A flag in the ledger would be a second source of truth that is wrong
   after a vault is copied to another Mac, after the ledger is deleted (which ADR-0036 §D-state
   says must lose nothing), or if the process dies mid-pass. It would also save nothing: the bytes
   are read either way. The pass is per-pratica, at that pratica's next sync — there is no
   vault-wide sweep because there is no vault-wide sync in this feature.
3. **`FileManager.trashItem`, never `removeItem`** — this repo has exactly one deletion
   convention and ADR-0022 §D6 states it. If trashing fails (a volume with no Trash, a permission
   refusal), **the file is left alone and its message is not downgraded**; the failure is reported
   through the sync outcome instead. A file that could not be removed but whose link was removed
   anyway would be an orphan nobody can find, and the next arrival of the real bytes would land
   beside it as `-2`.

The downgrade writes themselves are not done inside `folderContext` (which is synchronous and
writes nothing). The scan records the trashed names; one `async` step immediately after it
patches each owning message's attachment line through §D4's patch, updates the in-memory
`FolderContext` so the rest of the same run sees the new pending entries, and runs before the main
loop — so a single sync both repairs a corrupt file and re-imports it if Mail now has the bytes.

### §D8 — The chip's injected `fileExists` becomes a three-state probe, and a pending chip has no URL at all

`AttachmentChip.Content` gains a third case, and `AttachmentChipModel`'s six functions stop taking
`fileExists: (URL) -> Bool` (tester-declared):

```swift
extension AttachmentChip {
    enum Content: Equatable {
        case file(PraticaAttachmentRef)
        case storeReference(MessageDocument.StoreReference)
        /// ADR-0040 §D3: known by name, not yet written - Mail did not have the bytes.
        case pending(name: String)
    }
}

enum AttachmentChipModel {
    /// What the filesystem says about a candidate URL. `.unusable` is new and is why this
    /// is not a `Bool`: a file that is there and is not the file is a different sentence
    /// from a file that is not there, and R-09 forbids handing either to Quick Look.
    enum FileState: Equatable { case usable, missing, unusable }

    static func symbol(for content: Content, state: (URL) -> FileState) -> String
    static func previewURL(for content: Content, state: (URL) -> FileState) -> URL?
    static func openURL(for content: Content, state: (URL) -> FileState) -> URL?
    static func revealURL(for content: Content, state: (URL) -> FileState) -> URL?
    static func copyItems(for content: Content, state: (URL) -> FileState) -> [URL]
}
```

- `.pending` returns `nil`/`[]` from every URL-producing function **without consulting `state` at
  all** — there is no URL to consult one about. Its symbol is `clock.badge.questionmark`, distinct
  from the three that exist.
- `.usable` behaves exactly as `fileExists == true` did; `.missing` and `.unusable` both behave as
  `fileExists == false` did, so no existing *behaviour* changes — only the vocabulary and one new
  symbol (`exclamationmark.triangle` for `.unusable`, so a damaged file reads differently from an
  absent one in the help text).
- The production probe in `AttachmentChip.swift` reads
  `AttachmentIntegrity.verdict(ofFileAt:named:)`, which reads a prefix and a suffix, never the
  whole file (§D1) — this is R-09 and, for a `.storeReference`, R-07's «or handed to the UI» half.
- The chip's label for `.pending` is `In attesa`, not the file name (R-08). The file name moves to
  the help text.
- A click on a pending chip opens a `.popover` carrying one sentence and calls neither
  `onQuickLook` nor `NSWorkspace`. A popover rather than a tooltip because R-08 asks for a
  response to a click, and `.help(...)` is not one. It is local `@State` on the chip: no
  controller, no navigation state, no new type.

`PraticaMessageRow.attachments` renders pending chips **after** the store-reference chips, so the
`pratiche-attachment-<hash>-<n>` identifiers of the existing two groups keep their indices.

### §D9 — An inline image is checked like any other part, but a late arrival becomes a chip and never re-enters the body

`prepare`'s `.inlineImage` branch reads `part.decodedData ?? Data()` too (`:417`) and places those
bytes in `allegati/` exactly as an attachment, so it has the same defect and is covered by the
same check. This ADR reads R-01/R-02's «attachment part» as «any MIME part this engine places into
`allegati/`», which is the set of parts the requirement's own consequence — «never written to
`allegati/`» — can apply to.

Order and outcome:

1. Integrity first, `InlineImageClassifier.isDecorative` second. A corrupt image's pixel
   dimensions are unreadable, so `isDecorative` already answers `false` for it (its own «never
   drop on a guess» rule) and it would otherwise be placed.
2. A non-`.usable` inline image records a pending entry and has its `cid:` reference and the whole
   `![alt](cid:…)` construct stripped from the body — the same removal the decorative branch
   already performs, and the reason the body never ends up with an embed pointing nowhere.
3. **When it later validates, it is placed and linked as an ordinary attachment chip, not
   re-embedded into the body.** The body was written once and §D4 forbids re-rendering it; a late
   inline image therefore loses its position in the prose and keeps its content. That is a stated,
   deliberate cost, taken because the alternative is either a body rewrite (§D4's whole subject) or
   a second, different kind of surgery on somebody's prose.

### §D10 — `SyncOutcome` gains two fields, both defaulted and declared last, and no existing field changes meaning

```swift
/// Note paths whose attachment list this run amended - a pending entry that resolved,
/// or a corrupt file that was trashed and downgraded (§D5, §D7). Never a full rewrite:
/// `regeneratedPendingFiles` keeps its exact ADR-0036 meaning, a `pending` body that
/// arrived, and nothing is added to it by this fix.
var resolvedAttachmentFiles: [String] = []
/// Sentences for the pane's `problem` line: a file that could not be trashed, a
/// downgrade that could not be written (§D7.3). Empty on every healthy run.
var attachmentProblems: [String] = []
```

Defaulted and last for the reason `regenerating` and `storeReferences` already are in this
codebase: every existing construction site, production and test, keeps compiling unchanged.
`static let empty` is updated in the same file. `PraticheController.recordSyncOutcome` surfaces
`attachmentProblems` through the existing `problem` property — a failure this app noticed and did
not say is the thing ADR-0036 §D4 was written against.

---

## Alternatives considered

**A1 — A new frontmatter key, `pergamenum-mail-pending-attachments`.** Rejected. The SPEC's Data
model rules it out explicitly, and independently it is the worse design: two lists describing one
set have to be kept consistent by every writer and every reader, and the failure mode (a name in
both, or in neither) is silent. The `[[…]]`-versus-bare distinction inside the one existing list
cannot desynchronise, because there is only one list. It also spends ADR-0020's prefixed-key
precedent for nothing, when ADR-0036 already spent it for the keys that needed it.

**A2 — A retry counter, a cooldown, or an exponential backoff in the ledger.** Rejected. The SPEC
asks for no cap, and the reason survives scrutiny: the app cannot tell «still downloading» from
«will never complete» without a network call principle 2 forbids, so any cap converts the first
case into a permanent silent loss at whatever threshold was guessed. The usual argument for a cap
— cost — does not apply here, because §D6 makes an unresolved retry write nothing and the `.emlx`
read it performs is one the sync makes anyway. A cap would also need per-attachment persisted
state, which is exactly the new key A1 was rejected for.

**A3 — Re-render the whole note on each retry, reusing `commit` unchanged.** Rejected, and this is
the most tempting of the alternatives: it is four lines and reuses a path that already works
(«Rigenera» does exactly this). It is rejected on three counts. It discards any prose a person
added outside the three regions `splitBody` models — and a message note in a vault is a file
people annotate, which is the point of the feature. It rewrites the file on every sync for an
attachment that never arrives, so `lastActivity`, `messagesSinceLastOpen`, the folder watcher and
the pratica's unread dot all fire forever on nothing. And it walks back into the class of defect
this repo has documented three times (the culling deallocation in ADR-0029, `growToFitTheText`
costing the Diario its typed text, and ADR-0036 §D5 rejecting an entire timeline design over it).
The patch in §D4 costs one pure function and about forty lines of test.

**A4 — A `repairedAt`/`schemaRepairVersion` flag in `PraticaLedger`, so the repair pass runs
exactly once.** Rejected. It is a second source of truth about the state of the files, and it is
wrong in every case where the two can diverge: a vault copied to another Mac (the ledger is
per-machine derived state under Application Support, the `allegati/` files travel with the vault),
a ledger deleted on purpose — which ADR-0036 promises loses nothing — or a process killed
mid-pass, which would leave the flag set and half the folder unrepaired. The pass it would save is
free, because `folderContext` already reads every one of those bytes on every sync (finding 7).
Observable behaviour is identical: after the first post-fix sync the pass finds nothing.

**A5 — Validate the format properly: parse the PDF cross-reference table, walk the ZIP central
directory, decode through ImageIO.** Rejected. It would catch the one case §D2 admits it misses (a
file truncated between a valid head and a valid tail), and it would cost a format parser per
family, an ImageIO round-trip per attachment on every sync, and — decisively — a new class of
false rejection. A valid but unusual file rejected by a strict parser vanishes from the vault into
an «in attesa» chip that, by design (R-05), has no terminal state and no way for a person to say
«no, keep it». `InlineImageClassifier`'s own rule is the precedent: never drop on a guess. §D2's
rules are the subset that can be wrong only when there is positive evidence of corruption.

**A6 — Validate only at open time, in the chip, and leave the write path alone.** Rejected. It
leaves corrupt bytes being hashed and deduped (R-12's exact failure: two unrelated empty
attachments sharing one digest and one file name), leaves the file on disk for Finder and for
Obsidian to trip over, and leaves the message with nothing to retry from — the note would record
a link to a file everybody agrees is bad, with no state saying so. R-09's open-path check is kept
as defence in depth *on top of* the write-path gate, which is what the SPEC asks for and what
makes it honest: it exists for files that reached disk by some route other than this engine.

**A7 — `removeItem` instead of `trashItem` for the repair pass.** Rejected. This repo has exactly
one deletion convention, stated in ADR-0022 §D6 and in CLAUDE.md's own working agreements, and it
is the Trash. A file the app judged corrupt on a heuristic is precisely the file a person may want
back if the heuristic was wrong — and «a corrupt file was deleted» is not something a person can
appeal after the fact any other way.

**A8 — Keep `fileExists: (URL) -> Bool` on `AttachmentChipModel` and add a second, defaulted
`isIntact: (URL) -> Bool = { _ in true }`.** Rejected. It would keep all 21 existing assertions in
`Tests/AttachmentChipTests.swift` compiling untouched, which is its entire appeal. The default
means «assume intact», so any call site that forgets the new argument silently gets the old,
unsafe behaviour back — the optional-sentinel trap this project has a standing rule about. A
three-state probe makes the new case unrepresentable-by-omission: the `switch` does not compile
until it is handled.

**A9 — Put `AttachmentIntegrity` in `Sources/Features/Pratiche/` instead of `Sources/Core/Email/`.**
Rejected. It is a pure function over bytes with no UI, no actor and no vault knowledge, and its
sibling `InlineImageClassifier` — the same shape of decision about the same kind of bytes — is
already in `Sources/Core/Email/`. Splitting the two would put the answer to «is this part worth
keeping» in two directories. The cost of Core is the Foundation-only discipline, which this type
meets without effort.

---

## Consequences

### Positive

- An attachment Mail has not finished writing is never written to the vault, never hashed, never
  deduped against another one, and never handed to Quick Look or the Finder — the three symptoms
  that opened this ADR each lose their mechanism rather than being papered over.
- A message captured at a bad instant heals itself, without the person knowing there was anything
  to heal and without their doing anything. The «in attesa» chip becomes the file, silently, at
  whichever sync Mail has the bytes.
- Existing corrupt files already in somebody's vault are repaired by the first sync after the
  upgrade, per pratica, with no command to find and no migration to run.
- Dedup is left exactly as it was and becomes correct as a side effect: `digest(of:)` is now only
  ever reached with bytes that passed §D2 (R-12).
- The fix costs no new dependency, no new framework, no schema bump, no migration, no manifest
  edit, no index field, and no new file format. Two new files, both Foundation-only, both under
  globs that already exist.
- The note is amended in one line rather than re-rendered, so the feature is now *less* able to
  lose somebody's typed text than it was before this change.
- Every new decision is a pure function over bytes or over text, testable with Swift Testing and
  no filesystem, no Mail store, and no UI host.

### Negative

- **A file truncated between a valid head and a valid tail is still accepted** (§"What a magic-byte
  check can and cannot prove", A5). The fix reduces the failure class; it does not close it.
- **An attachment Mail will never complete stays «in attesa» forever**, retried at every sync, with
  no state that distinguishes it from one still arriving and no user-visible way to dismiss it.
  This is the SPEC's own choice and A2 explains why, but it is a permanent, visible artefact in a
  person's timeline.
- **A valid file wrongly judged corrupt is moved to the Trash by the repair pass** and its link
  becomes a pending entry. Recoverable — that is what §D7.3 is for — but it is the one path in
  this design that touches a file nobody asked it to touch.
- **An inline image that arrives late loses its position in the body** and becomes a chip (§D9).
- **21 assertions in `Tests/AttachmentChipTests.swift` and two tests in `Tests/PraticaSyncTests.swift`
  change**, plus one fixture in `EmailFixtureCorpus`. None of them are wrong today; all of them
  assert a contract this fix deliberately changes. They are enumerated in the plan's staleness
  table so the coder does not discover them.
- **`AttachmentChip.Content` gaining a case makes four `switch`es in `AttachmentChipModel`
  non-exhaustive** until handled. This is intended (A8) but it is a compile break, not a warning.
- **The sync now does slightly more work per file in `allegati/`**: one verdict per file, on bytes
  it already read. Measurable only on a pratica with a very large number of attachments, and
  bounded by the reads that already happen.

### Neutral

- `regeneratePending` keeps its name while its meaning widens by one clause; its doc comment
  already described the wider meaning.
- `SyncOutcome` grows by two defaulted fields; `regeneratedPendingFiles` keeps its exact previous
  meaning and no new value is ever appended to it.
- `PraticaRowDetail` grows by one defaulted field, declared last, so its existing construction
  sites keep compiling.
- The connectors (`perg`, `pergamenum-mcp`) compile the two new Core files and gain no capability:
  `VaultAPI.PraticaSummary` is untouched (R-13) and a pending attachment is invisible to both, by
  the same structural rule ADR-0036 §D19 already enforces.
- The UI suite is unaffected: no accessibility identifier changes, no new launch argument, and the
  pending chips are appended after the existing two groups so the existing indices hold.
- `IndexCache.schemaVersion` stays 3; `pergamenum-mail` stays 1.

---

## Protected-interface proposal (ADR-0053 — proposed, not written)

One candidate. The architect cannot create `.claude/protected-interfaces`; the operator does, at
Gate 2, if they want the protection — and it BLOCKS once it exists.

```
Sources/Core/Pratiche/MessageDocument.swift:MessageDocument.isPendingAttachmentEntry — added 2026-09-11 per ADR-0040 §D3; this predicate is the only thing that tells an attachment already in `allegati/` from one Mail has not finished writing, on every message note already on disk. A silent change re-links every pending entry to a file that does not exist, or orphans every placed one.
```

Deliberately *not* proposed: `AttachmentIntegrity.verdict`. It is policy, not format — it is
expected to be tuned (a family added, a window widened), and protecting it would block exactly the
maintenance this design anticipates.

---

## References

- `docs/adr/0036-pratiche.md` — §D6 (amended here, §D5/§D7), §D14, §D18, §D19, §D21 (not
  reopened), and the Task 4/5/6 implementation follow-ups.
- `docs/adr/0022-workspace-ui-creazione-board-toolbar-e-r.md` §D6 — deletions go to the Trash.
- `docs/adr/0020-image-card-crop.md` — the prefixed-key precedent, cited to say it is not spent
  again here.
- `SPEC.md` (this chain) — R-01…R-16, the Data model's «no new frontmatter key» constraint, and
  the Edge cases the no-cap rule comes from.
- `Sources/Features/Pratiche/PraticaSyncEngine.swift` — `:272-286` (the folder scan), `:356-364`
  (the §D6 guard), `:386-452` (the part loop), `:634-704` (`commit`, `regeneratePending`),
  `:719-737` (`place`).
- `Sources/Core/Pratiche/MessageDocument.swift` — `:59`, `:113-153`, `:229`.
- `Sources/Core/Email/InlineImageClassifier.swift` — the «never drop on a guess» precedent.
- `Sources/Features/Pratiche/AttachmentChipModel.swift`, `AttachmentChip.swift`,
  `PraticaMessageRow.swift:118-139`.
- `Tests/EmailFixtureCorpus.swift`, `Tests/PraticaSyncTests.swift:254-360`,
  `Tests/AttachmentChipTests.swift`.
