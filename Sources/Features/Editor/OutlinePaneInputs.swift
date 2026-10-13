import Foundation

// ADR-0095 §D7, plan Task 4 (PG-406).
//
// What the sidebar's index is drawn from, as a value whose equality is the declared one: the rows are
// the same when their source is the same, so SwiftUI compares a store's identity and generation and
// never the rows themselves.

struct OutlinePaneInputs: Equatable {
    var rows: [OutlineRow]
    var source: OutlineRowsSource
    var notePath: String
    var currentEntry: Int?
    var foldedOrdinals: Set<Int>

    /// The entries a folded ancestor hides from the index itself (PG-090), so folding `## A.1` also
    /// takes its `### A.1.1` out of INDICE, not just out of the editor: the "next heading of the same
    /// or a higher level ends the section" rule `NoteFolding.sectionEnd` applies to lines, applied to
    /// the rows. An embed never ends a section, so it stays hidden with the section it sits inside.
    var hiddenByFold: Set<Int> {
        guard !foldedOrdinals.isEmpty else { return [] }
        var hidden: Set<Int> = []
        for index in foldedOrdinals {
            guard rows.indices.contains(index), case .heading(let level) = rows[index].kind else { continue }
            for next in rows.indices where next > index {
                if case .heading(let nextLevel) = rows[next].kind, nextLevel <= level { break }
                hidden.insert(next)
            }
        }
        return hidden
    }

    /// Equal when the source, the note, the current entry and the folds are: never the rows.
    static func == (lhs: OutlinePaneInputs, rhs: OutlinePaneInputs) -> Bool {
        lhs.source == rhs.source && lhs.notePath == rhs.notePath
            && lhs.currentEntry == rhs.currentEntry && lhs.foldedOrdinals == rhs.foldedOrdinals
    }
}
