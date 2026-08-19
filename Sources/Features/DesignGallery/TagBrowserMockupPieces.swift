import SwiftUI

// The rows, panes and sheet `TagBrowserMockup` is drawn out of.
//
// In a file of its own because the mockup went past the 400 lines SwiftLint warns at, which is
// the same trade `EditorColumn+Text.swift` made: the scenes say what is being asked, the pieces
// say what it looks like, and neither reads better inside the other.

// MARK: - I pezzi disegnati

/// A framed column standing in for a sidebar pane, so a row is judged against the thing it
/// would sit on rather than against the sheet's background.
struct TagMockupPane<Content: View>: View {
    @Environment(\.theme) private var theme
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) { content }
            .padding(.vertical, theme.spacing(.xs))
            .frame(width: width, alignment: .leading)
            .background(theme.color(.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                    .stroke(theme.color(.borderSubtle), lineWidth: 1)
            )
    }
}

struct TagMockupHeader: View {
    @Environment(\.theme) private var theme
    let title: String

    var body: some View {
        Text(title)
            .themedText(.caption, color: .textTertiary)
            .padding(.horizontal, theme.spacing(.s))
            .padding(.top, theme.spacing(.xs))
    }
}

struct TagMockupNamespaceRow: View {
    @Environment(\.theme) private var theme
    let name: String
    let count: Int
    var isOpen = false

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                .themedText(.caption, color: .textTertiary)
                .frame(width: 10)
            Text(name).themedText(.body, color: .textPrimary).fontWeight(.semibold)
            Spacer()
            Text("\(count)").themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
    }
}

/// One tag: its name, how many notes carry it, and whether it is in the filter.
struct TagMockupTagRow: View {
    @Environment(\.theme) private var theme

    enum Marking: Hashable {
        case none, filled, checked, weighted
        /// The three ways of saying "chosen" the scene compares.
        static let chosen: [Marking] = [.filled, .checked, .weighted]
    }

    let name: String
    let count: Int
    let marking: Marking
    var isPinned = false

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            if marking == .checked {
                Image(systemName: "checkmark")
                    .themedText(.caption, color: .accentPrimary)
                    .frame(width: 12)
            } else if isPinned {
                Image(systemName: "pin.fill")
                    .themedText(.caption, color: .textTertiary)
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12, height: 1)
            }
            Text(name)
                .themedText(.body, color: marking == .none ? .textSecondary : .textPrimary)
                .fontWeight(marking == .weighted ? .semibold : .regular)
            Spacer()
            Text("\(count)")
                .themedText(.caption, color: marking == .weighted ? .accentPrimary : .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(theme.color(marking == .filled ? .accentMuted : .backgroundSecondary))
        )
        .padding(.horizontal, theme.spacing(.xs))
    }
}

struct TagMockupNoteRow: View {
    @Environment(\.theme) private var theme
    let title: String
    var isStarred = false

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: isStarred ? "star.fill" : "doc.text")
                .themedText(.caption, color: isStarred ? .accentPrimary : .textTertiary)
                .frame(width: 12)
            Text(title).themedText(.body, color: .textPrimary).lineLimit(1)
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
    }
}

struct TagMockupFolderRow: View {
    @Environment(\.theme) private var theme
    let name: String

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "chevron.right")
                .themedText(.caption, color: .textTertiary)
                .frame(width: 10)
            Image(systemName: "folder")
                .themedText(.caption, color: .textTertiary)
            Text(name).themedText(.body, color: .textPrimary)
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
    }
}

struct TagMockupFilterField: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "magnifyingglass").themedText(.caption, color: .textTertiary)
            Text("Filtra").themedText(.body, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
    }
}

/// The rename sheet, with its buttons drawn rather than described: what a person clicks is
/// part of what is being approved.
struct TagMockupSheet<Content: View>: View {
    @Environment(\.theme) private var theme
    let width: CGFloat
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(title).themedText(.heading, color: .textPrimary).lineLimit(2)
            content
            HStack(spacing: theme.spacing(.s)) {
                Spacer()
                Text("Annulla").themedText(.body, color: .textSecondary)
                Text("Rinomina")
                    .themedText(.body, color: .onAccent)
                    .padding(.horizontal, theme.spacing(.s))
                    .padding(.vertical, theme.spacing(.xs))
                    .background(
                        RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                            .fill(theme.color(.accentPrimary))
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

struct TagMockupDiff: View {
    @Environment(\.theme) private var theme

    struct Line: Hashable {
        enum Kind { case same, added, removed }
        let text: String
        let kind: Kind
    }

    let path: String
    let lines: [Line]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(path).themedText(.caption, color: .textTertiary)
            ForEach(lines, id: \.text) { line in
                Text(line.text)
                    .themedText(.mono, color: colour(for: line.kind))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.spacing(.xs))
                    .background(background(for: line.kind))
            }
        }
        .padding(theme.spacing(.xs))
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }

    private func colour(for kind: Line.Kind) -> ColorToken {
        switch kind {
        case .same: .textSecondary
        case .added: .codeString
        case .removed: .taskOverdue
        }
    }

    @ViewBuilder
    private func background(for kind: Line.Kind) -> some View {
        switch kind {
        case .same: Color.clear
        case .added: theme.color(.codeString).opacity(0.10)
        case .removed: theme.color(.taskOverdue).opacity(0.10)
        }
    }
}
