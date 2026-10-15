import AppKit

/// The faces and colours the fragments of ADR-0087 draw with, resolved from the theme on the main
/// actor and handed to `EditorDecorationDelegate` as one finished value, the way its other faces and
/// colours are: the delegate is not `@MainActor` and cannot read a `Theme` itself. One value rather
/// than a property per colour, because the delegate's file sits against its length cap.
///
/// The defaults are what an offscreen harness that never pushes a theme draws with; the app
/// overwrites them on every styling pass.
struct EditorConstructStyle: @unchecked Sendable {
    /// A pill's room and corners (§D5).
    var chip = InlineChip.Metrics()
    /// The fence header's language badge (§D6): `font.caption` on `color.surface.sunken`.
    var badgeFont: NSFont = .systemFont(ofSize: 11)
    var badgeText: NSColor = .secondaryLabelColor
    var badgeBackground: NSColor = .quaternaryLabelColor
    /// «N righe» beside the badge, in `color.text.tertiary`.
    var lineCountColor: NSColor = .tertiaryLabelColor
    /// The closing fence line's quiet rule, in `color.border.subtle`.
    var hairline: NSColor = .separatorColor
    /// A quote's bars (§D7), and a neutral callout's bar, symbol and title (§D8).
    var quoteBar: NSColor = .tertiaryLabelColor
    /// A neutral callout's band, `color.surface.sunken`.
    var neutralBand: NSColor = .quaternaryLabelColor
    /// The five type colours, by `CalloutKind.keyword`.
    var calloutColors: [String: NSColor] = [:]
    /// A callout's title: `font.prose`, semibold.
    var calloutTitleFont: NSFont = .systemFont(ofSize: 15, weight: .semibold)
    /// A callout card's corners, `radius.card`.
    var cardRadius: CGFloat = 10

    init() {}

    /// The colour of a callout's bar, symbol and title: its type colour, `color.quote.bar` when neutral.
    func accent(of kind: CalloutKind) -> NSColor {
        kind.colorToken == nil ? quoteBar : calloutColors[kind.keyword] ?? quoteBar
    }

    /// A pending embed's box (§D9): `color.surface.sunken`, its file name in `color.text.tertiary` and
    /// `font.caption`.
    func placeholder(named name: String) -> EmbedPlaceholder.Look {
        EmbedPlaceholder.Look(
            name: name, fill: neutralBand, text: lineCountColor, font: badgeFont, radius: chip.radius
        )
    }

    /// A callout's band: its type colour at `CalloutStyle.backgroundOpacity`, `color.surface.sunken`
    /// when neutral.
    func band(of kind: CalloutKind) -> NSColor {
        guard kind.colorToken != nil, let color = calloutColors[kind.keyword] else { return neutralBand }
        return color.withAlphaComponent(CalloutStyle.backgroundOpacity)
    }

    @MainActor
    init(_ theme: Theme) {
        chip = InlineChip.Metrics(theme)
        badgeFont = theme.nsFont(.caption)
        badgeText = NSColor(theme.color(.textSecondary))
        badgeBackground = NSColor(theme.color(.surfaceSunken))
        lineCountColor = NSColor(theme.color(.textTertiary))
        hairline = NSColor(theme.color(.borderSubtle))
        quoteBar = NSColor(theme.color(.quoteBar))
        neutralBand = NSColor(theme.color(.surfaceSunken))
        let kinds: [CalloutKind] = [.note, .tip, .important, .warning, .caution]
        for kind in kinds {
            if let token = kind.colorToken { calloutColors[kind.keyword] = NSColor(theme.color(token)) }
        }
        let prose = ProseTypography.prose(theme)
        let semibold = prose.fontDescriptor.addingAttributes(
            [.traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.semibold]]
        )
        calloutTitleFont = NSFont(descriptor: semibold, size: prose.pointSize) ?? prose
        cardRadius = theme.radius(.card)
    }
}
