import SwiftUI

/// The page every mockup in the gallery is drawn on: one vertical `ScrollView`, the gallery's
/// own padding and spacing, the primary background, and a content width that is
/// `MockupGalleryView.contentWidth` and never `.infinity`.
///
/// The width is why this is one type rather than seventeen copies of five lines. Nine mockups
/// used to say `.frame(maxWidth: .infinity, ...)` and eight said `contentWidth`; a vertical
/// scroll view does not scroll sideways, so anything the sheet cannot hold is centred and
/// clipped at both edges at once (`MockupGalleryView.contentWidth` tells the story). The
/// eight had been fixed one by one after a review round; the nine had not. Written here once,
/// a new mockup cannot be the tenth. ADR-0051 §D5.
struct MockupPage<Content: View>: View {
    @Environment(\.theme) private var theme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.l)) {
                content
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: MockupGalleryView.contentWidth, alignment: .leading)
        }
        .background(theme.color(.backgroundPrimary))
    }
}

/// One captioned picture on a `MockupPage`: the caption in tertiary text, then the content.
///
/// A mockup whose scene sits on a backdrop, or in a narrower column, builds that inside the
/// content it passes here - the backdrop is the mockup's own decision, the caption is not.
struct MockupScene<Content: View>: View {
    @Environment(\.theme) private var theme
    private let caption: String
    private let content: Content

    init(_ caption: String, @ViewBuilder content: () -> Content) {
        self.caption = caption
        self.content = content()
    }

    /// For a scene that is one already-built view, so a call site reads `MockupScene("...", mock)`
    /// rather than wrapping a single value in a closure.
    init(_ caption: String, _ content: Content) {
        self.caption = caption
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(caption)
                .themedText(.caption, color: .textTertiary)
                // A caption that wraps must keep the height it wraps to; three mockups
                // already said so, the other fourteen had not needed to yet.
                .fixedSize(horizontal: false, vertical: true)
            content
        }
    }
}

/// A small titled card inside a scene: the title in secondary text, then the content at a fixed
/// width on a raised, rounded surface. The outline, history and template mockups each drew this
/// by hand; `alignment` is the one thing they disagreed about (the template mockup's cells
/// start at the leading edge, the other two centre), so it is a parameter rather than a
/// reason for a second copy.
struct MockupCell<Content: View>: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let width: CGFloat
    private let alignment: Alignment
    private let content: Content

    init(
        _ title: String, width: CGFloat, alignment: Alignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.width = width
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(title).themedText(.caption, color: .textSecondary)
            content
                .frame(width: width, alignment: alignment)
                .padding(theme.spacing(.s))
                .background(theme.color(.backgroundSecondary))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        }
    }
}
