import Foundation

enum Help {
    static let text = """
    perg - il vault di Pergamenum dalla riga di comando (ADR-0007)

    USO
      perg <gruppo> <comando> [argomenti] [opzioni]

    VAULT
      --vault <cartella>   su quale vault agire
                           altrimenti $PERGAMENUM_VAULT, altrimenti l'ultimo aperto
                           dall'app

    NOTE
      note list [--folder <cartella>]   le note del vault
      note read <percorso>              il file come sta su disco
      note links <percorso>             i wikilink che porta, risolti e non
      note backlinks <titolo>           chi punta a quel titolo
      note unresolved                   ogni link che non risolve, con chi lo scrive

    RICERCA
      search <query>       tag:, path:, task:open, "frase esatta" e parole, in AND
                           es. perg search 'tag:type-note trasmissibilità'
                           --limit <n> per fermarsi prima (200 di default)

      note new <titolo>                 [--folder <cartella>] [--topic <tag>] [--date <data>]
      note append <percorso> <testo>    aggiunge in fondo, dopo una riga vuota
      note rename <percorso> <titolo>   rinomina, riscrivendo i link e le board che puntano
      note move <percorso> <cartella>   sposta; cartella vuota per portarla alla radice
      note trash <percorso>             al cestino; segnala chi resta senza link

    CATTURA
      capture <testo>      [--dest note|task|today|note:PERCORSO]  (note)
                           note   una nota nuova, il titolo è la prima riga
                                  [--folder <cartella>]  (00 Inbox)
                           task   una riga di task nell'inbox
                                  [--scheduled <data>] [--due <data>]
                           today  in fondo alla nota di oggi, creata se manca
                           note:  in fondo a una nota che esiste già
                           le date valgono solo con --dest task

    TASK
      task list            --view inbox|today|upcoming|by-project|all  (all)
                           --day <YYYY-MM-DD>   il giorno di riferimento (oggi)
                           --completed          mostra anche i chiusi
      task add <testo>     [--scheduled <data>] [--due <data>] [--note <percorso>]
                           senza --note va nell'inbox, che viene creato se manca
      task done <task>     il task per testo, oppure esatto come percorso:riga
      task reopen <task>
      task reschedule <task> --to <data|none>

    GIORNATA
      day show [data]      blocchi, cosa è in programma e cosa scade
                           senza EventKit: il giorno come è scritto, non come lo sa il Mac
      day block add <titolo> --at HH:MM [--minutes n] [--day <data>]
                           se l'ora è occupata il blocco scala, non si sovrappone

    CONFORMITÀ
      lint [percorso]      le regole di SPEC §4.7, riferite e basta
                           esce 2 se qualcosa non è conforme

    VISTE
      view list            i blocchi pergamenum-view del vault, con la loro posizione
                           nella nota; legge ogni nota, quindi non è gratis
      view run <percorso> [--ordinal n]
                           esegue quella vista e stampa le righe che trova

    INDICE
      index stats          quante note, quanti task, quanto ha impiegato la scansione

    APP
      app open today                    porta l'app sulla giornata di oggi
      app open note <percorso>          apre quella nota
      app open day <data>
      app open search <query>
                           l'unico comando che ha bisogno dell'app: la lancia se è
                           chiusa. --app <bundle> per indirizzare una copia precisa

    JOURNAL
      journal log          le scritture fatte da perg, dalla più vecchia [--limit n]
      journal undo <id>    rimette il file com'era, e si rifiuta se qualcuno lo ha
                           toccato dopo

    OPZIONI GLOBALI
      --json               risposta in JSON invece che per un lettore umano
      --dry-run            sui comandi che scrivono: mostra il diff e non tocca niente
      --help               questo testo

    USCITA
      0  fatto
      1  la riga di comando è sbagliata
      2  il comando era chiaro e non si è potuto eseguire

    Ogni scrittura è registrata in .pergamenum/ai-journal/ con il testo che aveva
    sostituito. Rinominare, spostare ed eliminare aprono un'unica operazione: «journal
    undo» accetta anche il suo id, e rimette a posto tutto quel che ha toccato oppure
    rifiuta l'intera operazione se nel frattempo qualcosa è cambiato.
    """
}
