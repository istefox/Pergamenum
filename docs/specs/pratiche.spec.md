# SPEC — Pratiche

**Topic slug:** pratiche

## Objective

A **pratica** (a matter: one offer, one claim, one negotiation with one counterpart) is the unit
Stefano actually thinks in, and it exists in no tool today. Apple Mail knows threads, which split on
every subject change and get archived out of sight; the Finder knows attachments; phone calls live
in his head. Reconstructing "where are we with Rossi on the anti-vibration mounts" is a manual join
across three places, done by scrolling, and with ADHD the cost of that join is the difference
between control and losing the thread.

This feature makes the pratica a **folder in the vault** that fills itself from Apple Mail's local
store, keeps every message as a readable markdown file plus its attachments as real files, lets
manual notes and phone calls sit between messages, and shows the whole thing as one chronological
timeline: received on the left, sent on the right, collapsed by default, every subject one click
away from the original in Mail.

No network. No server. No account. Consistent with all six binding principles of CLAUDE.md.

## Verified facts this design rests on (checked 2026-09-09 on Stefano's Mac)

- Apple Mail has **no public API** beyond its AppleScript dictionary. The dictionary exposes
  `message` (`source` = full RFC 822, `message id`, `mailbox`, `date sent`, `date received`) and
  `mail attachment` (name, MIME type, size, `downloaded`) but **no `save` command** in the macOS 26
  dictionary. `MailLink` (`Sources/Core/Email/MailLink.swift`) already reads Mail's selection this
  way, with the one-time Automation consent it entails.
- The local store `~/Library/Mail/V10/` holds 128,877 `.emlx` files (RFC 822 body preceded by a
  byte-count line and followed by a plist carrying `conversation-id`, `date-received`, `flags`,
  `remote-id`). 44,683 are full `.emlx`; the rest are `.partial.emlx`, whose attachments Mail has
  already extracted into sibling `Attachments/<message>/<part>/` directories (72,505 files). Reading
  it requires **Full Disk Access** (TCC).
- `~/Library/Mail/V10/MailData/Envelope Index` is SQLite (127,818 rows in `messages`) with
  `messages(ROWID, message_id, global_message_id, subject→subjects, sender→addresses, date_sent,
  date_received, mailbox→mailboxes, conversation_id, deleted, flags)`, `addresses(address, comment)`,
  `recipients(message, address, type, position)`, `attachments(message, attachment_id, name)`,
  `mailboxes(url)`. **Mail's own threading is `conversation_id`**; the longest local conversation has
  82 messages. It ships `-wal`/`-shm` companions and is open by Mail at all times.
- All accounts are Exchange (`ews://`), so archived and sent mail stays in the local store and in
  the index.
- MailKit (`MEMessageActionHandler`) sees incoming mail only and can only flag, colour or move: not
  usable for this feature.
- ChatGPT.app registers only the `codex://` URL scheme. No way to hand it text through a URL.
- The repo already has `EmailHeaders`/`EmailHeaderParser` (header-only RFC 5322 parser),
  `EmailHeaders.mailURL` (builds `message://`), `ImportNaming.emailFileName` (naming.md 4.3/7.3),
  the Workspace `.eml` card (M3), and the sidebar pane pattern of ADR-0032 (`Navigation.Pane
  .recordings`, «Registrazioni», last row of the LAVORO group).
- Shortcut catalogue (`ShortcutCommand.swift`): Cmd+Shift+E is taken by «Nuovo promemoria».
  Cmd+Shift+P is free in the catalogue (system-level check owed at wiring time, as ADR-0032 did
  for Cmd+R).
- Tag vocabulary (`Resources/vocabolari.json`): `status-{inbox,active,waiting,final,archived}`,
  `source-email`, `type-email`, `type-note`.

## Scope

**In scope:**
- A new kind of vault folder, the pratica, recognised by a `pratica.md` note carrying
  `pergamenum-dossier-*` frontmatter keys.
- Automatic acquisition of messages from Apple Mail's local store (Envelope Index + `.emlx` +
  extracted attachments), one markdown file per message, optional original `.eml`, attachments as
  files. Full Disk Access onboarding.
- Manual acquisition fallbacks: the message selected in Mail (AppleScript), drag-and-drop of
  messages from Mail onto the timeline.
- Membership rule: seed → conversation expansion → same-counterpart proposals → follow rule with a
  «Da smistare» tray → per-message include/exclude/move/copy.
- The «Pratiche» sidebar pane and the two-lane collapsible timeline, with inline manual entries
  (Nota / Telefonata) mirrored as one line into the daily note.
- Settings › Pratiche: root folder, own addresses, retention of `.eml`, attachment threshold,
  proposal window, Full Disk Access status.
- Read-only exposure through `VaultAPI` to `perg` and `pergamenum-mcp`: list of pratiche and one
  pratica's textual timeline.
- Amendment of SPEC §14 «Rendering corpo email: escluso»: plain-text/markdown *extraction* of the
  body is in; HTML *rendering* stays out.

**Out of scope (deferred, to be recorded in TODO.md at Step 7b — Stefano's explicit choice):**
- "ChatGPT inside Pergamenum" (an in-app assistant over a pratica). Stefano's stated direction is
  to bring ChatGPT into the app rather than export to it; this is a separate chain. No
  «Esporta per ChatGPT» command is built in this chain either — the timeline is plain markdown on
  disk and `perg pratica` prints it, which already covers copy-paste by hand.
- «Apri come board» (generate a `.canvas` with one card per message). Future chain.
- `pergamenum://pratica/add?message=…` URL scheme entry point (M6 territory).
- Write access to pratiche from `perg`/`pergamenum-mcp` (add-note). Read-only in v1.
- Any HTML rendering of email bodies, WebView, or `.html` sidecar.
- Any network access, IMAP, a Pergamenum mailbox / CC address, a MailKit extension (all rejected,
  see Alternatives).
- Contacts integration, calendar integration, replying/composing mail from Pergamenum.

## Stack and placement

- Swift 6 strict concurrency, SwiftUI, macOS 26 SDK. No new third-party dependency: SQLite is read
  through the system `SQLite3` module (already linkable, C API, no GRDB — GRDB is not in this repo).
- Pure logic in `Sources/Core/Email/` and `Sources/Core/Pratiche/` — **no AppKit/SwiftUI import**,
  because both directories are compiled into `perg` and `pergamenum-mcp` through `sharedSources`.
  What goes there: MIME decoder, HTML→markdown reducer, quoted-text splitter, `.emlx` reader,
  Envelope Index reader, membership rule evaluation, file naming, dossier frontmatter codec,
  timeline model.
- AppKit-only parts live under `Sources/Features/Pratiche/`: FSEvents watcher, TCC probe and the
  System Settings deep link, NSPasteboard drop handling, AppleScript bridge (reusing `MailLink`),
  the timeline views, the wizard, the sidebar rows.
- Connector reads live in `Sources/Connector/` (`VaultReads`/`VaultPayloads`), front ends in
  `Sources/CLI` and `Sources/MCPServer` only translate (CLAUDE.md «AI connector»).
- Per-vault non-vault state lives under `~/Library/Application Support/it.stefer.pergamenum/vaults/
  <id>/pratiche/` (ADR-0017/ADR-0032 precedent): the atomic copy of the Envelope Index used for
  queries, the sync ledger, and per-pratica "last opened" markers for the badges.

## Architecture

### Components

| Component | Layer | Responsibility |
|---|---|---|
| `MailStoreReader` | Core | Copies `Envelope Index` + `-wal` atomically into the state dir, opens the copy read-only, answers queries: messages by conversation id, conversations by counterpart address and date window, message row by `message_id`/`global_message_id`, attachment names, `.emlx` path resolution from mailbox url + ROWID. Never opens Mail's live database. |
| `EMLXReader` | Core | Reads one `.emlx`/`.partial.emlx`: strips the leading byte-count line, returns the RFC 822 bytes and the trailing plist. Locates extracted attachments in the sibling `Attachments/` directory. Reports «body not downloaded» when the RFC 822 part has headers only. |
| `MIMEDecoder` | Core | Multipart walk, transfer decodings (7bit/8bit/quoted-printable/base64), charset handling, part classification (text/plain, text/html, inline vs attachment, `Content-ID`). Extends, does not replace, `EmailHeaderParser`. |
| `HTMLTextReducer` | Core | HTML → light markdown: paragraphs, `<br>`, `<ul>/<ol>`, `<a>` → `[text](url)`, `<b>/<strong>` → `**`, regular `<table>` → GFM table, everything else stripped; remote images and tracking pixels dropped; inline `cid:` images resolved to attachment files. |
| `QuoteSplitter` | Core | Splits a body into new text and quoted history on the first recognised separator (see rules). Splits signature after `-- `. |
| `MessageDocument` | Core | The markdown file for one message: frontmatter codec (`pergamenum-mail-*`), body assembly, `<details>` block for quoted history, regeneration from `.eml`. |
| `Dossier` | Core | `pratica.md` frontmatter codec (`pergamenum-dossier-*`), membership rule evaluation (pure), timeline entry parsing from headings. |
| `PraticaSync` | Core (logic) + Features (triggers) | The sync algorithm: evaluate rule against the store, diff against what is on disk, write missing messages, update the tray, record the ledger. Cancellable, resumable, one message per atomic write. |
| `PraticaWatcher` | Features | FSEvents on `~/Library/Mail/V10` with 10 s debounce, window-key trigger with 60 s throttle, vault-open trigger. |
| `FullDiskAccessProbe` | Features | Detects whether the store is readable (attempts to open the index copy source); opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`. |
| `PraticheController` | Features | Observable facade over the pane: list, selection, timeline model, tray, sync progress, expansion state (per window, not persisted). |
| `PraticaTimelineView` etc. | Features | The views. All colours/fonts through tokens. |
| `VaultAPI` reads | Connector | `pratiche` (list) and `pratica` (timeline) payloads. |

### Data model on disk (file over app)

```
<root>/                              default `01 Progetti/`, Settings › Pratiche › Cartella radice
  <Cliente>/                         the client is the parent folder; tag `client-<slug>` is set on pratica.md
    <pratica>/
      pratica.md                     the dossier: rule + manual entries + tasks
      email/
        20260610_1406_Rossi_richiesta-offerta.md
        20260610_1406_Rossi_richiesta-offerta.eml   (optional, setting «Conserva l'originale», default on)
        20260611_0912_Ferri_re-richiesta-offerta.md
      allegati/
        20260610_offerta-2024-118.pdf
        20260610_disegno-staffa.dwg
```

**Message file name:** `YYYYMMDD_HHMM_<Controparte>_<oggetto-slug>.md`, derived from
`ImportNaming.emailFileName` extended with the `HHMM` component (naming.md 4.3/7.3 base; the time
is needed because one counterpart can send several messages a day and two files cannot share a
name). Counterpart = the display name, else the local part of the address, slugged by the existing
rules. Subject slug drops `Re:`/`R:`/`Fwd:`/`I:`/`AW:` prefixes, kebab-case, max 40 characters.
Collision on identical name with a different `Message-ID` appends `-2`, `-3`.

**Attachment file name:** `YYYYMMDD_<original-name-sanitised>`; collision on same name but different
SHA-256 appends `-2`. Same SHA-256 already in `allegati/` of this pratica → no second copy, the
message frontmatter links the existing file.

**`pratica.md` frontmatter** — the closed schema (`date`, `tags`, `related`, `aliases`) plus
`pergamenum-*` prefixed keys, the reopening mechanism ADR-0032 established:

```yaml
---
date: 2026-06-10
tags: [type-note, client-rossi, status-active, source-email]
related: []
aliases: []
pergamenum-dossier: 1                         # schema version of the dossier keys
pergamenum-dossier-counterparts:              # addresses of the other side (lowercase)
  - m.rossi@rossi-spa.it
  - ufficio.acquisti@rossi-spa.it
pergamenum-dossier-conversations: [112409, 92415]   # Mail conversation ids followed
pergamenum-dossier-keywords: ["OF-2026-118", "staffa antivibrante"]   # optional; subject match auto-admits
pergamenum-dossier-included: ["<abc@rossi-spa.it>"]     # message ids added by hand outside any followed conversation
pergamenum-dossier-excluded: ["<def@rossi-spa.it>"]     # message ids removed by hand; never re-imported
pergamenum-dossier-ignored: [3416]            # conversation ids dismissed from the tray, for this pratica only
---
```

Mail's `conversation_id` is a local integer that Mail may renumber if the index is rebuilt. It is
therefore stored **beside** the counterpart addresses and the message ids of the conversation's
members already on disk, and the sync re-derives a lost conversation id from any member message's
`Message-ID` (index lookup by `message_id` hash → row → `conversation_id`). No pratica depends on
the integer alone.

**Message file frontmatter:**

```yaml
---
date: 2026-06-10
tags: [type-email, client-rossi, source-email]
related: []
aliases: []
pergamenum-mail: 1
pergamenum-mail-message-id: "<AM7P191MB1011...@AM7P191MB1011.EURP191.PROD.OUTLOOK.COM>"
pergamenum-mail-conversation-id: 112409
pergamenum-mail-direction: received          # received | sent
pergamenum-mail-date: 2026-06-10T14:06:10+02:00   # header Date, ISO 8601 with offset; governs ordering
pergamenum-mail-received: 2026-06-10T14:06:31+02:00
pergamenum-mail-from: "Mario Rossi <m.rossi@rossi-spa.it>"
pergamenum-mail-to: ["Stefano Ferri <stefano@stefer.it>"]
pergamenum-mail-cc: []
pergamenum-mail-subject: "Richiesta offerta staffe antivibranti"
pergamenum-mail-attachments: ["[[20260610_offerta-2024-118.pdf]]", "[[20260610_disegno-staffa.dwg]]"]
pergamenum-mail-body: complete               # complete | pending (headers only, body not yet downloaded by Exchange)
pergamenum-mail-original: "20260610_1406_Rossi_richiesta-offerta.eml"   # absent when retention is off
---
Buongiorno Stefano,
…new text of this message, as light markdown…

<details>
<summary>Testo citato</summary>

> Il giorno 9 giu 2026, alle ore 18:02, Stefano Ferri ha scritto:
> …
</details>
```

Both file kinds pass the existing conformance linter: the four closed keys are present and
well-formed, tags come from the vocabulary, extra keys are prefixed and preserved, never
interpreted, by Obsidian.

**Manual entries** are level-2 headings in `pratica.md` whose text starts with a timestamp:

```markdown
## 2026-06-11 15:30 Telefonata · Rossi
Chiede se possiamo anticipare la consegna. Detto che verifico con produzione.
- [ ] Verificare con produzione anticipo consegna >2026-06-12

## 2026-06-12 09:00 Nota
Produzione conferma: 3 giorni prima.
```

Kind is `Telefonata` or `Nota` (free text after the time is allowed; the parser takes only the
timestamp for ordering and the rest as title). Everything under the heading up to the next heading
is the entry body, edited inline with the note editor engine, so tasks, wikilinks and tags work as
everywhere else. The daily note of the entry's date gets one appended line
`- [[<pratica title>]] — Telefonata · Rossi` through `VaultSession.write` in the same atomic
operation family as every other write (SPEC §5 Diario rules for the daily note file location).

**Per-vault state (not in the vault):** `…/vaults/<id>/pratiche/envelope-index.sqlite` (the copy),
`ledger.json` (`{ praticaPath: { lastSyncAt, lastOpenedAt, importedMessageIDs: [...], pending: [...] } }`),
regenerable from disk: deleting it costs one full re-sync, nothing else.

### Membership rule (pure evaluation)

Given the dossier `D` and the store `S`, the candidate set for a sync is:

1. every non-deleted message in `S` whose `conversation_id ∈ D.conversations`;
2. plus every message whose `Message-ID ∈ D.included`;
3. plus, when `D.keywords` is non-empty, every message from/to a `D.counterparts` address whose
   subject contains one keyword (case-insensitive) — its conversation is then **auto-followed**
   (appended to `D.conversations`, written back to `pratica.md` with the ordinary write path);
4. minus every message whose `Message-ID ∈ D.excluded`;
5. minus every message already on disk (dedup by `Message-ID`, read from the ledger and, when the
   ledger is missing, from the frontmatter of the files in `email/`).

The **tray** candidate set is: every conversation in `S` with at least one message from/to a
`D.counterparts` address, dated within the proposal window (default 90 days, setting), not in
`D.conversations`, not in `D.ignored`, and not in the `conversations` of another pratica that
shares the counterpart (a conversation already claimed by another pratica is not proposed again).

The evaluation is a pure function over value types, unit-tested with fixture indexes built in a
temporary SQLite file; no test touches `~/Library/Mail`.

### Sync algorithm

```
sync(pratica):
  guard status is active or waiting (archived/final → no automatic sync; «Aggiorna ora» still works)
  copy index (+wal) → state dir, atomically (write temp, rename); skip if source mtime unchanged
  candidates = rule(D, S)                       # see above
  for m in candidates ordered by date desc:     # newest first: what changed lands first
     locate .emlx (mailbox url → directory, ROWID → file); if missing → mark «not in Mail», continue
     parse headers; if body absent → write MessageDocument with body: pending, continue
     decode MIME → text/plain preferred, else HTML→markdown; split quotes; resolve inline cid: images
     for each attachment part or extracted Attachments/ file:
        if size > threshold (default 100 MB) → record reference (store path + name) in frontmatter, no copy
        else → SHA-256; if present in allegati/ → link existing; else copy to temp, rename into allegati/
     write .md to temp, rename into email/; if retention on → write .eml (RFC 822 bytes) the same way
     ledger.importedMessageIDs += m.messageID
     emit progress (n/total)
  re-check «pending» files from earlier runs: if body now present → regenerate the .md in place
  re-check «not in Mail»: any imported message whose row is now deleted/missing → mark in ledger (link off), file untouched
  tray = trayCandidates(D, S)
  ledger.lastSyncAt = now
```

Writes never touch a message file already on disk except: (a) a `pending` body that has arrived,
(b) an explicit «Rigenera» command. Manual edits to a message `.md` are therefore preserved unless
the user asks for regeneration, which warns and shows the diff first.

Cancelling a sync stops at the next message boundary; everything written is complete and the next
sync resumes from the ledger.

Cost: the index copy is ~few hundred MB at most and copied only when its mtime changed; a query per
pratica is milliseconds; message decode is proportional to message size. The first import of an
80-message conversation with attachments must keep the UI responsive (background actor, progress
bar, rows appearing as they land).

### Acquisition entry points

1. **Seed from Mail's selection** (`MailLink`-style AppleScript returning `message id` + subject):
   the wizard and «Aggiungi a pratica da Mail…» (Cmd+Shift+P) both use it. Automation consent
   dialog handled as today: a refusal is reported, never read as "nothing selected".
2. **In-app picker** over the index copy: search field (counterpart address/name, subject words),
   period, result rows = conversations with first/last date, message count, attachment count,
   participants; multi-select.
3. **Drag from Mail onto the timeline**: Mail puts `.eml` file promises / RFC 822 data on the
   pasteboard; the drop handler reads `Message-ID` from the dropped data, then proceeds as (1).
   Verified behaviour of SwiftUI `.dropDestination` with Mail's promise is **unknown** and is a
   tracer-bullet risk for the architect; the fallback is (1), which is always available.

Every entry point ends in the same pure operation: `addSeed(messageID | conversationID)` →
expand to the conversation → propose same-counterpart conversations → write `pratica.md` → sync.

### Full Disk Access

The app cannot detect TCC state directly. `FullDiskAccessProbe` attempts to `open(2)` the Envelope
Index for reading; `EPERM` means no access. States:

- **Not granted**: the Pratiche pane shows a banner «Pergamenum non può leggere Mail» with a
  button «Apri Impostazioni di Sistema» (deep link to Privacy & Security › Full Disk Access) and a
  three-line explanation; Settings › Pratiche shows the same status with the same button. All
  existing pratiche remain readable; only automatic sync is off; the manual entry points (1) and (3)
  still work because AppleScript and drag-and-drop do not need FDA.
- **Granted later**: the next trigger (window key, FSEvents, «Aggiorna ora») succeeds and the
  banner disappears. No restart required (the probe is repeated per trigger).
- **Revoked**: same as not granted; nothing on disk is touched.

The UI-test suite must never reach the real store: a launch argument `-mailStoreRoot <path>`
points the reader at a fixture directory with a small synthetic Envelope Index and `.emlx` files,
the same shape as `-disableCalendar`/`-disableUpdater`.

### The `.emlx` container and «body not downloaded»

Exchange accounts fetch bodies lazily. A `.emlx` whose RFC 822 part ends at the header block, or
whose plist `flags` mark it partial with no `Data/…/Attachments` present, is written as a
`pending` message: full frontmatter, body replaced by the line `*Corpo non ancora scaricato da
Mail.*`, row drawn dimmed with an «Apri in Mail» button (opening it in Mail triggers the download);
the next sync regenerates it. A `pending` file is the only message file a sync may rewrite
without being asked.

### Quoted-text rules (`QuoteSplitter`)

The body is cut at the **first** line matching one of:
- `^Il giorno .* ha scritto:$` / `^On .* wrote:$` (also across two folded lines),
- `^-{2,}\s*(Messaggio originale|Original Message)\s*-{2,}$`,
- a header block of ≥2 of `Da:|From:`, `Inviato:|Sent:`, `A:|To:`, `Oggetto:|Subject:` in 4
  consecutive lines,
- the first line starting with `>` when all remaining non-empty lines start with `>`,
- `^_{10,}$` (Outlook divider).

Signature: text after the last `^-- $` line, or after a line equal to the sender's display name
when followed only by ≤6 short lines, is moved to the `<details>` block as well, under its own
`Firma` summary. When no separator matches, the body stays whole. The splitter is a pure function
with a fixture corpus (Italian Mail, Italian Outlook, English Gmail, plain `>` quoting, no quote).

### Sent detection and counterpart

Settings › Pratiche › «I miei indirizzi» is a list, pre-filled from the index (`addresses` rows that
appear as `sender` in Sent/Posta inviata mailboxes, deduplicated), editable. A message is `sent`
when its `From` address ∈ own addresses; otherwise `received`. Counterpart = the sender of a
received message; for a sent one, the first `To` recipient not in own addresses, else the first
`Cc`. Mailbox is never used for direction (an archived sent message must still be on the right).

### Timeline model

Entries are the union of message files (ordered by `pergamenum-mail-date`, fallback `-received`)
and manual entries (ordered by their heading timestamp), sorted ascending; the view scrolls to the
bottom (newest) on open, with sticky day separators.

Row (collapsed): chevron · time · sender display name · **subject** (the clickable header) ·
attachment chips (icon + name, click = Quick Look, double-click = open with default app,
context menu = «Mostra nel Finder», «Copia») · first non-empty body line, truncated.
Row (expanded): the body rendered as markdown with the same read-only markdown block renderer used
for transclusions (`MarkdownBlocksView`), the `<details>` block as a native disclosure «Testo
citato», and a footer «Apri in Mail» + «Escludi dalla pratica» + «Sposta in…» + «Aggiungi anche
a…».
Lane: `received` rows aligned left, `sent` rows aligned right, at 70% of the column width, with the
two lane backgrounds from tokens; manual entries span the full width in a third token colour with
a phone/pencil symbol.
Subject click: `NSWorkspace.open(message://…)` built by `EmailHeaders.mailURL`. If the ledger marks
the message «not in Mail», the subject is plain text with a small caption «non più in Mail».
Chevron: toggles one row. Opt+click on any chevron: expand/collapse all. Keyboard: Space toggles
the focused row, arrows move. Expansion state lives in the controller for the window's lifetime.
Filters (toolbar): text (subject, sender, body of expanded and collapsed rows alike), sender menu,
«Solo con allegati» toggle. Filters never hide manual entries unless the text filter is active.
Tray («Da smistare»): a collapsible strip at the top listing proposed conversations (subject of the
first message, counterpart, date range, count) with «Aggiungi» / «Ignora»; hidden when empty.
Progress: a thin bar under the toolbar during sync with «n di N» and «Annulla».
Empty pratica: an illustration-free placeholder with the three ways to add mail.

### Sidebar

`Navigation.Pane.pratiche`, title «Pratiche», symbol `folder.badge.person.crop` (or `tray.full` if
the former is not in SF Symbols 7), placed in the LAVORO group immediately before «Registrazioni».
The pane's list (`List(selection:)` with flat recursive rows per ADR-0024 — no `DisclosureGroup`)
shows client folders as group rows and pratiche as selectable rows ordered by most recent
activity; badge = messages arrived since `lastOpenedAt`; a dot when the tray is non-empty;
«Chiuse» (status `archived`/`final`) as a collapsed group at the bottom. Toolbar: «Nuova pratica…»
(sheet), «Aggiorna ora», filter field. Context menu on a pratica row: Apri, Rinomina, Chiudi/Riapri
(toggles `status-active`/`status-archived`), Mostra nel Finder, Elimina (→ Trash via
`FileManager.trashItem`, same rule as ADR-0022). Commands are declared once and rendered on every
surface (ADR-0023).

### «Nuova pratica…» wizard (one sheet, three steps)

1. **Nome e cliente**: title (→ folder name via the existing slug rules), client (menu over the
   existing child folders of the root via `FolderPickerMenu`, plus «Nuovo cliente…»), root shown
   read-only with a link to Settings.
2. **Seme**: three buttons — «Dal messaggio selezionato in Mail», «Cerca nella posta…» (the picker),
   «Più tardi» (creates an empty pratica). After a seed, the conversation's messages are listed
   with counts, and the counterpart addresses detected are shown as removable chips.
3. **Proposte**: same-counterpart conversations in the window, each with a checkbox (default off),
   plus an optional keyword field. «Crea» writes `pratica.md`, closes the sheet, opens the
   timeline and starts the sync.

### Settings › Pratiche

Cartella radice (folder picker, default `01 Progetti`), I miei indirizzi (list), Conserva l'originale
`.eml` (toggle, on), Soglia allegati (MB, default 100), Finestra proposte (days, default 90),
Scrivi nel diario (toggle, on), Accesso completo al disco (status + button). Persisted in the
vault's settings file like every other vault setting (`VaultSettings`), except own addresses,
which are also vault-level (they describe the person, but the vault is personal).

### Connectors (`VaultAPI`, read-only)

- `pratiche` → `[{ path, title, client, status, counterparts, lastActivity, messageCount,
  trayCount }]`.
- `pratica <title|path>` → the timeline as ordered entries `{ kind: message|note|call, date,
  direction, from, subject, attachments, body }` and, for the CLI, a printed transcript in the same
  order (date, lane marker `←`/`→`, sender, subject, body, attachment names). Resolution of the
  argument reuses `VaultLookup`'s existing title/path rules. Both front ends translate only.
- No connector opens the Mail store or triggers a sync (TCC would attribute the permission to the
  terminal). What they read is what is on disk.
- `scripts/mcp-smoke.py` gains one call per new tool.

### SPEC §14 amendment

Row «Rendering corpo email — Escluso» becomes «Rendering HTML del corpo email — Escluso; estrazione
del testo del corpo in markdown leggero — Inclusa dal 2026-09-09 (pratiche)». Rationale column:
the exclusion was about maintaining an HTML renderer; a reducer to text has no such cost and the
pratica cannot exist without the text. The Workspace `.eml` card is unchanged (headers only).

## UI flows

1. **Create from Mail**: select a message in Mail → Pergamenum → Cmd+Shift+P (or menu Inserisci ›
   «Aggiungi a pratica da Mail…») → sheet asks «Nuova pratica» or an existing one (recent first) →
   for a new one the wizard opens at step 1 with the seed pre-filled → Crea → timeline fills.
2. **Follow-up arrives**: Mail receives a reply in a followed conversation → FSEvents fires →
   debounce 10 s → sync → row appears at the bottom, sidebar badge +1.
3. **New conversation from the counterpart**: lands in the tray → «Aggiungi» follows it and imports;
   «Ignora» silences it for this pratica only.
4. **Phone call**: open the pratica → «Telefonata» → heading inserted with now, cursor in the body →
   type → daily note gets its line on the first save.
5. **Insert between two messages**: hover the gap → «Inserisci qui» → heading timestamp = midpoint
   between the two neighbours.
6. **Exclude / move / copy**: row footer or context menu → Escludi (file → Trash, id → excluded),
   Sposta in… (files moved to the other pratica's folders, id → this excluded, other included),
   Aggiungi anche a… (copy, both included).
7. **Close**: Chiudi → `status-archived` replaces `status-active`; sidebar moves it to «Chiuse»;
   sync stops; Riapri reverses.
8. **No FDA**: banner → button → System Settings → toggle Pergamenum → back → «Aggiorna ora» works.

## Edge cases

- Two counterparts write from the same domain but different addresses: the counterpart list is
  addresses, not domains; the wizard offers «aggiungi tutto il dominio @rossi-spa.it» as one chip.
- A message where Stefano is in Cc and someone else replies-all: still in the conversation, imported
  as received from that sender.
- Mail rebuilds its index (conversation ids change): re-derived from member `Message-ID`s (see
  data model); a conversation whose members are all gone is reported in the tray as «non più
  ricostruibile» with the option to drop it from the rule.
- The same attachment sent twice (revised drawing with the same name, different content): both
  kept, second as `-2`; same content: one file, two links.
- Attachment over threshold: frontmatter records `{ name, size, storePath }`, the chip shows a
  cloud-slash symbol and opens the file from the store path if still there.
- `winmail.dat` / TNEF: not decoded; kept as an attachment as-is.
- Inline image light in both bytes (under 50 KB) and pixel dimensions (≤200×200): dropped
  (signatures, logos). Either signal alone saying otherwise (heavy, or bigger than 200×200):
  saved and embedded as `![[…]]`. Dimensions unreadable: also saved and embedded, never dropped
  on a guess.
- Non-UTF-8 charsets (`iso-8859-1`, `windows-1252`): decoded; undecodable bytes replaced with U+FFFD
  and the row shows a warning glyph.
- Message deleted in Mail after import: file untouched, subject link off, caption shown.
- Message imported, then user edits its `.md` by hand: never rewritten by sync; «Rigenera» shows a
  diff first.
- Vault on iCloud Drive: works; the state dir is local so two Macs each keep their own ledger and
  each re-derives from the files on disk (dedup by `Message-ID` prevents double imports).
- Pratica folder renamed or moved with the existing sidebar operations: the folder is still a pratica
  (recognised by `pratica.md`), ledger keys are rebased on next sync by `Message-ID` set match.
- Two pratiche follow the same conversation on purpose (copy): both import; tray excludes it for
  both.
- Envelope Index locked or mid-write: the copy is retried once after 2 s, then the sync reports
  «Mail sta scrivendo, riprovo più tardi» and the next trigger retries.
- Mail not installed or store missing: the pane shows «Nessun archivio di Mail trovato»; manual
  drag still works.
- Unit and UI suites never read the real store (`-mailStoreRoot` fixture); a test that does is a
  test about somebody's correspondence, the same rule as `-disableCalendar`.

## Alternatives considered

- **Pergamenum CC address / IMAP access**: needs a server or a live network connection; violates
  principle 2; and the CC variant re-creates the very problem (remembering to do something per
  email). Rejected.
- **MailKit extension**: incoming only; actions limited to flag/colour/move; cannot read sent
  mail; would require sandboxing the host. Rejected.
- **AppleScript as the only source** (`source` of every message): works without FDA but is slow
  (seconds per hundred messages), pops the Automation dialog, cannot enumerate conversations, and
  runs only while Mail is open. Kept as the manual fallback, not the engine.
- **Mail rule moving mail into a watched mailbox**: covers received mail only. Rejected.
- **Workspace board as the primary view**: 80 messages make a wall; no place for entries between
  messages. Deferred as an optional generated board.
- **Storing `.eml` only, no markdown**: opaque in Obsidian, unsearchable by the index, unreadable by
  the connectors. Rejected; `.eml` kept as the fidelity copy.

## Definition of Done (manual acceptance on the Labs vault, before merge)

Create a pratica from a message selected in Mail; the timeline shows the whole conversation in
order, sent on the right; attachments are in `allegati/` and open with Space; the subject opens
Mail; a reply sent from Mail appears by itself within 30 s; a new conversation from the same
counterpart lands in «Da smistare»; a phone call entry appears in today's daily note; Obsidian
opens the folder with no frontmatter complaint; `perg pratica <title>` prints the timeline;
`pergamenum-mcp` lists it; unit suite and `scripts/uitests.sh` green.

## Success criteria

- [ ] R-01 — A folder containing a `pratica.md` whose frontmatter carries `pergamenum-dossier: 1` is recognised as a pratica; the client is its parent folder under the configured root and `client-<slug>` is set among its tags.
- [ ] R-02 — `MailStoreReader` never opens Mail's live `Envelope Index`: it copies index and `-wal` atomically into the vault state directory and queries the copy read-only, skipping the copy when the source mtime is unchanged.
- [ ] R-03 — `MailStoreReader` answers: messages by conversation id, conversations by counterpart address within a date window, a row by `Message-ID`, attachment names per message, and the `.emlx` path for a row (mailbox url + ROWID), all verified against a fixture index.
- [ ] R-04 — `EMLXReader` strips the byte-count line, returns RFC 822 bytes and the trailing plist, locates extracted attachments in the sibling `Attachments/` directory, and reports a headers-only file as «body not downloaded».
- [ ] R-05 — `MIMEDecoder` walks multipart messages, decodes 7bit/8bit/quoted-printable/base64 and the charsets `utf-8`, `iso-8859-1`, `windows-1252` (undecodable bytes → U+FFFD), and classifies parts as text/plain, text/html, inline (`Content-ID`) or attachment.
- [ ] R-06 — `HTMLTextReducer` turns HTML into light markdown preserving paragraphs, line breaks, ordered/unordered lists, links as `[text](url)`, bold, and regular tables as GFM tables, and drops styles, scripts, remote images and tracking pixels.
- [ ] R-07 — `QuoteSplitter` cuts at the first recognised separator (Italian/English «ha scritto:/wrote:», «Messaggio originale/Original Message», Da:/Inviato:/A:/Oggetto: header block, all-`>` tail, Outlook underscore divider) and after `-- ` for signatures; with no separator the body stays whole. Verified on a fixture corpus of at least five styles.
- [ ] R-08 — Each imported message is one markdown file `email/YYYYMMDD_HHMM_<Controparte>_<slug>.md` whose frontmatter has the four closed keys plus the `pergamenum-mail-*` keys listed in the data model, with the new text as body and quoted history in a `<details>` block; name collisions get a numeric suffix.
- [ ] R-09 — With «Conserva l'originale» on (default), the RFC 822 bytes are written beside the markdown as `.eml` with the same base name and referenced by `pergamenum-mail-original`; with it off, no `.eml` is written.
- [ ] R-10 — Attachments are copied into `allegati/` as `YYYYMMDD_<name>`; an attachment whose SHA-256 already exists in the pratica is linked, not copied; one above the threshold (default 100 MB) is recorded as a store reference without copy; an inline image light in both bytes (under 50 KB) and pixel dimensions (≤200×200) is dropped, otherwise (heavy, bigger than 200×200, or with unreadable dimensions) saved and embedded.
- [ ] R-11 — Every file write of the sync is atomic (temporary file then rename) and a cancelled sync leaves only complete files, resumable from the ledger.
- [ ] R-12 — Direction is `sent` iff the `From` address is in Settings › Pratiche › «I miei indirizzi» (pre-filled from the index, editable), never derived from the mailbox; the counterpart is the sender of a received message or the first non-own `To`/`Cc` of a sent one.
- [ ] R-13 — The membership rule evaluation is a pure function producing the candidate set (followed conversations ∪ included ∪ keyword-matched, minus excluded, minus already imported by `Message-ID`) and the tray set (same-counterpart conversations within the window, minus followed, ignored, and conversations claimed by another pratica), unit-tested without touching `~/Library/Mail`.
- [ ] R-14 — A lost Mail `conversation_id` is re-derived from any member message's `Message-ID`; a conversation with no recoverable member is reported, never silently dropped.
- [ ] R-15 — A message whose body is not yet downloaded is written with `pergamenum-mail-body: pending` and a placeholder body, drawn dimmed with «Apri in Mail», and is the only message file a later sync rewrites without being asked.
- [ ] R-16 — A message deleted from Mail after import keeps its files; the subject stops being a link and shows «non più in Mail». No file is ever deleted by a sync.
- [ ] R-17 — Sync runs for pratiche with `status-active`/`status-waiting` on vault open, when the window becomes key (throttled to one per 60 s), and on FSEvents under `~/Library/Mail/V10` debounced 10 s; closed pratiche sync only through «Aggiorna ora».
- [ ] R-18 — The Pratiche pane, when the store is unreadable, shows a banner with a button that opens System Settings › Privacy & Security › Full Disk Access; after the grant, the next trigger syncs without restart; manual entry points keep working meanwhile.
- [ ] R-19 — The launch argument `-mailStoreRoot <path>` redirects the reader to a fixture store; every UI-test file passes it, and no test reads the real store.
- [ ] R-20 — «Nuova pratica…» is a three-step sheet (name and client; seed from Mail's selection, from the in-app picker, or later; proposals with optional keywords) that writes `pratica.md` and starts the first sync in the background with a progress bar and rows appearing as they land, newest first.
- [ ] R-21 — «Aggiungi a pratica da Mail…» is available in the Inserisci menu with the rebindable shortcut Cmd+Shift+P (verified free at wiring time against the system hot keys), in the sidebar toolbar and in the pratica row's context menu, declared once and rendered on every surface.
- [ ] R-22 — Dropping a message dragged from Mail onto the timeline adds it as a seed through the same operation as the Mail-selection path; if the SwiftUI drop cannot read Mail's promise, the ADR records the probe result and the selection path remains the documented way.
- [ ] R-23 — The timeline lists messages by `pergamenum-mail-date` (fallback received date) interleaved with manual entries by heading timestamp, ascending, with sticky day separators, scrolled to the newest on open.
- [ ] R-24 — Each message row is collapsed by default showing chevron, time, sender, subject, attachment chips and first body line; the chevron expands the body inline; Opt+click on a chevron expands or collapses all rows; expansion state is per window and not persisted.
- [ ] R-25 — Received rows sit in the left lane and sent rows in the right lane, each at 70% width with token-defined lane colours; manual entries span the full width in a third token colour.
- [ ] R-26 — The subject is a clickable header that opens the message in Apple Mail through the `message://` URL built from `pergamenum-mail-message-id`.
- [ ] R-27 — Attachment chips open Quick Look on click, the default app on double-click, and offer «Mostra nel Finder» and «Copia» in the context menu; an over-threshold attachment shows a distinct symbol and opens from its store path.
- [ ] R-28 — «Nota» and «Telefonata» insert a `## YYYY-MM-DD HH:MM <Kind> · <Controparte>` heading in `pratica.md` with the cursor in the body, editable inline with the note editor engine (tasks, wikilinks, tags work); «Inserisci qui» between two rows uses the midpoint timestamp.
- [ ] R-29 — Adding a manual entry appends one line `- [[<pratica>]] — <Kind> · <Controparte>` to the daily note of that date through `VaultSession.write`, controlled by the «Scrivi nel diario» setting (on by default).
- [ ] R-30 — The tray «Da smistare» lists proposed conversations with subject, counterpart, date range and count; «Aggiungi» follows and imports, «Ignora» records the conversation in `pergamenum-dossier-ignored` for this pratica only; the strip is hidden when empty.
- [ ] R-31 — Per-message commands «Escludi dalla pratica» (files to Trash, id to excluded), «Sposta in…» (files moved, ids updated on both dossiers) and «Aggiungi anche a…» (files copied, both included) exist in the row footer and context menu, and a moved or excluded message is never re-imported.
- [ ] R-32 — Toolbar filters (text over subject/sender/body, sender menu, «Solo con allegati») narrow the timeline; manual entries are hidden only by the text filter.
- [ ] R-33 — The «Pratiche» sidebar pane sits in the LAVORO group before «Registrazioni», groups pratiche by client folder ordered by latest activity, shows a badge with messages arrived since last open and a dot for a non-empty tray, and collapses closed pratiche under «Chiuse»; rows are flat `List(selection:)` rows, no `DisclosureGroup`.
- [ ] R-34 — Chiudi/Riapri swaps `status-active` and `status-archived` in `pratica.md` without moving any file; Elimina moves the folder to the Trash via `FileManager.trashItem`.
- [ ] R-35 — Settings › Pratiche exposes root folder, own addresses, `.eml` retention, attachment threshold, proposal window, daily-note mirroring and the Full Disk Access status, persisted with the vault settings.
- [ ] R-36 — `VaultAPI` gains read-only `pratiche` (list with client, status, counterparts, last activity, counts) and `pratica` (ordered timeline entries), exposed by `perg` as printed output and by `pergamenum-mcp` as tools, with `scripts/mcp-smoke.py` exercising both; no connector opens the Mail store.
- [ ] R-37 — Every message and dossier file passes the existing conformance linter: closed keys present, tags from the vocabulary, extra keys `pergamenum-`prefixed. The `IndexCache.schemaVersion` and the protected interfaces in `.claude/protected-interfaces` are unchanged.
- [ ] R-38 — No file under `Sources/Core` or `Sources/Connector` added by this feature imports AppKit or SwiftUI; `perg` and `pergamenum-mcp` build.
- [ ] R-39 — Every colour and font in the new views is read through a design token; light and dark themes both render the two lanes and the entry colour.
- [ ] R-40 — SPEC §14's «Rendering corpo email» row is amended to exclude HTML rendering only and record body-text extraction as included from this feature, and CLAUDE.md principle 2 gains no new exception because no network is used. (no-test: documentation amendment verified by reading the two files)
- [ ] R-41 — The deferred items «ChatGPT inside Pergamenum», «Apri come board», URL-scheme entry point and connector write access are recorded in TODO.md at Step 7b. (no-test: ledger entry, checked by reading TODO.md)
