import SwiftUI

/// The Workspace's chrome: the bar above the board, the tool column beside it, the
/// zoom controls, the pen controls and the tray.
///
/// Lifted out of `WorkspaceView` so that file holds the board itself. Each view takes
/// exactly what it needs, which is also what makes it readable on its own.

/// Breadcrumb and save state (SPEC §6.1).
///
/// Undo, redo, Anteprima and the tray toggle used to live here too and are now in the
/// window toolbar: they are window-level commands, and the top bar is about where you
/// are on the board, not what you can do to it.
struct BoardTopBar: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Circle()
                .fill(theme.color(workspace.hasUnsavedChanges ? .taskScheduled : .accentPrimary))
                .frame(width: 8, height: 8)

            ForEach(Array(workspace.breadcrumb.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Text("›").themedText(.body, color: .textTertiary)
                }
                Button(crumb.title) { workspace.open(folder: crumb.folder) }
                    .buttonStyle(.plain)
                    .themedText(
                        .body,
                        color: index == workspace.breadcrumb.count - 1 ? .textPrimary : .textSecondary
                    )
            }

            Spacer()

            Label(
                workspace.hasUnsavedChanges ? "Salvataggio…" : "Salvato",
                systemImage: workspace.hasUnsavedChanges ? "arrow.triangle.2.circlepath" : "checkmark.circle"
            )
            .themedText(.caption, color: .textSecondary)
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
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
                .keyboardShortcut(tool.shortcut.map { KeyEquivalent(Character($0)) } ?? "\0", modifiers: [])
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
            Button { workspace.zoom(by: 1 / 1.25) } label: { Image(systemName: "minus") }
            Button { workspace.resetZoom() } label: {
                Text("\(Int(workspace.zoom * 100))%").themedText(.caption)
            }
            Button { workspace.zoom(by: 1.25) } label: { Image(systemName: "plus") }
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

/// The right-hand column: items in the folder not yet on the board, and the tasks
/// that link to this board (SPEC §6.1, §7.2).
struct BoardTray: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    let workspace: WorkspaceController

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            if !workspace.contents.unplaced.isEmpty {
                newItems
            }
            // SPEC §7.2: the board shows the tasks that link to it, exactly as a note
            // does. The link target is the `.canvas` file name, which is how a
            // wikilink names a board.
            LinkedTasksPanel(
                title: boardFileName,
                emptyText: "nessun task linka questa board"
            )
            Spacer()
        }
        .padding(theme.spacing(.s))
        .frame(width: 200)
        .background(theme.color(.backgroundSecondary))
    }

    /// The board's own file name, as a wikilink would write it.

    private var boardFileName: String {
        guard let root = vault.root else { return "" }
        return (CanvasStore(root: root).boardPath(forFolder: workspace.folder) as NSString)
            .lastPathComponent
    }

    private var newItems: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("NUOVI ELEMENTI").themedText(.caption, color: .textTertiary)
            Text("Trascina o clicca per posare sulla board.")
                .themedText(.caption, color: .textTertiary)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    ForEach(workspace.contents.unplaced, id: \.self) { path in
                        Button {
                            _ = workspace.placeFile(path, at: CGPoint(x: 60, y: 60))
                        } label: {
                            HStack(spacing: theme.spacing(.xs)) {
                                Image(systemName: workspace.contents.subfolders.contains(path)
                                      ? "folder" : "doc")
                                Text((path as NSString).lastPathComponent)
                                    .themedText(.caption)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
