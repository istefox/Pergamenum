import Foundation
import Testing
@testable import Pergamenum

// (coverage) ADR-0096 §D6, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 6 (PG-406).
//
// The registry of the columns' outline stores is not named by an R-id test: `UpdatePathCounterTests` reads
// the store of column 0 through it, but nothing pins what its doc comment states (one store per column, made
// on first use, the same object on every call, dropped when the column closes). A registry that handed out a
// new store per call would turn every `splice` counter into a rebuild; one that kept a closed column's store
// would hold a whole outline per closed column for the life of the vault.

@MainActor
@Suite struct OutlineStoreRegistryTests {
    private func controller(_ vault: borrowing TemporaryVault) async throws -> VaultController {
        try vault.write("# Uno\n\ncorpo\n", to: "A.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        controller.watcher?.stop()
        controller.watcher = nil
        controller.openNote(at: "A.md")
        return controller
    }

    @Test func aColumnGetsTheSameStoreOnEveryCall() async throws {
        let vault = try TemporaryVault()
        let controller = try await controller(vault)
        defer { controller.close() }
        let id = controller.columns[0].id

        let first = controller.outlineStore(forColumn: id)
        #expect(controller.outlineStore(forColumn: id) === first)
        #expect(controller.outlineStores[id] === first)
    }

    @Test func twoColumnsGetTwoStores() async throws {
        let vault = try TemporaryVault()
        let controller = try await controller(vault)
        defer { controller.close() }
        controller.splitEditor()
        #expect(controller.columns.count == 2)
        // Read before anything that makes a store on demand: the split itself registered the new
        // column's store, the one the footer's body reads and never makes.
        #expect(controller.outlineStores.count == 2, "the split did not register the new column's store")
        #expect(controller.columns.allSatisfy { controller.registeredOutlineStore(forColumn: $0.id) != nil })

        let left = controller.outlineStore(forColumn: controller.columns[0].id)
        let right = controller.outlineStore(forColumn: controller.columns[1].id)
        #expect(left !== right, "the split editor's columns share one store, so one column's edit would shift the other's")
    }

    // The restore of a split desk makes its second column through `addColumn()` too, so the store is
    // registered before any view asks for it.
    @Test func restoringASplitDeskRegistersBothColumnsStores() async throws {
        let vault = try TemporaryVault()
        try vault.write("# Uno\n\ncorpo\n", to: "A.md")
        let tabs = OpenTabsStore.volatile()
        let first = VaultController(recents: .volatile(), openTabs: tabs)
        await first.open(vault.root)
        first.watcher?.stop()
        first.watcher = nil
        first.openNote(at: "A.md")
        first.splitEditor()
        defer { first.close() }

        let controller = VaultController(recents: .volatile(), openTabs: tabs)
        await controller.open(vault.root)
        controller.watcher?.stop()
        controller.watcher = nil
        defer { controller.close() }

        #expect(controller.columns.count == 2, "the split desk did not come back split")
        #expect(controller.outlineStores.count == 2, "the restore did not register the second column's store")
        #expect(controller.columns.allSatisfy { controller.registeredOutlineStore(forColumn: $0.id) != nil })
    }

    @Test func closingAColumnDropsItsStoreAndLeavesTheOthers() async throws {
        let vault = try TemporaryVault()
        let controller = try await controller(vault)
        defer { controller.close() }
        controller.splitEditor()
        let keptID = controller.columns[0].id
        let closedID = controller.columns[1].id
        let kept = controller.outlineStore(forColumn: keptID)
        _ = controller.outlineStore(forColumn: closedID)
        #expect(controller.outlineStores.count == 2)

        // The split column holds a clean copy of the note, so the close asks nothing.
        let closed = await controller.closeColumn(1) { _ in .cancel }

        #expect(closed)
        #expect(controller.outlineStores[closedID] == nil, "a closed column's store stayed registered")
        #expect(controller.outlineStore(forColumn: keptID) === kept)
        #expect(controller.outlineStores.count == 1)
    }

    // `close()` replaces the columns with one fresh column: the registry holds that column's store
    // and no store of a column that is gone.
    @Test func closingTheVaultLeavesOnlyTheFreshColumnsStore() async throws {
        let vault = try TemporaryVault()
        let controller = try await controller(vault)
        controller.splitEditor()
        let oldIDs = controller.columns.map(\.id)
        for id in oldIDs { _ = controller.outlineStore(forColumn: id) }

        controller.close()

        #expect(oldIDs.allSatisfy { controller.outlineStores[$0] == nil }, "a closed vault's column kept its store")
        #expect(Set(controller.outlineStores.keys) == Set(controller.columns.map(\.id)))
        #expect(controller.registeredOutlineStore(forColumn: controller.columns[0].id) != nil)
    }

    // `switchVault(to:)` does the same once the review lets it through (a clean tab asks nothing).
    @Test func switchingVaultLeavesOnlyTheFreshColumnsStore() async throws {
        let vault = try TemporaryVault()
        let other = try TemporaryVault()
        try other.write("# Due\n", to: "B.md")
        let controller = try await controller(vault)
        defer { controller.close() }
        controller.splitEditor()
        let oldIDs = controller.columns.map(\.id)
        for id in oldIDs { _ = controller.outlineStore(forColumn: id) }

        let switched = await controller.switchVault(to: other.root) { _ in .cancel }

        #expect(switched)
        #expect(oldIDs.allSatisfy { controller.outlineStores[$0] == nil }, "the left folder's column kept its store")
        #expect(Set(controller.outlineStores.keys) == Set(controller.columns.map(\.id)))
    }
}
