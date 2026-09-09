import Foundation

/// Whether the editor checks spelling, and in which language (M8).
///
/// A property of the notes folder rather than of the user: a vault written in Italian
/// stays Italian when it is opened on another Mac, which is the same reasoning that puts
/// the daily folder here and the theme in `UserDefaults`.
enum SpellCheck: Hashable, Sendable, Codable {
    case off
    /// `NSSpellChecker` identifies the language of each passage on its own. The default
    /// once the checker is turned on, because a note that quotes an English paragraph is
    /// the ordinary case in this vault and a fixed language would underline all of it.
    case automatic
    /// One identifier from `NSSpellChecker.availableLanguages`, such as `it_IT`.
    case language(String)

    var isEnabled: Bool { self != .off }

    /// The language to hand `NSSpellChecker`, or nil when it should identify one itself.
    var fixedLanguage: String? {
        if case let .language(identifier) = self { return identifier }
        return nil
    }

    private static let offKeyword = "off"
    private static let automaticKeyword = "auto"

    /// Encoded as a bare string - `"off"`, `"auto"`, `"it_IT"` - so `settings.json` stays
    /// something a person can edit (principle 1). Anything else read back means `.off`
    /// rather than a throw: one unrecognised word must not cost the whole file, which is
    /// the contract `VaultSettings.init(from:)` keeps for every other key.
    init(from decoder: any Decoder) throws {
        let keyword = try decoder.singleValueContainer().decode(String.self)
        switch keyword {
        case SpellCheck.offKeyword, "": self = .off
        case SpellCheck.automaticKeyword: self = .automatic
        default: self = .language(keyword)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .off: try container.encode(SpellCheck.offKeyword)
        case .automatic: try container.encode(SpellCheck.automaticKeyword)
        case let .language(identifier): try container.encode(identifier)
        }
    }
}

/// The per-vault settings stored in `.pergamenum/settings.json`.
///
/// They live in the vault rather than in `UserDefaults` because they describe the
/// vault: opening the same folder on another Mac must find the same daily folder,
/// and a vault copied to a colleague carries its own configuration.
struct VaultSettings: Codable, Equatable, Sendable {
    /// Folder holding the `YYYYMMDD.md` daily notes, relative to the vault root.
    var dailyFolder: String
    /// Folder holding the `YYYYMMDD.md` diary notes, relative to the vault root.
    ///
    /// Its own folder rather than the daily one: the daily note is what has to be done
    /// and the diary is what was actually done, and a day that is both leaves neither
    /// readable. Set to the same value as `dailyFolder` they share one file, which
    /// still works - the diary owns its section and nothing else.
    var diaryFolder: String
    /// Where the `harness-system` checkout lives, for "Importa convenzioni…".
    /// Absolute, and absent until the user points at it.
    var harnessRepositoryPath: String?
    /// Copy a dropped file into the vault, or reference it where it lies.
    var copyDroppedFiles: Bool
    /// Whether the Workspace draws its grid (SPEC §12, "Canvas").
    var boardShowsGrid: Bool
    /// Whether cards land on that grid when nothing else aligns them.
    var boardSnapsToGrid: Bool
    /// How long a time block lasts when the app makes one (SPEC §8.3 puts the default
    /// at 30 minutes; this is that default, made settable).
    var blockMinutes: Int
    /// The hours the Oggi pane's timeline draws.
    var dayHours: HourWindow
    /// The hours the Diario pane's timeline draws. Its own setting rather than one
    /// shared with the day view: the two panes are about different parts of a day, and
    /// a single number would make one of them wrong.
    var diaryHours: HourWindow
    /// Whether the editor underlines misspellings, and in which language (M8).
    var spellCheck: SpellCheck
    /// Whether the editor hides a heading's `#` marker (and the space after it) while the
    /// caret is elsewhere, redrawing it the instant the caret's paragraph, a selection, an
    /// IME composition or the find bar's current match touches that line (ADR-0018 §D1).
    /// On by default and fully reversible: the characters are never removed from the file,
    /// only what is drawn changes, so turning this off is a toggle rather than a revert.
    var hidesMarkup: Bool
    /// Whether the editor's text column is capped to a readable width and centred, rather
    /// than filling the whole pane (ADR-0030 §D6). On by default, following the same
    /// reasoning `hidesMarkup` gives: a page that reads like a code buffer at full window
    /// width is the thing this chain exists to fix, so the improved behaviour is what a
    /// vault gets until someone turns it off in Impostazioni.
    var readableWidth: Bool
    /// Whether emphasis, strikethrough and link markers reveal at the word they belong
    /// to, rather than the whole paragraph, while the caret is inside them (ADR-0037 §D7).
    /// **Off by default**: this narrows a rule ADR-0018 §D2 already shipped and settled,
    /// and a ruling that has to be reverted in code if the reveal does not convince is a
    /// ruling nobody tests honestly - the same reasoning `hidesMarkup` was given. It is
    /// also meaningless while `hidesMarkup` itself is off, since nothing is hidden to
    /// narrow the reveal of.
    var revealsInlineSpans: Bool
    /// Whether the day surfaces the unfinished tasks of the days before it (ADR-0013 §D1).
    ///
    /// **Off by default, and it shows rather than moves.** SPEC §7.3 rejects rollover outright
    /// and the amendment is narrow on purpose: a rolled-over task is a task whose `>date` still
    /// says Monday, drawn on Thursday with Monday written beside it. Nothing is rewritten, no
    /// second date is stored, and deleting `.pergamenum/` changes nothing about it.
    ///
    /// Per-vault rather than per-user, on the same reasoning as `blockMinutes`: whether a
    /// vault's unfinished tasks should follow you is a fact about how that vault is kept.
    var rollover: Bool
    /// How many days back the rollover looks.
    ///
    /// A number somebody has to choose, and a default of "all of them" would turn a quiet week
    /// into a list nobody reads. A week, because that is the unit the rest of M12 is about.
    var rolloverDays: Int

    /// The local patron saint's day, which the calendar draws as a holiday.
    ///
    /// Empty until somebody fills it in: the national holidays are computed
    /// (`ItalianHolidays`), and this is the one day no algorithm knows.
    var patronSaint: PatronSaint?

    /// This vault's identity, minted as a UUID the first time it is opened and
    /// written back through `updateSettings` (ADR-0017 §D2). Names the directory
    /// under `~/Library/Application Support/it.stefer.pergamenum/vaults/` where the
    /// derived stores this ADR moves out of the vault live.
    ///
    /// A path was rejected as the identifier: renaming the vault's folder in the
    /// Finder would silently orphan every derived store keyed on it.
    var vaultID: String?

    /// Named so the memberwise initialiser can default to it without repeating the
    /// string in every test that builds settings by hand.
    static let defaultDiaryFolder = "Diario"

    static let `default` = VaultSettings(
        dailyFolder: "Calendar",
        diaryFolder: VaultSettings.defaultDiaryFolder,
        harnessRepositoryPath: nil,
        copyDroppedFiles: true,
        boardShowsGrid: true,
        boardSnapsToGrid: false,
        blockMinutes: TimeBlock.defaultDuration,
        dayHours: .dayDefault,
        diaryHours: .diaryDefault,
        // Off, so that updating the app does not fill a vault of markdown with red
        // underlines nobody asked for. It is found in Impostazioni, not on first launch.
        spellCheck: .off,
        hidesMarkup: true,
        readableWidth: true,
        revealsInlineSpans: false,
        rollover: false,
        rolloverDays: VaultSettings.defaultRolloverDays,
        patronSaint: nil
    )

    /// A week back, which is the unit M12 is about.
    static let defaultRolloverDays = 7
    /// What the setting offers, in days.
    static let rolloverWindows = [1, 2, 3, 7, 14, 30]

    /// The durations the settings offer, in minutes.
    static let blockDurations = [15, 30, 45, 60, 90, 120]

    /// Decoded key by key, each falling back to its default.
    ///
    /// The synthesised initialiser would reject a `settings.json` written before a
    /// key existed, and the whole file would be discarded for one missing line: a
    /// vault would silently lose its daily folder the first time this struct grows.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = VaultSettings.default
        dailyFolder = try container.decodeIfPresent(String.self, forKey: .dailyFolder)
            ?? fallback.dailyFolder
        diaryFolder = try container.decodeIfPresent(String.self, forKey: .diaryFolder)
            ?? fallback.diaryFolder
        harnessRepositoryPath = try container.decodeIfPresent(String.self, forKey: .harnessRepositoryPath)
        copyDroppedFiles = try container.decodeIfPresent(Bool.self, forKey: .copyDroppedFiles)
            ?? fallback.copyDroppedFiles
        boardShowsGrid = try container.decodeIfPresent(Bool.self, forKey: .boardShowsGrid)
            ?? fallback.boardShowsGrid
        boardSnapsToGrid = try container.decodeIfPresent(Bool.self, forKey: .boardSnapsToGrid)
            ?? fallback.boardSnapsToGrid
        // Clamped as well as defaulted: a hand-edited settings.json holding 0 would
        // make every block zero minutes long and every one of them invisible.
        let minutes = try container.decodeIfPresent(Int.self, forKey: .blockMinutes)
            ?? fallback.blockMinutes
        blockMinutes = min(max(minutes, 5), 480)
        // Clamped on the way in, since `settings.json` is meant to be edited by hand
        // and a window that runs backwards would draw a grid of negative height.
        dayHours = (try container.decodeIfPresent(HourWindow.self, forKey: .dayHours)
            ?? fallback.dayHours).clamped
        diaryHours = (try container.decodeIfPresent(HourWindow.self, forKey: .diaryHours)
            ?? fallback.diaryHours).clamped
        spellCheck = try container.decodeIfPresent(SpellCheck.self, forKey: .spellCheck)
            ?? fallback.spellCheck
        hidesMarkup = try container.decodeIfPresent(Bool.self, forKey: .hidesMarkup) ?? fallback.hidesMarkup
        readableWidth = try container.decodeIfPresent(Bool.self, forKey: .readableWidth)
            ?? fallback.readableWidth
        revealsInlineSpans = try container.decodeIfPresent(Bool.self, forKey: .revealsInlineSpans)
            ?? fallback.revealsInlineSpans
        rollover = try container.decodeIfPresent(Bool.self, forKey: .rollover) ?? fallback.rollover
        // Clamped like `blockMinutes`, and for the same reason: this file is meant to be edited
        // by hand, and a 0 there would make the setting look on and show nothing.
        let days = try container.decodeIfPresent(Int.self, forKey: .rolloverDays)
            ?? fallback.rolloverDays
        rolloverDays = min(max(days, 1), 60)
        // Rejected rather than clamped when the date does not exist: a patron on the
        // 31st of February is a typo, and inventing the 28th for it would hide it.
        let saint = try container.decodeIfPresent(PatronSaint.self, forKey: .patronSaint)
        patronSaint = saint.flatMap { candidate in
            CalendarDate(year: 2000, month: candidate.month, day: candidate.day) == nil
                ? nil
                : candidate
        }
        vaultID = try container.decodeIfPresent(String.self, forKey: .vaultID)
    }

    init(
        dailyFolder: String,
        diaryFolder: String = VaultSettings.defaultDiaryFolder,
        harnessRepositoryPath: String?,
        copyDroppedFiles: Bool,
        boardShowsGrid: Bool,
        boardSnapsToGrid: Bool,
        blockMinutes: Int = TimeBlock.defaultDuration,
        dayHours: HourWindow = .dayDefault,
        diaryHours: HourWindow = .diaryDefault,
        spellCheck: SpellCheck = .off,
        hidesMarkup: Bool = true,
        readableWidth: Bool = true,
        revealsInlineSpans: Bool = false,
        rollover: Bool = false,
        rolloverDays: Int = VaultSettings.defaultRolloverDays,
        patronSaint: PatronSaint? = nil,
        vaultID: String? = nil
    ) {
        self.dailyFolder = dailyFolder
        self.diaryFolder = diaryFolder
        self.harnessRepositoryPath = harnessRepositoryPath
        self.copyDroppedFiles = copyDroppedFiles
        self.boardShowsGrid = boardShowsGrid
        self.boardSnapsToGrid = boardSnapsToGrid
        self.blockMinutes = blockMinutes
        self.dayHours = dayHours
        self.diaryHours = diaryHours
        self.spellCheck = spellCheck
        self.hidesMarkup = hidesMarkup
        self.readableWidth = readableWidth
        self.revealsInlineSpans = revealsInlineSpans
        self.rollover = rollover
        self.rolloverDays = rolloverDays
        self.patronSaint = patronSaint
        self.vaultID = vaultID
    }
}

/// The app's private directory inside the vault, and the file names in it.
///
/// `thumbnails/` and `cache.db` used to live here too; ADR-0017 moves both beside the
/// vault instead, and their names now live on `VaultState`.
enum VaultLayout {
    static let privateDirectory = ".pergamenum"
    static let settingsFile = "settings.json"
    static let vocabularyFile = "vocabolari.json"
    static let themesDirectory = "themes"
    /// The starred notes of ADR-0012 D6. In the vault because starring describes the notes and
    /// travels with them; the open tabs describe this machine and stay in `UserDefaults`.
    static let starredFile = "starred.json"

    /// Directory names never scanned for notes.
    ///
    /// `.pergamenum` is ours, `.obsidian` and `.trash` belong to Obsidian, and any
    /// other dot-directory is somebody's tooling. Indexing `.git` on a vault kept
    /// under version control would be both slow and wrong.
    static func isExcludedDirectory(_ name: String) -> Bool {
        name.hasPrefix(".")
    }
}
