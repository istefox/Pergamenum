import SwiftUI

/// The inspector's DOVE COMPARE (ADR-0084 §D6): the boards whose nodes point at the note and the
/// pratiche that link it, read-only.
///
/// **Asked for, never automatic** (SPEC Decision, 2026-10-07), in `UnlinkedMentionsSection`'s
/// shape: the pratiche half reads every message file's frontmatter, so the resting state says what
/// it will do and waits for the button. Each row opens its place: a board through
/// `routeState.pendingCanvas`, the door a board wikilink uses; a pratica, or a message under it,
/// through `PraticheController.select(_:in:)` and the Pratiche pane.
struct WhereNoteAppearsSection: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation
    @Environment(PraticheController.self) private var pratiche

    let notePath: String

    /// Made when the person asks, and dropped when the note changes: the answer is about this
    /// note, and kept across a change it would describe the one you came from.
    @State private var scan: WhereNoteAppearsScan?

    var body: some View {
        let header = VaultBrowser.InspectorSection.whereAppears(found: found.map(Self.count(of:)))
        TraySection(
            title: header.title,
            badge: found.map { Self.count(of: $0) }.flatMap { $0 > 0 ? "\($0)" : nil },
            accessibilityLabel: header.accessibilityLabel,
            identifier: header.identifier,
            isEmpty: false,
            emptyText: header.emptyText
        ) {
            content(emptyText: header.emptyText)
        }
        .onChange(of: notePath) { _, _ in scan = nil }
    }

    /// One place per board and per pratica; a message is counted under its pratica.
    static func count(of appearances: NoteAppearances) -> Int {
        appearances.boards.count + appearances.pratiche.count
    }

    private var found: NoteAppearances? {
        if case .found(let appearances) = scan?.state { return appearances }
        return nil
    }

    @ViewBuilder
    private func content(emptyText: String) -> some View {
        switch scan?.state ?? .resting {
        case .resting:
            explanation("Cerca questa nota nelle board e nelle pratiche: legge ogni board e ogni messaggio.")
            scanButton("Cerca dove compare", systemImage: "magnifyingglass", again: false)
        case .scanning:
            HStack(spacing: theme.spacing(.xs)) {
                ProgressView().controlSize(.small)
                Text("Lettura di board e pratiche…").themedText(.caption, color: .textSecondary)
            }
        case .found(let appearances):
            if Self.count(of: appearances) == 0 {
                explanation(emptyText)
            } else {
                results(appearances)
            }
            if appearances.unreadableBoards > 0 {
                explanation(
                    appearances.unreadableBoards == 1
                        ? "1 board non leggibile, saltata."
                        : "\(appearances.unreadableBoards) board non leggibili, saltate."
                )
            }
            scanButton("Cerca di nuovo", systemImage: "arrow.clockwise", again: true)
        }
    }

    @ViewBuilder
    private func results(_ appearances: NoteAppearances) -> some View {
        if !appearances.boards.isEmpty {
            group("BOARD")
            ForEach(appearances.boards, id: \.path) { board in
                entry(
                    board.name, glyph: "square.grid.2x2", help: board.path,
                    identifier: "where-appears-board-\(board.path)"
                ) {
                    vault.routeState.pendingCanvas = (board.path, nil)
                }
            }
        }
        if !appearances.pratiche.isEmpty {
            group("PRATICHE")
            ForEach(appearances.pratiche, id: \.folder) { pratica in
                // A pratica that does not link the note itself is named only as the place of the
                // message under it that does, so it is drawn in the secondary colour.
                entry(
                    pratica.title, glyph: "folder.badge.person.crop",
                    color: pratica.linksNote ? .accentPrimary : .textSecondary,
                    help: pratica.folder, identifier: "where-appears-pratica-\(pratica.folder)"
                ) { open(pratica: pratica.folder) }
                ForEach(pratica.messages, id: \.self) { message in
                    entry(
                        messageName(message), glyph: "envelope", indent: true, help: message,
                        identifier: "where-appears-message-\(message)"
                    ) { open(pratica: pratica.folder) }
                }
            }
        }
    }

    /// A message row names its file, the index's title for it when it has one.
    private func messageName(_ path: String) -> String {
        vault.index.note(at: path)?.title ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private func open(pratica folder: String) {
        pratiche.select(folder, in: vault)
        navigation.pane = .pratiche
    }

    private func group(_ title: String) -> some View {
        Text(title).themedText(.caption, color: .textTertiary).padding(.top, 2)
    }

    private func entry(
        _ title: String, glyph: String, indent: Bool = false, color: ColorToken = .accentPrimary,
        help: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: glyph).themedText(.caption, color: .textTertiary).frame(width: 16)
                Text(title).themedText(.body, color: color).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, indent ? theme.spacing(.m) : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityIdentifier(identifier)
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .themedText(.caption, color: .textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func scanButton(_ title: String, systemImage: String, again: Bool) -> some View {
        Button { run(again: again) } label: {
            Label(title, systemImage: systemImage)
                .themedText(.caption, color: .accentPrimary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityIdentifier("where-appears-scan")
    }

    private func run(again: Bool) {
        let model = scan ?? WhereNoteAppearsScan(vault: vault, notePath: notePath)
        scan = model
        Task { @MainActor in await model.scan(again: again) }
    }
}
