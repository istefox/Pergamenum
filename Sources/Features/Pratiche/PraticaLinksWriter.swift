import Foundation

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 2 - R-01, R-07, §D11.

/// One read-modify-write of a pratica's general links (`pratica.md`'s three
/// `pergamenum-dossier-links-*` keys), `DossierWriter.update`'s shape exactly - down
/// to the `expecting:` precondition, which matters more here than for the dossier
/// itself: a links write and a running sync's dossier write touch the same file's
/// frontmatter from two different actors, and the loser of that race must be told
/// rather than silently dropped (ADR §D11, reusing ADR-0046 §D1's argument).
@MainActor
enum PraticaLinksWriter {
    /// Reads `praticaPath`'s `pratica.md`, parses its links, hands them to `change`,
    /// re-renders and writes back only if something actually changed. Returns the
    /// Italian sentence to report on failure, `nil` on success - including "nothing
    /// changed", which is a success with no write.
    @discardableResult
    static func update(
        at praticaPath: String, session: VaultSession, _ change: (inout PraticaLinks) -> Void
    ) async -> String? {
        let notePath = PraticaNaming.praticaNotePath(of: praticaPath)
        do {
            let (record, text) = try session.read(notePath)
            var document = NoteDocument.parse(text)
            let before = document
            var links = PraticaLinks.parse(document.frontmatter.foreignKeys)
            change(&links)
            document.frontmatter.foreignKeys = PraticaLinks.merging(links, into: document.frontmatter.foreignKeys)
            guard document != before else { return nil }
            try await session.write(document.serialized(), to: notePath, expecting: record.contentHash)
            return nil
        } catch let refusal as VaultSession.WriteRefusal {
            return "«\(notePath)» non è stato aggiornato: \(refusal.description)"
        } catch {
            return "«\(notePath)» non è stato aggiornato: \(error.localizedDescription)"
        }
    }
}
