# PERGAMENUM — Specifica completa dell'applicazione

Versione: 2.2 — 11/08/2026 (sostituisce integralmente la v1)
Autore: Stefano Ferri
Stato: riferimento ufficiale per lo sviluppo con Claude Code. Ogni attività di sviluppo (skill/goal) deve essere verificata contro questo documento.
Novità v2: piattaforma macOS 26 Tahoe+; tassonomia allineata al sistema harness (repo harness-system, convenzioni naming/tag/frontmatter/wikilink); collegamento task-note e task-canvas; sezione GUI e design system a token con temi chiaro/scuro.
Novità v2.1: anteprima rapida con barra spaziatrice (Quick Look) su file selezionati in canvas, note e task (§6.6).
Novità v2.2: il canvas si chiama **Workspace**; struttura a cartelle di progetto navigabili (§6.1); barra strumenti laterale a 11 strumenti definita sul modello VisualOS (§6.4); disegno a mano libera come SVG (§6.2).

---

## 1. Obiettivo finale

Costruire **Pergamenum**, applicazione macOS nativa, completamente offline, per uso personale, che unisce in un unico strumento:

1. Un **vault di note markdown locali** con wikilink e backlink (modello Obsidian), compatibile con il vault Obsidian "Labs" esistente e conforme alle convenzioni del sistema harness.
2. Un **canvas spaziale infinito** dove note, PDF, immagini, email e link fluttuano come card ridimensionabili (modello VisualOS / JSON Canvas).
3. Un **sistema di task e calendario integrato** con note giornaliere, scheduling `>data`, timeblocking, integrazione bidirezionale con Calendario e Promemoria Apple, e task collegabili a note e canvas.

**Definizione di "fatto"**: l'app è completa quando Stefano può, senza connessione internet, aprire il vault Labs, scrivere una nota giornaliera con task, trascinare sul canvas un PDF che appare come immagine ridimensionabile, collegare alla nota un'email (file .eml o link `message://`) che si apre con un click, collegare un task a una nota o a un canvas e navigare il collegamento nei due sensi, pianificare un task su una data che appare nella nota di quel giorno, e vedere/creare eventi del Calendario Apple dalla timeline dell'app.

**Non-obiettivi (v1)**: collaborazione multi-utente, sync real-time proprietario, ecosistema plugin, rendering HTML delle email, gestione contatti, app iPad (futura, solo visualizzazione), versione Windows/web.

---

## 2. Identità

| Campo | Valore |
|---|---|
| Nome | Pergamenum |
| Bundle ID | `it.stefer.pergamenum` |
| Schema URL | `pergamenum://` (registrato via `CFBundleURLTypes`) |
| Piattaforma v1 | **macOS 26 Tahoe o superiore**, Apple Silicon |
| Lingua UI | Italiano (architettura pronta per localizzazione EN) |
| Distribuzione | Solo personale: firma Developer ID, niente App Store in v1 |

Il target macOS 26 consente l'uso senza fallback delle API SwiftUI correnti (incluso il linguaggio visivo Liquid Glass e le API di osservazione/animazione più recenti). Nessun codice di compatibilità per versioni precedenti.

---

## 3. Stack tecnologico

| Livello | Tecnologia | Note |
|---|---|---|
| Linguaggio | Swift 6 | Concurrency strict |
| UI | SwiftUI (SDK macOS 26), con AppKit (NSViewRepresentable) dove necessario | Editor e canvas richiedono AppKit |
| Editor testo | TextKit 2 via NSTextView incapsulato | Vedi §7 |
| PDF | PDFKit (`PDFDocument`, `PDFPage.thumbnail(of:for:)`) | Rendering card PDF |
| Email | Parsing header .eml in Swift puro (RFC 5322, solo header) | Nessun rendering del corpo |
| Calendario/Promemoria | EventKit (`EKEventStore`) | Permessi split |
| Persistenza note | File system: markdown + frontmatter YAML | Nessun database per i contenuti |
| Persistenza canvas | File `.canvas` in formato JSON Canvas 1.0 | Compatibilità Obsidian |
| Indice/cache | SQLite via GRDB solo come cache ricostruibile | L'indice non è mai fonte di verità |
| Anteprime file | QuickLookThumbnailing (`QLThumbnailGenerator`) | Fallback per file generici |
| Anteprima rapida | QuickLookUI (`QLPreviewPanel`) | Barra spazio su file selezionato (§6.6) |
| Apertura URI esterni | `NSWorkspace.shared.open(URL)` | obsidian://, x-devonthink-item://, message:// |
| Temi | Design token JSON (§11) caricati a runtime | Chiaro/scuro dal giorno 1 |

**Principi architetturali vincolanti:**

1. **File over app**: ogni contenuto vive in file leggibili sul disco (md, canvas, pdf, eml). Se Pergamenum sparisse, i dati restano usabili.
2. **Offline totale**: nessuna chiamata di rete in nessuna funzione. Nessun server, nessun account, nessuna telemetria.
3. **Indice ricostruibile**: la cache SQLite (link, backlink, task, thumbnail) si rigenera integralmente dalla scansione del vault. Cancellarla non perde dati.
4. **Compatibilità Obsidian**: il vault Labs si apre in Pergamenum senza conversione; i file .canvas prodotti da Pergamenum si aprono in Obsidian; le proprietà extra usano chiavi non in conflitto e vengono preservate, non interpretate.
5. **Conformità harness**: l'app applica le convenzioni della repo harness-system (naming.md, tag.md, frontmatter.md, wikilink.md) come schema nativo, non come opzione. La repo resta l'unica fonte di verità: se una convenzione cambia, si aggiorna la configurazione dell'app (§4.6), mai il contrario.
6. **Sync delegata**: la sincronizzazione (futura, verso iPad) avviene mettendo il vault in iCloud Drive. Pergamenum non implementa trasporto proprio.

**Entitlement e chiavi Info.plist richieste:**

- `CFBundleURLTypes` con scheme `pergamenum`
- `NSCalendarsFullAccessUsageDescription`
- `NSRemindersFullAccessUsageDescription`
- App non sandboxed in v1 (uso personale): semplifica accesso al vault e agli allegati.

---

## 4. Struttura del vault e tassonomia (allineata al sistema harness)

Fonte di verità: repo `harness-system`, documenti `convenzioni/naming.md` (v1.2), `convenzioni/tag.md` (v1.4), `convenzioni/frontmatter.md` (v1.5), `convenzioni/wikilink.md` (v1.1). Questa sezione ne è l'applicazione all'app, non una ridefinizione. In caso di divergenza vincono i documenti della repo.

### 4.1 Layout su disco

```
Labs/                           ← vault Obsidian esistente (o altro vault scelto)
├── .pergamenum/                ← metadati app (cache, thumbnail, impostazioni, vocabolari)
│   ├── cache.db
│   ├── thumbnails/
│   ├── settings.json
│   └── vocabolari.json         ← replica dichiarata delle tabelle chiuse di tag.md (§4.6)
├── 00 Inbox/                   ← capture in triage
├── 01 Progetti/
├── 02 Aree/
├── 03 Risorse/
├── Calendar/                   ← note giornaliere (cartella configurabile)
│   └── 20260811.md
└── qualsiasi altra cartella e nota
```

L'app non impone la struttura 00-03: la rispetta se esiste. Le uniche cartelle proprie sono `.pergamenum/` e la cartella daily configurabile.

### 4.2 Nomi dei file (naming.md §4.6)

- **Note**: il titolo è il nome file. Ammessi spazi e lettere accentate; vietati `/ \ : * ? " < > | # ^ [ ]`. Massimo 60 caratteri. Frase nominale. Niente `vN`, niente suffissi di stato.
- **Note legate a un evento**: data in testa, formato `YYYYMMDD Titolo evento`.
- **Daily note**: solo `YYYYMMDD` (es. `20260811.md`). NON `YYYY-MM-DD`.
- **Canvas**: stessa grammatica dei titoli nota (4.6). Nota di governance: la categoria "canvas" non esiste ancora in naming.md; la sua introduzione formale richiede ADR + nuova sottosezione in naming.md §4 (procedura G-04). Fino ad allora l'app applica per analogia la grammatica delle note.
- **Import .eml**: l'assistente di import propone la rinomina secondo naming.md 4.3/7.3: `YYYYMMDD_Controparte_Email_oggetto-sintetico.eml` (data della email, controparte esterna secondo N-07, oggetto in kebab-case).
- **Export deliverable**: `YYYYMMDD_Cliente_Tipo[_oggetto][_ll]_vN.est` (naming.md 4.1), Tipo dal vocabolario chiuso 6.1.
- **Rinomina note**: sempre e solo dall'interno dell'app (o di Obsidian), mai da Finder/shell (wikilink.md W-08). La rinomina aggiorna tutti i wikilink entranti; al termine l'app verifica che il pannello link non risolti sia invariato.

### 4.3 Frontmatter delle note (frontmatter.md, schema chiuso)

Schema chiuso a 4 chiavi, ordine fisso, nessuna altra chiave ammessa:

```yaml
---
date: 2026-08-11          # obbligatoria, ISO 8601, data del documento (F-03)
tags:                     # obbligatoria, lista a blocco, mai inline (F-04)
  - type-note
  - topic-vibration-isolation
related:                  # facoltativa, wikilink tra virgolette, ordine alfabetico (F-06)
  - "[[Titolo nota collegata]]"
aliases:                  # facoltativa, max 3, criteri F-07
  - Titolo senza accenti
---
```

Regole vincolanti per l'app:

- VIETATE le chiavi `title`, `status`, `type`, `draft`, `version`, `author`, chiavi di lingua o di data aggiuntive (F-02, F-05). La spec v1 le prevedeva: sono rimosse.
- Ordine dei tag nella lista: per namespace nell'ordine di T-01 (`client`, `competitor`, `project`, `type`, `topic`, `status`, `area`, `source`), poi alfabetico dentro il namespace (F-04).
- Chiavi facoltative senza valore: si omettono, mai vuote o `[]` (F-08).
- Daily note: `date` + `tags` con il solo `- type-note` (tag.md 5.1). Capture inbox senza argomento: `- type-note` + `- status-inbox`. L'app genera questi blocchi automaticamente.
- L'app crea ogni nuova nota con blocco conforme e segnala (linter, §4.7) le note non conformi senza correggerle in massa: l'adeguamento avviene solo quando la nota viene toccata (non retroattività, frontmatter.md 6.2).

### 4.4 Tag (tag.md)

- Tag piatti con namespace a prefisso, stringa `^(client|competitor|project|type|topic|status|area|source)-[a-z0-9]+(-[a-z0-9]+)*$` (regex madre T-01). NIENTE tag annidati con `/`: la spec v1 li prevedeva, sono rimossi.
- Famiglie chiuse (`type`, `status`, `area`, `source`): valori solo dalle tabelle di tag.md 4.4, 4.6, 4.7, 4.8, replicate in `vocabolari.json` (§4.6). L'autocompletamento propone solo valori in tabella; un valore fuori tabella è un errore bloccante alla digitazione.
- Famiglie aperte (`client`, `competitor`, `project`, `topic`): regole di formazione 4.2, 4.9, 4.3, 4.5 di tag.md. L'autocompletamento propone prima i valori già usati nel vault.
- Vincoli applicati dal linter: massimo 7 tag per nota (T-10); massimo un `status-*` (T-05); nessun tag data (T-07); sulla categoria Note, `status-*` vietato salvo `status-inbox` (tag.md 5.1); nota ordinaria richiede `type-note` + almeno un `topic-*` (con le eccezioni daily/capture).
- Sintassi: nel frontmatter la stringa nuda in `tags:`; nel corpo è ammesso l'inline `#client-acmespa` (tag.md 5.3, riga Obsidian).

### 4.5 Wikilink, related e progetti (wikilink.md)

- Wikilink `[[Titolo esatto]]`; inline ammessa la forma `[[Titolo|testo]]` e `[[Titolo#Sezione]]`; embed media `![[nome-file.est]]` con estensione (W-01, 4.2).
- Doppio binario: legami strutturali in `related` + sezione finale `## Note correlate` (bullet: `- [[Titolo]] — motivo di una riga`); citazioni puntuali solo inline (W-03). L'app mantiene le due scritture allineate automaticamente (stessi titoli, stesso ordine alfabetico, W-06): la UI di creazione di un legame strutturale chiede il motivo e scrive entrambe.
- Test del motivo (W-04): il campo motivo è obbligatorio nella UI di creazione legame; senza motivo il legame si crea come citazione inline, non come strutturale.
- Simmetria (W-05): la creazione di un legame strutturale scrive contestualmente il ritorno sulla nota di destinazione, con motivo richiesto per entrambi i versi. Operazione atomica: se la destinazione non è scrivibile, il legame non si crea.
- Massimo 5 legami strutturali per nota (W-09), salvo nota indice con motivi canonici (wikilink.md 6.5). Al superamento l'app propone la procedura di sfoltimento.
- Link non risolti: vietati in `related`/sezione (l'app li blocca), ammessi inline come segnaposto se il testo è già un titolo conforme (W-07). Pannello dedicato dei link non risolti.
- **Progetti**: un progetto è un valore della famiglia `project-*` (kebab-case, identico al nome cartella/repo, tag.md 4.3). La vista progetto dell'app aggrega tutto ciò che porta quel tag: note, canvas, task. Lo stato operativo del progetto non vive nei metadati delle note (frontmatter.md 2.3): l'app lo deriva dai task (aperti/completati/scadenze). La nota indice di progetto (wikilink.md 6.5) è supportata con i motivi canonici fissi.

### 4.6 Vocabolari e configurazione harness

`.pergamenum/vocabolari.json` contiene la replica dichiarata delle tabelle chiuse di tag.md e naming.md (namespace, type/status/area/source, Tipo deliverable, transizioni di stato). La fonte di verità resta la repo harness-system: quando le convenzioni cambiano (nuovo commit), il file si aggiorna a mano o con lo strumento "Importa convenzioni…" che legge i file md della repo. L'app non modifica mai i documenti della repo.

### 4.7 Linter di conformità

Vista "Conformità" che verifica su richiesta (mai in automatico di massa, non retroattività): frontmatter a schema (F-01..F-09), tag conformi (T-01..T-10, set 5.1), coerenza `related` ↔ "Note correlate" (W-06), simmetria dei legami (W-05), titoli conformi (4.6), link non risolti nei registri (W-07). Output: elenco di non conformità con azione proposta, applicabile solo nota per nota.

### 4.8 Nota di governance

L'architettura harness vigente (ADR 20/07/2026, emendata 30/07/2026) assegna i task a Craft e la gestione progetti a Curio. Pergamenum, a regime, candida a sostituire questi ruoli: la modifica dell'architettura degli strumenti richiede una voce ADR in `harness-system/memoria/decisioni.md` e non è decisa da questa specifica. Fino a quell'ADR, Pergamenum si sviluppa e si usa in parallelo senza dismettere nulla.

---

## 5. Editor markdown

- Editor a **sorgente visibile con stile applicato** (grassetto reso in grassetto, heading ingranditi, sintassi visibile): livello "Obsidian source mode migliorato", NON live preview completa che nasconde la sintassi (fuori scope v1).
- Requisiti minimi:
  - CommonMark + tabelle GFM + task list `- [ ]`
  - Wikilink con autocompletamento su `[[` (titoli esatti dal vault; gli alias F-07 servono la ricerca, mai il primo segmento del link, W-01)
  - Tag con autocompletamento su `#` vincolato ai vocabolari (§4.4)
  - Checkbox task cliccabili nel testo
  - Comando "Aggiungi nota correlata": flusso guidato legame strutturale (motivo + simmetria, §4.5)
  - Trascinamento file nell'editor → copia secondo impostazione + embed `![[file.pdf]]`
  - Incolla URL su testo selezionato → link markdown
  - Comando "Apri nel canvas": crea/apre un canvas e aggiunge la nota come card

---

## 6. Workspace (canvas spaziale)

Terminologia vincolante: la vista spaziale si chiama **Workspace** in tutta la UI, nei menu e nella documentazione. "Canvas" resta solo il nome tecnico del formato file (`.canvas`).

### 6.1 Struttura e navigazione (modello VisualOS)

- **Gerarchia**: il Workspace è organizzato in **board**, una per cartella. La board radice mostra le cartelle dei progetti come card cartella; il doppio click su una cartella entra nella sua board. Annidamento illimitato, corrispondente 1:1 alle cartelle reali del vault.
- **Mappatura su disco**: ogni cartella del vault può avere una board, salvata come file `.canvas` omonimo dentro la cartella stessa (es. `01 Progetti/vibrofer-emea/vibrofer-emea.canvas`), creato al primo ingresso. Un file spostato sulla board di una cartella viene spostato in quella cartella su disco: la board è una vista spaziale della cartella reale (file over app). La radice del Workspace è configurabile (default: radice del vault).
- **Barra superiore**: selettore del vault/workspace (pallino di stato + nome) · **breadcrumb** del percorso (es. `Workspace › 01 Progetti › vibrofer-emea`), ogni segmento cliccabile per risalire · annulla/ripeti · ricerca globale · impostazioni · indicatore **Salvato** (autosalvataggio continuo, ~1 s dopo ogni modifica; l'indicatore mostra lo stato di scrittura su disco).
- **Controlli zoom** (angolo basso destra): riduci `−` · percentuale corrente cliccabile (reset 100%) · ingrandisci `+` · adatta alla vista (zoom to fit). Range 5%–400%, pinch e Cmd+/−.
- **File nuovi rilevati**: file aggiunti alla cartella dal Finder o da altre app appaiono in un vassoio "Nuovi elementi" della board, da trascinare in posizione (modello VisualOS new-items pool). Nessun file viene posizionato automaticamente.

### 6.2 Formato file

JSON Canvas 1.0 (spec: jsoncanvas.org). Tipi nodo usati:

| Tipo JSON Canvas | Uso in Pergamenum |
|---|---|
| `text` | Nota adesiva colorata e testo libero (§6.4, strumenti 2 e 3) |
| `file` | Nota .md, PDF, immagine, .eml, SVG di disegno, qualsiasi file del vault; le cartelle sono nodi `file` che puntano alla cartella |
| `link` | URL web e URI esterni (obsidian://, x-devonthink-item://, message://) |
| `group` | Raggruppamento con etichetta |

Gli `edges` (frecce) seguono la spec. Proprietà aggiuntive di Pergamenum usano chiavi prefissate e devono essere ignorate/preservate da altre app.

**Disegno a mano libera**: JSON Canvas non ha un tipo nodo per i tratti. I tratti dello strumento Disegno (§6.4) si salvano come file SVG nella cartella della board (`disegno-YYYYMMDD-nnn.svg`) referenziati da un nodo `file`: Obsidian li mostra come immagini, la compatibilità è preservata. Un tratto resta modificabile in Pergamenum (riapertura dello SVG in editing).

### 6.3 Comportamento della board

- Pan (trascinamento su area vuota/trackpad), zoom come da §6.1, zoom su selezione.
- Card: selezione singola/multipla (click, Shift+click, marquee), spostamento, **ridimensionamento da angoli e lati** (Shift = proporzioni bloccate), z-order = ordine array, guide magnetiche di allineamento e griglia opzionale.
- Doppio click su area vuota → nuova nota adesiva. Trascinamento file dal Finder → card `file` nella cartella della board. Incolla URL → card `link`.
- Rendering: culling (si disegna solo il visibile); le card complesse a zoom < 25% degradano a segnaposto.

### 6.4 Strumenti della barra laterale (verticale, sinistra)

Undici strumenti, dall'alto in basso, sul modello dello screenshot VisualOS di riferimento. Ogni strumento ha scorciatoia a tasto singolo; dopo l'uso si torna a Seleziona (comportamento "one-shot", disattivabile con doppio click sullo strumento che lo blocca attivo).

| # | Strumento | Tasto | Funzione |
|---|---|---|---|
| 1 | **Seleziona** | V | Strumento di default: selezione singola/multipla/marquee, spostamento, resize, rotazione esclusa. Esc annulla la selezione. |
| 2 | **Nota** | N | Crea una nota adesiva colorata (nodo `text`): sfondo a scelta dai colori tema, il riquadro cresce col testo, markdown minimo (grassetto, corsivo, elenchi). Per appunti veloci che vivono solo sulla board. |
| 3 | **Testo** | T | Testo libero senza sfondo né bordo (nodo `text` senza colore): titoli di zona, etichette, didascalie. Dimensione font scalabile con la card. |
| 4 | **Cartella** | F | Crea una **cartella reale su disco** dentro la cartella della board e la sua card (icona cartella + nome + conteggio elementi). Doppio click → entra nella board della cartella. È lo strumento che genera la gerarchia dei progetti. |
| 5 | **Immagine** | I | Importa un'immagine (file picker o incolla): copia nella cartella della board, card ridimensionabile con crop non distruttivo, didascalia opzionale sotto la card. |
| 6 | **Documento** | D | Crea una **nota .md del vault** nella cartella della board, mostrata come card documento (icona, titolo, conteggio parole). Doppio click → editor a tutta finestra. È la porta tra Workspace e knowledge base: la nota è una nota a tutti gli effetti (frontmatter conforme §4.3, wikilink, task). |
| 7 | **Link** | L | Crea una card link: URL web o URI (`obsidian://`, `x-devonthink-item://`, `message://`, `pergamenum://`). Icona per schema, titolo editabile, doppio click apre la destinazione (§6.5). |
| 8 | **To Do** | K | Crea una card lista task: checkbox interattive con la sintassi §7.1. I task della card sono indicizzati come quelli delle note (appaiono in Attività, pianificabili, collegabili); il file di origine è il `.canvas`. |
| 9 | **Moduli** | — | ESCLUSO v1. Nello screenshot di riferimento è "Forms": per uso personale non ha un caso d'uso; rivalutare in v2 come scheda a campi strutturati. Lo slot resta nel design della barra per non rimaneggiare il layout. |
| 10 | **Disegno** | P | Penna a mano libera: tratti, cerchiature, sottolineature ed evidenziazioni sopra la board, colori dal tema, gomma. Salvataggio come SVG (§6.2). |
| 11 | **Freccia** | A | Connettore magnetico tra card (edge JSON Canvas): aggancio ai lati, resta attaccato quando le card si spostano, etichetta editabile sul tratto, estremità configurabili (nessuna/freccia). Trascinando da una card a area vuota propone la creazione di una nuova card collegata. |

### 6.5 Card per tipo

**Card nota (.md)**: contenuto renderizzato in sola lettura; doppio click → editing inline; click su titolo → apre nell'editor principale.

**Card PDF (requisito primario)**: immagine della prima pagina via `PDFPage.thumbnail(of:for:)`, cache in `.pergamenum/thumbnails/`; ridimensionabile liberamente, thumbnail rigenerata alla nuova risoluzione a fine resize; badge numero pagine, selettore pagina; doppio click → viewer PDFKit interno o app predefinita.

**Card email (requisito primario)**: file .eml (nodo `file`) con header From/Subject/Date letti da parser RFC 5322 interno, oppure link `message://` (nodo `link`); doppio click → apertura in Apple Mail. Ridimensionabile, nessun rendering del corpo.

**Card link URI (requisito primario)**: nodo `link` con qualsiasi URI (`https://`, `obsidian://`, `x-devonthink-item://`, `message://`, `pergamenum://`); icona per schema, titolo editabile; doppio click → `NSWorkspace.open(URL)`. Nessuna anteprima remota.

**Card immagine**: rendering diretto, resize proporzionale, crop non distruttivo opzionale.

**Card gruppo**: rettangolo etichettato; spostare il gruppo sposta le card contenute.

### 6.6 Anteprima rapida con barra spaziatrice (requisito, vale in tutta l'app)

Comportamento identico al Finder, implementato con `QLPreviewPanel` (framework QuickLookUI):

- **Workspace**: con una card `file` selezionata (PDF, immagine, .eml, video, qualsiasi file), la barra spaziatrice apre l'anteprima Quick Look a schermo; spazio o Esc la chiude. Con selezione multipla, il pannello naviga tra i file selezionati con le frecce.
- **Editor/note**: con il cursore su un embed `![[file.est]]` o su un wikilink a file, oppure con un file selezionato nella sidebar, la barra spaziatrice apre la stessa anteprima.
- **Viste task**: con un task selezionato che contiene wikilink a file o a note, la barra spaziatrice apre l'anteprima del primo file collegato; frecce per scorrere gli altri.
- Il pannello è quello di sistema: zoom, condivisione e "Apri con" inclusi; i tipi supportati dipendono dai generatori Quick Look installati (limite noto: .eml mostra solo gli header, coerente con §14).
- La barra spaziatrice apre l'anteprima solo quando la selezione è un file e nessun campo di testo è in editing attivo: in editing lo spazio resta un carattere.

### 7.1 Sintassi (nelle note markdown, solo ASCII)

```
- [ ] Testo del task
- [ ] Task pianificato >2026-08-15
- [ ] Task con scadenza !2026-08-20
- [ ] Task con promemoria @remind(2026-08-15 09:00)
- [ ] Task ricorrente finito @repeat(1/10)
- [ ] Task di progetto per [[Nota indice progetto]] #project-pergamenum
- [ ] Task con nota collegata, vedi [[Trasmissibilità e rapporto di frequenza]]
- [ ] Task con canvas collegato, vedi [[Progetto X.canvas]]
- [x] Task completato @done(2026-08-11)
- [>] Task ripianificato (spostato a data futura)
- [-] Task annullato
```

| Marcatore | Significato |
|---|---|
| `>YYYY-MM-DD` | Data pianificata: il task appare nei riferimenti della daily note di quel giorno (il task resta nella nota di origine) |
| `!YYYY-MM-DD` | Scadenza: oltre questa data il task è in ritardo (rosso) |
| `@remind(...)` | Promemoria locale (UserNotifications) e, se attivato, Promemoria Apple |
| `@repeat(n/N)` | Ricorrenza finita; ricorrenza infinita delegata a Promemoria Apple |
| `@done(...)` | Data completamento, apposta automaticamente |
| `[[...]]` nel testo | Collegamento del task a note e canvas (§7.2) |
| `#project-*` | Appartenenza a progetto (tag harness, §4.4) |

### 7.2 Collegamento task ↔ note e canvas (requisito)

- Un task può contenere uno o più wikilink a **note .md** e a **file .canvas**. Il wikilink nel testo del task è il meccanismo di collegamento: nessuna sintassi aggiuntiva.
- **Dal task alla nota/canvas**: nelle viste task ogni wikilink è cliccabile e apre la destinazione (editor o canvas). Menu contestuale: "Apri nota collegata" / "Apri canvas collegato".
- **Dalla nota/canvas ai task**: pannello "Task collegati" nella nota e nel canvas, che elenca tutti i task del vault il cui testo linka quella nota/canvas, con stato e date, completabili sul posto (la modifica scrive nel file di origine del task).
- **Collegamento assistito**: dalla vista task, comando "Collega nota/canvas…" apre il quick switcher e inserisce il wikilink nel testo del task. Dall'editor, un task su una riga qualsiasi si collega trascinandovi sopra una nota dalla sidebar.
- Questi collegamenti sono citazioni inline ai fini di wikilink.md (W-03): non impegnano `related`, non richiedono motivo né simmetria. Contano nell'indice backlink dell'app (la nota mostra il task tra i suoi backlink).

### 7.3 Comportamenti

- **Nessun rollover automatico** (modello NotePlan): i task non completati restano evidenziati; ripianificazione rapida Cmd+0 oggi, Cmd+1 domani, Cmd+2 +2 giorni, Cmd+3 settimana prossima.
- Pianificare = **link, non copia**: il task vive in una sola posizione, la daily note lo mostra per riferimento con origine cliccabile.
- Completare un task da qualsiasi vista aggiorna il file markdown di origine.

### 7.4 Viste task (sidebar "Attività")

| Vista | Contenuto |
|---|---|
| Inbox | Task senza data né progetto, cattura rapida globale (Cmd+Shift+N) |
| Oggi | Task con `>oggi` + task in ritardo |
| Prossimi | 7 giorni, raggruppati per giorno |
| Per progetto | Aggregazione per tag `#project-*`, con progresso |
| Tutti | Ogni task aperto del vault, raggruppato per nota di origine |

---

## 8. Calendario e integrazione Apple

### 8.1 Daily note

- Nome file `YYYYMMDD.md` (naming.md 4.6), cartella configurabile (default `Calendar/`). Frontmatter auto-generato conforme (§4.3).
- `Cmd+T` apre oggi; frecce giorno precedente/successivo; mini-calendario mensile come date picker. Template configurabile.
- Struttura vista giorno: (1) area riferimenti: task `>data` e backlink alla data; (2) corpo della nota; (3) timeline oraria laterale.

### 8.2 EventKit

- All'attivazione, richiesta di accesso completo a Calendario e Promemoria.
- **Lettura**: eventi di tutti i calendari attivi sul Mac nella timeline del giorno; selezione calendari visibili nelle preferenze.
- **Scrittura eventi**: `Cmd+E` crea evento con parsing naturale della riga corrente; trascinare un task sulla timeline crea un time block, opzionalmente salvato come evento sul calendario dedicato "Pergamenum".
- **Promemoria bidirezionali**: i Promemoria con data appaiono nella vista Oggi; completamento sincronizzato nei due sensi; le ricorrenze infinite vivono in Promemoria.
- Vincolo noto: EventKit è solo on-device; i Promemoria non sono raggiungibili via CalDAV.

### 8.3 Timeblocking

- Timeline verticale del giorno (06:00–22:00 default). Drag di un task → blocco da 30 min, bordi trascinabili. Blocchi interni o pubblicati come eventi (toggle per blocco).

---

## 9. Schema URL `pergamenum://`

Registrato via `CFBundleURLTypes`; gestito in `onOpenURL`. Route idempotenti, aprono l'app se chiusa.

| Route | Azione |
|---|---|
| `pergamenum://note?file=<path-relativo-urlencoded>` | Apre la nota nell'editor |
| `pergamenum://note?id=<uuid>` | Apre la nota per ID stabile (registrato nell'indice, non nel frontmatter: lo schema chiuso F-02 non ammette una chiave `id`; l'ID è quindi stabile finché il file non viene rinominato fuori dall'app) |
| `pergamenum://canvas?file=<path>` | Apre il canvas |
| `pergamenum://canvas?file=<path>&node=<nodeId>` | Apre il canvas e centra/seleziona la card |
| `pergamenum://day/20260811` | Apre la daily note (creandola se assente); data in formato `YYYYMMDD`, coerente col nome file |
| `pergamenum://today` | Apre la nota di oggi |
| `pergamenum://search?q=<query>` | Ricerca globale con la query |
| `pergamenum://capture?text=<testo>&note=<path>` | Appende testo alla nota indicata (default: daily di oggi) senza portare l'app in primo piano |
| `pergamenum://task?add=<testo>` | Crea un task nell'Inbox |

Ogni nota, canvas e card espone "Copia link Pergamenum" nel menu contestuale, per incollare il link in Obsidian, DEVONthink, Mail o Calendario.

**URI in uscita**: qualsiasi schema passa a `NSWorkspace.open`. Schemi con icona dedicata: `obsidian://`, `x-devonthink-item://`, `message://`, `https://`.

---

## 10. Struttura dei menu (barra macOS)

**Pergamenum**: Informazioni · Impostazioni… (Cmd+,) · Servizi · Nascondi · Esci

**File**: Nuova nota (Cmd+N) · Nuova board (Cmd+Shift+C) · Nuovo task rapido (Cmd+Shift+N) · Apri vault… · Vault recenti · Importa file… (con rinomina assistita §4.2) · Importa convenzioni… (§4.6) · Esporta nota (PDF/HTML/MD, con rimozione frontmatter e "Note correlate" per consegna a terzi, frontmatter.md 6.3 e wikilink.md 6.3) · Rivela nel Finder (Cmd+Shift+R) · Chiudi (Cmd+W)

**Modifica**: Annulla/Ripeti · Taglia/Copia/Incolla · Incolla come testo puro · Copia link Pergamenum (Cmd+Shift+L) · Trova nella nota (Cmd+F) · Sostituisci · Ricerca globale (Cmd+Shift+F)

**Inserisci**: Wikilink [[ · Tag # (autocompletamento vincolato) · Task (- [ ]) · Data pianificata > · Scadenza ! · Promemoria @remind · Nota correlata… (flusso W-04/W-05) · Tabella · Immagine/file… · Link email da Mail (legge la selezione corrente di Mail via AppleScript e inserisce `message://`)

**Vista**: Editor · Workspace · Oggi (Cmd+T) · Calendario · Attività · Conformità (linter §4.7) · Anteprima rapida (Spazio, §6.6) · Mostra/nascondi sidebar (Cmd+0) · Backlink · Task collegati · Timeline · Link non risolti · Solo sorgente/Stile applicato (Cmd+Shift+E) · Zoom board · Tema (chiaro/scuro/sistema, temi installati §11)

**Task**: Completa/riapri (Cmd+Invio) · Pianifica oggi (Cmd+0) · domani (Cmd+1) · +2 giorni (Cmd+2) · settimana prossima (Cmd+3) · Scegli data… · Aggiungi scadenza · Aggiungi promemoria · Collega nota/canvas… (§7.2) · Annulla task · Vai alla nota di origine

**Calendario**: Vai a oggi · Giorno precedente/successivo (Cmd+←/→) · Vai a data… · Nuovo evento (Cmd+E) · Nuovo promemoria (Cmd+Shift+E) · Pubblica time block come evento · Aggiorna da EventKit

**Finestra / Aiuto**: standard macOS; Aiuto include "Guida sintassi task" e "Convenzioni harness" (rinvio ai documenti della repo).

**Menu contestuali** (minimo richiesto): card canvas (apri, copia link Pergamenum, ridimensiona a preset, colore, elimina), task (pianifica, scadenza, collega nota/canvas, vai a origine), nota nella sidebar (rinomina con aggiornamento link W-08, sposta, elimina), giorno nel mini-calendario (apri daily note).

---

## 11. GUI e design system (requisito)

### 11.1 Processo di design

La GUI è progettata **con Claude in fase di design** (mockup, componenti e token prodotti da Claude prima dell'implementazione, iterati con Stefano) e poi implementata in SwiftUI. Ogni schermata delle milestone (§13) ha il suo mockup approvato prima di scrivere il codice della vista.

### 11.2 Direzione estetica

- Riferimento dichiarato: **Craft**. Stile minimal: molta aria, tipografia curata, gerarchia data da peso e spazio più che da linee e riquadri, angoli arrotondati, ombre leggere, icone SF Symbols, animazioni brevi e sobrie.
- **Tema chiaro e tema scuro completi dal giorno 1**, entrambi di prima classe: nessun colore hardcoded nelle viste.
- Nessuna emoji nell'interfaccia. La regola riguarda il **cromo** dell'app — menu, barra
  strumenti, barra laterale, messaggi, etichette: Pergamenum non si decora. Un selettore che
  mostra il glifo che si sta per inserire mostra **contenuto**, non interfaccia, ed è l'unica
  eccezione: il completamento emoji su `:` (§5) disegna le emoji che offre, perché sceglierne
  una dal solo nome è sceglierla alla cieca. L'emoji finisce nella nota, non nell'app.

### 11.3 Sistema temi a design token

Valutazione richiesta (CSS/HTML): un sistema di stili CSS/HTML non è applicabile direttamente a un'app SwiftUI, dove non esiste un DOM su cui applicare fogli di stile; sarebbe applicabile solo incapsulando le viste in WKWebView, scelta scartata (rinuncerebbe ai vantaggi nativi decisi in §14). L'equivalente nativo, adottato **dall'inizio**, è un sistema di **design token**:

- File tema in JSON, formato allineato alla spec W3C Design Tokens (DTCG), in `.pergamenum/themes/`: `pergamenum-light.json`, `pergamenum-dark.json` più eventuali temi aggiuntivi.
- Token semantici, mai riferimenti diretti a colori nelle viste: `color.background.primary`, `color.text.secondary`, `color.accent`, `color.canvas.grid`, `color.task.overdue`, `font.body`, `font.title`, `spacing.s/m/l`, `radius.card`, `shadow.card`, ecc.
- Un `ThemeEngine` carica i token a runtime e li espone alle viste SwiftUI via Environment; il cambio tema è istantaneo, senza riavvio. Chiaro/scuro seguono il sistema o si forzano.
- Vantaggio del formato DTCG: gli stessi file token sono leggibili da strumenti web e da Claude in fase di design; un tema disegnato come CSS variables si converte meccanicamente in token JSON. È il ponte richiesto con il mondo CSS/HTML, senza portare un webview nell'app.
- Regola di sviluppo vincolante: una vista che usa un colore o un font non passando dai token non supera la review.

---

## 12. Ricerca, indice e impostazioni

- Ricerca globale full-text (Cmd+Shift+F) su note, canvas e nomi file; operatori: `tag:`, `path:`, `task:open`, `"frase esatta"`. Quick switcher (Cmd+O) con fuzzy match su titoli e alias.
- Indice in `.pergamenum/cache.db`: note, link, backlink, tag, task (con date e collegamenti §7.2), thumbnail. Watcher FSEvents sul vault: modifiche esterne (anche da Obsidian) recepite in tempo reale.
- Impostazioni: Generali (vault, lingua, tema) · Editor · Canvas (griglia, snap, import copia/riferimento) · Task (orario default promemoria) · Calendario (calendari visibili, calendario di scrittura, fascia timeline) · Convenzioni (cartella daily, percorso repo harness per import vocabolari) · Avanzate (rigenera indice, svuota cache, log).

---

## 13. Milestone di sviluppo

| # | Milestone | Contenuto | Criterio di accettazione |
|---|---|---|---|
| M0 | Design system | Token chiaro/scuro, mockup Claude delle viste principali (editor, workspace, oggi, attività), ThemeEngine | Cambio tema a runtime su una vista demo; mockup approvati da Stefano |
| M1 | Vault + editor | Apertura vault Labs, sidebar, editor md con stile, wikilink, quick switcher, frontmatter conforme auto-generato, indice base | Apro il vault Labs reale e navigo/modifico note senza corromperle né violare le convenzioni |
| M2 | Workspace base | Gerarchia board/cartelle con breadcrumb (§6.1), barra strumenti §6.4 (Seleziona, Nota, Testo, Cartella, Immagine, Documento, Freccia), pan/zoom/resize, salvataggio JSON Canvas | Un .canvas creato in Pergamenum si apre correttamente in Obsidian e viceversa; la gerarchia board rispecchia le cartelle su disco |
| M3 | Card PDF ed email | Thumbnail PDFKit con cache e resize, card .eml con header, card URI e strumento Link, strumenti To Do e Disegno, apertura con doppio click, anteprima rapida con barra spazio (§6.6), import .eml con rinomina assistita | I requisiti primari di §6.5 e §6.6 funzionano su PDF e .eml reali; spazio su una card apre il pannello Quick Look |
| M4 | Task | Sintassi §7.1, collegamenti task-note/canvas §7.2, viste Attività, ripianificazione rapida, cattura rapida | Un task con wikilink a una nota è navigabile nei due sensi e si completa da ogni vista |
| M5 | Calendario | Daily note YYYYMMDD, EventKit lettura/scrittura, Promemoria bidirezionali, timeblocking | Un time block trascinato appare nel Calendario Apple; un Promemoria completato in-app risulta completato in Promemoria |
| M6 | URL scheme + conformità | Route §9, menu completi §10, linter §4.7, import convenzioni, notifiche locali | Da Obsidian e DEVONthink un link pergamenum:// apre la risorsa esatta; il linter segnala correttamente una nota non conforme di test |

Ordine vincolante M0→M6: ogni milestone produce un'app usabile. Non si inizia una milestone se il criterio della precedente non è verificato manualmente da Stefano.

---

## 14. Rischi noti e decisioni già prese (non riaprire senza motivo)

| Tema | Decisione | Motivo |
|---|---|---|
| Stack | SwiftUI nativo, non Electron | Requisito email ridotto a link+apertura; PDFKit ed EventKit nativi |
| Piattaforma | macOS 26 Tahoe+, nessun fallback | Uso personale su Mac aggiornato; API SwiftUI correnti senza compromessi |
| Rendering corpo email | Escluso | Nessuna libreria Swift mantenuta; il doppio click su Mail è sufficiente |
| Live preview completa | Esclusa v1 | Voce di costo massima; source mode con stile è sufficiente |
| Formato canvas | JSON Canvas 1.0 puro | Interoperabilità Obsidian |
| Tassonomia | Convenzioni harness applicate come schema nativo | Un solo sistema di regole in tutto l'ecosistema; la repo harness-system resta la fonte di verità (§4.8) |
| Frontmatter | Schema chiuso a 4 chiavi, niente chiavi app | Conformità F-02/F-05; l'ID per gli URL vive nell'indice, non nei file |
| Temi | Design token JSON (DTCG), no CSS/WKWebView | Il CSS richiederebbe webview; i token danno lo stesso risultato in nativo e restano interoperabili con gli strumenti web di design |
| Ricorrenze infinite | Delegate a Promemoria Apple | Evita un motore di ricorrenze completo |
| Sync | iCloud Drive sulla cartella vault | Nessun server; pattern validato da VisualOS e NotePlan |
| Quick Look per .eml | Non usato come renderer | Da Catalina mostra solo gli header; il parser interno basta |

---

## 15. Riferimenti

- Repo harness-system: `convenzioni/naming.md` 1.2, `convenzioni/tag.md` 1.4, `convenzioni/frontmatter.md` 1.5, `convenzioni/wikilink.md` 1.1 (fonti di verità della tassonomia)
- JSON Canvas 1.0: https://jsoncanvas.org/spec/1.0/
- W3C Design Tokens (DTCG): https://design-tokens.github.io/community-group/format/
- Apple EventKit: https://developer.apple.com/documentation/eventkit
- Apple PDFKit (thumbnail): https://developer.apple.com/documentation/pdfkit/pdfpage/thumbnail(of:for:)
- Modello scheduling/timeblocking NotePlan: https://help.noteplan.co/article/110-how-to-schedule-tasks · https://help.noteplan.co/article/121-time-blocking
- Modello task Craft: https://support.craft.do/en/plan-and-do
- Modello storage VisualOS: https://wiki.visualos.app/how-your-data-is-stored.html
