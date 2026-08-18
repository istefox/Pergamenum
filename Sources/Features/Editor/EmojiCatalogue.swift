import Foundation

/// One emoji the editor can write, as data.
///
/// `name` is what a person types after the `:` and what the row shows; `keywords` are the
/// other words that should find it, English included, so `:target` reaches «bersaglio»
/// without the catalogue having to be bilingual in its names.
struct EmojiEntry: Identifiable, Sendable, Equatable, RankableEntry {
    let glyph: String
    let name: String
    let keywords: [String]

    var id: String { glyph }
    var rankingTitle: String { name }
}

/// The emoji `:` offers, and the only ones it offers.
///
/// **A closed catalogue**, like `EditorCommand.editorEntries` and `KeyBinding.namedKeys`: the
/// list is the feature. Unicode has some four thousand emoji and a picker that offers all of
/// them is a picker nobody finds anything in - the useful ones for this app's three workflows
/// (work, knowledge, daily planning) are a couple of hundred, and an emoji that is not here
/// simply is not offered. Adding one is a line.
///
/// Names are Italian because the interface is. They carry no colons: the `:` that triggers
/// the picker is punctuation the person typed, not part of the name, and writing `:nota:`
/// here would put a shortcode syntax into the app that nothing else in it uses.
///
/// The glyph goes into the note; nothing about the file changes shape. SPEC §11.2 keeps
/// emoji out of the app's own chrome and this is the single, stated exception: a picker
/// showing what it is about to insert is showing content.
enum EmojiCatalogue {
    /// Fuzzy is on here and off for the command list, and the asymmetry is deliberate: the
    /// commands are a menu whose wording a person half-knows, so a subsequence match reshuffles
    /// what they were reading. An emoji is looked for by a name they may not know at all, and
    /// `stblmnt` reaching «stabilimento» is worth more than a stable order in a list of
    /// ninety-six.
    static func matching(_ query: String) -> [EmojiEntry] {
        EntryRanking.matching(query, in: entries, allowingFuzzy: true)
    }

    static let entries: [EmojiEntry] = work + planning + knowledge + people + signals + objects

    // MARK: Work

    private static let work: [EmojiEntry] = [
        EmojiEntry(glyph: "🎯", name: "bersaglio", keywords: ["obiettivo", "target", "goal", "mira"]),
        EmojiEntry(glyph: "📈", name: "crescita", keywords: ["grafico", "su", "chart", "aumento"]),
        EmojiEntry(glyph: "📉", name: "calo", keywords: ["grafico", "giù", "chart", "perdita"]),
        EmojiEntry(glyph: "📊", name: "grafico", keywords: ["barre", "dati", "chart", "report"]),
        EmojiEntry(glyph: "💰", name: "soldi", keywords: ["denaro", "prezzo", "money", "costo"]),
        EmojiEntry(glyph: "💶", name: "euro", keywords: ["valuta", "prezzo", "money"]),
        EmojiEntry(glyph: "🧾", name: "fattura", keywords: ["ricevuta", "scontrino", "invoice"]),
        EmojiEntry(glyph: "🤝", name: "accordo", keywords: ["stretta", "mano", "deal", "patto"]),
        EmojiEntry(glyph: "🏭", name: "stabilimento", keywords: ["fabbrica", "industria", "factory"]),
        EmojiEntry(glyph: "🏢", name: "azienda", keywords: ["ufficio", "edificio", "office", "cliente"]),
        EmojiEntry(glyph: "📦", name: "pacco", keywords: ["spedizione", "consegna", "box", "ordine"]),
        EmojiEntry(glyph: "🚚", name: "consegna", keywords: ["camion", "spedizione", "truck"]),
        EmojiEntry(glyph: "⚙️", name: "ingranaggio", keywords: ["meccanica", "config", "gear", "impostazioni"]),
        EmojiEntry(glyph: "🔧", name: "chiave", keywords: ["attrezzo", "riparazione", "wrench", "manutenzione"]),
        EmojiEntry(glyph: "🔨", name: "martello", keywords: ["attrezzo", "costruzione", "hammer"]),
        EmojiEntry(glyph: "🧪", name: "provetta", keywords: ["laboratorio", "prova", "test", "campione"]),
        EmojiEntry(glyph: "🔬", name: "microscopio", keywords: ["analisi", "ricerca", "lab"]),
        EmojiEntry(glyph: "📐", name: "squadra", keywords: ["misura", "disegno", "progetto", "quota"]),
        EmojiEntry(glyph: "📏", name: "righello", keywords: ["misura", "quota", "ruler"]),
        EmojiEntry(glyph: "🧰", name: "cassetta", keywords: ["attrezzi", "toolbox", "strumenti"]),
    ]

    // MARK: Planning

    private static let planning: [EmojiEntry] = [
        EmojiEntry(glyph: "✅", name: "fatto", keywords: ["spunta", "ok", "done", "completato"]),
        EmojiEntry(glyph: "☑️", name: "spunta", keywords: ["check", "casella", "task"]),
        EmojiEntry(glyph: "❌", name: "annullato", keywords: ["no", "errore", "cancel", "croce"]),
        EmojiEntry(glyph: "⏳", name: "attesa", keywords: ["clessidra", "pendente", "waiting", "sospeso"]),
        EmojiEntry(glyph: "⏰", name: "sveglia", keywords: ["ora", "promemoria", "alarm", "orario"]),
        EmojiEntry(glyph: "🗓️", name: "calendario", keywords: ["data", "giorno", "agenda", "calendar"]),
        EmojiEntry(glyph: "📅", name: "data", keywords: ["calendario", "giorno", "scadenza", "date"]),
        EmojiEntry(glyph: "⌛", name: "scaduto", keywords: ["tempo", "finito", "overdue"]),
        EmojiEntry(glyph: "🔁", name: "ricorrente", keywords: ["ripeti", "ciclo", "repeat", "loop"]),
        EmojiEntry(glyph: "🚧", name: "in corso", keywords: ["lavori", "wip", "cantiere", "progress"]),
        EmojiEntry(glyph: "🅿️", name: "parcheggiato", keywords: ["sospeso", "parked", "dopo"]),
        EmojiEntry(glyph: "🔝", name: "priorità", keywords: ["alto", "top", "primo", "urgente"]),
        EmojiEntry(glyph: "🧭", name: "bussola", keywords: ["direzione", "orientamento", "strategia"]),
        EmojiEntry(glyph: "🗺️", name: "mappa", keywords: ["roadmap", "percorso", "piano", "map"]),
        EmojiEntry(glyph: "🏁", name: "traguardo", keywords: ["fine", "milestone", "finish", "chiuso"]),
        EmojiEntry(glyph: "🚀", name: "lancio", keywords: ["rilascio", "release", "razzo", "partenza"]),
        EmojiEntry(glyph: "📌", name: "puntina", keywords: ["fissato", "pin", "importante", "nota"]),
        EmojiEntry(glyph: "🔖", name: "segnalibro", keywords: ["salvato", "bookmark", "riferimento"]),
    ]

    // MARK: Knowledge

    private static let knowledge: [EmojiEntry] = [
        EmojiEntry(glyph: "📝", name: "appunto", keywords: ["nota", "scrivere", "note", "memo"]),
        EmojiEntry(glyph: "📄", name: "documento", keywords: ["foglio", "file", "pagina", "doc"]),
        EmojiEntry(glyph: "📚", name: "libri", keywords: ["lettura", "studio", "books", "biblioteca"]),
        EmojiEntry(glyph: "📖", name: "libro", keywords: ["lettura", "aperto", "book", "capitolo"]),
        EmojiEntry(glyph: "🔍", name: "cerca", keywords: ["lente", "ricerca", "search", "trova"]),
        EmojiEntry(glyph: "💡", name: "idea", keywords: ["lampadina", "intuizione", "idea", "spunto"]),
        EmojiEntry(glyph: "🧠", name: "cervello", keywords: ["pensiero", "memoria", "brain", "ragionamento"]),
        EmojiEntry(glyph: "🗂️", name: "archivio", keywords: ["cartelle", "schedario", "files", "organizzazione"]),
        EmojiEntry(glyph: "📁", name: "cartella", keywords: ["folder", "raccolta", "directory"]),
        EmojiEntry(glyph: "🔗", name: "collegamento", keywords: ["link", "catena", "riferimento", "wikilink"]),
        EmojiEntry(glyph: "🧩", name: "tassello", keywords: ["puzzle", "pezzo", "incastro", "componente"]),
        EmojiEntry(glyph: "🏷️", name: "etichetta", keywords: ["tag", "cartellino", "label"]),
        EmojiEntry(glyph: "✍️", name: "scrittura", keywords: ["scrivere", "penna", "bozza", "write"]),
        EmojiEntry(glyph: "🖇️", name: "allegato", keywords: ["graffetta", "attach", "clip"]),
        EmojiEntry(glyph: "🗃️", name: "schedario", keywords: ["indice", "raccolta", "archivio"]),
        EmojiEntry(glyph: "📓", name: "quaderno", keywords: ["diario", "notebook", "taccuino"]),
    ]

    // MARK: People

    private static let people: [EmojiEntry] = [
        EmojiEntry(glyph: "👤", name: "persona", keywords: ["utente", "contatto", "person", "profilo"]),
        EmojiEntry(glyph: "👥", name: "persone", keywords: ["gruppo", "team", "riunione", "squadra"]),
        EmojiEntry(glyph: "📞", name: "telefonata", keywords: ["chiamata", "telefono", "call"]),
        EmojiEntry(glyph: "✉️", name: "email", keywords: ["posta", "messaggio", "mail", "lettera"]),
        EmojiEntry(glyph: "💬", name: "messaggio", keywords: ["chat", "commento", "fumetto", "nota"]),
        EmojiEntry(glyph: "🗣️", name: "parlato", keywords: ["voce", "detto", "riunione", "speaking"]),
        EmojiEntry(glyph: "👋", name: "saluto", keywords: ["ciao", "mano", "hello", "benvenuto"]),
        EmojiEntry(glyph: "🙏", name: "grazie", keywords: ["favore", "richiesta", "thanks", "prego"]),
        EmojiEntry(glyph: "👍", name: "ok", keywords: ["pollice", "approvato", "bene", "yes"]),
        EmojiEntry(glyph: "👎", name: "no", keywords: ["pollice", "respinto", "male", "negativo"]),
        EmojiEntry(glyph: "🎓", name: "formazione", keywords: ["laurea", "corso", "studio", "diploma"]),
        EmojiEntry(glyph: "🏆", name: "premio", keywords: ["coppa", "vittoria", "risultato", "trophy"]),
    ]

    // MARK: Signals

    private static let signals: [EmojiEntry] = [
        EmojiEntry(glyph: "⚠️", name: "attenzione", keywords: ["avviso", "warning", "pericolo", "rischio"]),
        EmojiEntry(glyph: "🚨", name: "urgente", keywords: ["allarme", "sirena", "alert", "critico"]),
        EmojiEntry(glyph: "🔥", name: "caldo", keywords: ["fuoco", "urgente", "hot", "bruciante"]),
        EmojiEntry(glyph: "❗", name: "importante", keywords: ["esclamativo", "attenzione", "nota"]),
        EmojiEntry(glyph: "❓", name: "domanda", keywords: ["dubbio", "question", "chiedere", "aperto"]),
        EmojiEntry(glyph: "🛑", name: "stop", keywords: ["fermo", "bloccato", "blocco", "halt"]),
        EmojiEntry(glyph: "🟢", name: "verde", keywords: ["ok", "libero", "green", "buono"]),
        EmojiEntry(glyph: "🟡", name: "giallo", keywords: ["attenzione", "medio", "yellow", "parziale"]),
        EmojiEntry(glyph: "🔴", name: "rosso", keywords: ["fermo", "grave", "red", "problema"]),
        EmojiEntry(glyph: "⭐", name: "stella", keywords: ["preferito", "importante", "star", "notevole"]),
        EmojiEntry(glyph: "🔒", name: "chiuso", keywords: ["lucchetto", "sicuro", "bloccato", "lock"]),
        EmojiEntry(glyph: "🔓", name: "aperto", keywords: ["lucchetto", "sbloccato", "unlock"]),
        EmojiEntry(glyph: "♻️", name: "riciclo", keywords: ["riuso", "ambiente", "recycle", "sostenibile"]),
        EmojiEntry(glyph: "🧯", name: "emergenza", keywords: ["estintore", "sicurezza", "incidente"]),
    ]

    // MARK: Objects

    private static let objects: [EmojiEntry] = [
        EmojiEntry(glyph: "💻", name: "computer", keywords: ["portatile", "laptop", "lavoro", "mac"]),
        EmojiEntry(glyph: "🖥️", name: "schermo", keywords: ["monitor", "desktop", "display"]),
        EmojiEntry(glyph: "📱", name: "telefono", keywords: ["cellulare", "mobile", "smartphone"]),
        EmojiEntry(glyph: "🖨️", name: "stampante", keywords: ["stampa", "printer", "carta"]),
        EmojiEntry(glyph: "📷", name: "foto", keywords: ["macchina", "immagine", "camera", "scatto"]),
        EmojiEntry(glyph: "🎥", name: "video", keywords: ["ripresa", "filmato", "camera", "registrazione"]),
        EmojiEntry(glyph: "🔋", name: "batteria", keywords: ["carica", "energia", "battery"]),
        EmojiEntry(glyph: "🧲", name: "magnete", keywords: ["attrazione", "calamita", "magnet"]),
        EmojiEntry(glyph: "🪛", name: "cacciavite", keywords: ["attrezzo", "vite", "montaggio"]),
        EmojiEntry(glyph: "⛓️", name: "catena", keywords: ["collegamento", "anelli", "chain", "vincolo"]),
        EmojiEntry(glyph: "🧱", name: "mattone", keywords: ["muro", "base", "costruzione", "brick"]),
        EmojiEntry(glyph: "🕒", name: "orario", keywords: ["ora", "orologio", "clock", "tempo"]),
        EmojiEntry(glyph: "☕", name: "caffè", keywords: ["pausa", "mattina", "coffee", "break"]),
        EmojiEntry(glyph: "🏠", name: "casa", keywords: ["abitazione", "home", "personale"]),
        EmojiEntry(glyph: "🚗", name: "auto", keywords: ["macchina", "viaggio", "car", "trasferta"]),
        EmojiEntry(glyph: "✈️", name: "aereo", keywords: ["volo", "viaggio", "trasferta", "flight"]),
    ]
}
