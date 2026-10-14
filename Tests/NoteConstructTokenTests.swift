import Foundation
import Testing
@testable import Pergamenum

// ADR-0087 §D4, plan docs/plans/note-workflow-n5-mockup.md, Task 2 - R-35. The eight colour tokens
// of the page's remaining constructs (inline code ground, highlight, quote bar, five callout types)
// are defined by both bundled themes, resolve in the emergency palette, and clear the contrast
// thresholds the ADR names. Beside `DesignSystemTests`, which is past comfortable length, in
// `PraticaRailTokenTests`'s shape.

private let noteConstructBundledIDs = ["pergamenum-light", "pergamenum-dark"]

@MainActor
@Suite struct NoteConstructTokenTests {
    private static let calloutTokens: [ColorToken] = [
        .calloutNote, .calloutTip, .calloutImportant, .calloutWarning, .calloutCaution,
    ]
    private static let tokens: [ColorToken] = [.codeInlineBackground, .highlight, .quoteBar] + calloutTokens
    private static let bundledIDs = noteConstructBundledIDs

    /// ADR-0087 §D4: a callout card is its type colour at this opacity over the page. The code PR's
    /// `CalloutStyle.backgroundOpacity` is pinned to the same literal.
    private static let cardOpacity = 0.08

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "pergamenum.tests.\(UUID().uuidString)")!
    }

    private func bundled(_ id: String, in engine: ThemeEngine) throws -> Theme {
        try #require(engine.themes.first { $0.id == id }, "\(id) is not loaded")
    }

    /// WCAG 2 relative luminance of an sRGB colour.
    private static func luminance(_ color: RGBA) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    private static func contrast(_ first: RGBA, _ second: RGBA) -> Double {
        let (lighter, darker) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// `foreground` at `opacity` composited over an opaque `background`.
    private static func composite(_ foreground: RGBA, opacity: Double, over background: RGBA) -> RGBA {
        RGBA(
            red: foreground.red * opacity + background.red * (1 - opacity),
            green: foreground.green * opacity + background.green * (1 - opacity),
            blue: foreground.blue * opacity + background.blue * (1 - opacity),
            alpha: 1
        )
    }

    // MARK: - Keys

    @Test func theTokensCarryTheirDTCGPaths() { // R-35
        #expect(ColorToken.codeInlineBackground.rawValue == "color.code.inlineBackground")
        #expect(ColorToken.highlight.rawValue == "color.highlight")
        #expect(ColorToken.quoteBar.rawValue == "color.quote.bar")
        #expect(ColorToken.calloutNote.rawValue == "color.callout.note")
        #expect(ColorToken.calloutTip.rawValue == "color.callout.tip")
        #expect(ColorToken.calloutImportant.rawValue == "color.callout.important")
        #expect(ColorToken.calloutWarning.rawValue == "color.callout.warning")
        #expect(ColorToken.calloutCaution.rawValue == "color.callout.caution")
    }

    // MARK: - Bundled themes

    @Test func bothBundledThemesDefineAllEightTokensAndLoadWithoutProblems() throws { // R-35
        let engine = ThemeEngine(defaults: isolatedDefaults())
        #expect(engine.problems.isEmpty, "\(engine.problems)")
        for id in Self.bundledIDs {
            let theme = try bundled(id, in: engine)
            for token in Self.tokens {
                #expect(!theme.inheritedTokens.contains(token.path), "\(id) should define \(token.path)")
                #expect(theme.rawColor(token).alpha == 1, "\(id) \(token.path) must be opaque")
            }
        }
    }

    @Test func theDarkThemesTokensDifferFromTheLightEmergencyPalette() throws { // R-35
        // The dark theme must carry its own values: if it silently fell to the emergency (light)
        // palette, every callout would be a light-theme colour on a dark page.
        let engine = ThemeEngine(defaults: isolatedDefaults())
        let dark = try bundled("pergamenum-dark", in: engine)
        for token in Self.tokens {
            #expect(dark.rawColor(token) != Theme.emergency.rawColor(token), "dark \(token.path) is the light value")
        }
    }

    // MARK: - Emergency palette (PG-225)

    @Test func theEmergencyThemeResolvesEachTokenToTheLightValue() throws { // R-35
        let expected: [(ColorToken, String)] = [
            (.codeInlineBackground, "#EEE9E1"),
            (.highlight, "#F9E7A1"),
            (.quoteBar, "#958D80"),
            (.calloutNote, "#3B6EA5"),
            (.calloutTip, "#3F7A45"),
            (.calloutImportant, "#7E4B7A"),
            (.calloutWarning, "#94600F"),
            (.calloutCaution, "#B3261E"),
        ]
        for (token, hex) in expected {
            let rgba = try #require(RGBA(hex: hex))
            #expect(Theme.emergency.rawColor(token) == rgba, "\(token.rawValue) should resolve to \(hex)")
        }
    }

    @Test func theEmergencyPaletteAgreesWithTheLightBundledTheme() throws { // R-35
        let engine = ThemeEngine(defaults: isolatedDefaults())
        let light = try bundled("pergamenum-light", in: engine)
        for token in Self.tokens {
            #expect(
                light.rawColor(token) == Theme.emergency.rawColor(token),
                "\(token.path): light and emergency drifted"
            )
        }
    }

    // MARK: - Inheritance

    /// A vault theme written before these tokens existed draws them in the bundled colour for its
    /// appearance, opaque.
    @Test(arguments: ["light", "dark"])
    func aVaultThemeWithoutTheTokensInheritsThemFromTheBundledTheme(appearance: String) throws { // R-35
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pergamenum-themes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let older = """
        {
          "meta": { "name": { "$type": "string", "$value": "Tema vecchio" },
                    "appearance": { "$type": "string", "$value": "\(appearance)" } },
          "color": { "$type": "color", "surface": { "entry": { "$value": "#112233" } } }
        }
        """
        try Data(older.utf8).write(to: directory.appendingPathComponent("tema-vecchio.json"))

        let engine = ThemeEngine(defaults: isolatedDefaults())
        let bundledTheme = try bundled("pergamenum-\(appearance)", in: engine)
        engine.loadUserThemes(in: directory)
        let custom = try #require(engine.themes.first { $0.id == "tema-vecchio" })

        #expect(engine.problems.isEmpty, "\(engine.problems)")
        for token in Self.tokens {
            #expect(custom.inheritedTokens.contains(token.path))
            #expect(
                custom.rawColor(token) == bundledTheme.rawColor(token),
                "\(token.path) not the bundled \(appearance) value"
            )
            #expect(custom.rawColor(token).alpha == 1, "\(token.path) would render clear")
        }
    }

    // MARK: - Contrast (ADR-0087 §D4)

    @Test func theHelpersAgreeWithKnownValues() throws {
        let black = try #require(RGBA(hex: "#000000"))
        let white = try #require(RGBA(hex: "#FFFFFF"))
        #expect(abs(Self.contrast(black, white) - 21) < 0.001)
        let grey = try #require(RGBA(hex: "#767676"))
        #expect(abs(Self.contrast(grey, white) - 4.54) < 0.01)
        // Half black over white is mid grey; zero opacity is the background, full opacity the foreground.
        let half = Self.composite(black, opacity: 0.5, over: white)
        #expect(abs(half.red - 0.5) < 0.0001 && abs(half.green - 0.5) < 0.0001 && abs(half.blue - 0.5) < 0.0001)
        #expect(Self.composite(black, opacity: 0, over: white) == white)
        #expect(Self.composite(black, opacity: 1, over: white) == black)
    }

    @Test(arguments: noteConstructBundledIDs)
    func eachCalloutColourMeetsFourPointFiveToOneAgainstThePageAndItsOwnCard(id: String) throws { // R-35
        let engine = ThemeEngine(defaults: isolatedDefaults())
        let theme = try bundled(id, in: engine)
        let page = theme.rawColor(.backgroundPrimary)
        for token in Self.calloutTokens {
            let colour = theme.rawColor(token)
            let onPage = Self.contrast(colour, page)
            #expect(onPage >= 4.5, "\(id) \(token.path): \(onPage):1 against color.background.primary")
            let card = Self.composite(colour, opacity: Self.cardOpacity, over: page)
            let onCard = Self.contrast(colour, card)
            #expect(onCard >= 4.5, "\(id) \(token.path): \(onCard):1 against its own card at 0.08")
        }
    }

    @Test(arguments: noteConstructBundledIDs)
    func theQuoteBarMeetsThreeToOneAgainstThePage(id: String) throws { // R-35
        let engine = ThemeEngine(defaults: isolatedDefaults())
        let theme = try bundled(id, in: engine)
        let ratio = Self.contrast(theme.rawColor(.quoteBar), theme.rawColor(.backgroundPrimary))
        #expect(ratio >= 3, "\(id) color.quote.bar: \(ratio):1 against color.background.primary")
    }

    @Test(arguments: noteConstructBundledIDs)
    func secondaryTextOnTheInlineCodeGroundMeetsFourPointFiveToOne(id: String) throws { // R-35
        let engine = ThemeEngine(defaults: isolatedDefaults())
        let theme = try bundled(id, in: engine)
        let ratio = Self.contrast(theme.rawColor(.textSecondary), theme.rawColor(.codeInlineBackground))
        #expect(ratio >= 4.5, "\(id) color.text.secondary on color.code.inlineBackground: \(ratio):1")
    }

    @Test(arguments: noteConstructBundledIDs)
    func primaryTextOnTheHighlightMeetsFourPointFiveToOne(id: String) throws { // R-35
        let engine = ThemeEngine(defaults: isolatedDefaults())
        let theme = try bundled(id, in: engine)
        let ratio = Self.contrast(theme.rawColor(.textPrimary), theme.rawColor(.highlight))
        #expect(ratio >= 4.5, "\(id) color.text.primary on color.highlight: \(ratio):1")
    }

    // MARK: - Distinctness

    @Test(arguments: noteConstructBundledIDs)
    func theFiveCalloutColoursArePairwiseDistinct(id: String) throws { // R-35
        let engine = ThemeEngine(defaults: isolatedDefaults())
        let theme = try bundled(id, in: engine)
        for (index, first) in Self.calloutTokens.enumerated() {
            for second in Self.calloutTokens[(index + 1)...] {
                #expect(theme.rawColor(first) != theme.rawColor(second), "\(id): \(first.path) equals \(second.path)")
            }
        }
    }
}
