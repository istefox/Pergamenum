import Foundation

/// Every design token the app is allowed to reference, keyed by its DTCG path.
///
/// The enums are the whole contract between the theme files and the views: a view
/// asks for `.textPrimary`, never for a colour literal and never for a string path.
/// Because they are `CaseIterable`, a theme can be checked for completeness at load
/// time rather than discovering a missing token when a view renders (ADR-0001 §D4).
protocol TokenKey: CaseIterable, Hashable, Sendable {
    /// Dot-separated path into the DTCG document, e.g. `color.text.primary`.
    var path: String { get }
}

enum ColorToken: String, TokenKey {
    case backgroundPrimary = "color.background.primary"
    case backgroundSecondary = "color.background.secondary"
    case backgroundTertiary = "color.background.tertiary"

    case surfaceCard = "color.surface.card"
    case surfaceRaised = "color.surface.raised"
    case surfaceSunken = "color.surface.sunken"

    // ADR-0036 (Pratiche) §D16, DESIGN.md "Binding decisions": the timeline's surface
    // tokens - `received` (neutral grey), `sent` (cool tint), and one per manual entry
    // kind: `entryNote` (amber, a sticky note) and `entryCall` (green, a phone), so a note
    // and a call never read as each other or as part of the mail around them (hand check
    // round 5). Direction is always redundant (glyph + alignment + colour), never colour
    // alone (R-25, R-39). `entry`, the single warm tint the timeline used before, stays for
    // the Contenitore inspector.
    case surfaceReceived = "color.surface.received"
    case surfaceSent = "color.surface.sent"
    case surfaceEntry = "color.surface.entry"
    case surfaceEntryNote = "color.surface.entryNote"
    case surfaceEntryCall = "color.surface.entryCall"

    // ADR-0079 §D6 (PG-369): the rail that ties an anchored entry to its message, one per
    // message lane, a stronger tone of `surface.received`/`surface.sent`, at least 3:1 on
    // `background.primary` (WCAG 2 non-text contrast).
    case railReceived = "color.rail.received"
    case railSent = "color.rail.sent"

    case borderSubtle = "color.border.subtle"
    case borderStrong = "color.border.strong"

    case textPrimary = "color.text.primary"
    case textSecondary = "color.text.secondary"
    case textTertiary = "color.text.tertiary"
    case textInverted = "color.text.inverted"

    case accentPrimary = "color.accent.primary"
    case accentMuted = "color.accent.muted"
    case onAccent = "color.accent.onAccent"

    case canvasBackground = "color.canvas.background"
    case canvasGrid = "color.canvas.grid"
    case canvasSelection = "color.canvas.selection"

    case taskOpen = "color.task.open"
    case taskDone = "color.task.done"
    case taskScheduled = "color.task.scheduled"
    case taskOverdue = "color.task.overdue"
    case taskCancelled = "color.task.cancelled"

    // The five roles a code fence is coloured by (M8). Five and not more: a grammar this
    // small cannot tell a class from a protocol, and a token nobody can fill honestly is a
    // colour that lies.
    case codeKeyword = "color.code.keyword"
    case codeString = "color.code.string"
    case codeComment = "color.code.comment"
    case codeNumber = "color.code.number"
    case codeType = "color.code.type"

    // The Italian calendar's red days (M12). Three and not one: a Saturday coloured
    // like Christmas says nothing, and telling the two apart is the whole reason the
    // colour was asked for.
    case calendarPrefestive = "color.calendar.prefestive"
    case calendarFestive = "color.calendar.festive"
    case calendarHoliday = "color.calendar.holiday"

    case stickyYellow = "color.sticky.yellow"
    case stickyGreen = "color.sticky.green"
    case stickyBlue = "color.sticky.blue"
    case stickyPink = "color.sticky.pink"
    case stickyGrey = "color.sticky.grey"
    // One token per entry of the sticky colour menu (PG-255, #569 point 10): with five
    // tokens for six JSON Canvas presets, red and orange drew alike and purple drew grey.
    case stickyOrange = "color.sticky.orange"
    case stickyPurple = "color.sticky.purple"

    // A category's own palette, saturated for an 8pt dot rather than a card
    // background - distinct from `sticky*` above on purpose (CategoryColor.swift).
    case categoryYellow = "color.category.yellow"
    case categoryGreen = "color.category.green"
    case categoryBlue = "color.category.blue"
    case categoryPink = "color.category.pink"
    case categoryGrey = "color.category.grey"

    var path: String { rawValue }
}

enum FontToken: String, TokenKey {
    case title = "font.title"
    case heading = "font.heading"
    case body = "font.body"
    case caption = "font.caption"
    case mono = "font.mono"

    // The page faces (ADR-0030): a named family (Avenir Next), read by
    // `ProseTypography`, never by the eleven chrome call sites that still use
    // `.title`/`.body` above.
    case prose = "font.prose"
    case proseTitle = "font.proseTitle"

    // Glyph sizes for SF Symbols inside controls, not text faces: a chevron, a
    // calendar mark, a badge dot. Never customizable (`ThemeCustomization
    // .customizableFonts` stays the two page faces). `iconSmall` is what
    // `.caption2` resolves to on macOS (10 pt, medium); `iconBadge` replaces
    // `.system(size: 7)`; `iconDisplay` is the one size of the large glyph
    // above an empty state (it replaced 26, 32 and 40 pt).
    case iconSmall = "font.icon.small"
    case iconBadge = "font.icon.badge"
    case iconDisplay = "font.icon.display"

    // The small caption an AppKit control group carries beside its buttons (the
    // table grid's «Riga»/«Colonna»): system 9 pt semibold, the value
    // `TableGridView` used to name by hand. Never customizable either.
    case controlLabel = "font.control.label"

    var path: String { rawValue }

    /// Whether this token sizes an SF Symbol rather than setting a text face.
    var isGlyphSize: Bool { path.hasPrefix("font.icon.") }
}

enum SpacingToken: String, TokenKey {
    case xs = "spacing.xs"
    case s = "spacing.s"
    case m = "spacing.m"
    case l = "spacing.l"
    case xl = "spacing.xl"

    // The editor's readable-width column (ADR-0030 §D7): 720pt, the horizontal
    // inset a text container clamps to rather than tracking the whole window.
    case readable = "spacing.readable"

    // The gap after a prose or heading paragraph in the note editor (n1-seams R-14), 8 in both
    // bundled themes. Its `Theme.emergency` entry is load-bearing: a case without one traps at
    // `theme.spacing(_:)` (PG-225).
    case paragraph = "spacing.paragraph"

    // The band of the text column reserved for block markers (ADR-0081 §D1): 48, which is
    // `spacing.xl` plus `spacing.s` (G1, 2026-10-07). Its `Theme.emergency` entry is load-bearing
    // for the same reason `paragraph`'s is (PG-225).
    case gutter = "spacing.gutter"

    var path: String { rawValue }
}

enum RadiusToken: String, TokenKey {
    case card = "radius.card"
    case control = "radius.control"
    case sticky = "radius.sticky"

    var path: String { rawValue }
}

enum ShadowToken: String, TokenKey {
    case card = "shadow.card"
    case raised = "shadow.raised"

    var path: String { rawValue }
}
