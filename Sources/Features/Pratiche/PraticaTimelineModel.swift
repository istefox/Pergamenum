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
    /// Stubbed to the primary date alone, ignoring the fallback - wrong whenever
    /// `frontmatter.date == .distantPast` and `frontmatter.received` is not `nil`.
    static func sortDate(of frontmatter: MessageDocument.MailFrontmatter) -> Date {
        frontmatter.date
    }

    /// Interleaves messages and manual entries by `date`, ascending (R-23): the
    /// oldest entry first, so a view scrolls to the *end* of this array to land on
    /// the newest, matching SPEC "Timeline model"'s "the view scrolls to the bottom
    /// (newest) on open".
    ///
    /// Stubbed as a pass-through - wrong whenever the input is not already sorted.
    static func ordered(_ entries: [PraticaTimelineEntry]) -> [PraticaTimelineEntry] {
        entries
    }

    // MARK: - R-32: filters

    /// Text narrows subject/sender/body of every row, case-insensitively, and is the
    /// only filter allowed to hide a manual entry (R-32: "manual entries are hidden
    /// only by the text filter"). Sender and «Solo con allegati» apply to messages
    /// only and never remove a `.note`/`.call` row.
    ///
    /// Stubbed as a pass-through - wrong whenever any of the three filters is active.
    static func filtered(_ entries: [PraticaTimelineEntry], by filter: PraticaTimelineFilter) -> [PraticaTimelineEntry] {
        entries
    }

    // MARK: - R-25, R-39: lane and direction

    /// A message's lane follows its direction; a manual entry is always `.entry`
    /// (SPEC "Timeline model" Lane paragraph).
    ///
    /// Stubbed to always answer `.entry` - wrong for every `.message` entry.
    static func lane(for entry: PraticaTimelineEntry) -> PraticaLane {
        .entry
    }

    /// Direction is carried by more than colour (R-25: "always redundant"): a glyph,
    /// a label, and the lane's own `ColorToken` (R-39). Never used to draw colour
    /// alone - `laneColorToken(_:)` is what the coder still reads through a token,
    /// this is the accessible-redundancy half.
    ///
    /// Stubbed to the empty string - wrong for every lane.
    static func laneGlyph(_ lane: PraticaLane) -> String {
        ""
    }

    /// Stubbed to the empty string - wrong for every lane.
    static func laneLabel(_ lane: PraticaLane) -> String {
        ""
    }

    /// The three tokens declared in `Sources/DesignSystem/TokenKeys.swift`
    /// (`.surfaceReceived`/`.surfaceSent`/`.surfaceEntry`, R-39).
    ///
    /// Stubbed to `.surfaceReceived` for every lane - wrong for `.sent`/`.entry`.
    static func laneColorToken(_ lane: PraticaLane) -> ColorToken {
        .surfaceReceived
    }

    // MARK: - R-26: subject link

    /// The subject's click target (SPEC "Timeline model" Subject click paragraph):
    /// a `message://` URL when the message is still in Mail, or `nil` plus a caption
    /// when the ledger marked it «non più in Mail» (R-16).
    ///
    /// Stubbed to `(nil, nil)` regardless of input - wrong for both branches.
    static func subjectLink(messageID: String?, isInMail: Bool) -> (url: URL?, caption: String?) {
        (nil, nil)
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
        ///
        /// Stubbed as a no-op - wrong for every id.
        mutating func toggle(_ id: String) {
        }

        /// Opt+click on any chevron (R-24): expands every id when at least one of
        /// `ids` is collapsed, else collapses all of them.
        ///
        /// Stubbed as a no-op - wrong for every non-empty `ids`.
        mutating func toggleAll(_ ids: [String]) {
        }
    }
}
