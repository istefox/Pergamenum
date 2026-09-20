import SwiftUI

/// The inspector's «Assegna una categoria…» (PG-166), for a note that carries no
/// `pergamenum-category` yet: the other half of `VaultBrowser.categoryLink`, which shows and
/// unlinks an existing one. A menu over the registry's assignable categories, grouped the
/// way `CategoryPicker` groups them - a menu and not a sheet, since it is a one-shot choice
/// in a narrow pane. It goes through `setCategoryHome`, so choosing a category that already
/// has a home note moves the home here instead of leaving two. Absent while the registry is
/// empty: there is nothing to assign.
struct AssignCategoryMenu: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let notePath: String

    var body: some View {
        let groups = vault.categories.assignableGroups
        if !groups.isEmpty {
            Menu {
                ForEach(groups, id: \.parent.slug) { group in
                    button(group.parent)
                    ForEach(group.children) { child in
                        button(child)
                    }
                }
            } label: {
                Label("Assegna una categoria…", systemImage: "link.badge.plus")
                    .themedText(.caption, color: .accentPrimary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("inspector-assign-category")
        }
    }

    private func button(_ category: Category) -> some View {
        Button {
            Task { await vault.setCategoryHome(category.slug, toNoteAt: notePath) }
        } label: {
            Label(category.name, systemImage: category.symbol ?? "tag")
        }
        .accessibilityIdentifier("inspector-assign-category-\(category.slug)")
    }
}
