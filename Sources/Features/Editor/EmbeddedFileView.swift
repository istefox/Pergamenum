import AppKit
import SwiftUI

/// A file embedded in a note, drawn where the note put it.
///
/// The renderer is `ThumbnailStore`, the same one the Workspace cards use: images come
/// back through Quick Look and PDFs through PDFKit, both cached on disk, so a note full
/// of pictures costs one render each and nothing on the second read.
///
/// Never the network. A remote target never reaches this view - `MarkdownBlockParser`
/// leaves it to the inline path, which draws it as a link (principle 2, fully offline).
struct EmbeddedFileView: View {
    @Environment(\.theme) private var theme

    /// What the note wrote: `foto.png`, or a path relative to the note.
    let target: String
    /// The label of `![alt](…)`, drawn as a caption under the picture.
    let alt: String?
    /// The note doing the embedding, so the file is looked for beside it first.
    let notePath: String
    let root: URL?
    let thumbnails: ThumbnailStore?

    /// The width the reading column gives a picture. Quantised by the store anyway, so
    /// one constant is one cached render for every note in the vault.
    private static let renderWidth: CGFloat = 720

    @State private var image: NSImage?
    @State private var hasLooked = false

    private var relativePath: String? {
        guard let root else { return nil }
        return Attachment.resolve(target, nearNoteAt: notePath, inVaultAt: root)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            content
            if let alt, !alt.isEmpty {
                Text(alt).themedText(.caption, color: .textTertiary)
            }
        }
        .task(id: relativePath ?? target) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                // Scaled down to the column, never blown up past what the file holds:
                // an icon embedded in a note is an icon, not a poster.
                .frame(maxWidth: max(1, image.size.width))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                .accessibilityLabel(alt ?? target)
                .accessibilityIdentifier("note-embed")
        } else if hasLooked {
            missing
        } else {
            // Sized like a picture rather than a line, so the page does not jump when
            // the render arrives.
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(theme.color(.surfaceSunken))
                .frame(height: 120)
                .accessibilityIdentifier("note-embed-loading")
        }
    }

    /// Said out loud rather than left blank: a picture that is not there is something
    /// the user has to know about, and an empty gap says nothing.
    private var missing: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(theme.color(.textTertiary))
            Text("file non trovato nel vault: \(target)")
                .themedText(.caption, color: .textTertiary)
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .accessibilityIdentifier("note-embed-missing")
    }

    private func load() async {
        image = nil
        hasLooked = false
        guard let relativePath, let thumbnails else {
            hasLooked = true
            return
        }
        let task = await thumbnails.thumbnail(for: relativePath, width: Self.renderWidth)
        let rendered = await task.value
        guard !Task.isCancelled else { return }
        image = rendered
        hasLooked = true
    }
}
