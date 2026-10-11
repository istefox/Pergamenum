import Foundation

// ADR-0084 §D3, §D4 (PG-386, N3 session A): connector parity for «Collega» and «Scollega»,
// mandatory per the SPEC. Both go through the session's doors, armed by `VaultAPI.arm` like
// every other write, so a rehearsal returns the diff and a real write is journalled.
extension VaultAPI {
    /// «Collega» as a connector write: `title` is the target's, `path` the note written.
    ///
    /// Plans and writes in one call, expecting the hash the plan was read from, so a writer
    /// landing in between is refused rather than overwritten.
    @MainActor
    static func linkMention(
        _ session: VaultSession, in path: String, title: String
    ) async throws -> WriteSummary {
        guard !path.isEmpty else {
            throw ConnectorError("serve il percorso della nota da scrivere", usage: true)
        }
        guard !title.isEmpty else {
            throw ConnectorError("serve il titolo della nota da collegare", usage: true)
        }
        try requireNote(session, path)
        // A title no note answers to would write a dangling link, and a title several notes share
        // would write whichever spelling came first: both refused by name, never written.
        let carriers = session.index.resolve(title: title).compactMap { session.index.note(at: $0) }
        guard carriers.count <= 1 else {
            // The tool takes a title, and a wikilink names a title: there is no "which" to give,
            // so the sentence says what does resolve it, as `removeStructuralLink`'s does.
            throw ConnectorError(
                "il titolo «\(title)» è di più note, e il link si scrive per titolo: rinomina una delle omonime"
            )
        }
        guard let target = carriers.first else {
            throw ConnectorError("nessuna nota si chiama «\(title)»")
        }
        // The resolution is case-insensitive; the link written is the note's own title, so a
        // caller's «curva» for «Curva» writes `[[Curva]]`, never a dangling-looking `[[curva|Curva]]`.
        let title = target.title
        let noMention = ConnectorError("nessuna menzione non collegata di «\(title)» in «\(path)»")
        guard let plan = session.planLinkMention(in: path, to: title) else { throw noMention }

        switch await session.linkMention(in: path, to: title, expecting: plan.hash) {
        case .linked(let result):
            return summarise(result, session: session)
        case .noMention:
            throw noMention
        case .movedOn:
            throw ConnectorError("non scritto: \(VaultWriteRefusal.movedOn(path).description)")
        case .failed(let reason):
            throw ConnectorError("non scritto: \(reason)")
        }
    }

    /// «Scollega» as a connector write: both paths, never a title, so a connector never
    /// resolves a title to the first match.
    ///
    /// One summary per file written. Under a dry run the session computes both writes and
    /// performs neither, so a rehearsal returns both diffs. A removal refused before anything
    /// landed throws the session's sentence; a half-done one returns what landed, with a note
    /// naming the side that was refused (ADR-0084 §D4).
    @MainActor
    static func removeStructuralLink(
        _ session: VaultSession, from path: String, to target: String
    ) async throws -> [WriteSummary] {
        guard !path.isEmpty, !target.isEmpty else {
            throw ConnectorError("servono il percorso della nota e quello della destinazione", usage: true)
        }
        try requireNote(session, path)
        try requireNote(session, target)
        let problemsBefore = session.problems.count
        let (removed, written) = await session.removeStructuralLink(from: path, toNoteAt: target)
        // The sentence this call recorded, and nobody else's.
        let problem = session.problems.dropFirst(problemsBefore).last
        guard removed || !written.isEmpty else {
            throw ConnectorError(problem ?? "legame strutturale non tolto")
        }
        return written.map { summarise($0, session: session, note: removed ? nil : problem) }
    }

    /// Both doors write wikilinks and frontmatter into a note: a path that exists but is not an
    /// indexed note (a `.canvas`, a `.pergamenum/*.json`) is refused before anything is read, in the
    /// session's own words (`VaultSession.linkEndRefusal`) so the app and a connector refuse alike.
    @MainActor
    private static func requireNote(_ session: VaultSession, _ path: String) throws {
        if let refusal = session.linkEndRefusal(path) { throw ConnectorError(refusal) }
    }
}
