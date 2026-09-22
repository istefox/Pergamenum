import SwiftUI

/// The Workspace's chrome: the bar above the board, the tool column beside it, the
/// zoom controls and the pen controls. The tray is a panel rather than furniture and
/// lives in `BoardTray.swift`.
///
/// Lifted out of `WorkspaceView` so that file holds the board itself. Each view takes
/// exactly what it needs, which is also what makes it readable on its own.

/// Breadcrumb and save state (SPEC §6.1).
///
/// Undo, redo, Anteprima and the tray toggle used to live here too and are now in the
/// window toolbar: they are window-level commands, and the top bar is about where you
/// are on the board, not what you can do to it.
struct BoardTopBar: View {
    let workspace: WorkspaceController

    var body: some View {
        // The last segment is where you already are, so it is not a link (ADR-0024 §D8.2):
        // as a `Button` it re-ran the open command on the open board, which resets its zoom
        // and pan for a click that was meant to go nowhere. Emphasis carries "you are here" -
        // the tree says it with the system's row fill and this pane's `.accentPrimary` no
        // longer means "selected" anywhere (§D8.3). `BreadcrumbBar` already draws the last
        // segment this way for every caller.
        //
        // Every segment now also carries `.accessibilityIdentifier("breadcrumb-crumb-\(index)")`
        // (PG-081) - previously only the Note side's bar had one.
        BreadcrumbBar(
            segments: workspace.breadcrumb,
            isUnsaved: workspace.hasUnsavedChanges,
            identifierPrefix: "breadcrumb-crumb",
            onSelectAncestor: { open(ancestor: $0) }
        ) {
            saveIndicator
        }
    }

    /// The "Salvato"/"Salvataggio…"/"Conflitto" indicator of §6.1 (ADR-0054 §D5). Non-modal:
    /// a conflict is shown beside the two verbs that resolve it, never a sheet or an alert -
    /// the board stays fully usable while it is up.
    @ViewBuilder
    private var saveIndicator: some View {
        switch workspace.saveState {
        case .saved:
            Label("Salvato", systemImage: "checkmark.circle")
                .themedText(.caption, color: .textSecondary)
                .accessibilityIdentifier("board-save-indicator")
        case .pending:
            Label("Salvataggio…", systemImage: "arrow.triangle.2.circlepath")
                .themedText(.caption, color: .textSecondary)
                .accessibilityIdentifier("board-save-indicator")
        case .conflicted:
            HStack(spacing: 8) {
                Label("Conflitto", systemImage: "exclamationmark.triangle")
                    .themedText(.caption, color: .taskOverdue)
                    .accessibilityIdentifier("board-save-indicator")
                Button("Mantieni le mie modifiche") { workspace.keepLocalBoard() }
                    .buttonStyle(.plain)
                    .themedText(.caption, color: .accentPrimary)
                    .accessibilityIdentifier("board-conflict-keep-local")
                Button("Ricarica dal disco") { workspace.reloadBoardFromDisk() }
                    .buttonStyle(.plain)
                    .themedText(.caption, color: .accentPrimary)
                    .accessibilityIdentifier("board-conflict-reload")
            }
        }
    }

    /// An ancestor segment, under the one rule §D5 gives every folder→board navigation:
    /// the board that folder unambiguously means is opened, and `.ambiguous`/`.notFound`
    /// selects the folder instead - never a board derived from its name (§D1). The root
    /// segment is `select(nil)`, the only spelling of "nothing selected": `.folder("")` is
    /// never produced (§D3).
    ///
    /// The rule is `WorkspaceController.enter(folder:)`'s, shared with the folder card and the
    /// editor hand-off. The root guard stays here because it answers a different question:
    /// `enter(folder: "")` would resolve the vault root's own board, and a root holding exactly
    /// one would open it for a click that means "nothing selected".
    private func open(ancestor folder: String) {
        guard !folder.isEmpty else {
            workspace.select(nil)
            return
        }
        workspace.enter(folder: folder)
    }
}

/// The eleven tools of SPEC §6.4, in a column down the left.
struct BoardToolbar: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController

    var body: some View {
        VStack(spacing: theme.spacing(.xs)) {
            ForEach(WorkspaceController.Tool.allCases) { tool in
                Button {
                    workspace.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(theme.color(
                            tool == workspace.tool ? .onAccent : (tool.isAvailable ? .textSecondary : .textTertiary)
                        ))
                        .background(tool == workspace.tool ? theme.color(.accentPrimary) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!tool.isAvailable)
                .opacity(tool.isAvailable ? 1 : 0.4)
                .overlay(alignment: .topTrailing) {
                    // A locked tool has to look locked, or the board keeps creating
                    // cards and the user cannot see why.
                    if tool == workspace.tool, workspace.isToolLocked {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(theme.color(.onAccent))
                            .padding(2)
                    }
                }
                // Double click keeps the tool active instead of returning to
                // Seleziona after one use (SPEC §6.4).
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    workspace.tool = tool
                    workspace.isToolLocked.toggle()
                })
                .help(tool.shortcut.map { "\(tool.title) (\($0.uppercased()))" } ?? tool.title)
                // Suspended while a card is being written into: a bare-key shortcut with
                // no modifier reaches `performKeyEquivalent:` ahead of the first
                // responder, so typing the word "nota" into a `TextEditor` would switch
                // tools on its own "n".
                .keyboardShortcut(
                    workspace.editingTextNodeID == nil
                        ? (tool.shortcut.map { KeyEquivalent(Character($0)) } ?? "\0")
                        : "\0",
                    modifiers: []
                )
            }
            Spacer()
        }
        .padding(theme.spacing(.xs))
        .frame(width: 44)
    }
}

/// Zoom out, the current percentage, zoom in, zoom to fit (SPEC §6.1).
struct BoardZoomControls: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController
    let viewportSize: CGSize

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Button { workspace.zoom(by: 1 / 1.25, in: viewportSize) } label: { Image(systemName: "minus") }
                .accessibilityIdentifier("board-zoom-out")
            Button { workspace.resetZoom() } label: {
                Text("\(Int(workspace.zoom * 100))%").themedText(.caption)
            }
            .accessibilityIdentifier("board-zoom-level")
            .accessibilityValue("\(Int(workspace.zoom * 100))")
            Button { workspace.zoom(by: 1.25, in: viewportSize) } label: { Image(systemName: "plus") }
            Divider().frame(height: 12)
            Button { workspace.zoomToFit(in: viewportSize) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.color(.textSecondary))
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.surfaceRaised))
        .clipShape(Capsule())
        .themedShadow(.card)
    }
}

/// Colour, width, eraser and "Fatto" for the Disegno tool (SPEC §6.4, tool 10).
struct BoardPenControls: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController
    @Binding var penColor: ColorToken
    @Binding var penWidth: CGFloat
    @Binding var isErasing: Bool

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            ForEach([ColorToken.textPrimary, .accentPrimary, .taskOverdue, .stickyYellow], id: \.self) { token in
                Circle()
                    .fill(theme.color(token))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle().strokeBorder(
                            token == penColor ? theme.color(.canvasSelection) : theme.color(.borderSubtle),
                            lineWidth: token == penColor ? 2 : 1
                        )
                    )
                    .onTapGesture { penColor = token; isErasing = false }
            }
            Divider().frame(height: 14)
            ForEach([CGFloat(2), 6, 14], id: \.self) { width in
                Circle()
                    .fill(theme.color(width == penWidth && !isErasing ? .accentPrimary : .textTertiary))
                    .frame(width: width + 4, height: width + 4)
                    .onTapGesture { penWidth = width; isErasing = false }
            }
            Divider().frame(height: 14)
            Image(systemName: "eraser")
                .foregroundStyle(theme.color(isErasing ? .accentPrimary : .textSecondary))
                .onTapGesture { isErasing.toggle() }
            Divider().frame(height: 14)
            Button("Fatto") {
                _ = workspace.commitDrawing()
                workspace.tool = .select
            }
            .buttonStyle(.plain)
            .themedText(.caption, color: .accentPrimary)
            .disabled(workspace.activeDrawing.strokes.isEmpty)
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.surfaceRaised))
        .clipShape(Capsule())
        .themedShadow(.card)
    }
}
