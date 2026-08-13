import SwiftUI

/// The vault-wide conformance view of SPEC §4.7.
///
/// Checks on request, never in bulk automatically, and never corrects: a note is
/// brought into line when it is touched, not retroactively (frontmatter.md 6.2). So
/// this lists what is wrong and opens the note; the fixing is the user's.
struct ConformanceView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @State private var results: [Result] = []
    @State private var isChecking = false
    @State private var hasRun = false

    private struct Result: Identifiable {
        var id: String { path }
        var path: String
        var title: String
        var lines: [String]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .background(theme.color(.backgroundPrimary))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: check) {
                    Label("Verifica ora", systemImage: "checkmark.seal")
                }
                .help("Verifica le note contro le convenzioni harness")
                .disabled(isChecking || vault.root == nil)
            }
        }
        // Asked for from the Vista menu, which cannot call into a view. The pane is
        // brought forward by the command itself, so by the time this fires the view
        // exists to answer.
        .onChange(of: vault.isCheckingConformance) { _, requested in
            guard requested else { return }
            vault.isCheckingConformance = false
            check()
        }
        .task {
            // A request that arrived while another pane was showing: the command sets
            // the flag and switches pane in the same breath, so this view appears
            // after the change and never sees the transition.
            if vault.isCheckingConformance {
                vault.isCheckingConformance = false
                check()
            }
        }
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.s)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Conformità").themedText(.heading)
                Text("Verifica su richiesta. Il linter segnala, non corregge.")
                    .themedText(.caption, color: .textTertiary)
            }
            Spacer()
            if vault.vocabulary.isEmpty {
                Label("Vocabolari non importati", systemImage: "exclamationmark.triangle")
                    .themedText(.caption, color: .taskOverdue)
                    .help("Le famiglie chiuse non sono verificabili finché non importi le convenzioni")
            }
            if isChecking {
                ProgressView().controlSize(.small)
            }
        }
        .padding(theme.spacing(.m))
    }

    @ViewBuilder
    private var content: some View {
        if !hasRun {
            placeholder("Nessuna verifica eseguita.")
        } else if results.isEmpty {
            placeholder("Tutte le \(vault.index.count) note sono conformi.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    Text("\(results.count) note non conformi su \(vault.index.count)")
                        .themedText(.caption, color: .textSecondary)

                    ForEach(results) { result in
                        ThemedCard {
                            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                                Button {
                                    vault.openNote(at: result.path)
                                } label: {
                                    Text(result.title).themedText(.body, color: .accentPrimary)
                                }
                                .buttonStyle(.plain)
                                Text(result.path).themedText(.caption, color: .textTertiary)

                                ForEach(result.lines, id: \.self) { line in
                                    Text("· \(line)").themedText(.caption, color: .taskOverdue)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(theme.spacing(.m))
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .themedText(.body, color: .textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func check() {
        isChecking = true
        defer { isChecking = false; hasRun = true }

        results = vault.index.allNotes.compactMap { record in
            let violations = vault.violations(forRecordAt: record.relativePath)
            guard let violations, !violations.isEmpty else { return nil }
            return Result(
                path: record.relativePath,
                title: record.title,
                lines: ConformanceText.lines(violations)
            )
        }
    }
}
