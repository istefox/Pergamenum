import SwiftUI

/// Which end of a chronological list comes first. Pratiche and Registrazioni both ask the same
/// question of a list of dated rows, so it is named once - and persisted as its raw string
/// through `@AppStorage`, which describes the screen and never the vault.
///
/// The direction inverts the date comparison and nothing else: every caller breaks a tie on a
/// stable ascending key (title, name, id), so two rows carrying the same instant keep one order
/// in both directions instead of swapping under the reader.
enum ChronologicalOrder: String, CaseIterable, Identifiable, Sendable {
    /// Today's behaviour of every list that offers the choice.
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: "Più recenti prima"
        case .oldestFirst: "Più vecchie prima"
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst: "arrow.down"
        case .oldestFirst: "arrow.up"
        }
    }

    /// Whether `left` leads `right` for this order, given two instants that are not equal.
    func precedes(_ left: Date, _ right: Date) -> Bool {
        switch self {
        case .newestFirst: left > right
        case .oldestFirst: left < right
        }
    }
}

/// The menu both panes draw for a `ChronologicalOrder`: the icon, the current value and the
/// chevron pair that says it opens, the shape `TaskListControls` gave its own two menus.
///
/// The identifier is the caller's, because two panes each want theirs and a UI test finds a
/// control by it and never by the words on it (CLAUDE.md).
struct ChronologicalOrderMenu: View {
    @Environment(\.theme) private var theme

    @Binding var order: ChronologicalOrder
    let identifier: String

    var body: some View {
        Menu {
            Picker("Ordine", selection: $order) {
                ForEach(ChronologicalOrder.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: order.systemImage).themedText(.caption, color: .textTertiary)
                Text(order.title).themedText(.caption, color: .textSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .themedText(.caption, color: .textTertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.color(.surfaceSunken))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Ordine cronologico della lista")
        .accessibilityLabel(order.title)
        .accessibilityIdentifier(identifier)
    }
}
