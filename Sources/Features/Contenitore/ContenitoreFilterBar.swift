import SwiftUI

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D11, plan
// docs/plans/contenitore.md, Task 7 - R-15, R-17; mockup 1c.

/// The filters above the documents: a click on a colour turns it on (accent ring), a chosen tag
/// becomes a removable chip, «Azzera filtri» shows only while one is on.
struct ContenitoreFilterBar: View {
    @Environment(\.theme) private var theme
    @Environment(ContenitoreController.self) private var contenitore
    /// The rows in view, whose tags the «＋ tag…» menu offers.
    let rows: [ContenitoreRow]

    var body: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text("Colore").themedText(.caption, color: .textSecondary)
            ForEach(ContenitoreColour.allCases, id: \.self) { colour in
                colourToggle(colour)
            }
            Text("Tag")
                .themedText(.caption, color: .textSecondary)
                .padding(.leading, theme.spacing(.s))
            ForEach(contenitore.filter.tags.sorted(), id: \.self) { tag in
                Button {
                    contenitore.filter.tags.remove(tag)
                } label: {
                    Label(tag.description, systemImage: "xmark")
                        .labelStyle(.titleAndIcon)
                        .themedText(.caption, color: .textPrimary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, theme.spacing(.xs))
                .background(theme.color(.accentMuted), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
            }
            Menu("＋ tag…") {
                ForEach(availableTags, id: \.self) { tag in
                    Button(tag.description) { contenitore.filter.tags.insert(tag) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(availableTags.isEmpty)
            .accessibilityIdentifier("contenitore-filter-add-tag")
            Spacer()
            if contenitore.filter.isActive {
                Button("Azzera filtri") {
                    contenitore.filter.colours = []
                    contenitore.filter.tags = []
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("contenitore-filter-clear")
            }
            Menu("Ordina: \(contenitore.filter.sort.title)") {
                ForEach(ContenitoreSort.allCases, id: \.self) { sort in
                    Button(sort.title) { contenitore.filter.sort = sort }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, theme.spacing(.l))
        .padding(.vertical, theme.spacing(.s))
    }

    private func colourToggle(_ colour: ContenitoreColour) -> some View {
        let isOn = contenitore.filter.colours.contains(colour)
        return Button {
            if isOn { contenitore.filter.colours.remove(colour) } else { contenitore.filter.colours.insert(colour) }
        } label: {
            Circle()
                .fill(theme.color(colour.token))
                .overlay(Circle().strokeBorder(theme.color(.borderStrong), lineWidth: 1))
                .frame(width: 12, height: 12)
                .padding(2)
                .overlay(Circle().strokeBorder(theme.color(.accentPrimary), lineWidth: isOn ? 2 : 0))
        }
        .buttonStyle(.plain)
        .help(colour.displayName)
        .accessibilityLabel(colour.displayName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("contenitore-filter-colour-\(colour.rawValue)")
    }

    /// Every tag on a row in view that is not already a filter, `type-note` aside (every scheda
    /// carries it, so it narrows nothing).
    private var availableTags: [Tag] {
        let typeNote = Tag(namespace: .type, value: "note")
        return Set(rows.flatMap(\.tags))
            .subtracting(contenitore.filter.tags)
            .subtracting([typeNote])
            .sorted()
    }
}
