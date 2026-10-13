import Foundation

/// The registry of the columns' outline stores (ADR-0096 §D6, PG-406): one store per editor column,
/// made where the column is made and dropped when the column closes. A store follows the column's
/// storage, not a tab: a tab switch is a full restyle, which rebuilds it.
extension VaultController {
    /// The column's store, the same object on every call until the column closes; made here for a
    /// column no door registered (a test that assigns `columns` itself). Never called from a view
    /// body, which reads `registeredOutlineStore(forColumn:)` and writes nothing.
    func outlineStore(forColumn id: EditorColumn.ID) -> OutlineStore {
        if let store = outlineStores[id] { return store }
        let store = OutlineStore()
        outlineStores[id] = store
        return store
    }

    /// The column's store as registered, without making one: what a view body reads.
    func registeredOutlineStore(forColumn id: EditorColumn.ID) -> OutlineStore? {
        outlineStores[id]
    }

    /// Forgets the store of a column that closed (`closeColumn`).
    func dropOutlineStore(forColumn id: EditorColumn.ID) {
        outlineStores[id] = nil
    }

    /// Replaces the registry with one fresh store per current column: called once the columns are
    /// replaced wholesale (`init`, `close()`, `switchVault(to:)`), so no store outlives its column.
    func resetOutlineStores() {
        outlineStores = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, OutlineStore()) })
    }
}
