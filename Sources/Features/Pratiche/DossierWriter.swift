import Foundation

// ADR-0036 §D22.4 (PG-117), plan
// docs/superpowers/plans/2026-09-10-pratiche-pg105-pg108.md, Task 4.
//
// `PraticaCommandActions.updateDossier` is a thin wrapper over `update` below - every
// one of that method's call-sites keeps calling the wrapper unchanged.

/// One read-modify-write of a pratica's `pratica.md` dossier keys, through
/// `VaultSession.write` so the index and the watcher stay in step - never
/// `String.write(to:)`, which would leave the app looking at its own file as an
/// external change. Byte-preserving on every foreign key it does not own
/// (`Dossier.merging`, §D12).
@MainActor
enum DossierWriter {
    /// Reads `praticaPath`'s `pratica.md`, parses its dossier, hands it to `change`,
    /// re-renders and writes back only if something actually changed. Returns the
    /// Italian sentence to report on failure, `nil` on success - including "nothing
    /// changed", which is a success with no write.
    @discardableResult
    static func update(
        at praticaPath: String, session: VaultSession, _ change: (inout Dossier) -> Void
    ) async -> String? {
        let notePath = PraticaCommandActions.praticaNotePath(of: praticaPath)
        do {
            var document = NoteDocument.parse(try session.read(notePath).text)
            let before = document
            guard var dossier = Dossier.parse(document.frontmatter.foreignKeys) else { return nil }
            change(&dossier)
            document.frontmatter.foreignKeys = Dossier.merging(dossier, into: document.frontmatter.foreignKeys)
            guard document != before else { return nil }
            try await session.write(document.serialized(), to: notePath)
            return nil
        } catch {
            return "«\(notePath)» non è stato aggiornato: \(error.localizedDescription)"
        }
    }
}
