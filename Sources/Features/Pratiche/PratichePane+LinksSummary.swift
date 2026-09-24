import SwiftUI

// SPEC (task side of ADR-0049's pratica links), plan
// docs/plans/pratiche-links-task-side-and-inspector-summary.md, Task 5 - R-04, R-05.
//
// One line above `pratica.md`'s body saying how many notes, tasks and boards the pratica
// links, so the count is visible without scrolling past the body; a click scrolls down
// to the three sections `PratichePane+Links.swift` draws, which stay where they are.

extension PratichePane {
    /// The scroll target: set on `praticaLinksSection`'s call site in `inspector`, never
    /// inside `PratichePane+Links.swift`, whose sections are unchanged (R-05).
    ///
    /// Not `private`: `PratichePane+Inspector.swift`'s `inspector` reads it twice.
    static let praticaLinksAnchor = "pratiche-links-anchor"

    /// R-04: the counts, or a muted «nessun collegamento» that cannot be clicked when all
    /// three are zero - still drawn, so the line's position stays predictable.
    ///
    /// Not `private`: `PratichePane+Inspector.swift`'s `inspector` draws it, handing in the
    /// scroll as `onJump` because only that view holds the `ScrollViewProxy`.
    ///
    /// The three counts are **the same three expressions the section headers count**
    /// (`linkedNotesSection`, `linkedTasksSection`, `linkedBoardsSection`), so the summary
    /// and the sections it leads to cannot disagree: notes are `aggregatedNoteLinks` -
    /// general links plus notes reached only through a message - not `links.notes`, and a
    /// broken reference counts here exactly as it does there.
    @ViewBuilder
    func praticaLinksSummary(onJump: @escaping () -> Void) -> some View {
        let parts = Self.summaryParts(
            notes: pratiche.aggregatedNoteLinks.count,
            tasks: pratiche.links.tasks.count,
            boards: pratiche.links.boards.count
        )
        if parts.isEmpty {
            Text("nessun collegamento")
                .themedText(.caption, color: .textTertiary)
                .accessibilityIdentifier("pratiche-links-summary")
        } else {
            Button(action: onJump) {
                Text("\(Image(systemName: "link")) \(parts.joined(separator: " · "))")
                    .themedText(.caption, color: .accentPrimary)
            }
            .buttonStyle(.plain)
            .help("Vai ai collegamenti")
            .accessibilityLabel("Collegamenti: \(parts.joined(separator: ", "))")
            .accessibilityIdentifier("pratiche-links-summary")
        }
    }

    /// «3 note», «1 task», «2 board», a zero category left out. «nota»/«note» agrees in
    /// number; «task» and «board» are invariant in Italian.
    private static func summaryParts(notes: Int, tasks: Int, boards: Int) -> [String] {
        var parts: [String] = []
        if notes > 0 { parts.append("\(notes) \(notes == 1 ? "nota" : "note")") }
        if tasks > 0 { parts.append("\(tasks) task") }
        if boards > 0 { parts.append("\(boards) board") }
        return parts
    }
}
