# SPEC — Ridimensionamento con maniglie di trascinamento per gli embed dell'editor

**Topic slug:** ridimensionamento-maniglie-embed-editor

## Objectives

L'editor disegna già un'immagine o un PDF al posto della sintassi `![[file.est]]` /
`![alt](file.est)` quando è da sola su una riga (ADR-0018 slice 3, mergiata in PR #96 insieme
al fix di accessibilità che rende quell'embed raggiungibile da VoiceOver/XCUITest). Oggi la
dimensione disegnata è fissa (720pt di larghezza, la stessa usata in Lettura). Questa feature
aggiunge una maniglia di trascinamento sull'embed disegnato in editor, per ridimensionarlo a
vista, e persiste la dimensione scelta nel testo sorgente della nota con la sintassi nativa di
Obsidian `![[file.png|larghezza]]` o `![[file.png|larghezzaxaltezza]]`, così la scelta
sopravvive alla riapertura e resta compatibile con Obsidian.

## Scope

In scope:
- Una maniglia di trascinamento sull'angolo in basso a destra di ogni embed disegnato (immagine
  o PDF) mentre `hidesMarkup` è attivo.
- Ridimensionamento libero, larghezza e altezza indipendenti (non vincolato al rapporto
  d'aspetto originale).
- Persistenza della dimensione nel testo sorgente al rilascio del mouse, in sintassi Obsidian
  nativa: `|larghezza` quando l'altezza risultante coincide con quella proporzionale
  all'originale, `|larghezzaxaltezza` quando differisce.
- Limiti: larghezza/altezza minime intorno a 80px, larghezza massima pari alla colonna
  dell'editor (il trascinamento si blocca al bordo, mai oltre).
- Un embed già scritto senza `|larghezza` mostra comunque la maniglia, con dimensione di
  partenza pari al rendering naturale/thumbnail attuale; il file non viene toccato finché non
  si trascina almeno una volta.

Out of scope (esplicitamente rimandato):
- Ridimensionamento raggiungibile da tastiera o VoiceOver (solo mouse in questa feature; la
  maniglia stessa non è resa accessibile via `NSAccessibilityElement` qui — lavoro futuro
  separato, deciso deliberatamente per non allargare lo scope).
- Aggiornamento continuo/throttled del testo sorgente durante il trascinamento (si scrive solo
  al `mouseUp`, un solo evento di editing/undo per trascinamento).
- Qualunque sintassi diversa da quella Obsidian nativa (niente attributi custom, niente
  frontmatter per-embed).

## Stack

Invariato rispetto al progetto: Swift 6 strict concurrency, SwiftUI/AppKit ibrido, macOS 26,
TextKit 2 (`NSTextView(usingTextLayoutManager: true)`), nessun fallback di compatibilità.

## Background tecnico

- L'embed è disegnato da `EditorDecorationDelegate.embedParagraph(at:storage:)`
  (`Sources/Features/Editor/EditorDecorationDelegate.swift`), che sostituisce il carattere
  portante del run con `NSAttachmentCharacter` solo nella copia del paragrafo mostrata via
  `NSTextContentStorageDelegate`, mai nello storage reale (vincolo di lunghezza invariata,
  `NSTextContentManager.h:120`).
- Il rendering della thumbnail passa da `EmbedTable` (`Sources/Features/Editor/NoteTextView+Embeds.swift`)
  e `ThumbnailStore`, oggi a una larghezza fissa di 720pt condivisa con `EmbeddedFileView` in
  modalità Lettura.
- Il parsing della sintassi embed è in `EmbedRun.swift` / `Attachment.embed(inLine:)`.
- L'unica interazione di mouse custom esistente sull'embed è il click-to-select in
  `NoteTextView+EmbedCaret.swift` (nessun precedente di drag in questo codebase).
- L'accessibilità dell'embed disegnato (elemento `editor-embed`, ruolo immagine) è stata appena
  corretta in `CompletingTextView+Accessibility.swift` (PR #96): l'elemento vive sulla text
  view reale, non sul delegate (che non è `@MainActor` e non ha accesso alla view). Qualunque
  nuovo elemento interattivo (la maniglia) deve tenere conto di questo stesso vincolo se in
  futuro verrà reso accessibile.
- Sintassi Obsidian verificata (non assunta): `![[file.png|300]]` per la sola larghezza,
  `![[file.png|300x200]]` per larghezza e altezza insieme (la "x" minuscola). Nessun `|height`
  isolato esiste nella sintassi Obsidian. Fonti: [Resizing Images in Obsidian](https://zenn.dev/secula/articles/d1f3e9c57847ee?locale=en),
  [Resize embedded content — Obsidian Forum](https://forum.obsidian.md/t/resize-embedded-content/877).

## Architecture (decisioni di alto livello, l'ADR le vincola)

- Punto di intercettazione del drag: `CompletingTextView` (la sottoclasse `NSTextView`), da
  coordinare con la gestione mouse già esistente per il click-select dell'embed
  (`NoteTextView+EmbedCaret.swift`) così che un click continui a selezionare e solo un drag
  che parte dalla maniglia ridimensioni.
- Durante il trascinamento: overlay visivo (riquadro/anteprima di dimensione) senza toccare il
  testo sorgente; la riscrittura di `![[file|larghezza[xaltezza]]]` avviene una sola volta, al
  `mouseUp`.
- La maniglia esiste se e solo se l'embed è effettivamente disegnato (`hidesMarkup` on e
  rendition disponibile); con `hidesMarkup` off la sintassi resta testo grezzo e non c'è nulla
  su cui trascinare.

## Data model

Nessuno schema nuovo. La dimensione vive esclusivamente nel testo sorgente della nota, come
parte della sintassi embed già esistente (`EmbedRun`), estesa a leggere il suffisso opzionale
`|larghezza` o `|larghezzaxaltezza`.

## UI flow

1. L'utente apre una nota con un embed disegnato (immagine o PDF), `hidesMarkup` attivo.
2. Una maniglia appare nell'angolo in basso a destra dell'embed disegnato.
3. L'utente trascina la maniglia: un overlay mostra la nuova dimensione in tempo reale,
   bloccata tra ~80px e la larghezza della colonna dell'editor.
4. Al rilascio, il testo sorgente viene riscritto con `|larghezza` (o `|larghezzaxaltezza` se
   il rapporto d'aspetto non coincide con l'originale), in un solo passo di undo.
5. Riaprendo la nota, l'embed si disegna già alla dimensione salvata.

## Edge cases

- Embed senza `|larghezza` preesistente: maniglia visibile subito, dimensione di partenza
  naturale/thumbnail; nessuna scrittura fino al primo trascinamento.
- Trascinamento oltre il limite (sotto 80px o oltre la colonna): il valore si blocca al limite,
  non supera mai i bordi.
- `hidesMarkup` spento: nessuna maniglia, nessun modo di ridimensionare se non editando
  `|larghezza` a mano nel testo.
- Rendition non ancora atterrata (render della thumbnail ancora in corso): nessuna maniglia
  finché l'embed non è effettivamente disegnato.
- File mancante (embed `.missing`, segnaposto disegnato): nessuna maniglia — non c'è
  un'immagine reale da ridimensionare.

## Success criteria

- [ ] R-01 — Una maniglia di trascinamento appare nell'angolo in basso a destra di ogni embed
  immagine o PDF disegnato, solo quando `hidesMarkup` è attivo e la rendition è disponibile.
- [ ] R-02 — Trascinare la maniglia ridimensiona in tempo reale un overlay visivo, senza
  modificare il testo sorgente durante il trascinamento.
- [ ] R-03 — Al rilascio del mouse, il testo sorgente viene riscritto una sola volta con
  `![[file.est|larghezza]]` quando l'altezza risultante è proporzionale all'originale, o
  `![[file.est|larghezzaxaltezza]]` quando non lo è.
- [ ] R-04 — Il rilascio del mouse produce esattamente un passo di undo per l'intero
  trascinamento, indipendentemente da quanti pixel sono stati percorsi.
- [ ] R-05 — La dimensione non può mai scendere sotto ~80px né superare la larghezza della
  colonna dell'editor; il trascinamento si blocca ai limiti invece di superarli.
- [ ] R-06 — Un embed già scritto senza `|larghezza` mostra comunque la maniglia, a una
  dimensione di partenza naturale/thumbnail, senza alcuna scrittura sul file finché non si
  trascina almeno una volta.
- [ ] R-07 — Con `hidesMarkup` spento, nessuna maniglia esiste su alcun embed.
- [ ] R-08 — Riaprendo una nota il cui embed è stato ridimensionato, l'embed si disegna già
  alla dimensione salvata letta da `|larghezza[xaltezza]`.
- [ ] R-09 — La feature funziona identicamente per embed immagine ed embed PDF.
- [ ] R-10 — Il ridimensionamento via tastiera o VoiceOver non è implementato in questa feature (no-test: decisione di scope esplicita, verificata rileggendo l'ADR e il piano, non un comportamento che un test automatico può asserire come assente in modo affidabile).
- [ ] R-11 — Tenendo premuto Shift durante il trascinamento, l'altezza segue proporzionalmente
  la larghezza (rapporto dell'immagine originale), invece che muoversi libera come nel
  trascinamento normale; il vincolo si applica e si toglie in tempo reale seguendo lo stato
  del tasto durante il gesto, non solo al momento in cui la maniglia viene afferrata. (Non
  Ctrl: su macOS Control-clic apre il menu contestuale prima che il drag raggiunga l'editor,
  verificato a schermo il 2026-08-23.)
