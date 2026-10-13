import SwiftUI

/// The inspector's «MENZIONI NON LINKATE», under the backlinks (ADR-0012 D9, mockup approved
/// 2026-08-19).
///
/// **The button is the feature.** Finding every note that names this one is a full-vault text
/// scan, the same read loop a search runs, and D9 forbids paying it on every note opening. A
/// panel that filled itself would be exactly the thing the decision rules out, so the resting
/// state says what it will do and waits to be asked.
///
/// A view of its own rather than another method on `VaultBrowser`: the result belongs to the
/// note it was computed for and has to be thrown away when the note changes, which is one line
/// here and a fourth kind of state to keep in step over there.
///
/// Each row gains «Collega» (ADR-0084 §D3): a `LinkMentionReview` and the `LinkMentionSheet` over
/// its diff. A row whose link landed leaves the list; a row with nothing left to link becomes a
/// sentence until the next scan. A title several notes share gets no «Collega» and the
/// connectors' sentence instead: `[[Titolo]]` would point at every homonym.
struct UnlinkedMentionsSection: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let notePath: String

    @State private var results: [VaultController.SearchResult]?
    @State private var isScanning = false
    /// The review the «Collega» sheet shows, while it is up.
    @State private var review: LinkMentionReview?
    /// Rows «Collega» linked: they leave the list.
    @State private var linked: Set<String> = []
    /// Rows «Collega» found nothing to link in: a sentence replaces them until the next scan.
    @State private var nothingLeft: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            header
            content
        }
        // The result answers a question about *this* note. Kept across a change it would show
        // the mentions of the note you came from under the title of the one you are looking at,
        // which is worse than showing nothing.
        .onChange(of: notePath) { _, _ in
            results = nil
            isScanning = false
            linked = []
            nothingLeft = []
        }
        // `.contain` first: an identifier on a plain container is pushed down onto every child on
        // macOS and overwrites theirs, so «Cerca nel vault» and «Collega» lost
        // `unlinked-mentions-scan` / `unlinked-mention-link-…` (TraySection does the same).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unlinkedMentions")
        .sheet(isPresented: Binding(
            get: { review != nil },
            set: { if !$0 { finishReview() } }
        )) {
            if let review { LinkMentionSheet(review: review) }
        }
    }

    /// The rows still to show: a linked row is gone.
    private var shown: [VaultController.SearchResult]? {
        results?.filter { !linked.contains($0.path) }
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text("MENZIONI NON LINKATE").themedText(.caption, color: .textTertiary)
            Spacer()
            // Only once there is an answer: a zero before the scan would be a number nobody
            // has computed. A row that became the «niente da collegare» sentence is not counted.
            if let pending = shown?.filter({ !nothingLeft.contains($0.path) }).count, pending > 0 {
                Text("\(pending)").themedText(.caption, color: .textTertiary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isScanning {
            HStack(spacing: theme.spacing(.xs)) {
                ProgressView().controlSize(.small)
                Text("Scansione delle note…").themedText(.caption, color: .textSecondary)
            }
        } else if let shown {
            if shown.isEmpty {
                explanation("Nessuna nota nomina questa senza linkarla.")
            } else {
                let shared = vault.sharedTitle(ofNoteAt: notePath)
                ForEach(shown) { result in
                    if nothingLeft.contains(result.path) {
                        explanation(
                            "«\(result.title)» non nomina più questa nota, o la linka già: niente da collegare."
                        )
                            .padding(.vertical, 2)
                    } else {
                        row(result, canLink: shared == nil)
                    }
                }
                // No «Collega» on a shared title (the rows above have none): the connectors'
                // sentence says why, and what would make it possible.
                if let shared {
                    let refusal = VaultSession.sharedTitleLinkRefusal(shared)
                    explanation(refusal.prefix(1).uppercased() + refusal.dropFirst() + ".")
                        .accessibilityIdentifier("unlinked-mentions-shared-title")
                }
            }
            scanButton("Cerca di nuovo", systemImage: "arrow.clockwise")
        } else {
            explanation("Cerca il titolo di questa nota nel testo delle altre.")
            scanButton("Cerca nel vault", systemImage: "magnifyingglass")
        }
    }

    /// The note and the line its name falls on. Titles alone would make you open each one to
    /// find out why it is in the list. «Collega» sits over the title line's trailing end, above the
    /// row's own button, so a click there links and a click anywhere else opens the note. Without
    /// `canLink` (a shared title) the row only opens.
    private func row(_ result: VaultController.SearchResult, canLink: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Button { vault.openNote(at: result.path) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: theme.spacing(.xs)) {
                        Text(result.title).themedText(.body, color: .accentPrimary).lineLimit(1)
                        Spacer(minLength: theme.spacing(.xs))
                        // Holds the place «Collega» is drawn over, so a long title stops short of it.
                        if canLink { linkLabel.hidden() }
                    }
                    Text(result.excerpt)
                        .themedText(.caption, color: .textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(result.path)

            if canLink {
                Button { beginReview(of: result) } label: { linkLabel }
                    .buttonStyle(.plain)
                    .help("Mostra il confronto prima di scrivere il link")
                    .accessibilityIdentifier("unlinked-mention-link-\(result.path)")
            }
        }
        .padding(.vertical, 2)
    }

    private var linkLabel: some View {
        Text("Collega")
            .themedText(.caption, color: .accentPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .fill(theme.color(.backgroundTertiary))
            )
            .contentShape(Rectangle())
    }

    /// Plans the diff and raises the sheet over it. A mention already gone has no diff to show:
    /// the row becomes the sentence straight away.
    private func beginReview(of result: VaultController.SearchResult) {
        guard let title = vault.index.note(at: notePath)?.title else { return }
        let candidate = LinkMentionReview(vault: vault, notePath: result.path, title: title)
        if candidate.state == .nothingToLink {
            nothingLeft.insert(result.path)
        } else {
            review = candidate
        }
    }

    /// The sheet went away: reads how the review ended. A diff closed unconfirmed is forgotten by
    /// the session, so no later write can be checked against it.
    private func finishReview() {
        guard let finished = review else { return }
        review = nil
        switch finished.state {
        case .linked: linked.insert(finished.notePath)
        case .nothingToLink: nothingLeft.insert(finished.notePath)
        case .reviewing, .failed: finished.cancel()
        }
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .themedText(.caption, color: .textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func scanButton(_ title: String, systemImage: String) -> some View {
        Button { scan() } label: {
            Label(title, systemImage: systemImage)
                .themedText(.caption, color: .accentPrimary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityIdentifier("unlinked-mentions-scan")
    }

    /// The scan runs on the main actor because the session does, so the spinner needs a turn of
    /// the run loop to be drawn before the loop starts. Without the yield the panel goes from
    /// the button straight to the answer and a long scan looks like a frozen window.
    private func scan() {
        let path = notePath
        isScanning = true
        Task { @MainActor in
            await Task.yield()
            guard path == notePath else { return }
            results = vault.linkableMentions(ofNoteAt: path)
            linked = []
            nothingLeft = []
            isScanning = false
        }
    }
}
