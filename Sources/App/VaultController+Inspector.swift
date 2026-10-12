import Foundation

// ADR-0084 §D1, §D2, §D4, §D6 (PG-386, N3 session C).

/// One of the open note's own unresolved link targets, as the inspector lists it.
struct UnresolvedLinkRow: Equatable, Sendable, Identifiable {
    var id: String { target.lowercased() }
    let target: String
    let isCreatable: Bool
}

extension VaultController {
    /// The rows of the backlinks section for `title`: the line, the count and the badge, read from
    /// the files and memoised by `(indexGeneration, title)`.
    ///
    /// The index keeps storing paths (SPEC R-24): the lines are read off disk here, on demand,
    /// and the memo is what keeps the inspector's per-keystroke redraw from reading them again.
    func backlinkRows(toTitle title: String) -> [BacklinkRow] {
        backlinkRowsMemo.value(generation: indexGeneration, input: title) {
            guard let session else { return [] }
            return index.backlinks(toTitle: title).map { record in
                // The index says this note links here; a file that cannot be read now loses its
                // line, not its row: it was listed before the lines were read off disk. Whether
                // the link is structural is the index's `related`, the same list the badge reads.
                guard let read = try? session.read(record.relativePath) else {
                    return BacklinkRow(
                        title: record.title, path: record.relativePath, firstLine: nil, count: 1,
                        isStructural: BacklinkRow.isStructural(related: record.frontmatter.related, linking: title)
                    )
                }
                return BacklinkRow.make(
                    path: record.relativePath,
                    title: record.title,
                    text: read.text,
                    linking: title,
                    related: read.record.frontmatter.related
                )
            }
        }
    }

    /// «MENZIONI NON LINKATE» as the inspector lists them: the session's scan for the note at
    /// `path`, whole. On a title several notes share the section offers no «Collega» on any row
    /// (`sharedTitle(ofNoteAt:)`), so an alias-only row cannot answer it with `noMention`: it is a
    /// real mention of the note and stays in the list and its counter (ADR-0084 §D3).
    func linkableMentions(ofNoteAt path: String) -> [SearchResult] {
        unlinkedMentions(for: path)
    }

    /// The title of the note at `path` when another note carries it too, else nil. «Collega» is
    /// not offered for it: `[[Titolo]]` would point at every homonym, and the connectors refuse
    /// the same write by name (`VaultSession.sharedTitleLinkRefusal(_:)`).
    func sharedTitle(ofNoteAt path: String) -> String? {
        guard let title = index.note(at: path)?.title, index.resolve(title: title).count > 1 else { return nil }
        return title
    }

    /// The open note's own dangling targets, deduplicated case-insensitively: the first spelling
    /// the note uses is the one shown, in the order the note links them.
    func unresolvedLinkRows(ofNoteAt path: String) -> [UnresolvedLinkRow] {
        var seen: Set<String> = []
        return index.unresolvedTargets(of: path).compactMap { target in
            guard seen.insert(target.lowercased()).inserted else { return nil }
            return UnresolvedLinkRow(target: target, isCreatable: LinkDestination.isCreatable(target))
        }
    }

    /// «Scollega» as the inspector asks it: nil when the link is gone from both notes, otherwise
    /// the sentence naming why it is not (a homonym title, a note that moved on, a link taken from
    /// one side only), so the section can show it (SPEC R-27, ADR-0084 §D4).
    func unlinkStructuralLink(from sourcePath: String, toNoteAt targetPath: String) async -> String? {
        if await removeStructuralLink(from: sourcePath, toNoteAt: targetPath) { return nil }
        return problems.last ?? "il legame non è stato tolto"
    }

    /// Opens the structural-link sheet, with `targetPath` selected when given. A nil path still
    /// replaces an earlier row's choice, so «Nota correlata…» never inherits it.
    func beginStructuralLink(preselecting targetPath: String?) {
        structuralLinkPreselection = targetPath
        isAddingRelatedLink = true
    }

    /// Hands the preselection over once.
    func takeStructuralLinkPreselection() -> String? {
        defer { structuralLinkPreselection = nil }
        return structuralLinkPreselection
    }

    /// Where the note at `path` appears outside notes; `rescan` skips the memo.
    ///
    /// Memoised by `(path, indexGeneration)` (ADR-0084 §D6). A board save does not move the
    /// generation, so «Cerca di nuovo» passes `rescan` and its answer replaces the memo.
    func noteAppearances(ofNoteAt path: String, rescan: Bool) -> NoteAppearances {
        let generation = indexGeneration
        if !rescan, let memo = appearancesMemo, memo.generation == generation, memo.path == path {
            return memo.value
        }
        guard let session else { return .empty }
        let value = session.noteAppearances(of: path)
        appearancesMemo = AppearancesMemo(generation: generation, path: path, value: value)
        return value
    }

    /// One remembered «Dove compare» answer. Not an `IndexKeyedMemo`: a rescan has to replace
    /// the answer under an unchanged key, which that type never does.
    struct AppearancesMemo {
        let generation: Int
        let path: String
        let value: NoteAppearances
    }
}
