import SwiftUI

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D11, plan
// docs/plans/contenitore.md, Task 7 - R-13; mockup 1c.

/// The documents as a grid of thumbnails, each with a badge saying how its text was obtained or
/// which page the OCR has reached.
struct ContenitoreGrid: View {
    @Environment(\.theme) private var theme
    @Environment(ContenitoreController.self) private var contenitore
    let rows: [ContenitoreRow]
    let actions: ContenitoreCommandActions
    let preview: (String) -> Void

    @FocusState private var isGridFocused: Bool

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: theme.spacing(.m))],
                spacing: theme.spacing(.m)
            ) {
                ForEach(rows) { row in
                    tile(row)
                }
            }
            .padding(theme.spacing(.l))
        }
        .focusable()
        .focused($isGridFocused)
        .focusEffectDisabled()
        .onChange(of: contenitore.selection) { _, selected in
            if selected != nil { isGridFocused = true }
        }
        .onDeleteCommand {
            guard let path = contenitore.selection else {
                NSSound.beep()
                return
            }
            actions.run(.trash, on: path)
        }
        .onKeyPress(.space) {
            guard let path = contenitore.selection else { return .ignored }
            preview(path)
            return .handled
        }
        .onKeyPress(.return) {
            guard let path = contenitore.selection else { return .ignored }
            actions.run(.open, on: path)
            return .handled
        }
        .accessibilityIdentifier("contenitore-grid")
    }

    private func tile(_ row: ContenitoreRow) -> some View {
        let isSelected = contenitore.selection == row.schedaPath
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            ZStack(alignment: .topTrailing) {
                ContenitoreThumbnail(row: row, width: 180)
                    .frame(height: 180)
                Text(badge(row))
                    .themedText(.caption, color: .textSecondary)
                    .padding(.horizontal, theme.spacing(.xs))
                    .background(theme.color(.backgroundPrimary), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
                    .padding(theme.spacing(.xs))
            }
            HStack(spacing: theme.spacing(.xs)) {
                ContenitoreColourDot(colour: row.colour)
                Text(row.name).themedText(.caption).lineLimit(2)
            }
            HStack(spacing: theme.spacing(.xs)) {
                Text(row.date?.italianForm ?? "").themedText(.caption, color: .textTertiary)
                if row.isFileMissing {
                    Text("file mancante").themedText(.caption, color: .taskOverdue)
                }
            }
        }
        .padding(theme.spacing(.s))
        .background(
            RoundedRectangle(cornerRadius: theme.radius(.card))
                .fill(theme.color(isSelected ? .accentMuted : .backgroundPrimary))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card))
                .strokeBorder(theme.color(isSelected ? .accentPrimary : .borderSubtle), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { actions.run(.open, on: row.schedaPath) }
        .onTapGesture { contenitore.selection = row.schedaPath }
        .contextMenu {
            ContenitoreMenuItems(commands: ContenitoreCommand.rowMenu, schedaPath: row.schedaPath, actions: actions)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("contenitore-tile")
    }

    private func badge(_ row: ContenitoreRow) -> String {
        if let sha = row.sha256, let progress = contenitore.queue?.progress[sha], progress.total > 0 {
            return "OCR · \(progress.done) di \(progress.total)"
        }
        switch row.extractionLabel {
        case "testo": return "Testo"
        case "testo da OCR": return "OCR"
        default: return row.extractionLabel
        }
    }
}
