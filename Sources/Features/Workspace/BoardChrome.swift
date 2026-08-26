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
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController

    var body: some View {
        // Read once per redraw: `breadcrumb` is computed - it splits the folder path and
        // allocates a fresh array on every access - so reading it inside the `ForEach`
        // body cost one more array construction per segment on top of the enumeration.
        let crumbs = workspace.breadcrumb
        return HStack(spacing: theme.spacing(.xs)) {
            Circle()
                .fill(theme.color(workspace.hasUnsavedChanges ? .taskScheduled : .accentPrimary))
                .frame(width: 8, height: 8)

            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Text("›").themedText(.body, color: .textTertiary)
                }
                if index == crumbs.count - 1 {
                    // The last segment is where you already are, so it is not a link
                    // (ADR-0024 §D8.2): as a `Button` it re-ran `open(folder:)` on the
                    // open folder, which resets the board's zoom and pan for a click
                    // that was meant to go nowhere. Emphasis carries "you are here" -
                    // the tree says it with the system's row fill and this pane's
                    // `.accentPrimary` no longer means "selected" anywhere (§D8.3).
                    Text(crumb.title).themedText(.body, color: .textPrimary)
                } else {
                    Button(crumb.title) { workspace.open(folder: crumb.folder) }
                        .buttonStyle(.plain)
                        .themedText(.body, color: .textSecondary)
                }
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
