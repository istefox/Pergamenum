import Foundation

/// The entries of a table column's menu and the edit each one makes (ADR-0087 §D11): the three
/// alignments, the column's own one ticked, then the two sorts. One list for the column control and
/// the header cell's right-click, so the two cannot offer different things.
enum TableColumnMenu {
    enum Entry: Equatable, Sendable {
        case align(GFMTable.Alignment, isCurrent: Bool)
        case sort(ascending: Bool)
    }

    static func entries(current: GFMTable.Alignment) -> [Entry] {
        [GFMTable.Alignment.leading, .center, .trailing].map { .align($0, isCurrent: $0 == current) }
            + [.sort(ascending: true), .sort(ascending: false)]
    }

    static func title(of entry: Entry) -> String {
        switch entry {
        case .align(.leading, _): "Allinea a sinistra"
        case .align(.center, _): "Allinea al centro"
        case .align(.trailing, _): "Allinea a destra"
        case .sort(ascending: true): "Ordina A→Z"
        case .sort(ascending: false): "Ordina Z→A"
        }
    }

    /// The `TableEdit` an entry makes on `column`; nil for the alignment the column already has,
    /// which writes nothing.
    static func edit(for entry: Entry, column: Int) -> TableEdit? {
        switch entry {
        case .align(_, isCurrent: true): nil
        case .align(let alignment, isCurrent: false): .align(column: column, alignment)
        case .sort(let ascending): .sort(column: column, ascending: ascending)
        }
    }
}
