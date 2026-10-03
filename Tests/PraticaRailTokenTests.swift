import Foundation
import Testing
@testable import Pergamenum

// ADR-0079 §D6 (PG-369), plan docs/plans/pg-369-pratiche-timeline-rail-and-excluded.md, Task 5 -
// R-10. One rail colour per message lane, defined by both bundled themes, inherited by a vault
// theme that lacks them, at least 3:1 (WCAG 2 non-text contrast) against the timeline's
// `color.background.primary`. Beside `DesignSystemTests`, which is past comfortable length.

@MainActor
@Suite struct PraticaRailTokenTests {
    private static let tokens: [ColorToken] = [.railReceived, .railSent]
    private static let bundledIDs = ["pergamenum-light", "pergamenum-dark"]

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

    // MARK: - Keys

    @Test func theTokensCarryTheirPathsInTheColorRailGroup() {
        #expect(ColorToken.railReceived.rawValue == "color.rail.received")
        #expect(ColorToken.railSent.rawValue == "color.rail.sent")
    }

    @Test func bothBundledThemesDefineBothTokensAndLoadWithoutProblems() throws {
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

    @Test func theEmergencyThemeResolvesBothTokens() throws {
        let expected: [(ColorToken, String)] = [(.railReceived, "#8F897C"), (.railSent, "#6189B4")]
        for (token, hex) in expected {
            let rgba = try #require(RGBA(hex: hex))
            #expect(Theme.emergency.rawColor(token) == rgba, "\(token.rawValue) should resolve to \(hex)")
        }
    }

    @Test func eachLanesTokenDiffersFromTheOtherAndFromTheirSurface() throws {
        let engine = ThemeEngine(defaults: isolatedDefaults())
        for id in Self.bundledIDs {
            let theme = try bundled(id, in: engine)
            #expect(theme.rawColor(.railReceived) != theme.rawColor(.railSent), Comment(rawValue: id))
            #expect(theme.rawColor(.railReceived) != theme.rawColor(.surfaceReceived), Comment(rawValue: id))
            #expect(theme.rawColor(.railSent) != theme.rawColor(.surfaceSent), Comment(rawValue: id))
        }
    }

    // MARK: - Inheritance

    /// A vault theme written before the rail tokens existed draws the rail in the bundled theme's
    /// colour for its appearance: opaque, never the emergency's.
    @Test(arguments: ["light", "dark"])
    func aVaultThemeWithoutTheRailTokensInheritsThemFromTheBundledTheme(appearance: String) throws {
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
            if appearance == "dark" {
                // The emergency palette mirrors the light theme, so only the dark one can tell them apart.
                #expect(
                    custom.rawColor(token) != Theme.emergency.rawColor(token), "\(token.path) fell to the emergency"
                )
            }
            #expect(custom.rawColor(token).alpha == 1, "\(token.path) would render clear")
        }
    }

    // MARK: - Contrast (WCAG 2, non-text, 3:1)

    @Test func theContrastHelperAgreesWithKnownWCAGValues() throws {
        let black = try #require(RGBA(hex: "#000000"))
        let white = try #require(RGBA(hex: "#FFFFFF"))
        #expect(abs(Self.contrast(black, white) - 21) < 0.001)
        #expect(abs(Self.contrast(white, white) - 1) < 0.001)
        // #767676 on white is the textbook 4.54:1 boundary.
        let grey = try #require(RGBA(hex: "#767676"))
        #expect(abs(Self.contrast(grey, white) - 4.54) < 0.01)
    }

    @Test(arguments: [("pergamenum-light", ColorToken.railReceived), ("pergamenum-light", .railSent),
                      ("pergamenum-dark", .railReceived), ("pergamenum-dark", .railSent)])
    func eachRailTokenMeetsThreeToOneAgainstThePrimaryBackground(id: String, token: ColorToken) throws {
        let engine = ThemeEngine(defaults: isolatedDefaults())
        let theme = try bundled(id, in: engine)
        let ratio = Self.contrast(theme.rawColor(token), theme.rawColor(.backgroundPrimary))
        #expect(ratio >= 3, "\(id) \(token.path): \(ratio):1 against color.background.primary")
    }

    // MARK: - railToken(for:)

    @Test func railTokenFollowsTheMessageLane() {
        #expect(PraticaTimelineModel.railToken(for: .received) == .railReceived)
        #expect(PraticaTimelineModel.railToken(for: .sent) == .railSent)
        #expect(PraticaTimelineModel.railToken(for: .entry) == nil, "an entry lane hosts no rail")
    }
}
