import SwiftUI

/// The «Collega» confirmation (ADR-0084 §D3, mockup «Menzioni», N3 half): the diff of the exact
/// bytes that will land, «Collega» as the default button, «Annulla».
///
/// Nothing is written before the person has seen this diff. A note that moved on between the diff
/// and the click is planned again and shown again here with the notice; the sheet closes itself
/// once the link is written or nothing is left to link, and the section that opened it reads the
/// review's final state.
struct LinkMentionSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let review: LinkMentionReview

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Collegare «\(review.title)» in «\(noteName)»?").themedText(.title)
            content
            HStack {
                Spacer()
                // Off while the write is in flight: a dismissal then reads `.reviewing`, forgets the
                // plan, and the link lands anyway under a row that stays listed.
                Button("Annulla") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(review.isConfirming)
                    .accessibilityIdentifier("link-mention-cancel")
                if isReviewing {
                    Button("Collega") { Task { @MainActor in await review.confirm() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(review.isConfirming)
                        .accessibilityIdentifier("link-mention-confirm")
                }
            }
        }
        .padding(theme.spacing(.l))
        // `RelatedLinkSheet`'s width, the other sheet that writes a link; wide enough for the
        // diff's mono lines, which `DiffView` cuts at one line each.
        .frame(width: 560)
        .background(theme.color(.surfaceCard))
        .onChange(of: review.state) { _, state in
            if state == .linked || state == .nothingToLink { dismiss() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch review.state {
        case .reviewing(let diff, let notice):
            if let notice {
                Label(notice, systemImage: "arrow.triangle.2.circlepath")
                    .themedText(.caption, color: .textSecondary)
                    .accessibilityIdentifier("link-mention-notice")
            }
            DiffView(path: review.notePath, diff: diff)
        case .failed(let message):
            Text(message)
                .themedText(.caption, color: .taskOverdue)
                .fixedSize(horizontal: false, vertical: true)
        case .linked, .nothingToLink:
            EmptyView()
        }
    }

    private var isReviewing: Bool {
        if case .reviewing = review.state { return true }
        return false
    }

    /// The note the link is written into, by its file name.
    private var noteName: String {
        ((review.notePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}
