import SwiftUI

/// One card on the board, drawn by node kind.
struct NodeCard: View {
    @Environment(\.theme) private var theme
    let node: CanvasNode
    let subfolder: String?
    let workspace: WorkspaceController
    /// Shift, for the crop editor's aspect lock (ADR-0020 D5) - the same modifiers the
    /// board already tracks for the resize grips, threaded one level further in.
    var modifiers: EventModifiers = []

    var body: some View {
        switch node.kind {
        case .text:
            StickyTextCard(node: node, workspace: workspace)
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
                Group {
                    if workspace.croppingNodeID == node.id {
                        BoardCropEditor(workspace: workspace, node: node, path: path, modifiers: modifiers)
                    } else {
                        ThumbnailImage(
                            workspace: workspace,
                            relativePath: path,
                            width: node.width,
                            fallbackSymbol: symbol(for: path),
                            crop: CanvasCrop.read(from: node)
                        )
                    }
                }
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
    /// ADR-0020: the region of the image to draw, or `nil` for the whole thing. The
    /// uncropped path below is untouched by this parameter's addition - same requested
    /// width, same `fit`, same cache key - so a card with no crop cannot regress.
    var crop: CanvasCrop?

    @State private var image: NSImage?

    /// A crop of fractional width `w` magnifies the visible region by `1/w` (D7), so the
    /// render is asked for at the resolution the *visible* region needs rather than the
    /// whole picture's.
    private var requestWidth: CGFloat {
        guard let crop, crop.width > 0 else { return width }
        return width / crop.width
    }

    var body: some View {
        Group {
            if let image {
                if let crop {
                    CroppedThumbnail(image: image, crop: crop)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
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
        .task(id: "\(relativePath)@\(ThumbnailStore.bucket(for: requestWidth))") {
            guard let store = workspace.thumbnails else { return }
            let task = await store.thumbnail(for: relativePath, width: requestWidth)
            let rendered = await task.value
            if !Task.isCancelled { image = rendered }
        }
    }
}

/// Draws only the region of `image` named by `crop`, scaled to fill the view under the
/// same `fit` rule the whole image uses (ADR-0020 D4): the crop rectangle's own aspect
/// ratio decides how the view fits its available space, then the whole image is scaled
/// and offset so that exactly the cropped region lands inside it.
private struct CroppedThumbnail: View {
    let image: NSImage
    let crop: CanvasCrop

    private var croppedAspect: CGFloat {
        let width = crop.width * image.size.width
        let height = crop.height * image.size.height
        return height > 0 ? width / height : 1
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / max(crop.width * image.size.width, 0.001)
            Image(nsImage: image)
                .resizable()
                .frame(width: image.size.width * scale, height: image.size.height * scale)
                .offset(x: -crop.x * image.size.width * scale, y: -crop.y * image.size.height * scale)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
        }
        .aspectRatio(croppedAspect, contentMode: .fit)
    }
}


/// Confirms the names of files being imported, so the assisted rename of SPEC §4.2
/// is a proposal rather than something done behind the user's back.
