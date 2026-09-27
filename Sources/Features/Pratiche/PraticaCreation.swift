import Foundation

// ADR-0067 §D13 item 7: the «Crea» wizard's write, pulled out of
// `NuovaPraticaWizard+Actions.performCreate` so it carries the `expectingAbsent:`
// precondition without `performCreate` itself growing a second write door. The `exists`
// check stays in `performCreate` as the filter that gives the early sentence; this is the
// guard, on the far side of every `await` the wizard crossed.

/// Writes a new `pratica.md`, app target only (`PraticaCommandActions`'s own scope, not
/// `Sources/Connector`).
enum PraticaCreation {
    /// Writes `document` as `folder`'s `pratica.md`, refusing when one is already there -
    /// including one created during the suspension between `performCreate`'s `exists` check
    /// and this write, which is never overwritten. `nil` once the note landed, the sentence
    /// to show otherwise.
    static func writeNote(at folder: String, document: NoteDocument, session: VaultSession) async -> String? {
        let path = PraticaNaming.praticaNotePath(of: folder)
        do {
            try await session.write(document.serialized(), to: path, expectingAbsent: true)
            return nil
        } catch is VaultWriteRefusal {
            return "«\(folder)» esiste già."
        } catch {
            return "«\(path)» non è stato creato: \(error.localizedDescription)"
        }
    }
}
