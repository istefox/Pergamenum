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

    COMANDI
      index stats          quante note, quanti task, quanto ha impiegato la scansione
      help                 questo testo

    OPZIONI GLOBALI
      --json               risposta in JSON invece che per un lettore umano
      --help               questo testo

    USCITA
      0  fatto
      1  la riga di comando è sbagliata
      2  il comando era chiaro e non si è potuto eseguire

    Le scritture arriveranno con i loro guardrail: --dry-run mostra il diff senza
    applicarlo, e ogni scrittura finisce in un journal annullabile.
    """
}
