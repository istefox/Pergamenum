import Foundation

/// The notes a Workspace board references, for the "Note referenziate" section of its
/// dashboard (ADR-0021 §D7, §D8; R-06).
///
/// Read from the open board document itself, never from the index: the board is
/// already loaded and already in memory, and asking the index would answer a
/// different question ("which notes mention this board") and would be wrong on a
/// board whose cards were placed and never linked. Pure and in `Core` so it is tested
/// against a `CanvasDocument` built in memory, with no window, no vault and no
/// SwiftUI - the same reason `TaskArrangement` is where it is.
enum WorkspaceReferences {
    /// Every note this board carries: the `.md` Document cards, plus every wikilink
    /// found inside its text nodes. De-duplicated, stable order.
    ///
    /// Order is the board document's own node order, and within a text node the
    /// source order `WikilinkParser.links` returns - so two calls on the same document
    /// answer identically and the section does not reshuffle itself on every redraw.
    /// `.link`, `.group` and `.unknown` nodes carry no note, and a `.file` node whose
    /// path is not a `.md` is a PDF, an image or an email card rather than a note.
    static func notes(in document: CanvasDocument) -> [String] {
        var results: [String] = []
        var seen: Set<String> = []

        func append(_ path: String) {
            guard !path.isEmpty, seen.insert(path).inserted else { return }
            results.append(path)
        }

        for node in document.nodes {
            switch node.kind {
            case .file(let path, _):
                // Case-insensitively, the way the rest of the app reads an extension:
                // a card pointing at `Nota.MD` is still a note.
                guard (path as NSString).pathExtension.lowercased() == "md" else { continue }
                append(path)
            case .text(let text):
                for link in WikilinkParser.links(in: text) {
                    append(link.target)
                }
            case .link, .group, .unknown:
                continue
            }
        }

        return results
    }

    /// `references` with every entry that names an already-listed note dropped (PG-359).
    ///
    /// `notes(in:)` de-duplicates by the string it read, and the same note arrives under two
    /// spellings: a `.file` card carries its vault path, a wikilink its title. `resolve` turns
    /// either into the path it names, or nil when it names nothing; an unresolved entry is keyed
    /// on its own text, so it stays listed once and never collapses into another. First
    /// occurrence wins, so the order is still the board's.
    static func collapsing(_ references: [String], resolve: (String) -> String?) -> [String] {
        var seen: Set<String> = []
        return references.filter { seen.insert(resolve($0) ?? $0).inserted }
    }
}
