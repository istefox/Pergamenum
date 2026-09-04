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
        return Font.system(size: value.size, weight: value.weight.asFontWeight, design: value.family.asDesign)
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
        case .named:
            // TESTER STUB (ADR-0030 §D3): coder replaces this arm with
            // `NSFont(name: name, size:)`, `>= 600` promoted through
            // `withSymbolicTraits(.bold)`, falling back to this same system-font call
            // when the named family is not installed. Left unresolved on purpose so
            // `TypographyResolutionTests`'s named-family assertions stay red.
            return NSFont.systemFont(ofSize: value.size, weight: weight)
        }
    }

    /// The AppKit face `font(_:)`'s SwiftUI value is meant to match - same resolution
    /// `nsFont(_:)` uses, so the two surfaces never draw two different faces for one
    /// token (ADR-0030 §D3). Exists so a test can pin that equivalence down without
    /// reaching into SwiftUI's opaque `Font`.
    ///
    /// TESTER STUB: forwards to `nsFont(_:)` unconditionally. Once the coder wires
    /// `font(_:)`'s `.named` arm through `Font.custom(name:size:)`, this should keep
    /// reporting the name that call actually uses.
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
            // TESTER STUB (ADR-0030 §D2): placeholder system-family entries, only
            // here so `fonts[token] ?? Theme.emergency.fonts[token]!` cannot force-
            // unwrap `nil` and crash the test process before a bundled theme defines
            // these. The coder's real values are Avenir Next 16/1.4 and Avenir Next
            // Bold 24 (ADR-0030 §D2) - deliberately not guessed here so
            // `bundledThemesDefineEveryToken` and the `.prose`/`.proseTitle`
            // resolution tests stay red until the coder adds them to both theme
            // JSON files.
            .prose: TypographyValue(family: .system, size: 13, weight: 400, lineHeight: 1.5),
            .proseTitle: TypographyValue(family: .system, size: 22, weight: 600, lineHeight: 1.2),
        ],
        spacings: [
            .xs: 4, .s: 8, .m: 16, .l: 24, .xl: 40,
            // TESTER STUB (ADR-0030 §D7): same reasoning as `.prose` above - a
            // placeholder so `spacing(.readable)` cannot force-unwrap `nil`. The
            // coder's real value is 720; deliberately not 720 here so
            // `theme.spacing(.readable) == 720` stays red until the coder adds it to
            // both theme JSON files.
            .readable: 24,
        ],
        radii: [.card: 10, .control: 6, .sticky: 4],
        shadows: [
            .card: ShadowValue(color: RGBA(hex: "#00000014")!, offsetX: 0, offsetY: 1, blur: 3, spread: 0),
            .raised: ShadowValue(color: RGBA(hex: "#0000001F")!, offsetX: 0, offsetY: 6, blur: 18, spread: 0),
        ]
    )
}

// MARK: - Token to SwiftUI mapping

private extension Int {
    /// DTCG numeric weights map onto the nine SwiftUI weights; anything between two
    /// stops rounds down to the lighter one, which is how CSS behaves.
    var asFontWeight: Font.Weight {
        switch self {
        case ..<150: .ultraLight
        case ..<250: .thin
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
    }
}

private extension Int {
    /// The same nine stops as `asFontWeight`, in AppKit's units.
    var asNSFontWeight: NSFont.Weight {
        switch self {
        case ..<150: .ultraLight
        case ..<250: .thin
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
    }
}

private extension TypographyValue.Family {
    var asDesign: Font.Design {
        switch self {
        case .system: .default
        case .monospace: .monospaced
        case .serif: .serif
        // TESTER STUB (ADR-0030 §D3): `Font.Design` has no "named family" case, so
        // this can never be the coder's real answer - `font(_:)`'s `.named` arm has
        // to stop calling `Font.system(design:)` altogether and build a
        // `Font.custom(name:size:)` instead. Left as `.default` only so this switch
        // stays exhaustive.
        case .named: .default
        }
    }
}
