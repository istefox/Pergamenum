Status: Approved (2026-09-18)

# SPEC — Collegamenti Pratiche a note, attività e workspace

## Destination

Uno SPEC pronto per `/workplan`, che produce un piano d'implementazione e un ADR proporzionato
(estende ADR-0036 e la famiglia note↔attività↔workspace di ADR-0021/ADR-0039).

## Objectives

Oggi una Pratica (ADR-0036) è un dominio isolato: non ha alcun modo di collegarsi a note,
attività o board Workspace, mentre questo collegamento esiste già tra note, attività e progetti
(ADR-0021, ADR-0039). L'obiettivo è portare lo stesso concetto di relazione nel dominio Pratiche,
su due livelli distinti:

1. **Collegamento generale** — una Pratica può collegarsi a più note, più attività, più board
   Workspace, in modo indipendente dai singoli messaggi.
2. **Collegamento per messaggio** — ogni singolo messaggio email nel timeline di una Pratica può
   avere una nota collegata, mostrata visivamente allineata a quel messaggio e apribile
   direttamente in loco.

## Scope and non-goals

In scope:
- Collegamento generale Pratica → note (multiple), attività (multiple), board Workspace (multiple).
- Collegamento singolo messaggio email → una nota (0 o 1 per messaggio).
- Creazione di una nuova nota/attività/board al volo dal contesto pratica, oltre al collegamento
  a un elemento esistente.
- UI: nuove sezioni nell'inspector esistente della pratica per i collegamenti generali; nuova
  colonna allineata al timeline per le note per-messaggio; icona indicatore sulla riga messaggio.
- Esposizione lettura e scrittura via connettore (`perg`, `pergamenum-mcp`).

Non-goals (una riga, dettaglio in Out of scope):
- Collegamento per-riga per le voci manuali del timeline (Nota/Telefonata).
- Più note collegate allo stesso messaggio.
- Un secondo pannello separato per la nota del messaggio (si riusa/commuta l'inspector esistente).

## Decisions

- **Cardinalità collegamento generale** — multipla per tipo (più note, più attività, più board
  per pratica). Coerente con ADR-0021. Rejected: uno-per-tipo — meno flessibile, nessun vantaggio
  concreto indicato.
- **Cardinalità nota per messaggio** — una sola nota per messaggio (0 o 1). Rejected: più note per
  messaggio — complessità non giustificata dal caso d'uso descritto.
- **Rappresentazione dati collegamento generale** — nuove chiavi frontmatter su `pratica.md`
  (pattern `pergamenum-dossier-links-*`), coerente con lo stile già usato dal resto del file.
  Rejected: wikilink nel corpo markdown — funzionerebbe solo per le note, richiederebbe comunque
  un meccanismo separato per attività e board, rompendo l'uniformità.
- **Rappresentazione dati nota-per-messaggio** — nuova chiave frontmatter sul file del singolo
  messaggio (famiglia `pergamenum-mail-*`, es. `pergamenum-mail-note`). Rejected: riferimento nel
  corpo del messaggio — il corpo è contenuto email importato, non pensato per essere editato a
  mano, e verrebbe perso/alterato dai trigger di riscrittura esistenti (ADR-0036 §D6).
- **Riferimento by-title, non by-path** — sia i link generali sia il link per-messaggio puntano
  alla nota/attività/board per titolo (o nome file per le board), non per percorso. Una rinomina
  del target segue automaticamente, coerente con la convenzione già stabilita (ADR-0022: "una
  wikilink nomina una nota per titolo, mai per percorso").
- **Comportamento su cancellazione del target** — il collegamento non viene rimosso in silenzio:
  resta e viene mostrato come rotto/mancante in UI. Rejected: rimozione automatica silenziosa —
  nasconderebbe una perdita di contesto senza che l'utente se ne accorga.
- **Creazione nuova nota dal contesto pratica** — precompilata con titolo dal contesto (oggetto
  email per il collegamento per-messaggio, titolo pratica per quello generale) e con i tag già
  usati dalla pratica (`topic-pratica`, `client-<slug>`). Rejected: nota vuota standard — costringe
  l'utente a ricostruire a mano un contesto già noto.
- **Creazione nuova board dal contesto pratica** — riusa il flusso di creazione board già esistente
  (ADR-0022: l'utente sceglie nome e cartella), la pratica la collega subito dopo la creazione.
  Rejected: cartella dedicata automatica per pratica/cliente — introduce una convenzione di
  posizionamento nuova, non richiesta altrove nell'app.
- **Creazione nuova attività dal contesto pratica** — supportata, in parallelo al comportamento
  della nota. Rejected: solo collegamento ad attività esistenti — meno utile, dato che generare un
  task dal contesto di una pratica è un caso d'uso comune (follow-up su un'email).
- **Layout nota per-messaggio: colonna persistente allineata al timeline**, non un'espansione
  inline sotto la riga. La colonna scorre in sincrono col timeline e mostra la nota collegata alla
  stessa altezza della sua riga; ogni messaggio con nota collegata ha anche un'icona indicatore
  sulla riga stessa. Rejected: espansione inline sotto/accanto alla riga — meno leggibile quando si
  vuole vedere email e nota fianco a fianco, e non corrisponde a quanto illustrato dall'utente.
- **Inspector generale invariato, nessuna riapertura di ADR-0036 §D5** — la nota per-messaggio non
  sostituisce mai il contenuto dell'inspector esistente (che resta sempre e solo `pratica.md`); vive
  esclusivamente nella nuova colonna allineata al timeline. Rejected: inspector che si commuta in
  base alla riga selezionata — l'utente ha chiarito di volere l'allineamento visivo per-riga, non
  uno scambio di contenuto nel pannello pratica-level; questo evita di riaprire una decisione
  architetturale già presa.
- **Le note per-messaggio compaiono anche nella lista generale "note collegate" della pratica** —
  un'unica vista aggregata evita di dover cercare in due posti. Rejected: liste separate — più
  aderente alla distinzione concettuale dei due meccanismi, ma meno pratico per chi cerca "tutte le
  note di questa pratica".
- **Posizione delle liste generali nell'inspector** — nuove sezioni sotto il corpo di `pratica.md`
  nello stesso pannello, stesso pattern già usato da `BoardTray` per "NOTE REFERENZIATE"/"TASK
  ASSEGNATI". Rejected: tab/area separata — introduce una seconda superficie di navigazione senza
  un vantaggio chiaro sul pattern già in uso altrove nell'app.
- **Creazione del collegamento via menu contestuale** — click destro sulla riga (pratica o
  messaggio) apre un comando dedicato, stesso pattern di `MessageMenuItems`/`TaskCommand`/
  `CardCommand`. Rejected: pulsante dedicato permanente in UI — meno coerente con le superfici di
  comando già esistenti nell'app.
- **Ambito per-riga limitato alle email** — il collegamento nota-per-riga copre solo i messaggi
  email del timeline, non le voci manuali (Nota/Telefonata). Rejected: estenderlo anche alle voci
  manuali — fuori dalla richiesta originale, si può riconsiderare in futuro.
- **Esposizione connettore: lettura e scrittura** — sia i collegamenti generali sia quello
  per-messaggio sono leggibili e scrivibili via `perg`/`pergamenum-mcp`, seguendo il principio del
  progetto per cui una nuova capability va nel Connector (`Sources/Connector`), non in uno dei due
  front-end. Rejected: solo lettura, o solo UI — limiterebbe l'utilità per un agente AI che lavora
  sul vault senza passare dall'app.

## Constraints

- **`pratica.md` ha esattamente un editor, l'inspector** — origine: ADR-0036 §D5, non riaperta da
  questa feature (vedi Decisions: nessuna commutazione di contenuto nell'inspector).
- **Sync non riscrive mai un file messaggio fuori dai tre trigger già elencati** — origine:
  ADR-0036 §D6, amendato da ADR-0040 §D5/§D7 e ADR-0042 §D7. La scrittura della chiave
  `pergamenum-mail-note` è un'azione utente esplicita (collegamento manuale), non un trigger di
  sync, e non deve interferire con quella lista chiusa.
- **Riferimenti by-title, mai by-path** — origine: ADR-0022 (già stabilita per i wikilink di
  qualsiasi tipo nell'app).
- **Ogni nuovo file sotto `Sources/Core` deve restare Foundation-only** — origine: ADR-0001 §D1,
  enforcement strutturale (rompe entrambe le build dei connettori se violato).
- **Scritture via connettore passano dalle tre garanzie esistenti** (`isDryRun`, `UnifiedDiff`,
  `WriteJournal`) e, lato MCP, restano nascoste da `tools/list` senza `--allow-write`, con
  `dryRun` di default `true` — origine: ADR-0007 §D6.

## Stack

Nessuna nuova dipendenza. Swift 6 / SwiftUI su `Sources/Core`, `Sources/Features/Pratiche`,
`Sources/Connector`, secondo l'architettura shared-sources esistente (CLAUDE.md, "AI connector").

## Data model

- **Pratica → collegamenti generali**: liste di riferimenti per tipo (note, attività, board),
  salvate come nuove chiavi frontmatter su `pratica.md`, in aggiunta alle chiavi
  `pergamenum-dossier-*` già esistenti. Ogni riferimento è un nome/titolo, non un percorso.
- **Messaggio → nota collegata**: un riferimento opzionale (0 o 1), salvato come nuova chiave
  frontmatter sul file messaggio, in aggiunta al set `pergamenum-mail-*` già esistente. Anche qui
  il riferimento è per titolo, non per percorso.
- **Risoluzione**: entrambi i riferimenti si risolvono per titolo/nome contro il vault corrente,
  seguendo automaticamente una rinomina del target; se il target non esiste più, il riferimento
  resta e viene segnalato come rotto invece di essere silenziosamente rimosso.
- **Vista aggregata**: la lista "note collegate" mostrata nell'inspector generale della pratica
  unisce i collegamenti generali e le note per-messaggio della stessa pratica.

## API / interfaces

Nuove capability nel Connector (lette/scritte da entrambi `perg` e `pergamenum-mcp`, seguendo il
pattern esistente di `Sources/Connector/VaultPratiche.swift`):

- Lettura dei collegamenti generali di una pratica (note/attività/board) e delle note per-messaggio
  del suo timeline.
- Scrittura: collegare/scollegare una nota/attività/board esistente a una pratica; collegare/
  scollegare una nota a un messaggio specifico; creare una nuova nota/attività/board già collegata
  al contesto (pratica o messaggio).

Le scritture passano dalle tre garanzie esistenti (dry-run, diff, journal) come ogni altra
scrittura del connettore.

## UI flows

- **Collegamento generale**: dall'inspector della pratica, nuove sezioni sotto il corpo di
  `pratica.md` (pattern `BoardTray`) elencano note/attività/board collegate. Click destro sulla
  pratica (o su un elemento della lista) apre il comando "Collega nota/attività/workspace…", con
  opzione di collegare un elemento esistente o crearne uno nuovo precompilato dal contesto.
- **Collegamento per-messaggio**: click destro su una riga email nel timeline apre "Collega
  nota…", con la stessa scelta (esistente o nuova). Una volta collegata, la riga mostra un'icona
  indicatore e la nota appare nella colonna a destra del timeline, allineata verticalmente alla
  riga del messaggio, apribile direttamente da lì.
- **Link rotto**: se il target di un collegamento (generale o per-messaggio) non esiste più, la
  voce nella lista/colonna è visivamente marcata come rotta invece di scomparire.

## Edge cases

- Messaggio con nota collegata che viene poi cancellata: la riga mantiene l'icona indicatore, la
  colonna mostra lo stato "rotto" invece del contenuto della nota.
- Nota o attività o board rinominata: il collegamento (per titolo/nome) continua a risolvere
  correttamente, nessuna azione richiesta.
- Stesso titolo di nota usato altrove nel vault (ambiguità di risoluzione by-title): comportamento
  coerente con quello già esistente per `WorkspaceBoardResolver`/wikilink altrove nell'app (caso
  `.ambiguous`), non una nuova categoria di errore introdotta da questa feature.
- Messaggio senza nota collegata: nessuna icona, colonna vuota a quell'altezza (come nello
  screenshot di riferimento).
- Scrittura via connettore con `dryRun` di default: nessun collegamento viene creato finché non è
  esplicitamente confermato, coerente con le garanzie MCP esistenti.

## Test seams

- Unit test sul parsing/scrittura delle nuove chiavi frontmatter (collegamenti generali su
  `pratica.md`, nota-per-messaggio), stesso pattern dei test già esistenti per Dossier/
  MessageDocument.
- Unit test sulla logica di risoluzione by-title e sul rilevamento di link rotto.
- Unit test sulle nuove capability del connettore (lettura/scrittura, incluso il comportamento
  dry-run).
- Verifica manuale via UI suite (`scripts/uitests.sh`) per gli aspetti visivi (colonna allineata,
  icona indicatore, sezioni nell'inspector), coerente con la convenzione già in uso per la UI di
  Pratiche — nessun test UI automatico dedicato aggiunto in questa iterazione.

## Success criteria

- [ ] R-01 — Una pratica può essere collegata a più note, più attività e più board Workspace
      contemporaneamente, tramite il comando "Collega…" dal menu contestuale della pratica.
- [ ] R-02 — Un singolo messaggio email nel timeline di una pratica può avere al massimo una nota
      collegata, tramite il comando "Collega nota…" dal menu contestuale del messaggio.
- [ ] R-03 — Il comando "Collega…" (generale e per-messaggio) permette sia di scegliere un elemento
      esistente sia di crearne uno nuovo, precompilato con titolo e tag dal contesto.
- [ ] R-04 — I collegamenti generali (note/attività/board) sono visibili in nuove sezioni
      nell'inspector della pratica, sotto il corpo di `pratica.md`.
- [ ] R-05 — Un messaggio con nota collegata mostra un'icona indicatore sulla riga e la nota nella
      colonna allineata a destra del timeline, apribile direttamente da lì.
- [ ] R-06 — Le note collegate per-messaggio compaiono anche nella lista aggregata "note collegate"
      dell'inspector generale della pratica.
- [ ] R-07 — La rinomina della nota/attività/board collegata non rompe il collegamento (risoluzione
      by-title).
- [ ] R-08 — La cancellazione del target collegato mostra il collegamento come rotto/mancante,
      senza rimuoverlo in silenzio.
- [ ] R-09 — L'inspector della pratica resta sempre e solo la vista di `pratica.md`: nessuna
      selezione di riga nel timeline ne sostituisce il contenuto (ADR-0036 §D5 non riaperta).
- [ ] R-10 — Tutte le operazioni di lettura e scrittura di questa feature sono raggiungibili via
      `perg` e `pergamenum-mcp`, con le stesse garanzie (dry-run di default, diff, journal, hide
      senza `--allow-write`) delle altre scritture del connettore.

## Not yet specified

_none_

## Out of scope

- Collegamento nota per-riga per le voci manuali del timeline (Nota/Telefonata) — limitato alle
  email per restare aderente alla richiesta originale; riconsiderabile in una iterazione futura.
- Più note collegate allo stesso messaggio — la relazione è 0/1 per messaggio in questa iterazione.
- Un secondo pannello/tab separato per la nota del messaggio, distinto dall'inspector esistente —
  scelto invece l'allineamento nella colonna del timeline, senza toccare l'inspector.

## Domain terms

- **Pratica** — vedi ADR-0036: cartella riconosciuta dalla chiave frontmatter `pergamenum-dossier`
  su `pratica.md`, sincronizzata da Apple Mail.
- **Collegamento generale** — relazione Pratica → nota/attività/board, indipendente dai singoli
  messaggi, analoga a quella già esistente tra note/attività/progetti (ADR-0021, ADR-0039).
- **Collegamento per-messaggio** — relazione 0/1 tra un singolo messaggio email del timeline di una
  pratica e una nota.
