import AppKit

extension NSPasteboard {
    /// Una pasteboard privata e usa-e-getta, per i test.
    ///
    /// Non è una comodità: con `.general`, eseguire la suite lasciava un link
    /// `pergamenum://` negli appunti reali dell'utente a ogni run. Stessa disciplina di
    /// `RecentVaults.volatile()` — eseguire i test non deve cambiare il Mac.
    static func volatile() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("pergamenum.tests.\(UUID())"))
    }
}
