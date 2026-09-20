import AppKit
import SwiftUI

/// A fully resolved theme: every token the app can ask for has a value.
///
/// Resolution happens once, at load time, so a view's token lookup is a dictionary
/// hit that cannot fail. That totality is what makes the "no colour outside the
/// token system" rule enforceable rather than aspirational (ADR-0001 §D4): there is
/// no optional to unwrap and therefore no reason for a view to reach for a literal.
struct Theme: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let appearance: ThemeAppearance

    private let colors: [ColorToken: RGBA]
    private let fonts: [FontToken: TypographyValue]
    private let spacings: [SpacingToken: CGFloat]
    private let radii: [RadiusToken: CGFloat]
    private let shadows: [ShadowToken: ShadowValue]

    /// Tokens the source file did not define, filled in from the inherited theme.
    /// Empty for the bundled themes - a test asserts that.
    let inheritedTokens: [String]
    /// Parse problems carried over from the document, for the settings UI to show.
    let problems: [String]

    // MARK: Lookup

    func color(_ token: ColorToken) -> Color {
        let rgba = rawColor(token)
        return Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    /// The same colour as the token file holds it, for the parts of the app that
    /// write tokens rather than draw with them: a colour well has to open on the
    /// stored value and a customisation has to be saved back as hex.
    func rawColor(_ token: ColorToken) -> RGBA {
        colors[token] ?? Theme.emergency.colors[token]!
    }

    func font(_ token: FontToken) -> Font {
        let value = fonts[token] ?? Theme.emergency.fonts[token]!
        guard case .named(let family) = value.family else {
            return Font.system(size: value.size, weight: value.weight.asFontWeight, design: value.family.asDesign)
        }
        // ADR-0030 §D3: probe the family with AppKit and hand SwiftUI the resolved
        // *PostScript* name (`AvenirNext-Bold`, not `Avenir Next`). `Font.custom` on a
        // name it cannot find substitutes a different face and reports nothing, so the
        // two surfaces would draw two faces from one token; going through the same
        // resolver `nsFont(_:)` uses is what keeps the fallback explicit.
        guard let resolved = Theme.namedFont(family, value) else {
            return Font.system(size: value.size, weight: value.weight.asFontWeight)
        }
        return Font.custom(resolved.fontName, size: value.size)
    }

    /// The same face as `font(_:)`, for the AppKit views the app bridges to.
    ///
    /// Without it a bridged control would have to name a size and a weight of its own,
    /// which is the hardcoding the token system exists to prevent - the rule is about
    /// where the value comes from, not about which framework draws it.
    func nsFont(_ token: FontToken) -> NSFont {
        let value = fonts[token] ?? Theme.emergency.fonts[token]!
        let weight = value.weight.asNSFontWeight
        switch value.family {
        case .monospace:
            return NSFont.monospacedSystemFont(ofSize: value.size, weight: weight)
        case .serif:
            let system = NSFont.systemFont(ofSize: value.size, weight: weight)
            let descriptor = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
            return NSFont(descriptor: descriptor, size: value.size) ?? system
        case .system:
            return NSFont.systemFont(ofSize: value.size, weight: weight)
        case .named(let family):
            // A family nobody installed is not an error worth shouting about: the page
            // degrades to the system face at the token's own size and weight, which is
            // what SPEC §8 means by an explicit fallback (ADR-0030 §D3).
            return Theme.namedFont(family, value) ?? NSFont.systemFont(ofSize: value.size, weight: weight)
        }
    }

    /// The face a named family resolves to, or `nil` when the family is not installed.
    ///
    /// Shared by `nsFont(_:)` and `font(_:)` on purpose: two independent resolutions of
    /// one token are two faces waiting to disagree.
    ///
    /// Bold comes from the *symbolic* trait and the weight is read as one `>= 600` step,
    /// never as the nine-stop weight map the other families use. Measured (ADR-0030
    /// §Context): `descriptor.addingAttributes([.traits: [.weight: .bold]])` returns
    /// `AvenirNext-Regular` and reports nothing. A family ships whatever weights it
    /// ships; the bold trait is the only axis AppKit reaches reliably on an arbitrary
    /// one, so a token declaring 700 gets the bold face and one declaring 500 gets the
    /// regular face - stated rather than pretended otherwise.
    private static func namedFont(_ family: String, _ value: TypographyValue) -> NSFont? {
        guard let base = NSFont(name: family, size: value.size) else { return nil }
        guard value.weight >= 600 else { return base }
        let bold = base.fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: bold, size: value.size) ?? base
    }

    /// The AppKit face `font(_:)`'s SwiftUI value is meant to match - same resolution
    /// `nsFont(_:)` uses, so the two surfaces never draw two different faces for one
    /// token (ADR-0030 §D3). Exists so a test can pin that equivalence down without
    /// reaching into SwiftUI's opaque `Font`.
    ///
    /// Reading `nsFont(_:)` is not an approximation of what `font(_:)` does: for a named
    /// family `font(_:)` passes `Font.custom` exactly this name, and for the other three
    /// families both calls describe the same system face.
    func resolvedFontName(_ token: FontToken) -> String {
        nsFont(token).fontName
    }

    /// SwiftUI takes spacing *between* lines, while DTCG expresses a multiple of the
    /// font size, so the conversion subtracts the size the glyphs already occupy.
    func lineSpacing(_ token: FontToken) -> CGFloat {
        let value = fonts[token] ?? Theme.emergency.fonts[token]!
        return max(0, value.size * CGFloat(value.lineHeight - 1))
    }

    func spacing(_ token: SpacingToken) -> CGFloat {
        spacings[token] ?? Theme.emergency.spacings[token]!
    }

    func radius(_ token: RadiusToken) -> CGFloat {
        radii[token] ?? Theme.emergency.radii[token]!
    }

    func shadow(_ token: ShadowToken) -> ShadowValue {
        shadows[token] ?? Theme.emergency.shadows[token]!
    }

    // MARK: Resolution

    /// Builds a theme from a parsed document, filling anything the document omits
    /// from `inherited`. A user theme in `.pergamenum/themes/` can therefore define
    /// only the tokens it wants to change.
    init(document: DesignTokenDocument, id: String, inheriting inherited: Theme) {
        self.id = id
        name = document.name
        appearance = document.appearance
        problems = document.problems

        var missing: [String] = []
        colors = Theme.resolve(document, inherited.colors, &missing) {
            if case .color(let value) = $0 { return value } else { return nil }
        }
        fonts = Theme.resolve(document, inherited.fonts, &missing) {
            if case .typography(let value) = $0 { return value } else { return nil }
        }
        spacings = Theme.resolve(document, inherited.spacings, &missing) {
            if case .dimension(let value) = $0 { return value } else { return nil }
        }
        radii = Theme.resolve(document, inherited.radii, &missing) {
            if case .dimension(let value) = $0 { return value } else { return nil }
        }
        shadows = Theme.resolve(document, inherited.shadows, &missing) {
            if case .shadow(let value) = $0 { return value } else { return nil }
        }
        inheritedTokens = missing.sorted()
    }

    private init(
        id: String,
        name: String,
        appearance: ThemeAppearance,
        colors: [ColorToken: RGBA],
        fonts: [FontToken: TypographyValue],
        spacings: [SpacingToken: CGFloat],
        radii: [RadiusToken: CGFloat],
        shadows: [ShadowToken: ShadowValue]
    ) {
        self.id = id
        self.name = name
        self.appearance = appearance
        self.colors = colors
        self.fonts = fonts
        self.spacings = spacings
        self.radii = radii
        self.shadows = shadows
        inheritedTokens = []
        problems = []
    }

    private static func resolve<Key: TokenKey, Value>(
        _ document: DesignTokenDocument,
        _ inherited: [Key: Value],
        _ missing: inout [String],
        _ extract: (TokenValue) -> Value?
    ) -> [Key: Value] {
        var resolved: [Key: Value] = [:]
        for key in Key.allCases {
            if let raw = document.tokens[key.path], let value = extract(raw) {
                resolved[key] = value
            } else {
                if document.tokens[key.path] != nil {
                    missing.append("\(key.path) (wrong type)")
                } else {
                    missing.append(key.path)
                }
                resolved[key] = inherited[key]
            }
        }
        return resolved
    }
}

extension Theme {
    /// The hex spelling of a colour token.
    ///
    /// Drawings are stored as SVG, which needs a literal colour: a token reference
    /// would not survive outside the app, and the file has to render in Obsidian.
    func hexValue(_ token: ColorToken) -> String {
        let rgba = colors[token] ?? Theme.emergency.colors[token]!
        return String(
            format: "#%02X%02X%02X",
            Int((rgba.red * 255).rounded()),
            Int((rgba.green * 255).rounded()),
            Int((rgba.blue * 255).rounded())
        )
    }
}

extension Color {
    /// Builds a colour from a hex string, falling back to grey so a malformed value
    /// in a hand-edited SVG cannot make a stroke invisible.
    init(hex: String) {
        let rgba = RGBA(hex: hex) ?? RGBA(hex: "#808080")!
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

// MARK: - Emergency theme

extension Theme {
    /// The last-resort theme, defined in code rather than in a token file.
    ///
    /// It is never offered to the user and never appears in Settings. It exists so
    /// that a missing or corrupt bundled resource degrades to a plain, readable
    /// window with a visible error instead of an unrenderable app. Reaching it means
    /// the build is broken, which is why a test asserts the bundled themes resolve
    /// without touching it.
    static let emergency = Theme(
        id: "emergency",
        name: "Fallback",
        appearance: .light,
        colors: [
            .backgroundPrimary: RGBA(hex: "#FFFFFF")!,
            .backgroundSecondary: RGBA(hex: "#F4F4F4")!,
            .backgroundTertiary: RGBA(hex: "#EAEAEA")!,
            .surfaceCard: RGBA(hex: "#FFFFFF")!,
            .surfaceRaised: RGBA(hex: "#FFFFFF")!,
            .surfaceSunken: RGBA(hex: "#F0F0F0")!,
            // ADR-0036 (Pratiche) §D16: placeholders only, so a test resolving
            // `.color(.surfaceReceived)` before the bundled themes define the token
            // reads the emergency fallback rather than force-unwrapping `nil` and
            // crashing the whole xctest process (Theme.color(_:)/rawColor(_:)).
            .surfaceReceived: RGBA(hex: "#F0F0F0")!,
            .surfaceSent: RGBA(hex: "#E4EEF8")!,
            .surfaceEntry: RGBA(hex: "#FBF0C4")!,
            .borderSubtle: RGBA(hex: "#E0E0E0")!,
            .borderStrong: RGBA(hex: "#C4C4C4")!,
            .textPrimary: RGBA(hex: "#111111")!,
            .textSecondary: RGBA(hex: "#666666")!,
            .textTertiary: RGBA(hex: "#999999")!,
            .textInverted: RGBA(hex: "#FFFFFF")!,
            .accentPrimary: RGBA(hex: "#0A66C2")!,
            .accentMuted: RGBA(hex: "#E4EEF8")!,
            .onAccent: RGBA(hex: "#FFFFFF")!,
            .canvasBackground: RGBA(hex: "#F0F0F0")!,
            .canvasGrid: RGBA(hex: "#E0E0E0")!,
            .canvasSelection: RGBA(hex: "#0A66C2")!,
            .taskOpen: RGBA(hex: "#111111")!,
            .taskDone: RGBA(hex: "#999999")!,
            .taskScheduled: RGBA(hex: "#3B6EA5")!,
            .taskOverdue: RGBA(hex: "#B3261E")!,
            .taskCancelled: RGBA(hex: "#999999")!,
            .codeKeyword: RGBA(hex: "#7E4B7A")!,
            .codeString: RGBA(hex: "#4B7A4F")!,
            .codeComment: RGBA(hex: "#999999")!,
            .codeNumber: RGBA(hex: "#2F6E6B")!,
            .codeType: RGBA(hex: "#3B6EA5")!,
            .stickyYellow: RGBA(hex: "#FBF0C4")!,
            .stickyGreen: RGBA(hex: "#DFEBD4")!,
            .stickyBlue: RGBA(hex: "#D8E5F0")!,
            .stickyPink: RGBA(hex: "#F6DEE0")!,
            .stickyGrey: RGBA(hex: "#E8E8E8")!,
        ],
        fonts: [
            .title: TypographyValue(family: .system, size: 22, weight: 600, lineHeight: 1.2),
            .heading: TypographyValue(family: .system, size: 16, weight: 600, lineHeight: 1.3),
            .body: TypographyValue(family: .system, size: 13, weight: 400, lineHeight: 1.5),
            .caption: TypographyValue(family: .system, size: 11, weight: 400, lineHeight: 1.35),
            .mono: TypographyValue(family: .monospace, size: 12, weight: 400, lineHeight: 1.45),
            // The page faces (ADR-0030 §D2), the same values the bundled themes carry.
            // Naming a family here rather than `.system` is deliberate: the emergency
            // theme is what a broken bundle degrades to, and a page that silently reads
            // as chrome would hide exactly that.
            .prose: TypographyValue(family: .named("Avenir Next"), size: 16, weight: 400, lineHeight: 1.4),
            .proseTitle: TypographyValue(family: .named("Avenir Next"), size: 24, weight: 700, lineHeight: 1.2),
        ],
        spacings: [
            .xs: 4, .s: 8, .m: 16, .l: 24, .xl: 40,
            // The editor's readable column (ADR-0030 §D7). Not a step of the ramp above:
            // it is a measure, which is why `DesignGalleryView` draws the five steps by
            // name instead of iterating `allCases` and rendering a 720x720 swatch.
            .readable: 720,
        ],
        radii: [.card: 10, .control: 6, .sticky: 4],
        shadows: [
            .card: ShadowValue(color: RGBA(hex: "#00000014")!, offsetX: 0, offsetY: 1, blur: 3, spread: 0),
            .raised: ShadowValue(color: RGBA(hex: "#0000001F")!, offsetX: 0, offsetY: 6, blur: 18, spread: 0),
        ]
    )
}

// MARK: - Token to SwiftUI mapping

/// The nine weight stops a DTCG numeric weight (100...900) lands on.
///
/// The thresholds are written once, in `init(dtcg:)`; `swiftUI` and `appKit` only name
/// the same stop in each framework's units. Two threshold ladders used to sit side by
/// side, identical by hand, which is how a token would one day draw a different weight
/// in a SwiftUI view and in a bridged AppKit one.
enum FontWeightStop: CaseIterable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black

    /// Anything between two stops rounds down to the lighter one, which is how CSS
    /// behaves.
    init(dtcg weight: Int) {
        switch weight {
        case ..<150: self = .ultraLight
        case ..<250: self = .thin
        case ..<350: self = .light
        case ..<450: self = .regular
        case ..<550: self = .medium
        case ..<650: self = .semibold
        case ..<750: self = .bold
        case ..<850: self = .heavy
        default: self = .black
        }
    }

    var swiftUI: Font.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }

    var appKit: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
}

private extension Int {
    var asFontWeight: Font.Weight { FontWeightStop(dtcg: self).swiftUI }
    var asNSFontWeight: NSFont.Weight { FontWeightStop(dtcg: self).appKit }
}

private extension TypographyValue.Family {
    var asDesign: Font.Design {
        switch self {
        case .system: .default
        case .monospace: .monospaced
        case .serif: .serif
        // `Font.Design` has no "named family" case, so a named family never reaches
        // here: `font(_:)` peels `.named` off and builds a `Font.custom(name:size:)`
        // before ever asking for a design (ADR-0030 §D3). `.default` is what this
        // answers if a future caller forgets that, and it is the same face
        // `nsFont(_:)` falls back to for an uninstalled family - not a third answer.
        case .named: .default
        }
    }
}
