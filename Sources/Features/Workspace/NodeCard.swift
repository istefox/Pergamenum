import SwiftUI

/// One card on the board, drawn by node kind.
struct NodeCard: View {
    @Environment(\.theme) private var theme
    let node: CanvasNode
    let subfolder: String?
    let workspace: WorkspaceController

    var body: some View {
        switch node.kind {
        case .text(let text):
            stickyOrText(text)
        case .file(let path, _):
            fileCard(path)
        case .link(let url):
            linkCard(url)
        case .group(let label):
            groupCard(label)
        case .unknown(let type):
            // Drawn as a placeholder rather than skipped, so a node from another tool
            // is visible and movable instead of silently invisible.
            placeholder("nodo «\(type)»")
        }
    }

    @ViewBuilder
    private func stickyOrText(_ text: String) -> some View {
        if let color = node.color {
            Text(text.isEmpty ? "Nota" : text)
                .themedText(.body)
                .padding(theme.spacing(.s))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(stickyColor(color))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.sticky), style: .continuous))
                .themedShadow(.card)
        } else {
            Text(text.isEmpty ? "Testo" : text)
                .themedText(.heading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Maps the six JSON Canvas presets onto theme tokens so a canvas made in
    /// Obsidian keeps its colour coding here, in this app's palette.
    private func stickyColor(_ color: CanvasColor) -> Color {
        switch color {
        case .hex(let value):
            let rgba = RGBA(hex: value) ?? RGBA(hex: "#E8E5DF")!
            return Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
        case .preset(let index):
            return switch index {
            case 1: theme.color(.stickyPink)
            case 2: theme.color(.stickyPink)
            case 3: theme.color(.stickyYellow)
            case 4: theme.color(.stickyGreen)
            case 5: theme.color(.stickyBlue)
            default: theme.color(.stickyGrey)
            }
        }
    }

    @ViewBuilder
    private func fileCard(_ path: String) -> some View {
        if subfolder != nil {
            folderCard(path)
        } else if (path as NSString).pathExtension.lowercased() == "eml" {
            emailCard(path)
        } else {
            previewCard(path)
        }
    }

    private func folderCard(_ path: String) -> some View {
        cardChrome {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                HStack(spacing: theme.spacing(.xs)) {
                    Image(systemName: "folder.fill").foregroundStyle(theme.color(.accentPrimary))
                    Text((path as NSString).lastPathComponent).themedText(.body).lineLimit(2)
                }
                Text("cartella").themedText(.caption, color: .textTertiary)
                Spacer(minLength: 0)
            }
        }
    }

    /// A PDF, an image or any other file, shown with its Quick Look preview.
    ///
    /// SPEC §6.5 makes the PDF card a primary requirement: the first page rendered by
    /// PDFKit, cached, and regenerated at the new resolution when the card is resized.
    private func previewCard(_ path: String) -> some View {
        cardChrome {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                ThumbnailImage(
                    workspace: workspace,
                    relativePath: path,
                    width: node.width,
                    fallbackSymbol: symbol(for: path)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                HStack {
                    Text((path as NSString).lastPathComponent)
                        .themedText(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text((path as NSString).pathExtension.uppercased())
                        .themedText(.caption, color: .textTertiary)
                }
            }
        }
    }

    /// From / Subject / Date read from the header block, with no body rendering
    /// (SPEC §6.5 and §14).
    private func emailCard(_ path: String) -> some View {
        let headers = workspace.emailHeaders[path]
        return cardChrome {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: theme.spacing(.xs)) {
                    Image(systemName: "envelope").foregroundStyle(theme.color(.accentPrimary))
                    Text(headers?.from?.displayText ?? (path as NSString).lastPathComponent)
                        .themedText(.body)
                        .lineLimit(1)
                }
                Text(headers?.subject ?? "—")
                    .themedText(.caption, color: .textSecondary)
                    .lineLimit(2)
                if let date = headers?.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .themedText(.caption, color: .textTertiary)
                }
                Spacer(minLength: 0)
            }
            .task(id: path) { workspace.loadEmailHeaders(for: path) }
        }
    }

    private func cardChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(theme.spacing(.s))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.color(.surfaceCard))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                    .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
            )
            .themedShadow(.card)
    }

    private func symbol(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "md": "doc.text"
        case "pdf": "doc.richtext"
        case "eml": "envelope"
        case "png", "jpg", "jpeg", "heic", "gif", "svg": "photo"
        case "canvas": "square.on.square"
        default: "doc"
        }
    }

    private func linkCard(_ url: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: symbol(forScheme: url))
                    .foregroundStyle(theme.color(.accentPrimary))
                Text(url).themedText(.body).lineLimit(1)
            }
            Text(URL(string: url)?.scheme.map { "\($0)://" } ?? "link")
                .themedText(.caption, color: .textTertiary)
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
        .themedShadow(.card)
    }

    /// Schemes SPEC §9 singles out for their own icon.
    private func symbol(forScheme url: String) -> String {
        switch URL(string: url)?.scheme {
        case "obsidian": "circle.hexagongrid"
        case "x-devonthink-item": "square.stack.3d.up"
        case "message": "envelope"
        case "pergamenum": "scroll"
        default: "link"
        }
    }

    private func groupCard(_ label: String?) -> some View {
        RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
            .strokeBorder(theme.color(.borderStrong), lineWidth: 1)
            .overlay(alignment: .topLeading) {
                if let label {
                    Text(label)
                        .themedText(.caption, color: .textSecondary)
                        .padding(theme.spacing(.xs))
                }
            }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .themedText(.caption, color: .textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.color(.backgroundTertiary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }
}

/// Names a new folder, link or note before it is created.
struct ThumbnailImage: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController
    let relativePath: String
    let width: CGFloat
    let fallbackSymbol: String

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.color(.backgroundTertiary))
                    .overlay(
                        Image(systemName: fallbackSymbol)
                            .foregroundStyle(theme.color(.textTertiary))
                    )
            }
        }
        // Keyed on the size bucket rather than the raw width, so dragging a resize
        // handle does not start a render per frame (SPEC §6.5 asks for a regenerated
        // thumbnail at the end of a resize, not during it).
        .task(id: "\(relativePath)@\(ThumbnailStore.bucket(for: width))") {
            guard let store = workspace.thumbnails else { return }
            let task = await store.thumbnail(for: relativePath, width: width)
            let rendered = await task.value
            if !Task.isCancelled { image = rendered }
        }
    }
}


/// Confirms the names of files being imported, so the assisted rename of SPEC §4.2
/// is a proposal rather than something done behind the user's back.
