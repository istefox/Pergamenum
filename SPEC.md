# SPEC — Rendering markdown WYSIWYG (liste + concealment) unificato tra Nota e Workspace

**Topic slug:** wysiwyg-markdown-in-workspace

## Objective

Nota e le card di testo del Workspace (unificate da ADR-0027) già rendono grassetto, corsivo,
barrato e titoli con stile reale, ma con due lacune condivise: nessuna delle due superfici
disegna le liste in modo diverso dal testo piatto (nessuno span `.list` esiste in
`MarkdownStyler`), e nessuna delle due nasconde davvero i marcatori markdown — Nota li mostra
sempre, attenuati (per emphasis/heading esiste già un concealment parziale via
`EditorDecorationDelegate`, ma non per le liste), le card Workspace non nascondono nulla
(ADR-0027 §D10 lo escludeva esplicitamente). Questa feature chiude entrambe le lacune: aggiunge
il rendering visivo delle liste (bullet/numerazione, con nesting), estende il concealment
esistente alle liste in Nota, e porta un concealment nuovo (marcatori nascosti a riposo, rivelati
sulla riga del cursore in editing) nelle card Workspace per heading, emphasis e liste insieme.

## Scope

**In scope:**

- Nuovo span/famiglia `.list` in `MarkdownStyler` (Foundation-only, condiviso Nota+Workspace):
  riconosce marcatori non ordinati (`-`, `*`, `+`) e ordinati (`N.`), a qualunque livello di
  indentazione, distinti dalle righe checkbox (`- [ ]`/`- [x]`, già `.taskMarker`).
- Rendering visivo: bullet reale (es. `•`) per liste non ordinate, numero reale per liste
  ordinate, indentazione visiva proporzionale al livello di nesting nel sorgente.
- Una riga checkbox mostra solo il suo glifo box/check esistente, mai un bullet aggiuntivo.
- Concealment esteso alle liste in Nota: `EditorDecorationDelegate` guadagna un caso `.list` su
  `HiddenMarker.Kind`, nascosto/rivelato con la stessa regola già usata per heading ed emphasis
  (nascosto fuori dal paragrafo del cursore).
- Concealment nuovo nelle card Workspace (`FormattingTextView`/`CardTextView`), per heading,
  emphasis e liste insieme:
  - A riposo (`isEditable == false`): ogni marcatore è sempre nascosto — WYSIWYG vero.
  - In editing (`isEditable == true`): stessa regola di Nota — il paragrafo del cursore rivela
    il proprio sorgente raw, tutti gli altri restano nascosti.
- Fold degli heading (badge + righe nascoste, oggi solo in Nota) esteso alle card Workspace,
  con lo stesso modello transiente (non persistito) che Nota già usa.
- Auto-continuazione dei marcatori di lista su Invio, in Nota e nelle card Workspace: Invio
  dentro un elemento di lista inserisce il prefisso del successivo (bullet, numero rinumerato, o
  checkbox vuota); Invio su un elemento di lista già vuoto esce dalla lista (rimuove il prefisso)
  invece di continuare all'infinito.
- Rinumerazione automatica delle liste ordinate ad ogni modifica che ne cambia la lunghezza
  (inserimento, cancellazione, riordino), non solo al toggle da selezione (`LineFormat` già lo fa
  per il toggle, ADR-0027 §D6 — questa feature estende la stessa aritmetica all'auto-continue).

**Fuori scope (non-goal espliciti):**

- Concealment di qualunque altro costrutto oltre heading/emphasis/liste (code fence, link, tag,
  task marker, embed restano come oggi).
- Qualunque cambiamento alla sintassi markdown persistita su disco — una lista resta scritta
  `- elemento` / `1. elemento` sia nelle note `.md` sia nei nodi `.canvas` (CLAUDE.md principio 1
  "file over app"; round-trip Obsidian, principio 4).
- Persistere lo stato di fold su disco (per nota o per card) — resta transiente/di sessione,
  come oggi in Nota.
- Riordino drag-and-drop degli elementi di lista, o navigazione da tastiera specifica per liste
  oltre Invio (Tab per indentare, Shift-Tab per togliere indentazione) — se non emerge gratis dal
  lavoro di rendering/nesting, resta un follow-up in TODO.md.
- Riaprire qualunque altra decisione di ADR-0027 (colore/allineamento dell'intera card, dominio
  dell'undo, architettura della format bar flottante) oltre a quanto richiesto da liste e
  concealment.

## Stack

Swift 6, SwiftUI + AppKit (`NSTextView`, TextKit 2 — `usingTextLayoutManager: true`, già vero per
`FormattingTextView` per ADR-0027 §D1), macOS 26 SDK. Il codice classificatore condiviso resta
Foundation-only in `Sources/Core/Editor/` (compilato anche in `perg`/`pergamenum-mcp`, ADR-0001
§D1 — nessun `import AppKit`/`SwiftUI` può entrarci).

## Architecture

Deciso in dettaglio dall'architect a Gate 2; qui solo le direzioni che l'interview ha già forzato.

- `MarkdownStyler` (`Sources/Features/Editor/MarkdownStyler.swift`) guadagna il riconoscimento
  delle liste: emette un nuovo span (o famiglia di span) con tipo di marcatore
  (bullet/ordinato/escluso-da-checkbox) e livello di nesting, per prefissi non ordinati e ordinati
  a qualunque indentazione.
- `LineFormat` (`Sources/Core/Editor/LineFormat.swift`) già rinumera un run ordinato al toggle
  (ADR-0027 §D6) — l'auto-continuazione riusa quell'aritmetica invece di duplicarla.
- `EditorDecorationDelegate` (`Sources/Features/Editor/EditorDecorationDelegate.swift`) guadagna
  un caso `.list` su `HiddenMarker.Kind`, popolato come già avviene per `.heading`/`.emphasis`,
  dallo stesso walk su `MarkdownStyler.spans(in:)` che `applyStyling` già esegue.
- Le card Workspace (`FormattingTextView`/`CardTextView`) necessitano di un meccanismo di
  concealment equivalente. Se sia letteralmente la stessa classe `EditorDecorationDelegate`
  riusata, o un sibling scoperto per le card (seguendo il precedente di ADR-0027 §D1, "condividi
  la logica pura, non le classi AppKit"), è una decisione architetturale per Gate 2 —
  `EditorDecorationDelegate` non è uno dei file protetti/recintati che ADR-0027 §D9 elencava,
  quindi il riuso non è bloccato come lo era per `CompletingTextView`.
- L'estensione del fold heading (`FoldedHeadingFragment`/`NoteFolding`) alle card è allo stesso
  modo una decisione di riuso-vs-fork per l'architect.

## Data model

Nessun nuovo campo persistito. Il markdown delle liste (`- `, `* `, `+ `, `N. `) è già testo
valido e ordinario sia nelle note `.md` sia nei nodi `text` dei `.canvas` — non si scrive nulla
di nuovo in nessuno dei due formati. Lo stato di fold e di concealment è solo a runtime, tenuto
come già avviene per `editingTextDraft` (ADR-0020 §D5) e per lo stato interno esistente di
`EditorDecorationDelegate`.

## UI flows

1. **Lettura di una card a riposo.** Una card `.text` del Workspace con `- primo\n- secondo`
   mostra due righe puntate, senza alcun carattere `-` visibile — come un documento renderizzato.
2. **Editing di una card.** Il doppio click entra in editing; posizionare il cursore sulla riga
   di `secondo` rivela `- secondo` al suo posto, mentre la riga di `primo` resta un bullet senza
   trattino. Spostare il cursore su `primo` inverte quale riga mostra il proprio prefisso raw.
3. **Digitare un nuovo elemento di lista.** Con il cursore alla fine di `- secondo`, Invio
   inserisce un nuovo elemento `- `; un secondo Invio sull'elemento ora vuoto rimuove il prefisso
   di lista e torna a un paragrafo normale.
4. **Riordinare una lista ordinata.** Modificando `1. uno / 2. due / 3. tre` premendo Invio dopo
   `uno` si inserisce un nuovo elemento che diventa `2.`, mentre `due`/`tre` si rinumerano
   automaticamente a `3.`/`4.`.
5. **Fold di un heading in una card.** Cliccare il controllo di disclosure di un heading
   (rispecchiando Nota) collassa le righe sottostanti e mostra un badge col conteggio delle righe
   nascoste, esattamente come in Nota; lo stato di fold si azzera alla riapertura della board (non
   persistito).
6. **Riga checkbox.** `- [ ] fai qualcosa` mostra solo il glifo checkbox, mai un bullet
   aggiuntivo, sia in Nota che in Workspace, a riposo e in editing.

## Edge cases

- Lista annidata (`  - sotto-elemento`, due spazi): renderizzata al secondo livello di nesting,
  indentata oltre il genitore; concealment/reveal segue la stessa regola per-paragrafo degli
  elementi di primo livello.
- Un elemento di lista che contiene già emphasis inline (`- **grassetto** elemento`): il livello
  bullet/concealment e il livello di concealment del grassetto già esistente coesistono sulla
  stessa riga senza conflitti — sono entrambi basati su span indirizzati per range, come già
  avviene oggi per heading+emphasis sulla stessa riga.
- Liste ordinate/non ordinate adiacenti senza riga vuota (`1. uno` seguito immediatamente da
  `- due`): trattate come due liste separate di un elemento ciascuna ai fini della
  rinumerazione, seguendo la stessa regola di CommonMark che le separa.
- Una card distrutta e ricreata mentre attraversa il rettangolo di culling della board (la
  preoccupazione di undo pendente di ADR-0027 §D2) durante un editing con fold o paragrafo
  rivelato attivo: qualunque nuovo meccanismo di concealment/fold sulla card segue la stessa
  disciplina `dismantleNSView` che `CardTextView` già ha, così nessuno stato sopravvive oltre il
  ciclo di vita della view.
- L'undo/redo di una modifica di lista (auto-continue, rinumerazione) è un singolo passo
  annullabile per azione equivalente a una pressione di tasto, coerente con come `InlineFormat`/
  `LineFormat` sono già un passo ciascuno.

## Success criteria

- [ ] R-01 — `MarkdownStyler.spans(in:)` riconosce marcatori di lista non ordinati (`-`, `*`,
      `+`) e ordinati (`N.`), a qualunque profondità di indentazione, come span distinti dal
      testo piatto e dalle righe checkbox `.taskMarker`.
- [ ] R-02 — Una card a riposo (`isEditable == false`) e una nota in condizioni di lettura
      renderizzano entrambe uno span di lista come bullet reale (non ordinata) o ordinale
      corretto (ordinata), senza che il prefisso markdown raw sia mai visibile.
- [ ] R-03 — In una card editabile e in Nota, il paragrafo del cursore rivela il proprio
      prefisso di lista raw; ogni altro paragrafo di lista resta nascosto come glifo renderizzato.
- [ ] R-04 — I marcatori di heading ed emphasis guadagnano nelle card Workspace lo stesso
      comportamento di concealment (nascosto a riposo, rivelato sul paragrafo del cursore in
      editing) che Nota già ha, ribaltando la regola "sempre visibile, solo attenuato" di
      ADR-0027 §D10 specificamente per le card.
- [ ] R-05 — Gli elementi di lista annidati (indentati nel sorgente) si renderizzano a
      un'indentazione visivamente distinta e più profonda del genitore, proporzionale al livello
      di nesting.
- [ ] R-06 — Una riga checkbox (`- [ ] …` / `- [x] …`) mostra solo il proprio glifo checkbox
      esistente, mai un bullet aggiunto, sia in Nota che in Workspace, a riposo e in editing.
- [ ] R-07 — Premere Invio dentro un elemento di lista (bullet, ordinata, o checkbox) inserisce
      il prefisso dell'elemento successivo sulla nuova riga; premere Invio su un elemento di
      lista già vuoto rimuove il prefisso di lista invece di continuare la lista.
- [ ] R-08 — Inserire, cancellare o riordinare elementi in una lista ordinata rinumera
      automaticamente ogni elemento successivo di quella lista in una sequenza contigua, senza
      buchi né duplicati.
- [ ] R-09 — Il fold degli heading di Nota (collasso + badge col conteggio righe) è raggiungibile
      su una card `.text` del Workspace e si comporta come in Nota; lo stato di fold non è
      persistito nel file `.canvas` e si azzera alla riapertura della board.
- [ ] R-10 — Nessuna sintassi markdown scritta in una nota `.md` o in un nodo di testo `.canvas`
      cambia per effetto di questa feature — un vault fatto passare per Obsidian mostra testo
      sorgente di liste/heading/emphasis identico prima e dopo (no-test: verificato tramite
      ispezione manuale di round-trip contro un vault Obsidian reale, non da un'asserzione
      automatica).
- [ ] R-11 — Una card distrutta e ricreata a metà editing (culling della board) non lascia stato
      di concealment/fold pendente né un'azione di undo che punti alla view deallocata, coerente
      con la disciplina `dismantleNSView` esistente (`a853e8e`).
- [ ] R-12 — Ogni interazione di lista, concealment e fold (auto-continue, rinumerazione,
      reveal-on-caret, uscita-su-elemento-vuoto, fold/unfold) è annullabile come singolo passo
      via Cmd+Z, coerente con la granularità di undo per-modifica già esistente nell'app.
