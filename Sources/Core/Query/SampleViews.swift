import Foundation

/// The views M11 ships with and the weekly review M12 adds, as templates (ADR-0009,
/// ADR-0011 §D5, ADR-0013).
///
/// **Templates rather than notes written into the vault.** A template is an ordinary note in a
/// reserved folder, so these open, edit, index and search like anything else, and nothing is
/// written until somebody asks for it. A vault that gets five files it did not ask for on first
/// launch is an app deciding what belongs in a person's notes, which principle 1 is against.
///
/// Each one is a working example of one renderer, and each carries a line of prose saying what
/// it is for - a block of seven keys with no sentence around it teaches nothing.
enum SampleViews {
    struct Sample: Equatable, Sendable {
        /// The file name inside `Templates/`, without the extension.
        let name: String
        let text: String

        var relativePath: String { "\(NoteTemplate.folder)/\(name).md" }
    }

    static let all: [Sample] = [clients, projects, readings, orphans, deadlines, weeklyReview]

    private static func sample(_ name: String, _ prose: String, _ block: String) -> Sample {
        Sample(
            name: name,
            text: """
            ---
            date: 2026-08-20
            tags:
              - topic-viste
              - type-note
            ---

            \(prose)

            ```pergamenum-view
            \(block)
            ```
            """
        )
    }

    /// The roadmap asks for this one as a board by status. It is grouped by `project-*`
    /// instead, and the note says why: tag.md 5.1 forbids `status-*` on a note, so a status
    /// board would refuse its own drops (ADR-0009 §D5, amended 2026-08-20). Grouping by an
    /// open family makes it the working example it is meant to be.
    private static let clients = sample(
        "Vista - Clienti attivi",
        """
        Il lavoro per cliente, una colonna per progetto. Trascinare una card fra due colonne
        riscrive il tag nella nota, con il journal dietro.

        Raggruppata per `project-*` e non per `status-*` perché tag.md 5.1 vieta uno stato
        sulle note: una board per stato disegnerebbe le colonne e rifiuterebbe ogni drop.
        """,
        """
        from: path("Clienti")
        where: tag("client-*")
        group: tag("project-*")
        sort: modified desc
        render: board
        columns: [title, tags, tasks.open]
        """
    )

    private static let projects = sample(
        "Vista - Progetti",
        """
        I progetti aperti con quanto lavoro resta e quando scade il prossimo. Ordinata per
        scadenza: quello che scade prima sta in cima, e una nota senza scadenza va in fondo.
        """,
        """
        where: tag("project-*")
        sort: deadline.next
        render: table
        columns: [title, tags, tasks.open, deadline.next, modified]
        """
    )

    private static let readings = sample(
        "Vista - Letture",
        """
        Quello che c'è da leggere, con la copertina del primo file che ogni nota allega.
        Le miniature vengono da `embedTargets`, il campo che M11 ha aggiunto all'indice.
        """,
        """
        where: has(embedTargets)
        sort: modified desc
        render: gallery
        """
    )

    private static let orphans = sample(
        "Vista - Note orfane",
        """
        Le note che nessuno linka e che non linkano nessuno. Non è una lista di errori: è
        dove si guarda quando il vault sembra pieno e la mappa sembra vuota.
        """,
        """
        where: not has(links) and not has(linkedFrom)
        sort: title
        render: list
        columns: [title, tags, modified]
        """
    )

    private static let deadlines = sample(
        "Vista - Scadenze",
        """
        Le scadenze dei task, posate sul giorno in cui cadono. Il giorno è il primo campo di
        tipo data fra le `columns`, qui `deadline.next`.
        """,
        """
        where: has(deadline.next)
        sort: deadline.next
        render: calendar
        columns: [title, deadline.next]
        """
    )

    /// The weekly review the roadmap asks for: a template plus a view, in one note (ADR-0013).
    ///
    /// Written by hand rather than through `sample()` because it is four blocks and not one -
    /// a review is four questions, and four notes to open on a Friday afternoon is a ritual
    /// nobody keeps.
    ///
    /// **None of the four asks for "this week", and the note says why.** The block grammar
    /// compares `date` and `modified` against an ISO date and nothing else (ADR-0009 §D1), so a
    /// literal week would be a week that went stale the following Monday, silently. Ordering by
    /// `modified` answers the same question without a date in it, and adding a relative literal
    /// to the grammar is a decision for its own ADR rather than something to slip into a
    /// template.
    private static let weeklyReview = Sample(
        name: "Revisione settimanale",
        text: """
        ---
        date: 2026-08-21
        tags:
          - topic-revisione
          - type-note
        ---

        Da usare come template il venerdì: `Cmd+N`, poi «Revisione settimanale».

        Nessuno dei quattro blocchi dice «questa settimana», ed è voluto: il linguaggio
        delle viste confronta `modified` con una data scritta per esteso, quindi una
        settimana letterale sarebbe scaduta il lunedì dopo senza dirlo. L'ordine per
        `modified` risponde alla stessa domanda senza avere una data dentro.

        ## Cosa si è mosso

        ```pergamenum-view
        sort: modified desc
        limit: 15
        render: table
        columns: [title, modified, tasks.open]
        ```

        ## Cosa è rimasto aperto

        ```pergamenum-view
        where: task(open)
        sort: tasks.open desc
        render: table
        columns: [title, tasks.open, deadline.next]
        ```

        ## Cosa non è pianificato

        Task aperti in note che non hanno nessun `>data`: è la lista da cui si pesca
        quando si programma la settimana dopo, trascinando sui giorni.

        ```pergamenum-view
        where: task(open) and not has(scheduled.next)
        sort: title
        render: list
        columns: [title, tasks.open]
        ```

        ## Quali progetti si sono mossi

        ```pergamenum-view
        where: tag("project-*")
        sort: modified desc
        render: table
        columns: [title, tags, modified]
        ```

        ## Note della settimana

        - Cosa ha funzionato:
        - Cosa è slittato, e perché:
        - Cosa decido per la settimana prossima:
        """
    )
}
