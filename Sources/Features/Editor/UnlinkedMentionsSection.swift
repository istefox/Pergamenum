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
struct UnlinkedMentionsSection: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let notePath: String

    @State private var results: [VaultController.SearchResult]?
    @State private var isScanning = false

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
        }
        .accessibilityIdentifier("unlinkedMentions")
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text("MENZIONI NON LINKATE").themedText(.caption, color: .textTertiary)
            Spacer()
            // Only once there is an answer: a zero before the scan would be a number nobody
            // has computed.
            if let results, !results.isEmpty {
                Text("\(results.count)").themedText(.caption, color: .textTertiary)
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
        } else if let results {
            if results.isEmpty {
                explanation("Nessuna nota nomina questa senza linkarla.")
            } else {
                ForEach(results) { result in
                    row(result)
                }
            }
            scanButton("Cerca di nuovo", systemImage: "arrow.clockwise")
        } else {
            explanation("Cerca il titolo di questa nota nel testo delle altre.")
            scanButton("Cerca nel vault", systemImage: "magnifyingglass")
        }
    }

    /// The note and the line its name falls on. Titles alone would make you open each one to
    /// find out why it is in the list.
    private func row(_ result: VaultController.SearchResult) -> some View {
        Button { vault.openNote(at: result.path) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title).themedText(.body, color: .accentPrimary).lineLimit(1)
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
            results = vault.unlinkedMentions(for: path)
            isScanning = false
        }
    }
}
