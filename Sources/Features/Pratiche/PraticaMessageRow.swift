import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
// R-23, R-24, R-25, R-26, R-27, R-39; DESIGN.md "Binding decisions" (message row
// anatomy), UX-BLUEPRINT "Timeline column anatomy" §5.
//
// One message of the timeline. Collapsed it is one line - chevron, time, sender,
// subject, chips, first line; expanded it adds the body through `MarkdownBlocksView`
// (R-27), the quoted history under «Testo citato», and the footer.
//
// Direction is carried three ways and never by colour alone (R-25): the lane's
// alignment, the glyph beside the time, and the spoken label that opens the row's
// accessibility text. The lane's own background is a token (`surface.received` /
// `surface.sent`, R-39), never a hardcoded colour.
struct PraticaMessageRow: View {
    @Environment(\.theme) private var theme

    let entry: PraticaTimelineEntry
    /// `nil` while the folder is being re-read: the row still draws its header, which
    /// came from the timeline itself rather than from the file.
    let detail: PraticaRowDetail?
    let isExpanded: Bool
    /// `true` when Opt was held, which expands or collapses every visible row (R-24).
    let onToggle: (_ expandsAll: Bool) -> Void
    let onQuickLook: (URL) -> Void
    var vaultRoot: URL?
    /// The pane's own command runner. Optional so a preview can build this row without
    /// a `VaultController`; `nil` draws the footer's «Apri in Mail» alone, which is
    /// what a row outside the pane can honestly offer.
    var actions: PraticaCommandActions?

    /// Per row and per window, like the row's own expansion (R-24): a quoted history
    /// opened once is not a preference, and nothing about it belongs on disk.
    @State private var isShowingQuoted = false

    private var lane: PraticaLane { PraticaTimelineModel.lane(for: entry) }
    private var link: (url: URL?, caption: String?) {
        PraticaTimelineModel.subjectLink(messageID: entry.messageID, isInMail: entry.isInMail)
    }
    private var isPending: Bool { detail?.isPending == true }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            header
            if isExpanded {
                expanded
            } else if !entry.bodyPreview.isEmpty {
                Text(entry.bodyPreview)
                    .themedText(.body, color: .textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(theme.spacing(.s))
        // Pending means Mail has the header but not the body yet (R-15): the row is
        // dimmed rather than hidden, since the message *is* part of the pratica.
        .opacity(isPending ? 0.6 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(PraticaTimelineModel.laneColorToken(lane)))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(Self.identifier(for: entry))
    }

    // MARK: - Collapsed line

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
            Button {
                onToggle(NSEvent.modifierFlags.contains(.option))
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.plain)
            .themedText(.caption, color: .textTertiary)
            .accessibilityLabel(isExpanded ? "Comprimi" : "Espandi")
            .accessibilityIdentifier("pratiche-message-chevron-\(Self.hash(of: entry))")

            Image(systemName: PraticaTimelineModel.laneGlyph(lane))
                .themedText(.caption, color: .textSecondary)
                .accessibilityLabel(PraticaTimelineModel.laneLabel(lane))
            Text(PraticaRowFormat.time(entry.date))
                .themedText(.caption, color: .textSecondary)
            Text(entry.senderDisplayName)
                .themedText(.body)
                .lineLimit(1)
            subject
            attachments
            Spacer(minLength: 0)
        }
    }

    /// R-26: a `message://` URL through the one builder while the message is in Mail,
    /// plain text plus «non più in Mail» when the ledger says it is gone.
    @ViewBuilder
    private var subject: some View {
        if let url = link.url {
            Button(entry.subject) { NSWorkspace.shared.open(url) }
                .buttonStyle(.plain)
                .themedText(.body, color: .accentPrimary)
                .lineLimit(1)
                .help("Apri in Mail")
                .accessibilityIdentifier("pratiche-message-subject-\(Self.hash(of: entry))")
        } else {
            HStack(spacing: theme.spacing(.xs)) {
                Text(entry.subject)
                    .themedText(.body)
                    .lineLimit(1)
                if let caption = link.caption {
                    Text(caption).themedText(.caption, color: .textTertiary)
                }
            }
            .accessibilityIdentifier("pratiche-message-subject-\(Self.hash(of: entry))")
        }
    }

    @ViewBuilder
    private var attachments: some View {
        if let detail,
           !detail.attachments.isEmpty || !detail.storeReferences.isEmpty || !detail.pendingAttachments.isEmpty {
            HStack(spacing: theme.spacing(.xs)) {
                ForEach(Array(detail.attachments.enumerated()), id: \.offset) { index, reference in
                    AttachmentChip(
                        content: .file(reference),
                        identifier: "pratiche-attachment-\(Self.hash(of: entry))-\(index)",
                        onQuickLook: onQuickLook
                    )
                }
                ForEach(Array(detail.storeReferences.enumerated()), id: \.offset) { index, reference in
                    AttachmentChip(
                        content: .storeReference(reference),
                        identifier: "pratiche-attachment-\(Self.hash(of: entry))-"
                            + "\(detail.attachments.count + index)",
                        onQuickLook: onQuickLook
                    )
                }
                ForEach(Array(detail.pendingAttachments.enumerated()), id: \.offset) { index, name in
                    AttachmentChip(
                        content: .pending(name: name),
                        identifier: "pratiche-attachment-\(Self.hash(of: entry))-"
                            + "\(detail.attachments.count + detail.storeReferences.count + index)",
                        onQuickLook: onQuickLook
                    )
                }
            }
        }
    }

    // MARK: - Expanded body

    @ViewBuilder
    private var expanded: some View {
        if isPending {
            Text("Corpo non ancora scaricato")
                .themedText(.caption, color: .textTertiary)
        } else if let detail, !detail.body.isEmpty {
            MarkdownBlocksView(
                blocks: MarkdownBlockParser.blocks(in: detail.body),
                notePath: detail.notePath,
                vaultRoot: vaultRoot,
                expandsTransclusions: false
            )
        }
        quotedHistory
        if let signature = detail?.signature, !signature.isEmpty {
            Text(signature)
                .themedText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        footer
    }

    /// A hand-drawn disclosure, not a `DisclosureGroup`: these rows live inside the
    /// timeline's `List(selection:)`, whose binding a `DisclosureGroup` label cannot
    /// satisfy (CLAUDE.md's own trap, ADR-0024).
    @ViewBuilder
    private var quotedHistory: some View {
        if let quoted = detail?.quotedHistory, !quoted.isEmpty {
            Button {
                isShowingQuoted.toggle()
            } label: {
                Label("Testo citato", systemImage: isShowingQuoted ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.plain)
            .themedText(.caption, color: .accentPrimary)
            .accessibilityIdentifier("pratiche-message-quoted-\(Self.hash(of: entry))")
            if isShowingQuoted {
                Text(quoted)
                    .themedText(.caption, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// «Apri in Mail · Escludi · Sposta in ▸ · Aggiungi anche a ▸» (DESIGN.md's message
    /// row anatomy), built by iterating the catalogue - the *same* iteration the row's
    /// context menu makes, which is the whole of ADR-0023 §D1: a command is named once
    /// and rendered twice, never written out twice.
    ///
    /// `MessageMenuItems.item` draws an argument-carrying command as a submenu on both
    /// surfaces, so «Sposta in ▸» offers the same destinations here and in the menu.
    @ViewBuilder
    private var footer: some View {
        if let actions {
            HStack(spacing: theme.spacing(.s)) {
                ForEach(actions.commands(for: detail), id: \.self) { command in
                    MessageMenuItems.item(command, entry: entry, detail: detail, actions: actions)
                        .buttonStyle(.plain)
                        .themedText(.caption, color: .accentPrimary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pratiche-message-footer-\(Self.hash(of: entry))")
        } else if let url = link.url {
            Button("Apri in Mail") { NSWorkspace.shared.open(url) }
                .buttonStyle(.plain)
                .themedText(.caption, color: .accentPrimary)
                .accessibilityIdentifier("pratiche-message-open-\(Self.hash(of: entry))")
        }
    }

    /// «Ricevuta, 10 giugno 14:06, Mario Rossi, Richiesta offerta…, 2 allegati,
    /// compressa» - the blueprint's composed label, in its order.
    private var accessibilityText: String {
        var parts = [
            PraticaTimelineModel.laneLabel(lane),
            PraticaRowFormat.spokenDate(entry.date),
            entry.senderDisplayName,
            entry.subject,
        ]
        let count = (detail?.attachments.count ?? 0) + (detail?.storeReferences.count ?? 0)
        if count > 0 { parts.append(count == 1 ? "1 allegato" : "\(count) allegati") }
        if isPending { parts.append("corpo non ancora scaricato") }
        parts.append(isExpanded ? "espansa" : "compressa")
        return parts.joined(separator: ", ")
    }

    // MARK: - Identifiers

    /// `pratiche-message-<messageIDHash>` (UX-BLUEPRINT's checklist).
    static func identifier(for entry: PraticaTimelineEntry) -> String {
        "pratiche-message-\(hash(of: entry))"
    }

    /// A `Message-ID` is an arbitrary string with `<`, `@` and `.` in it - unusable as
    /// an identifier and unstable to read. This is FNV-1a written out rather than
    /// `hashValue`, which is seeded per process and would give a UI test a different
    /// answer on every launch.
    static func hash(of entry: PraticaTimelineEntry) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array((entry.messageID ?? entry.id).utf8) {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01b3
        }
        return String(value, radix: 16)
    }
}

/// The two ways a timeline row spells a date. One place, so the row, the day
/// separator and the accessibility label cannot drift apart.
enum PraticaRowFormat {
    /// `14:06` - the time beside the direction glyph.
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// `martedì 10 giugno 2026` - the sticky day separator (R-23).
    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// `10 giugno 14:06` - what VoiceOver reads inside a row's composed label.
    static func spokenDate(_ date: Date) -> String {
        spokenFormatter.string(from: date)
    }

    /// The person's own locale and time zone, unlike the file formats
    /// (`PraticheController.entryHeadingFormatter`), which are `en_US_POSIX` because a
    /// heading is a file format and not a presentation.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("HHmm")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    private static let spokenFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("ddMMMM HHmm")
        return formatter
    }()
}
