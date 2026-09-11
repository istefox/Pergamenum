import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 -
// R-30; DESIGN.md screen 1a and its Binding decision ("Tray «Da smistare» sits above
// the timeline as a collapsible strip with a count subtitle; each proposal shows
// subject, address, date range, count, and Aggiungi (default) / Ignora").
//
// The strip draws `PraticaTrayModel.PraticaTrayProposal`s and nothing else: which
// conversations are proposed is `MembershipRule.trayCandidates`' answer, reduced by
// `PraticaTrayModel.proposals(from:)` at the end of a sync. This view never reads the
// Mail store and never decides membership.
//
// Hidden when empty, by `PraticaTrayModel.isHidden(_:)` rather than by an `.isEmpty`
// written a second time here (R-30: "the strip is hidden when empty").
struct PraticaTrayStrip: View {
    @Environment(\.theme) private var theme
    @Environment(PraticheController.self) private var pratiche

    let proposals: [PraticaTrayModel.PraticaTrayProposal]
    /// «Aggiungi» and «Ignora», both from `PraticaCommandActions` - the strip owns no
    /// verb of its own, for the same reason the row footers own none (ADR-0023 §D1).
    let onFollow: (PraticaTrayModel.PraticaTrayProposal) -> Void
    let onIgnore: (PraticaTrayModel.PraticaTrayProposal) -> Void

    var body: some View {
        if !PraticaTrayModel.isHidden(proposals) {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                header
                if !pratiche.isTrayCollapsed {
                    ForEach(proposals, id: \.conversationID) { proposal in
                        row(proposal)
                    }
                }
            }
            .padding(.horizontal, theme.spacing(.m))
            .padding(.vertical, theme.spacing(.s))
            .background(theme.color(.backgroundSecondary))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pratiche-tray")
        }
    }

    /// «Da smistare · 2 conversazioni proposte» (screen 1a), with the whole line as the
    /// collapse affordance - the strip is chrome, and a person reaching for it is
    /// reaching for the words as much as for the chevron.
    private var header: some View {
        Button {
            pratiche.isTrayCollapsed.toggle()
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: pratiche.isTrayCollapsed ? "chevron.right" : "chevron.down")
                    .themedText(.caption, color: .textTertiary)
                Text("Da smistare").themedText(.heading)
                Text(countText).themedText(.caption, color: .textSecondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Da smistare, \(countText)")
        .accessibilityIdentifier("pratiche-tray-toggle")
    }

    private var countText: String {
        proposals.count == 1 ? "1 conversazione proposta" : "\(proposals.count) conversazioni proposte"
    }

    private func row(_ proposal: PraticaTrayModel.PraticaTrayProposal) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(proposal.subject.isEmpty ? "(senza oggetto)" : proposal.subject)
                    .themedText(.body)
                    .lineLimit(1)
                Text(subtitle(proposal))
                    .themedText(.caption, color: .textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // «Aggiungi» is the default (DESIGN.md), so it is the prominent one and the
            // one Return reaches when the strip has focus.
            Button("Aggiungi") { onFollow(proposal) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("pratiche-tray-add-\(proposal.conversationID)")
            Button("Ignora") { onIgnore(proposal) }
                .accessibilityIdentifier("pratiche-tray-ignore-\(proposal.conversationID)")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText(proposal))
        .accessibilityIdentifier("pratiche-tray-row-\(proposal.conversationID)")
    }

    /// `mario@rossi-spa.it · 3–10 giu · 4 messaggi` - the address, the range and the
    /// count, in the order the design draws them.
    private func subtitle(_ proposal: PraticaTrayModel.PraticaTrayProposal) -> String {
        [
            proposal.counterpart,
            Self.range(proposal.dateRange),
            proposal.messageCount == 1 ? "1 messaggio" : "\(proposal.messageCount) messaggi",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private func accessibilityText(_ proposal: PraticaTrayModel.PraticaTrayProposal) -> String {
        "\(proposal.subject), \(subtitle(proposal))"
    }

    /// One day when the conversation lived inside a single one, `da … a …` otherwise -
    /// a range whose two ends are the same date reads as an error, not as a range.
    static func range(_ dates: ClosedRange<Date>) -> String {
        let calendar = Calendar.current
        let lower = rangeFormatter.string(from: dates.lowerBound)
        guard !calendar.isDate(dates.lowerBound, inSameDayAs: dates.upperBound) else { return lower }
        return "\(lower) – \(rangeFormatter.string(from: dates.upperBound))"
    }

    /// The reader's own locale, like every other date this pane draws
    /// (`PraticaRowFormat`) and unlike the file formats, which are `en_US_POSIX`.
    private static let rangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("ddMMM")
        return formatter
    }()
}
