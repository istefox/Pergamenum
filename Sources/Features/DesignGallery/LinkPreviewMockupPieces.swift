import SwiftUI

// The note, the popover, the menu and the sheet the three N3 pages are drawn out of
// (`LinkPreviewMockup`, `InspectorLinksMockup`, the «Collega» half of `UnlinkedMentionsMockup`).
//
// In a file of its own for the reason `TagBrowserMockupPieces.swift` gives: the scenes say what is
// being asked, the pieces say what it looks like, and together they pass the 400 lines SwiftLint
// warns at. Literal content only, every colour and font through a token.

// MARK: - The note a link sits in

/// A stand-in for the note being read, on the secondary background `SlashMenuMockup`'s backdrop
/// uses, so a popover or a menu is judged against text rather than against the sheet.
struct LinkMockupNote<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) { content }
            .padding(theme.spacing(.m))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }
}

extension HorizontalAlignment {
    private enum LinkAnchor: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.center]
        }
    }

    /// The centre of the link a popover is anchored to. `NSPopover` centres its arrow on the anchor
    /// rect and its card on the arrow, so a scene that stacks a `LinkMockupLine` and a
    /// `LinkMockupPopover` on this alignment puts the arrow under the link rather than guessing an
    /// inset from the width of the prose before it.
    static var linkAnchor: HorizontalAlignment { HorizontalAlignment(LinkAnchor.self) }
}

/// One line of prose with a link in it, the link in the accent as the editor draws a followable
/// run, and an optional pointer resting on the link. The link's centre is the line's
/// `.linkAnchor`.
struct LinkMockupLine: View {
    @Environment(\.theme) private var theme
    let before: String
    let link: String
    var after = ""
    var pointer = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(before).themedText(.body, color: .textSecondary)
            Text(link)
                .themedText(.body, color: .accentPrimary)
                .alignmentGuide(.linkAnchor) { $0[HorizontalAlignment.center] }
                .overlay(alignment: .center) {
                    if pointer {
                        // Where the pointer rests while the 250 ms dwell runs, right of the
                        // popover's arrow so neither hides the other; its exact shape is
                        // ADR-0090's, decided in the editor, not here.
                        Image(systemName: "cursorarrow")
                            .themedText(.body, color: .textPrimary)
                            .offset(x: 28, y: 6)
                    }
                }
            Text(after).themedText(.body, color: .textSecondary)
        }
        .lineLimit(1)
    }
}

// MARK: - The popover

/// The preview as AppKit draws an `NSPopover` on the edge below its anchor: a raised card with an
/// arrow centred on its top edge, pointing back at the link (ADR-0083 §D7, amended: a popover, not
/// a panel). Anchored to the edge of the link's rect, it sits beside the link and never over it.
/// Its centre is its `.linkAnchor`, so stacked under a `LinkMockupLine` the arrow meets the link.
struct LinkMockupPopover<Content: View>: View {
    @Environment(\.theme) private var theme
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            ZStack {
                LinkMockupArrow().fill(theme.color(.surfaceCard))
                LinkMockupArrow(closed: false).stroke(theme.color(.borderSubtle), lineWidth: 1)
            }
            .frame(width: 18, height: 9)
            // Over the card's own border by one point, so the arrow and the card read as one shape.
            .offset(y: 1)
            .zIndex(1)
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) { content }
                .padding(theme.spacing(.s))
                .frame(width: width, alignment: .leading)
                .background(theme.color(.surfaceCard))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                        .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
                )
                .themedShadow(.raised)
        }
        .alignmentGuide(.linkAnchor) { $0[HorizontalAlignment.center] }
    }
}

/// The popover's arrow. Closed for the fill, open (the two slanted sides only) for the stroke, so
/// the base that meets the card draws no line across it.
struct LinkMockupArrow: Shape {
    var closed = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        if closed { path.closeSubpath() }
        return path
    }
}

/// A folder label as a choice row shows it (`LinkChoice.folderLabel(of:)`): the vault-relative
/// folder, «radice del vault» for a note at the root.
struct LinkMockupFolder: View {
    @Environment(\.theme) private var theme
    let label: String

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "folder").themedText(.caption, color: .textTertiary)
            Text(label).themedText(.body, color: .textSecondary).lineLimit(1)
        }
    }
}

// MARK: - The menu

/// A system menu imitated with shapes, as `HistoryMockup`'s menu entry does: the real one is an
/// `NSMenu` and takes no token, so what is approved here is its content, not its paint.
struct LinkMockupMenu: View {
    @Environment(\.theme) private var theme

    enum Item: Hashable {
        /// A disabled line that says what the menu is for.
        case header(String)
        /// A command; `glyph` is the SF Symbol drawn before it, `shortcut` the key on the right,
        /// `highlighted` the row under the pointer.
        case row(String, glyph: String? = nil, shortcut: String? = nil, highlighted: Bool = false)
        case separator
    }

    let items: [Item]
    var width: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .header(let title):
                    Text(title)
                        .themedText(.caption, color: .textTertiary)
                        .padding(.horizontal, theme.spacing(.s))
                        .padding(.vertical, theme.spacing(.xs))
                case .row(let title, let glyph, let shortcut, let highlighted):
                    row(title, glyph: glyph, shortcut: shortcut, highlighted: highlighted)
                case .separator:
                    Rectangle()
                        .fill(theme.color(.borderSubtle))
                        .frame(height: 1)
                        .padding(.vertical, theme.spacing(.xs))
                        .padding(.horizontal, theme.spacing(.s))
                }
            }
        }
        .padding(.vertical, theme.spacing(.xs))
        .frame(width: width, alignment: .leading)
        .background(theme.color(.surfaceRaised))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
        .themedShadow(.raised)
    }

    private func row(
        _ title: String, glyph: String?, shortcut: String?, highlighted: Bool
    ) -> some View {
        let color: ColorToken = highlighted ? .onAccent : .textPrimary
        return HStack(spacing: theme.spacing(.xs)) {
            if let glyph {
                Image(systemName: glyph).themedText(.caption, color: highlighted ? .onAccent : .textTertiary)
                    .frame(width: 14)
            }
            Text(title).themedText(.body, color: color).lineLimit(1)
            Spacer(minLength: theme.spacing(.s))
            if let shortcut {
                Text(shortcut).themedText(.caption, color: highlighted ? .onAccent : .textTertiary)
            }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(highlighted ? theme.color(.accentPrimary) : .clear)
                .padding(.horizontal, theme.spacing(.xs) / 2)
        )
    }
}

// MARK: - The sheet

/// A sheet or a confirmation with its buttons drawn rather than described, the
/// `TagMockupSheet` shape with the confirm button's label and role as parameters: the three N3
/// pages confirm with «Apri», «Crea», «Collega» and «Scollega», and a destructive one says so in
/// the colour the diff uses for a removed line (`DiffView`), there being no destructive token.
struct LinkMockupSheet<Content: View>: View {
    @Environment(\.theme) private var theme
    let width: CGFloat
    let title: String
    let confirm: String
    var destructive = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(title)
                .themedText(.heading, color: .textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            content
            HStack(spacing: theme.spacing(.s)) {
                Spacer()
                Text("Annulla").themedText(.body, color: .textSecondary)
                Text(confirm)
                    .themedText(.body, color: destructive ? .taskOverdue : .onAccent)
                    .padding(.horizontal, theme.spacing(.s))
                    .padding(.vertical, theme.spacing(.xs))
                    .background(
                        RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                            .fill(theme.color(destructive ? .backgroundTertiary : .accentPrimary))
                    )
            }
        }
        .padding(theme.spacing(.m))
        .frame(width: width, alignment: .leading)
        .background(theme.color(.surfaceRaised))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .stroke(theme.color(.borderSubtle), lineWidth: 1)
        )
    }
}

/// One row of a choice list inside a sheet: a glyph, a label, the selection in the muted accent
/// the completion panel selects with.
struct LinkMockupChoiceRow: View {
    @Environment(\.theme) private var theme
    let title: String
    var glyph = "folder"
    var trailing: String?
    var selected = false

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: glyph)
                .themedText(.caption, color: selected ? .textPrimary : .textTertiary)
                .frame(width: 14)
            Text(title).themedText(.body, color: selected ? .textPrimary : .textSecondary).lineLimit(1)
            Spacer(minLength: theme.spacing(.s))
            if let trailing {
                Text(trailing).themedText(.caption, color: .textTertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(selected ? theme.color(.accentMuted) : .clear)
        )
    }
}
