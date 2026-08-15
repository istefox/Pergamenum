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

    TASK
      task list            --view inbox|today|upcoming|by-project|all  (all)
                           --day <YYYY-MM-DD>   il giorno di riferimento (oggi)
                           --completed          mostra anche i chiusi

    GIORNATA
      day show [data]      blocchi, cosa è in programma e cosa scade
                           senza EventKit: il giorno come è scritto, non come lo sa il Mac

    CONFORMITÀ
      lint [percorso]      le regole di SPEC §4.7, le stesse del pannello Conformità
                           esce 2 se qualcosa non è conforme

    INDICE
      index stats          quante note, quanti task, quanto ha impiegato la scansione

    OPZIONI GLOBALI
      --json               risposta in JSON invece che per un lettore umano
      --help               questo testo

    USCITA
      0  fatto
      1  la riga di comando è sbagliata
      2  il comando era chiaro e non si è potuto eseguire

    Nessuno di questi comandi scrive. Le scritture arriveranno con i loro guardrail:
    --dry-run mostra il diff senza applicarlo, e ogni scrittura finisce in un journal
    annullabile.
    """
}
