# ADR-0048: An attachment part decoding to zero inline bytes is not always "not yet downloaded"

- Status: accepted, implemented on this branch (`fix-pratiche-allegati`, on top of `ef8d28d`).
- Date: 2026-09-17. Written after reading every file it names, at the line, on this worktree.
  Independent of, and a follow-up to, the ledger-orphaning fix already committed on this branch
  (`ba09c06`, `ef8d28d`) - unrelated to it.
- **Amends ADR-0040 §D2** by adding a second reading of the `.empty` verdict. §D2's own doc comment
  for `AttachmentIntegrity.Verdict.empty` says "Nothing at all: Mail has the part's headers and none
  of its bytes" and its surrounding prose attributes every `.empty` case to "Mail has not finished
  downloading" - correct for *some* `.empty` parts (that is what ADR-0040 fixed), wrong for the
  shape this ADR closes. **Nothing else of ADR-0040 changes**: §D1 (the verdict type and its
  Foundation-only shape), §D3 (the pending-entry codec), §D4 (the write-mode table), §D5/§D6 (the
  free, no-cost retry and the identical-patch no-write rule), §D7 (the repair pass) and §D8 (the
  chip's three-state content) are all untouched and are exactly what makes this fix cost nothing
  beyond the sibling-directory read: an attachment this ADR still cannot resolve falls through to
  ADR-0040's own retry, unchanged.
- **Widens SPEC R-10 and "The `.emlx` container and «body not downloaded»"**: the sibling
  `Attachments/<ROWID>/<part>/` directory `EMLXReader.attachmentsDirectory` already computed a path
  for (SPEC "Components", `EMLXReader`'s own row) is now actually read from, for the first time.
- **Reopens nothing else.** No SPEC §14 decision, no frontmatter key, no schema bump
  (`IndexCache.schemaVersion` stays where ADR-0047 left it, `MessageDocument`'s own
  `pergamenum-mail` schema version stays 1), no protected interface
  (`PraticaNaming.messageFileName`, `Dossier.render`, `VaultAPI.PraticaSummary` are all untouched).
- **Adds no exception to CLAUDE.md principle 2.** Every byte this ADR reads was already on the same
  Mac, in a directory `EMLXReader` already knew the path to. No network call, no socket, no new
  framework.
- Depends on: **ADR-0036** in full (this is a defect fix inside Pratiche), **ADR-0040** in full
  (this ADR's whole retry/dedup/quarantine/patch-mode machinery is reused unchanged - see the
  amendment note above).

---

## Context

Stefano's real-world report ("gli allegati rimangono in attesa") survived ADR-0040's fix and
survived a manual ledger repair verified correct on his real vault. Direct inspection of the two
originally-reported messages' `.emlx` files on his Mac (rowID 4408 and 1417, both Exchange account,
`Posta in arrivo.mbox`) found the actual cause, with direct evidence rather than inference:

- The RFC 822 body is **not** headers-only. It fully decodes: a real `text/plain` body, real
  `Subject`/`From`/`Message-ID` headers, and a `multipart/mixed` structure with a genuine attachment
  part header (`Content-Disposition: attachment; filename=OrdineFornitore_Nr_2026_OF_372.pdf`,
  `Content-Type: application/pdf`, `X-Apple-Content-Length: 62103`). `EMLXDocument.bodyState` is
  `.complete`, not `.pending` - confirmed by reading the frontmatter on disk
  (`pergamenum-mail-body: complete`). The SPEC's «corpo non ancora scaricato» path is not what is
  firing here.
- Between that attachment part's headers and the next MIME boundary there are **zero bytes** of
  base64 payload. `MIMEDecoder.decode` returns a non-nil, empty `Data()` for this part
  (`decodedData?.isEmpty == true`), never `nil`.
- `AttachmentIntegrity.verdict(of: Data(), ...)` correctly answers `.empty` - "the case that
  actually fires in production" (ADR-0040 §D2, rule 1). `decodeBody` (formerly
  `PraticaSyncEngine.swift`, now `PraticaSyncEngine+Messages.swift`) treats `.empty` as "not usable
  yet" and files the name into `pendingAttachmentNames`. Every subsequent sync re-decodes the same
  `.emlx`, finds the same empty part, same result - this is not "not yet", it is permanent for this
  file.
- The real bytes are not missing from the Mac. They sit in Mail's own sibling directory:
  `.../Data/4/Attachments/4408/2/OrdineFornitore_Nr_2026_OF_372.pdf`, 45970 bytes, a valid PDF
  (opened it). `EMLXReader.attachmentsDirectory(forMessageAt:rowID:part:)` already computed exactly
  this path shape before this ADR - it existed in the codebase, but **no code anywhere read bytes
  from it**, confirmed by a full-repo search for `Data(contentsOf:)`/`FileHandle`/
  `contentsOfDirectory` against that path (none). Its one production caller, `storePath`
  (`PraticaSyncEngine+Attachments.swift`), only built a path *string* for the frontmatter's
  `StoreReference`, and only for an attachment whose *inline* bytes were already `.usable` and over
  the size threshold - never reached for an `.empty` verdict, which is this bug's actual shape.
  `MailAttachmentRef.swift`'s doc comment claiming "the bytes themselves come from `EMLXReader`'s
  sibling `Attachments/` walk" was stale - no such walk existed yet.
- Verified independently via Mail's own AppleScript dictionary (`sdef`, then a live query) that this
  is not a transient "still downloading" state: `mail attachment`'s `downloaded` property reports
  `true`, `file size` reports `45970` - matching the sibling file exactly. Stefano also reproduced
  this live: opened the message in Mail, saved and opened the PDF successfully, left it open,
  resynced in Pergamenum - still pending, and the `.emlx` on disk is unchanged (still the same empty
  part). There is no AppleScript command to force re-embedding. This is Apple's own storage
  optimization for Exchange, not a lazy-load state that resolves with time or user action.
- Also confirmed live: this is not rare. A recursive scan of `~/Library/Mail/V10` found 84319
  `.partial.emlx` files and thousands of numbered `Attachments/<ROWID>/<part>/` directories across
  every mailbox - a systemic Exchange behavior, not a one-off. It plausibly explains most or all of
  the "In attesa" rows Stefano's screenshots showed across the whole Tifone thread, not only the two
  originally reported messages.

### A second, independent bug found while tracing this: part numbering

Mail's own numbering for the sibling directory is **not** a flat position in decode order. It is
IMAP-style hierarchical numbering (RFC 3501 body-part numbers): a multipart container's immediate
children are numbered `1, 2, 3…` in document order, *including* nested container parts themselves
(which consume a number but hold no bytes); a child that is itself a multipart container has its own
children numbered `<parent>.1`, `<parent>.2`, recursively. Confirmed against real files: a flat
`multipart/mixed` with a text part and an attachment puts the attachment at `2`; a `multipart/mixed`
containing a `multipart/alternative` (2 children) followed by an attachment puts the attachment at
`2` too (the alternative consumes slot `1`, its own children are `1.1`/`1.2`), not `3`. A store-wide
scan found real examples up to three levels deep (`1.2.2`, `1.2.3`, `2.1`…).

`MIMEDecoder.decode`'s recursive walk flattened all of this with `flatMap`: container parts vanished
entirely from its `[MIMEPart]` output, and the array index carried no relationship to Mail's
numbering once there was any nesting or any non-attachment leaf ahead of the attachment. The one
existing caller of Mail's numbering, `storePath`'s over-threshold branch, used `part: ordinal + 1`
where `ordinal` was the flattened array's own index - silently wrong whenever a message nested
`multipart/alternative` under `multipart/mixed` (a very common shape: plain+HTML alternatives)
- though it failed safe: `storePath` falls back to the `.emlx` path when the file is not found at
the wrong guess, so nothing corrupted, it just silently degraded to "open the container" for the
chip's «if still there» link.

Reading the sibling directory needs the correct part number to have any chance of finding the file
at all for a non-trivial message shape, and fixing the numbering once, in one place, closes the
pre-existing `storePath` bug for free.

---

## Decision

### §D1 - `MIMEPart` carries Mail's own IMAP-style (RFC 3501) part number

`Sources/Core/Email/MIMEPart.swift` gains `var partNumber: String`, next to `filename`, compared in
the type's hand-written `==`.

`Sources/Core/Email/MIMEDecoder.swift`'s recursive `parts(of:depth:)` threads a third parameter,
`numberPrefix: String`, empty at the root call. Where it enumerates a multipart's child bodies, each
child gets its own one-based index within that call, and `childNumber = numberPrefix.isEmpty ?
"\(i)" : "\(numberPrefix).\(i)"`:

- a child that is itself `multipart/*` recurses with `numberPrefix: childNumber` - its own children
  are then `childNumber.1`, `childNumber.2`, … - and produces no `MIMEPart` of its own, exactly as
  `flatMap` already dropped it before this field existed: the container's slot is spent, never
  inherited by what follows it in the parent;
- a leaf child's `MIMEPart.partNumber` is `childNumber` itself;
- a message whose top level is not multipart at all gets `partNumber: "1"` for its one part, RFC
  3501's own convention for a non-multipart message - harmless, since a bare non-multipart message
  cannot carry a separate attachment part this fix cares about.

No behavior change to `kind`/`contentType`/`decodedData`/anything else `MIMEDecoder` already
computed - purely an additive field, confirmed by the full existing suite staying green unchanged.

Three `MIMEDecoderTests` cases pin the scheme against the plan's own worked examples: a flat
`multipart/mixed` puts its attachment at `"2"`; a `multipart/alternative` nested under
`multipart/mixed` puts its own two children at `"1.1"`/`"1.2"` and the sibling attachment at `"2"`,
not `"3"`; a third level of nesting (`mixed` › `related` › `alternative`) puts the innermost pair at
`"1.1.1"`/`"1.1.2"`, the `related` level's own second child at `"1.2"`, and the outer sibling
attachment at `"2"`.

### §D2 - `storePath` takes the real number, not a flattened-array index

`PraticaSyncEngine+Attachments.swift`'s `storePath(of:at:rowID:part:)` changes `part: Int` to
`part: String`, dropping the `"\(part)"` interpolation at its call into
`EMLXReader.attachmentsDirectory` (already a string). Its one call site in
`PraticaSyncEngine+Messages.swift` passes `part.partNumber` instead of `ordinal + 1`. This is the
pre-existing bug named above, closed as a side effect of §D1 rather than as a separate patch: there
is now exactly one source of truth for "which number is this part," and both the sibling-attachment
lookup below and the over-threshold `StoreReference` path read it from the same field.

### §D3 - `decodeBody` tries the sibling directory before conceding a part is unusable

A new private, static, actor-free helper on the `PraticaSyncEngine` extension in
`PraticaSyncEngine+Messages.swift`:

```swift
private enum ExternalizedResolution {
    case unavailable
    case bytes(Data)
    case overThreshold(size: Int, storePath: String)
}

private static func resolveExternalized(
    name: String, contentType: String, context: PrepareContext, rowID: Int,
    partNumber: String, settings: PraticheSettings
) -> ExternalizedResolution
```

Tried only when the *inline* MIME payload's own `AttachmentIntegrity.verdict` is `.empty` -
`.signatureMismatch`/`.truncated` mean bytes are present and corrupt, ADR-0040's own already-handled
problem, not this one. In order:

1. Compute the candidate path: `EMLXReader.attachmentsDirectory(forMessageAt:rowID:part:)`, the
   part number from §D1, appended with the declared file name.
2. Stat it (`resourceValues(forKeys: [.fileSizeKey])`, `try?`, the same "no permission prompt, no
   crash on a missing file" idiom `storePath` already used). Missing, unreadable or zero-length →
   `.unavailable`, and the caller's existing `pendingAttachmentNames` path fires exactly as it did
   before this ADR. This is the common case in practice (most attachments are not externalized) and
   costs one failed `stat`.
3. Over `Self.thresholdBytes(settings)` → verified with `AttachmentIntegrity.verdict(ofFileAt:)`
   (the existing head/tail-window check, never a full read) and, only if `.usable`, answered as
   `.overThreshold(size:storePath:)` - the caller folds this straight into a `StoreReference`,
   without ever loading the file into memory. An oversized sibling file that fails this check is
   `.unavailable`, exactly like a corrupt inline over-threshold part already was under ADR-0040 -
   R-07's guarantee ("both halves are designed") now covers the externalized case too, not only the
   inline one.
4. Otherwise, read the whole file (`try? Data(contentsOf:)`) and re-run
   `AttachmentIntegrity.verdict(of:named:contentType:)` on those bytes, the same in-memory rule an
   ordinarily-inline attachment already goes through. `.usable` → `.bytes(data)`. Anything else →
   `.unavailable`.

The `.attachment` case in `decodeBody`'s decode loop is restructured so both an inline `.usable`
verdict and a `.bytes(data)` resolution from `resolveExternalized` feed the **same**
threshold-check-then-`place`/`links.append` code, not two near-duplicate copies of it - the
Decision's own governing rule ("route the file's bytes through the exact same
AttachmentIntegrity/threshold/place pipeline an inline attachment already uses, so there is exactly
one placement code path"). `.overThreshold` short-circuits straight to a `StoreReference` append.
`.unavailable` falls through to the pre-existing `pendingAttachmentNames.append`, byte-for-byte the
same line ADR-0040 wrote.

Net effect: an attachment whose bytes are genuinely not yet available behaves exactly as before
(free retry, ADR-0040 §D5/§D6 untouched); one whose bytes are sitting in the sibling directory
resolves on the very next sync, without a second sync needed, because `decodeBody` runs the full
decode loop on every sync regardless of whether the message note already exists on disk.

### §D4 - Inline images get the same mechanism, deliberately narrower

The `.inlineImage` case has the identical `bytes.isEmpty` shape and calls the same
`resolveExternalized`. It differs in one place: `.overThreshold` is treated the same as
`.unavailable`. Inline images have never had a size-threshold/`StoreReference` concept in this
feature - only ordinary attachments do (SPEC "Edge cases", R-07) - and growing one for the narrow
case of an oversized externalized inline picture is out of scope for a bug fix whose own reported
symptom is attachments, not inline images (Stefano's own aside, "ha scaricato 3 file di firma",
suggests small inline images are not the ones Mail externalizes in practice). An inline image this
large falls back to the existing deferred-token/pending-placeholder path (ADR-0042), unchanged.

One symmetry test (`anInlineImageWithEmptyInlineBytesResolvesFromTheSiblingDirectory`) covers the
primary "resolves and embeds" case; nothing further is chased per the plan's own instruction not to,
absent evidence Mail externalizes inline parts in practice.

### §D5 - `MailAttachmentRef.swift`'s doc comment is corrected

Its claim that "the bytes themselves come from `EMLXReader`'s sibling `Attachments/` walk" was false
when written and stayed false until this ADR. It now names where the read actually happens:
`resolveExternalized` in `PraticaSyncEngine+Messages.swift`, not inside `EMLXReader`, which still
only computes the path.

---

## Alternatives considered

**Treat every `.empty` verdict as permanently unresolvable and stop retrying it.** Rejected: this
would silently regress the case ADR-0040 was built for - a part genuinely still downloading - back
into a permanent "In attesa" with no path to resolution. The whole point of ADR-0040 §D5/§D6's
no-cost, no-cap retry is that the app cannot tell the two `.empty` cases apart in advance; this ADR
makes one of them resolvable rather than declaring the other unresolvable.

**Parse the sibling directory eagerly, before even trying the inline payload.** Rejected: the inline
payload is already fully decoded by the time `decodeBody` reaches this part (`MIMEDecoder.decode`
runs once per message, not per attachment), so trying it first costs nothing and is correct for the
overwhelming majority of attachments, which are not externalized. Trying the sibling directory only
on `.empty` keeps the added filesystem work (one `stat`, and only sometimes one full read) scoped to
exactly the messages that need it.

**Give the sibling-directory attachment its own `StoreReference`-like frontmatter shape, distinct
from an ordinary placed attachment.** Rejected: the whole Decision is that an attachment resolved
from the sibling directory is indistinguishable, once resolved, from one that arrived inline -
same `place`/dedup/quarantine pipeline, same `[[wikilink]]` entry. A reader of the note has no
reason to know or care where Mail happened to store the bytes.

**Grow a `StoreReference`-equivalent for over-threshold inline images too, for full symmetry with
attachments.** Rejected for this ADR, per §D4: no evidence this case occurs in practice, and adding
a new frontmatter/UI shape for a hypothetical is exactly the "chase it further" the plan explicitly
declined.

---

## Consequences

### Positive

- The two originally-reported messages (and, per the store-wide scan, plausibly most of the "In
  attesa" rows in Stefano's Tifone thread) resolve to linked attachments on the very next sync, with
  no manual repair.
- `storePath`'s pre-existing silent-degradation bug (flattened-index numbering under nesting) is
  closed as a side effect, for the over-threshold chip path too.
- `MIMEPart.partNumber` is a small, purely additive surface other future work can read (a chip that
  wants to show Mail's own part number, for instance) without re-deriving it.
- ADR-0040's entire retry/dedup/quarantine/patch-mode machinery is reused unchanged - this fix adds
  one more source of bytes into the front of that pipeline, not a second pipeline.

### Negative

- One extra `stat` call per attachment/inline-image part whose inline payload is empty, on every
  sync until it resolves (or forever, for a part genuinely never downloaded) - bounded, since
  `.empty` inline payloads are the exception, not the rule, and a `stat` on a missing path is cheap.
- `resolveExternalized`'s over-threshold branch reads a file's head/tail windows through
  `AttachmentIntegrity.verdict(ofFileAt:)` before recording a `StoreReference` - one more disk read
  than a bare "trust the size and record it" would have cost, accepted because R-07 already commits
  this feature to never trusting an unverified large-file reference.
- Inline images keep a narrower guarantee than attachments (§D4): an oversized externalized inline
  picture stays "In attesa" indefinitely rather than gaining a store-reference-like resolution. This
  is a known, named limitation, not an oversight.

### Neutral

- No on-disk format change, no frontmatter key, no schema bump, no protected-interface signature,
  no new dependency, no network.
- `MailAttachmentRef`'s doc comment changes; its stored fields do not.

---

## Tests

- `Tests/MIMEDecoderTests.swift`: three new `partNumber` tests (flat, one level of nesting, two
  levels of nesting), described in §D1.
- `Tests/PraticaSyncFixtures.swift`: `writeExternalizedAttachment(_:named:rowID:part:into:)`, a
  fixture helper that locates the `.emlx` `MailStoreFixture.build` already wrote for a given rowID
  (by a plain recursive filesystem search, rather than re-deriving `MailStoreFixture`'s own private
  fan-out digits a third time) and writes bytes into the sibling
  `Attachments/<rowID>/<part>/<name>` directory `EMLXReader.attachmentsDirectory` computes for it -
  the one capability the existing fixture had no way to exercise before this ADR.
- `Tests/PraticaSyncExternalizedAttachmentTests.swift`, a new file (kept separate so
  `PraticaSyncAttachmentTests`/`PraticaSyncRetryTests` do not grow further):
  - an attachment with empty inline bytes resolves from the sibling directory and lands in
    `allegati/`, linked and quarantined, on the first sync;
  - the existing "stays pending" behavior is an explicit regression when no sibling file exists;
  - a corrupt sibling file (wrong magic bytes for the declared extension) stays pending and is never
    placed;
  - an over-threshold externalized attachment becomes a `StoreReference` naming where it really
    lives, without ever being copied;
  - an externalized attachment behind a nested `multipart/alternative` resolves at its real RFC
    3501 number (`"2"`), the regression test proving the numbering fix - the old `ordinal + 1`
    scheme would have looked for it at `"3"` and found nothing;
  - one inline-image symmetry test, same shape as the first, for `.inlineImage`.

All new and existing tests pass: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum
-destination 'platform=macOS' -only-testing:PergamenumTests test` - 3129 tests, 156 suites, 0
failures.

---

## References

- ADR-0036 - `docs/adr/0036-pratiche.md`
- ADR-0040 (amended, §D2) - `docs/adr/0040-pratiche-attachment-reliability-bugs.md`
- ADR-0042 (the inline-image deferral/placeholder path §D4 falls back to) -
  `docs/adr/0042-pratiche-inline-image-placeholders.md`
- SPEC "The `.emlx` container and «body not downloaded»", R-10 -
  `docs/specs/pratiche.spec.md`
