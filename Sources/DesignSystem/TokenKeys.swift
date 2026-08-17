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

    case stickyYellow = "color.sticky.yellow"
    case stickyGreen = "color.sticky.green"
    case stickyBlue = "color.sticky.blue"
    case stickyPink = "color.sticky.pink"
    case stickyGrey = "color.sticky.grey"

    var path: String { rawValue }
}

enum FontToken: String, TokenKey {
    case title = "font.title"
    case heading = "font.heading"
    case body = "font.body"
    case caption = "font.caption"
    case mono = "font.mono"

    var path: String { rawValue }
}

enum SpacingToken: String, TokenKey {
    case xs = "spacing.xs"
    case s = "spacing.s"
    case m = "spacing.m"
    case l = "spacing.l"
    case xl = "spacing.xl"

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
