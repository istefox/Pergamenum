<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md tasks=2,3 lines=168-229 -->
# Step 5 Batch Brief -- 2026-09-09-pratiche.md -- tasks 2-3

## Task text (verbatim, plan lines 168-229)

### Task 2 — `.emlx`, MIME, HTML→markdown, quotes, and one `message://` builder (R-04, R-05, R-06, R-07)

- Budget: `Sources/Core/Email/EMLXReader.swift`, `EMLXLocator.swift`, `MIMEDecoder.swift`,
  `MIMEPart.swift`, `HTMLTextReducer.swift`, `QuoteSplitter.swift`, `MailURL.swift`,
  `EmailHeaders.swift` (delegation only), `Tests/EMLXReaderTests.swift`,
  `Tests/MIMEDecoderTests.swift`, `Tests/HTMLTextReducerTests.swift`,
  `Tests/QuoteSplitterTests.swift`, `Tests/EmailTests.swift` (2 lines) (~900 lines)
- Tester writes the declarations and a fixture corpus committed as **synthetic** `.emlx`/MIME text:
  Italian Mail, Italian Outlook, English Gmail, bare `>` quoting, and no quote at all (R-07's «at
  least five styles»), plus one `iso-8859-1` and one `windows-1252` part, one `quoted-printable`
  and one `base64` part, one multipart/alternative with both text and HTML, one inline `cid:`
  image, one `.partial.emlx` with headers only, and one `winmail.dat` attachment.
- Tests (red): byte-count line stripped and the trailing plist returned (R-04); headers-only file
  reports «body not downloaded»; sibling `Attachments/<message>/<part>/` located; the four transfer
  encodings and three charsets decode, undecodable bytes become U+FFFD (R-05); HTML reduces to
  paragraphs, `<br>`, lists, `[text](url)`, `**bold**` and a GFM table, and drops styles, scripts,
  remote images and 1×1 pixels (R-06); each of the five quote styles cuts at the right line, the
  signature after `-- ` moves to its own `Firma` block, and an unrecognised body stays whole (R-07).
- **The `message://` measurement (ADR §D9):** build both encodings for one real message id and
  `NSWorkspace.open` each, once, with Stefano watching. The winner becomes `MailURL.forMessageID`;
  `EmailHeaders.mailURL` and `MailLink.url(forMessageID:)` both delegate to it. Update
  `Tests/EmailTests.swift:149,159` in this task; update `Tests/ConventionsTests.swift:739-740` only
  if the measurement changes `MailLink.url`'s output.
- Coder: bodies. `MIMEDecoder` **extends** `EmailHeaderParser`, it does not replace it.
- `tuist generate --no-open`; full unit suite.

## Phase 2 — the pratica as a file

### Task 3 — dossier codec, naming, message document, membership rule, ledger (R-01, R-08, R-12, R-13, R-14, R-37)

- Budget: `Sources/Core/Pratiche/Dossier.swift`, `DossierYAML.swift`, `PraticaNaming.swift`,
  `MessageDocument.swift`, `MembershipRule.swift`, `PraticaLedger.swift`, `PraticheSettings.swift`,
  `Sources/Vault/VaultSettings.swift` (one field), `Tests/DossierTests.swift`,
  `Tests/PraticaNamingTests.swift`, `Tests/MembershipRuleTests.swift`,
  `Tests/MessageDocumentTests.swift` (~900 lines)
- Tester writes the declarations: `Dossier` (the seven `pergamenum-dossier-*` keys, §D12's line
  codec over `Frontmatter.ForeignKey`), `PraticaNaming.messageFileName(date:time:counterpart:subject:)`
  and `.attachmentFileName(date:name:)`, `MessageDocument.render(_:)`/`.parse(_:)`,
  `MembershipRule.candidates(dossier:store:onDisk:)` and `.trayCandidates(...)`,
  `PraticaLedger` (the (Message-ID, ROWID, conversation id) triple of §D3),
  `PraticheSettings` with its six values and clamps.
- Tests (red):
  - a folder with a `pratica.md` carrying `pergamenum-dossier: 1` is a pratica; the client is the
    parent folder under the configured root; `client-<slug>` is among its tags (R-01);
  - **`Tag.violations` returns empty for both generated files** with the C1/C2 tag sets, and
    `status-final` is never emitted (R-37, C1–C3);
  - the dossier round-trips byte-for-byte through parse→render, including a foreign key this app
    did not write, and never reorders the four closed keys (C4);
  - file names carry `HHMM`, drop `Re:`/`R:`/`Fwd:`/`I:`/`AW:`, cap the slug at 40 characters, and
    collide into `-2`/`-3` only when the `Message-ID` differs (R-08);
  - direction is `sent` iff `From` ∈ own addresses and **never** from the mailbox; the counterpart
    is the sender of a received message and the first non-own `To`, else `Cc`, of a sent one (R-12);
  - the candidate set is (conversations ∪ included ∪ keyword-matched) − excluded − already-imported,
    the tray set is same-counterpart conversations in the window − followed − ignored − claimed by
    another pratica, and a keyword match auto-follows its conversation (R-13);
  - a `conversation_id` absent from the store is re-derived from a member's `Message-ID` through the
    ledger, and a conversation with no recoverable member is **reported**, never dropped (R-14);
  - **no test touches `~/Library/Mail`.**
- Coder: bodies. `PraticaNaming` reuses `ImportNaming.kebabCase`/`canonicalCounterparty`/
  `uniqueFileName` and adds nothing to `ImportNaming` itself.
- `tuist generate --no-open`; full unit suite.

## File map (from Budget: declarations, tasks 2-3)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 2 3 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 9 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 10 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md

Full plan: /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0036-pratiche.md -- D3, D4, D9, D12, D15 and the Follow-up section (Task 1 probe results: message_id_header lookup, .emlx rule with .partial.emlx, Unix epoch dates) bind Task 2's EMLXLocator/MIME/message:// builder and Task 3's ledger/dossier
- SPEC: SPEC.md -- requirement IDs R-04..R-07 (Task 2) and the ids Task 3 cites, for this batch's tests
- CLAUDE.md: CLAUDE.md -- sharedSources rule (Foundation-only under Sources/Core), closed frontmatter/tag schemas, tuist generate after adding files
