import AppKit

// ADR-0083 §D6 (PG-386, N3 session B). Its own file because `CompletingTextView.swift` is at the
// file length the linter warns at: each arm there stays one line.

extension CompletingTextView {
    /// The `[[` popup's rows: the candidates, or, when nothing matches and the typed text can be a
    /// note's title, the one «Crea «X»» row. Only where something can act on it: a host with no
    /// `offerCreation` (a Workspace card has its own completion) shows no row.
    func wikilinkItems(matching prefix: String) -> [CompletionItem] {
        let candidates = wikilinkCandidates(matching: prefix)
        guard candidates.isEmpty, offerCreation != nil, LinkDestination.isCreatable(prefix) else {
            return candidates.map(CompletionItem.wikilink)
        }
        return [.createNote(title: prefix)]
    }

    /// Completes the link through the insertion N1 shipped for a candidate (never `]]]]`,
    /// n1-seams R-07), then offers the title to the composer. The offer never creates a file.
    func createNote(_ title: String, replacing range: NSRange) {
        insertWikilink(WikilinkCandidate(displayTitle: title, insertText: title, kind: .note), replacing: range)
        offerCreation?(title)
    }
}
