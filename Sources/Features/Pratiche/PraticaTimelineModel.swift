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
//
// Every function below is a tester-declared boundary (ADR-0155 §D1): stubbed to a
// wrong-but-safe constant or a pass-through, never `fatalError`, so a test that calls
// one exercises a real (failing) assertion instead of crashing the process.

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
    var subject: String
    var bodyPreview: String
    var hasAttachments: Bool
    /// `pergamenum-mail-message-id`, present only for `.kind == .message`.
    var messageID: String?
    /// Whether the ledger still finds this message in Mail (R-26/R-16's "non più in
    /// Mail" caption). Irrelevant for a manual entry.
    var isInMail: Bool
}

/// Where a row sits and how it is coloured (SPEC "Timeline model" Lane paragraph,
/// DESIGN.md "Binding decisions"): `received` left, `sent` right, `entry` full width.
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
    /// The id breaks a tie, so two messages carrying the same header second (an
    /// Exchange conversation sent to several mailboxes at once produces them) keep one
    /// stable order across reloads instead of swapping places under the reader.
    static func ordered(_ entries: [PraticaTimelineEntry]) -> [PraticaTimelineEntry] {
        entries.sorted { left, right in
            left.date == right.date ? left.id < right.id : left.date < right.date
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
    static func filtered(
        _ entries: [PraticaTimelineEntry], by filter: PraticaTimelineFilter
    ) -> [PraticaTimelineEntry] {
        entries.filter { entry in
            matchesText(entry, filter.text)
                && matchesSender(entry, filter.sender)
                && matchesAttachments(entry, onlyWithAttachments: filter.attachmentsOnly)
        }
    }

    private static func matchesText(_ entry: PraticaTimelineEntry, _ text: String) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [entry.subject, entry.senderDisplayName, entry.bodyPreview].contains {
            $0.localizedCaseInsensitiveContains(needle)
        }
    }

    /// A substring match rather than an equality one: the menu offers addresses, and
    /// what a row carries is the display name Mail put on the header
    /// (`"Mario Rossi <m.rossi@rossi-spa.it>"` as often as the bare address).
    private static func matchesSender(_ entry: PraticaTimelineEntry, _ sender: String?) -> Bool {
        guard let sender, !sender.isEmpty else { return true }
        guard entry.kind == .message else { return true }
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
    /// alone - `laneColorToken(_:)` is what the coder still reads through a token,
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

    /// The three tokens declared in `Sources/DesignSystem/TokenKeys.swift`
    /// (`.surfaceReceived`/`.surfaceSent`/`.surfaceEntry`, R-39).
    static func laneColorToken(_ lane: PraticaLane) -> ColorToken {
        switch lane {
        case .received: .surfaceReceived
        case .sent: .surfaceSent
        case .entry: .surfaceEntry
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
