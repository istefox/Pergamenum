import SwiftUI

// MARK: - Il tag browser e le preferite (M10)

/// The third slice of ADR-0012: a way through the tags, and the notes worth keeping to hand.
///
/// The data model is settled and is not what this is for. Starred notes are a set of relative
/// paths in `.pergamenum/starred.json` (D6); renaming a tag across the vault is N single-note
/// writes through `VaultSession.write`, journalled, shown as a diff first (D7); the pinned tags
/// are this machine's business and stay in `UserDefaults` (D10's reasoning). Three questions of
/// placement were answered on 2026-08-19 before this was drawn:
///
/// - **The browser is a pane of its own**, the seventh, beside Note, Workspace, Oggi, Diario,
///   Attività and Conformità. The Note pane already carries a filter, a folder tree and the
///   index in 230 points of width; a fourth stacked section there would be the cheap answer.
/// - **Starred notes are a «PREFERITE» section at the top of the Note pane**, folded away when
///   there are none, filled from the note's context menu and from the inspector.
/// - **Choosing two tags narrows**: the notes that carry *all* of them survive. AND, with no
///   switch for OR - a tag added must take notes away, or "narrowing" means nothing.
///
/// Three things were left to this mockup, and all three were **approved on 2026-08-19**:
///
/// 1. **The notes that survive stay under the tags, in the same pane.** Choosing a tag and
///    seeing what it leaves is one gesture; sending the result to another pane makes every
///    choice cost a look somewhere else.
/// 2. **A chosen tag is filled with the accent**, on `accentMuted`, the way the active tab is.
///    It reads from across the room in both themes, and it adds no glyph to a row that has a
///    name and a count on it already.
/// 3. **The rename shows one diff and a count.** The line that changes is the same line in
///    every note it touches, so showing it twelve times says what showing it once says, and
///    costs twelve blocks between the person and the button.
///
/// Everything here is literal: no controller, no index, no real tag. A mockup that reads the
/// vault is a feature half-built wearing a mockup's name.
struct TagBrowserMockup: View {
    @Environment(\.theme) private var theme

    /// Full width inside `MockupGalleryView.contentWidth`: 720 less 24 of padding a side.
    private static let sceneWidth: CGFloat = 672
    /// The sidebar at its usual width, so the pane is judged at the size it will have.
    private static let paneWidth: CGFloat = 300
    /// Two across: 2 × 328 + 16 of spacing = 672.
    private static let pairWidth: CGFloat = 328

    var body: some View {
        MockupPage {
            resting
            narrowed
            marking
            starred
            rename
        }
    }

    // MARK: A riposo

    /// Namespaces closed, counts on the right, and one pinned tag above them all. The count is
    /// the reason to open a namespace rather than guess.
    private var resting: some View {
        MockupScene("Il pannello a riposo: namespace chiusi, conteggi a destra, un tag appuntato in cima") {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                TagMockupPane(width: Self.pairWidth) {
                    TagMockupHeader(title: "TAG")
                    TagMockupTagRow(name: "client-nexion", count: 4, marking: .none, isPinned: true)
                    Divider().padding(.vertical, 2)
                    ForEach(Self.namespaces, id: \.name) { group in
                        TagMockupNamespaceRow(name: group.name, count: group.total, isOpen: false)
                    }
                }
                TagMockupPane(width: Self.pairWidth) {
                    TagMockupHeader(title: "TAG")
                    TagMockupNamespaceRow(name: "client", count: 12, isOpen: true)
                    TagMockupTagRow(name: "client-vibrofer", count: 8, marking: .none)
                    TagMockupTagRow(name: "client-nexion", count: 4, marking: .none)
                    TagMockupNamespaceRow(name: "topic", count: 31, isOpen: false)
                    TagMockupNamespaceRow(name: "project", count: 6, isOpen: false)
                }
            }
        }
    }

    // MARK: Ristretto

    /// Two tags chosen. The left column keeps the surviving notes under the tags, in the same
    /// pane; the right sends them to the Note pane and leaves the browser to the tags alone.
    private var narrowed: some View {
        MockupScene("Due tag scelti, in AND: le note restano qui sotto · le note tornano nel pannello Note") {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                TagMockupPane(width: Self.pairWidth) {
                    TagMockupHeader(title: "TAG")
                    TagMockupNamespaceRow(name: "client", count: 12, isOpen: true)
                    TagMockupTagRow(name: "client-nexion", count: 4, marking: .filled)
                    TagMockupNamespaceRow(name: "topic", count: 31, isOpen: true)
                    TagMockupTagRow(name: "topic-gomma", count: 19, marking: .filled)
                    TagMockupTagRow(name: "topic-ceramica", count: 12, marking: .none)
                    Divider().padding(.vertical, theme.spacing(.xs))
                    TagMockupHeader(title: "NOTE CON TUTTI E DUE (3)")
                    ForEach(Self.notes, id: \.self) { TagMockupNoteRow(title: $0) }
                }
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    TagMockupPane(width: Self.pairWidth) {
                        TagMockupHeader(title: "TAG")
                        TagMockupNamespaceRow(name: "client", count: 12, isOpen: true)
                        TagMockupTagRow(name: "client-nexion", count: 4, marking: .filled)
                        TagMockupNamespaceRow(name: "topic", count: 31, isOpen: true)
                        TagMockupTagRow(name: "topic-gomma", count: 19, marking: .filled)
                        TagMockupTagRow(name: "topic-ceramica", count: 12, marking: .none)
                    }
                    TagMockupPane(width: Self.pairWidth) {
                        TagMockupHeader(title: "NOTE · client-nexion + topic-gomma (3)")
                        ForEach(Self.notes, id: \.self) { TagMockupNoteRow(title: $0) }
                    }
                }
            }
        }
    }

    // MARK: Il segno della scelta

    private var marking: some View {
        MockupScene("Il tag scelto: riempito · con la spunta · in grassetto col conteggio acceso") {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                ForEach(TagMockupTagRow.Marking.chosen, id: \.self) { marking in
                    TagMockupPane(width: 213) {
                        TagMockupTagRow(name: "topic-gomma", count: 19, marking: marking)
                        TagMockupTagRow(name: "topic-ceramica", count: 12, marking: .none)
                    }
                }
            }
        }
    }

    // MARK: Le preferite

    /// The Note pane with the section, and without it. The empty case is the common one for
    /// weeks after the feature ships, and a heading over nothing is a heading in the way.
    private var starred: some View {
        MockupScene("Il pannello Note con le preferite in cima · senza nessuna preferita") {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                TagMockupPane(width: Self.pairWidth) {
                    TagMockupFilterField()
                    TagMockupHeader(title: "PREFERITE")
                    ForEach(Self.starredNotes, id: \.self) { TagMockupNoteRow(title: $0, isStarred: true) }
                    Divider().padding(.vertical, theme.spacing(.xs))
                    ForEach(Self.folders, id: \.self) { TagMockupFolderRow(name: $0) }
                }
                TagMockupPane(width: Self.pairWidth) {
                    TagMockupFilterField()
                    ForEach(Self.folders, id: \.self) { TagMockupFolderRow(name: $0) }
                    TagMockupNoteRow(title: "Curva di trasmissibilità")
                }
            }
        }
    }

    // MARK: La rinomina

    /// D7 shown to a person: the diff comes before the write, and the write is one note at a
    /// time through the journal. The question is how much diff.
    private var rename: some View {
        MockupScene("Rinomina in tutto il vault: il diff di una nota e il conteggio · tutte le note, scorrendo") {
            HStack(alignment: .top, spacing: theme.spacing(.m)) {
                TagMockupSheet(width: Self.pairWidth, title: "Rinomina «topic-gomma» in «topic-gomma-metallo»") {
                    Text("12 note toccate").themedText(.caption, color: .textSecondary)
                    TagMockupDiff(path: "Clienti/Nexion.md", lines: Self.diff)
                    Text("e altre 11, tutte con la stessa riga")
                        .themedText(.caption, color: .textTertiary)
                }
                TagMockupSheet(width: Self.pairWidth, title: "Rinomina «topic-gomma» in «topic-gomma-metallo»") {
                    Text("12 note toccate").themedText(.caption, color: .textSecondary)
                    TagMockupDiff(path: "Clienti/Nexion.md", lines: Self.diff)
                    TagMockupDiff(path: "Progetti/Sospensione.md", lines: Self.diff)
                    Text("scorri per le altre 10")
                        .themedText(.caption, color: .textTertiary)
                }
            }
        }
    }

    // MARK: Il contenuto finto

    private static let namespaces: [(name: String, total: Int)] = [
        ("client", 12), ("project", 6), ("topic", 31), ("type", 44), ("area", 9),
    ]

    private static let notes = [
        "Nexion — offerta antivibranti",
        "Curva di trasmissibilità",
        "Sospensione motore",
    ]

    private static let starredNotes = ["Nexion — offerta antivibranti", "Listino 2026"]

    private static let folders = ["Clienti", "Progetti", "Diario"]

    private static let diff: [TagMockupDiff.Line] = [
        .init(text: "  date: 2026-08-19", kind: .same),
        .init(text: "- tags: [topic-gomma, client-nexion]", kind: .removed),
        .init(text: "+ tags: [topic-gomma-metallo, client-nexion]", kind: .added),
        .init(text: "  related: []", kind: .same),
    ]
}
