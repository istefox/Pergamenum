import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
// R-23, R-24, R-25, R-26, R-32, R-39.
//
// The timeline's pure model (SPEC "Timeline model"): ordering, filtering, the
// direction-to-lane mapping and the subject's `message://` resolution. Deliberately
// self-contained rather than built over `MessageDocument`/a manual-entry parser
// directly - Task 7 owns `PraticaEntry.insert(kind:at:in:)` and the manual-entry
// heading grammar, and this file must not race that declaration. A caller (the
// coder's view layer) maps a `MessageDocument`/manual entry into a
// `PraticaTimelineEntry` before handing it here.

/// One row of the timeline - a message or a manual entry (SPEC "Timeline model").
struct PraticaTimelineEntry: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case message
        case note
        case call
    }

    var id: String
    var kind: Kind
    /// The entry's own sort key: `pergamenum-mail-date` (fallback received) for a
    /// message, the heading timestamp for a manual entry (R-23). Already resolved by
    /// the caller - see `PraticaTimelineModel.sortDate(of:)` for the message half of
    /// that resolution.
    var date: Date
    /// `nil` for `.note`/`.call` - direction only exists for a message (R-25).
    var direction: MessageDocument.Direction?
    var senderDisplayName: String
    /// The bare address the sender menu offers and filters by (R-32) - `nil` for a
    /// manual entry, and defaulted so the memberwise init stays source-compatible
    /// everywhere a caller has no address to give. `senderDisplayName` alone cannot
    /// serve the menu: it holds Mail's own display name, which two different people
    /// share far more often than they share a mailbox.
    var senderAddress: String? = nil
    var subject: String
    var bodyPreview: String
    var hasAttachments: Bool
    /// `pergamenum-mail-message-id`, present only for `.kind == .message`.
    var messageID: String?
    /// Whether the ledger still finds this message in Mail (R-26/R-16's "non più in
    /// Mail" caption). Irrelevant for a manual entry.
    var isInMail: Bool
    /// ADR-0076 §D3 (PG-338). Each defaulted, so every memberwise call written before the
    /// anchor existed compiles unchanged.
    ///
    /// A manual entry's anchor line, the Message-ID verbatim; nil for a message and a free entry.
    var anchor: String?
    /// A manual entry's index among `pratica.md`'s entries, in file order: the tie-break
    /// between two entries at one instant (R-08).
    var fileOrdinal: Int = 0
    /// Where `PraticaTimelineModel.ordered` put the row (`PraticaTimelineOrder.arrange`).
    var placement: PraticaTimelineOrder.Placement = .free
    /// The instant the row is placed at: its message's date for an anchored entry.
    var placementDate: Date?
    /// An anchored entry's message's direction, which `hostLane(for:)` aligns it to.
    var hostDirection: MessageDocument.Direction?
    /// A manual entry's `fileOrdinal` names a position in one specific version of `pratica.md`:
    /// this is that version's hash (`timelineOrigin` at the read that produced the entry). The
    /// entry verbs compare it, not the controller's current origin, which a later reload may
    /// have advanced (ADR-0076 §D5, R-18). Nil for a message.
    var sourceHash: String?

    /// The instant the row counts at for day sections and «Inserisci qui» (R-07).
    var placedAt: Date { placementDate ?? date }
}

/// Where a row sits and how it is coloured (SPEC "Timeline model" Lane paragraph,
/// DESIGN.md "Binding decisions"): `received` left, `sent` right, `entry` the whole readable column.
enum PraticaLane: Equatable, Sendable {
    case received
    case sent
    case entry
}

/// The toolbar filters (R-32): text over subject/sender/body, an optional sender
/// address, and «Solo con allegati». Manual entries are hidden only by `text`.
struct PraticaTimelineFilter: Equatable, Sendable {
    var text: String = ""
    var sender: String? = nil
    var attachmentsOnly: Bool = false

    static let none = PraticaTimelineFilter()
}

enum PraticaTimelineModel {
    // MARK: - R-23: ordering

    /// `pergamenum-mail-date`, falling back to `pergamenum-mail-received` when the
    /// primary date could not be parsed (`MessageDocument.parse` defaults an
    /// unparseable `pergamenum-mail-date` to `.distantPast`).
    ///
    /// `.distantPast` is the exact value `MessageDocument.parse` leaves behind for a
    /// `pergamenum-mail-date` it could not read, so it is the signal - not a heuristic
    /// on the age of the message. A message with no readable date and no received date
    /// keeps `.distantPast` and sorts to the top of the timeline, where a person can
    /// see that something is wrong with it.
    static func sortDate(of frontmatter: MessageDocument.MailFrontmatter) -> Date {
        guard frontmatter.date == .distantPast, let received = frontmatter.received else {
            return frontmatter.date
        }
        return received
    }

    /// Interleaves messages and manual entries by `date`, ascending (R-23): the
    /// oldest entry first, so a view scrolls to the *end* of this array to land on
    /// the newest, matching SPEC "Timeline model"'s "the view scrolls to the bottom
    /// (newest) on open".
    ///
    /// ADR-0076 §D3: the order is `PraticaTimelineOrder.arrange`'s, the one rule the
    /// connectors share. An anchored entry follows its message (R-04); at an equal instant
    /// a message sorts before an entry (R-08, the old id tie-break put the entry first,
    /// ADR-0076 F2); two messages at one instant sort by id, so an Exchange conversation
    /// sent to several mailboxes at once keeps one stable order across reloads.
    static func ordered(_ entries: [PraticaTimelineEntry]) -> [PraticaTimelineEntry] {
        let items = entries.map { entry in
            PraticaTimelineOrder.Item(
                kind: entry.kind == .message
                    ? .message(messageID: entry.messageID ?? "", tieKey: entry.id)
                    : .entry(anchor: entry.anchor, ordinal: entry.fileOrdinal),
                date: entry.date
            )
        }
        var hostDirections: [String: MessageDocument.Direction] = [:]
        return PraticaTimelineOrder.arrange(items).map { placed in
            var entry = entries[placed.index]
            entry.placement = placed.placement
            entry.placementDate = placed.placementDate
            switch placed.placement {
            case .message:
                // The first message carrying an id owns it (ADR-0076 §D2), and it is also
                // the first one met in this order.
                if let messageID = entry.messageID, hostDirections[messageID] == nil {
                    hostDirections[messageID] = entry.direction
                }
            case let .anchored(messageID):
                entry.hostDirection = hostDirections[messageID]
            case .free, .orphaned:
                break
            }
            return entry
        }
    }

    // MARK: - R-32: filters

    /// Text narrows subject/sender/body of every row, case-insensitively, and is the
    /// only filter allowed to hide a manual entry (R-32: "manual entries are hidden
    /// only by the text filter"). Sender and «Solo con allegati» apply to messages
    /// only and never remove a `.note`/`.call` row.
    ///
    /// The asymmetry is R-32's own: «Solo con allegati» and the sender menu are
    /// questions about the correspondence, and a phone call has neither a sender
    /// address nor an attachment - narrowing them away would empty the timeline of the
    /// very entries a person wrote by hand. The text field is a question about the
    /// whole pratica, so it does reach them.
    ///
    /// ADR-0076 §D3 (R-06): a message and its anchored entries are one unit. The message
    /// shows when it passes the sender and attachments filters and the text matches it or
    /// any entry anchored to it; its anchored entries show exactly when it does, a
    /// non-matching one included. Free and orphaned entries keep the rule above.
    static func filtered(
        _ entries: [PraticaTimelineEntry], by filter: PraticaTimelineFilter
    ) -> [PraticaTimelineEntry] {
        let hosts = hostVisibility(in: entries, by: filter)
        return entries.filter { entry in
            // An anchored entry handed in without its message (never the case for
            // `ordered`'s output) keeps today's rule rather than vanishing.
            if case let .anchored(messageID) = entry.placement, let host = hosts[messageID] {
                return host.isVisible
            }
            // The owning message follows its unit: an anchored entry the text matches brings it.
            if entry.kind == .message, let messageID = entry.messageID,
               let host = hosts[messageID], host.rowID == entry.id {
                return host.isVisible
            }
            return matchesText(entry, filter.text)
                && matchesSender(entry, filter.sender)
                && matchesAttachments(entry, onlyWithAttachments: filter.attachmentsOnly)
        }
    }

    /// The message that owns a Message-ID, and whether it passes the filter as a unit.
    private struct Host {
        var rowID: String
        var isVisible: Bool
    }

    /// Every owning message, keyed by its Message-ID (R-06). Only the first message carrying
    /// an id owns it, as `PraticaTimelineOrder.arrange` decides. One pass each way:
    /// `filteredTimeline` runs on every body read (ADR-0072 §D7).
    private static func hostVisibility(
        in entries: [PraticaTimelineEntry], by filter: PraticaTimelineFilter
    ) -> [String: Host] {
        var anchoredTextMatches: Set<String> = []
        for entry in entries {
            if case let .anchored(messageID) = entry.placement, matchesText(entry, filter.text) {
                anchoredTextMatches.insert(messageID)
            }
        }
        var hosts: [String: Host] = [:]
        for entry in entries where entry.kind == .message {
            guard let messageID = entry.messageID, hosts[messageID] == nil else { continue }
            hosts[messageID] = Host(
                rowID: entry.id,
                isVisible: matchesSender(entry, filter.sender)
                    && matchesAttachments(entry, onlyWithAttachments: filter.attachmentsOnly)
                    && (matchesText(entry, filter.text) || anchoredTextMatches.contains(messageID))
            )
        }
        return hosts
    }

    private static func matchesText(_ entry: PraticaTimelineEntry, _ text: String) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [entry.subject, entry.senderDisplayName, entry.bodyPreview].contains {
            $0.localizedCaseInsensitiveContains(needle)
        }
    }

    /// Equality against the parsed address (R-32: "addresses, not display names" -
    /// `PraticheController.senderAddresses` offers only addresses, so a substring
    /// match against `senderDisplayName` could match a *different* Mario Rossi's
    /// display name). Falls back to the old substring match on `senderDisplayName`
    /// only when a row carries no parsed address at all, so a message somehow missing
    /// one is not unconditionally hidden.
    private static func matchesSender(_ entry: PraticaTimelineEntry, _ sender: String?) -> Bool {
        guard let sender, !sender.isEmpty else { return true }
        guard entry.kind == .message else { return true }
        if let address = entry.senderAddress {
            return address.localizedCaseInsensitiveCompare(sender) == .orderedSame
        }
        return entry.senderDisplayName.localizedCaseInsensitiveContains(sender)
    }

    private static func matchesAttachments(
        _ entry: PraticaTimelineEntry, onlyWithAttachments: Bool
    ) -> Bool {
        guard onlyWithAttachments, entry.kind == .message else { return true }
        return entry.hasAttachments
    }

    // MARK: - R-25, R-39: lane and direction

    /// A message's lane follows its direction; a manual entry is always `.entry`
    /// (SPEC "Timeline model" Lane paragraph).
    ///
    static func lane(for entry: PraticaTimelineEntry) -> PraticaLane {
        guard entry.kind == .message else { return .entry }
        return entry.direction == .sent ? .sent : .received
    }

    /// Direction is carried by more than colour (R-25: "always redundant"): a glyph,
    /// a label, and the lane's own `ColorToken` (R-39). Never used to draw colour
    /// alone - `surfaceToken(for:)` is what the coder still reads through a token,
    /// this is the accessible-redundancy half.
    ///
    /// The two arrows are the blueprint's own («direction glyph `arrow.down.left` /
    /// `arrow.up.right` beside the time for colour-blind users»); the third is the
    /// pencil the manual-entry row already carries, so the lane and the row agree.
    static func laneGlyph(_ lane: PraticaLane) -> String {
        switch lane {
        case .received: "arrow.down.left"
        case .sent: "arrow.up.right"
        case .entry: "square.and.pencil"
        }
    }

    /// The word beside the glyph, and the first word of a row's composed
    /// accessibility label («Ricevuta, 10 giugno 14:06, Mario Rossi, …»).
    static func laneLabel(_ lane: PraticaLane) -> String {
        switch lane {
        case .received: "Ricevuta"
        case .sent: "Inviata"
        case .entry: "Voce"
        }
    }

    /// The row's surface (R-39): one token per message lane and one per manual-entry kind, so a
    /// note and a call never read as each other or as mail. Every entry but a call is a note.
    static func surfaceToken(for entry: PraticaTimelineEntry) -> ColorToken {
        switch lane(for: entry) {
        case .received: .surfaceReceived
        case .sent: .surfaceSent
        case .entry: entry.kind == .call ? .surfaceEntryCall : .surfaceEntryNote
        }
    }

    // MARK: - R-26: subject link

    /// The subject's click target (SPEC "Timeline model" Subject click paragraph):
    /// a `message://` URL when the message is still in Mail, or `nil` plus a caption
    /// when the ledger marked it «non più in Mail» (R-16).
    ///
    /// Through `MailURL.forMessageID` and never through a second encoding of the same
    /// id (ADR §D9, C5): `EmailHeaders.mailURL` and `MailLink.url(forMessageID:)` both
    /// delegate to it, and a third spelling here is exactly the drift that measurement
    /// closed.
    ///
    /// «non più in Mail» is shown for `isInMail == false` alone - a caption is what the
    /// ledger's `.notInStore` earns, never a failure to locate the `.emlx` (R-16).
    static func subjectLink(messageID: String?, isInMail: Bool) -> (url: URL?, caption: String?) {
        guard isInMail else { return (nil, notInMailCaption) }
        return (MailURL.forMessageID(messageID), nil)
    }

    /// Named once so the row and `Tests/PraticaTimelineTests.swift` read the same
    /// string rather than two copies that can drift apart.
    static let notInMailCaption = "non più in Mail"

    // MARK: - PG-298, ADR-0070 §D2: Backspace's own target

    /// The pure rule behind Backspace («Escludi»): the selected row is the target only
    /// when it is a message the person can currently see. A manual entry (`.note`/
    /// `.call`), no selection, or an id naming no row of `entries` - a row the filter
    /// hides, or another pratica's path - all answer `nil` (R-04).
    ///
    /// `entries` is the caller's `filteredTimeline`, never the unfiltered `timeline`:
    /// a row hidden by the filter must not be excludable by a key the person cannot
    /// see land on it.
    static func deleteKeyTarget(
        selectedID: String?, in entries: [PraticaTimelineEntry]
    ) -> PraticaTimelineEntry? {
        guard let selectedID,
              let entry = entries.first(where: { $0.id == selectedID }),
              entry.kind == .message
        else { return nil }
        return entry
    }

    // MARK: - R-16, ADR-0072 §D7: «Inserisci qui»'s neighbours

    /// Each row's successor in `entries`, keyed by the row's id; the last row has none. One pass
    /// per body, where every row menu used to search the array for its own row. An id that
    /// appears twice keeps its first row's successor, as that search did.
    ///
    /// ADR-0076 §D3: a free entry cannot land between a message and its anchored entries, so a
    /// row whose next row is anchored gets no successor, and the group's last row gets the
    /// next spine row. With no anchored entry this is the map above, unchanged.
    static func nextRows(in entries: [PraticaTimelineEntry]) -> [PraticaTimelineEntry.ID: PraticaTimelineEntry] {
        var next: [PraticaTimelineEntry.ID: PraticaTimelineEntry] = [:]
        var seen: Set<PraticaTimelineEntry.ID> = []
        for index in entries.indices.dropLast() where seen.insert(entries[index].id).inserted {
            let following = entries[index + 1]
            if case .anchored = following.placement { continue }
            next[entries[index].id] = following
        }
        return next
    }

    // MARK: - R-24: expansion (chevron / Opt+click expand-collapse-all)

    /// Per-window expansion state (SPEC "Timeline model" Chevron paragraph):
    /// collapsed by default, never persisted. A pure value type so a view holds it
    /// as `@State`, matching R-24's "lives in the controller for the window's
    /// lifetime" without forcing every timeline test through `PraticheController`.
    struct ExpansionState: Equatable, Sendable {
        private(set) var expandedIDs: Set<String> = []

        init(expandedIDs: Set<String> = []) {
            self.expandedIDs = expandedIDs
        }

        func isExpanded(_ id: String) -> Bool {
            expandedIDs.contains(id)
        }

        /// The chevron's own click: toggles exactly one row.
        mutating func toggle(_ id: String) {
            if expandedIDs.contains(id) {
                expandedIDs.remove(id)
            } else {
                expandedIDs.insert(id)
            }
        }

        /// Opt+click on any chevron (R-24): expands every id when at least one of
        /// `ids` is collapsed, else collapses all of them.
        ///
        /// "At least one collapsed means expand" rather than "the majority wins": with
        /// one row of forty left closed, the gesture a person expects is the one that
        /// opens it, not the one that closes the other thirty-nine.
        ///
        /// Only the ids handed in are touched. The set can hold rows of a pratica that
        /// is no longer on screen - collapsing those too would silently undo the state
        /// of a timeline the person is coming back to.
        mutating func toggleAll(_ ids: [String]) {
            guard !ids.isEmpty else { return }
            if ids.allSatisfy({ expandedIDs.contains($0) }) {
                expandedIDs.subtract(ids)
            } else {
                expandedIDs.formUnion(ids)
            }
        }
    }
}
