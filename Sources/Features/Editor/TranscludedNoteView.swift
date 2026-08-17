import SwiftUI

/// How a view reaches another note's text.
///
/// A closure rather than a protocol, and `@MainActor` rather than `Sendable`, because the
/// only implementation reads `VaultSession`, which is main-actor isolated. A caller with no
/// vault behind it - the Diario's preview, a mockup - passes nil and the transclusion draws
/// as unresolved, which is the honest thing for a surface that cannot look anything up.
struct TransclusionSource {
    struct Resolved: Equatable {
        var title: String
        var relativePath: String
        var text: String
    }

    /// Reference to note, or nil when the vault has no note by that name.
    var resolve: @MainActor (String) -> Resolved?
    /// Bumped when the vault is rescanned, so a target edited outside the app is redrawn
    /// without anything being re-read on every keystroke (ADR-0010 §D8).
    var generation: Int = 0
}

/// Another note, drawn inside the one that names it (ADR-0010).
///
/// Nothing is copied: the host note still says `![[nota]]` on disk and this reads the
/// target fresh. What is drawn is set apart by a rule and a header naming its source,
/// because text that reads like the host note's own but is not is the one failure that
/// makes a person edit the wrong file.
struct TranscludedNoteView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    let reference: String
    var section: String?
    var source: TransclusionSource?
    /// Passed down so a picture inside a transcluded note is looked for beside *that*
    /// note rather than beside the host.
    var vaultRoot: URL?
    var thumbnails: ThumbnailStore?
    /// False inside a rendition. Depth one (§D6): a nested `![[…]]` is drawn as a link, so
    /// a note transcluding itself is one row rather than a loop. No visited set, no depth
    /// counter - the cycle is not representable.
    var expands = true

    @State private var lookup: Lookup = .looking

    /// Not named `State`: a nested type by that name shadows SwiftUI's property wrapper
    /// and every `@State` in the file stops compiling.
    private enum Lookup: Equatable {
        case looking
        case shown(TransclusionSource.Resolved, excerpt: String)
        case noNote
        case noSection
    }

    /// Past this, the rendition is cut and the note offered instead. Without a cap the
    /// length of this page would depend on how long somebody else's note is.
    private static let maximumHeight: CGFloat = 320

    var body: some View {
        content
            .task(id: taskID) { load() }
    }

    private var taskID: String {
        "\(reference)#\(section ?? "")@\(source?.generation ?? -1)"
    }

    @ViewBuilder
    private var content: some View {
        if !expands {
            link
        } else {
            switch lookup {
            case .looking:
                // Sized like one line rather than nothing, so the page does not jump when
                // the note arrives.
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .fill(theme.color(.surfaceSunken))
                    .frame(height: 24)
                    .accessibilityIdentifier("transclusion-loading")
            case .shown(let resolved, let excerpt):
                rendition(of: resolved, excerpt: excerpt)
            case .noNote:
                missing("nota non trovata: \(reference)")
            case .noSection:
                missing("sezione non trovata: \(section ?? "") in \(reference)")
            }
        }
    }

    // MARK: The rendition

    private func rendition(of resolved: TransclusionSource.Resolved, excerpt: String) -> some View {
        HStack(alignment: .top, spacing: theme.spacing(.m)) {
            // A rule, not a framed card: a card would read as a different kind of object,
            // and this is the same note seen from here.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(theme.color(.accentPrimary).opacity(0.35))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                header(resolved.title)
                CappedContent(maximumHeight: Self.maximumHeight) {
                    MarkdownBlocksView(
                        blocks: MarkdownBlockParser.blocks(in: excerpt),
                        notePath: resolved.relativePath,
                        vaultRoot: vaultRoot,
                        thumbnails: thumbnails,
                        transclusions: source,
                        expandsTransclusions: false
                    )
                } whenCut: {
                    Button("apri la nota") { open(resolved.title) }
                        .buttonStyle(.plain)
                        .themedText(.caption, color: .accentPrimary)
                }
            }
        }
        .accessibilityIdentifier("transclusion")
    }

    /// Where this text comes from, and the way back to it.
    private func header(_ title: String) -> some View {
        Button {
            open(title)
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "text.append").themedText(.caption, color: .textTertiary)
                Text(section.map { "\(title) › \($0)" } ?? title)
                    .themedText(.caption, color: .accentPrimary)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    /// Depth one, drawn.
    private var link: some View {
        Button {
            open(reference)
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "text.append").themedText(.caption, color: .textTertiary)
                Text(section.map { "\(reference) › \($0)" } ?? reference)
                    .themedText(.body, color: .accentPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, theme.spacing(.xs))
            .padding(.horizontal, theme.spacing(.s))
            .background(theme.color(.surfaceSunken))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transclusion-link")
    }

    /// Said out loud, and saying which of the two was looked for: the message this
    /// replaces claimed a *file* was missing when a note was asked for.
    private func missing(_ message: String) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(theme.color(.textTertiary))
            Text(message).themedText(.caption, color: .textTertiary)
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .accessibilityIdentifier("transclusion-missing")
    }

    // MARK: -

    private func load() {
        guard let source else {
            lookup = .noNote
            return
        }
        guard let resolved = source.resolve(reference) else {
            lookup = .noNote
            return
        }
        guard let excerpt = Transclusion.excerpt(of: resolved.text, section: section) else {
            lookup = .noSection
            return
        }
        lookup = .shown(resolved, excerpt: excerpt)
    }

    private func open(_ title: String) {
        guard let url = MarkdownBlocksView.noteURL(title) else { return }
        openURL(url)
    }
}

// MARK: - The cap

/// Content limited to a height, with what is past it faded out and an escape offered.
///
/// The measurement is taken on the content at its ideal height, inside an overlay, so the
/// cap cannot feed back into what is being measured - a frame that constrained the content
/// would measure its own limit and never report an overflow.
private struct CappedContent<Content: View, Escape: View>: View {
    @Environment(\.theme) private var theme

    let maximumHeight: CGFloat
    @ViewBuilder let content: Content
    @ViewBuilder let whenCut: Escape

    @State private var idealHeight: CGFloat = 0

    private var isCut: Bool { idealHeight > maximumHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Color.clear
                .frame(height: idealHeight == 0 ? nil : min(idealHeight, maximumHeight))
                .overlay(alignment: .top) {
                    content
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            idealHeight = height
                        }
                }
                .clipped()
                .mask(isCut ? AnyView(fade) : AnyView(Rectangle()))
            if isCut { whenCut }
        }
    }

    private var fade: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.82),
                .init(color: .black.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
