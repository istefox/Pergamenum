import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
// R-18; DESIGN.md screen 1c, UX-BLUEPRINT "Timeline column anatomy" §2.
//
// The one thing this app can say when TCC has not granted Full Disk Access: macOS
// denies the read silently and never prompts, so the banner *is* the prompt (ADR
// §D10). Inline and never modal - a person reading their pratica keeps reading it,
// and the pane behind this strip is still usable for everything that does not need
// Mail.
struct FullDiskAccessBanner: View {
    @Environment(\.theme) private var theme

    /// Collapsed by default: the sentence above is the message, and the four steps
    /// are for the person who wants them.
    @State private var isShowingHowTo = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
                Label(Self.message, systemImage: "exclamationmark.triangle")
                    .themedText(.body, color: .taskOverdue)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: theme.spacing(.s))
                // Hand-drawn disclosure rather than `DisclosureGroup`: this strip sits
                // above a `List` whose selection binding a `DisclosureGroup` label
                // cannot satisfy (CLAUDE.md's own trap, ADR-0024), and there is no
                // reason for two different disclosure mechanisms in one column.
                Button {
                    isShowingHowTo.toggle()
                } label: {
                    Label("Come fare", systemImage: isShowingHowTo ? "chevron.down" : "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .themedText(.caption, color: .accentPrimary)
                .accessibilityIdentifier("pratiche-fda-how-to")

                Button("Apri Impostazioni di Sistema") {
                    FullDiskAccessProbe.openSystemSettings()
                }
                .accessibilityIdentifier("pratiche-fda-open-settings")
            }

            if isShowingHowTo {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .themedText(.caption, color: .textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.accentMuted))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-fda-banner")
    }

    /// Named once so screen 1c, this view and a UI test read the same sentence.
    static let message = "Pergamenum non può leggere Mail"

    /// The grant is per app *bundle*, so the last step is the one people miss.
    static let steps = [
        "Apri Impostazioni di Sistema › Privacy e sicurezza › Accesso completo al disco.",
        "Attiva l'interruttore accanto a Pergamenum (usa + se non è in elenco).",
        "Torna qui: la prossima sincronizzazione riprova da sola, senza riavviare l'app.",
    ]
}
