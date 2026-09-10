import SwiftUI

/// A unified diff, coloured by line. Shared by every surface that shows one to a
/// person before a write (`TagRenameSheet`'s rename-across-the-vault preview, the
/// Pratiche «Rigenera» preview, ADR-0036 §D21) - one rendering, not two kept in step.
struct DiffView: View {
    @Environment(\.theme) private var theme
    let path: String
    let diff: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(path).themedText(.caption, color: .textTertiary)
            ForEach(Array(diff.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                Text(line)
                    .themedText(.mono, color: colour(of: line))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }

    private func colour(of line: String) -> ColorToken {
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") { return .textTertiary }
        if line.hasPrefix("+") { return .codeString }
        if line.hasPrefix("-") { return .taskOverdue }
        return .textSecondary
    }
}
