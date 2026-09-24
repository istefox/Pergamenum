import Foundation
import Testing
@testable import Pergamenum

// MARK: - Colour parsing

@Test func parsesSixDigitHex() throws {
    let color = try #require(RGBA(hex: "#9A5B1F"))
    #expect(abs(color.red - 154.0 / 255) < 0.0001)
    #expect(abs(color.green - 91.0 / 255) < 0.0001)
    #expect(abs(color.blue - 31.0 / 255) < 0.0001)
    #expect(color.alpha == 1)
}

@Test func parsesEightDigitHexWithAlpha() throws {
    let color = try #require(RGBA(hex: "00000080"))
    #expect(color.alpha > 0.5 && color.alpha < 0.505)
}

@Test func expandsShorthandHex() throws {
    let short = try #require(RGBA(hex: "#A3F"))
    let long = try #require(RGBA(hex: "#AA33FF"))
    #expect(short == long)
}

@Test(arguments: ["", "#", "#12345", "#GGGGGG", "not a colour"])
func rejectsMalformedHex(_ input: String) {
    // A bad value must fail loudly rather than resolve to black, which would be
    // indistinguishable from a deliberate black in a rendered view.
    #expect(RGBA(hex: input) == nil)
}

// MARK: - Token document parsing

@Test func parsesNestedGroupsAndInheritsType() throws {
    let json = """
    {
      "color": { "$type": "color", "text": { "primary": { "$value": "#112233" } } },
      "spacing": { "$type": "dimension", "m": { "$value": { "value": 16, "unit": "px" } } }
    }
    """
    let document = try DesignTokenDocument(data: Data(json.utf8), fallbackName: "test")
    #expect(document.tokens["color.text.primary"] == .color(RGBA(hex: "#112233")!))
    #expect(document.tokens["spacing.m"] == .dimension(16))
    #expect(document.problems.isEmpty)
}

@Test func acceptsEveryDimensionSpelling() throws {
    let json = """
    { "spacing": { "$type": "dimension",
      "a": { "$value": 4 }, "b": { "$value": "8px" },
      "c": { "$value": "12" }, "d": { "$value": { "value": 16, "unit": "px" } } } }
    """
    let document = try DesignTokenDocument(data: Data(json.utf8), fallbackName: "test")
    #expect(document.tokens["spacing.a"] == .dimension(4))
    #expect(document.tokens["spacing.b"] == .dimension(8))
    #expect(document.tokens["spacing.c"] == .dimension(12))
    #expect(document.tokens["spacing.d"] == .dimension(16))
}

@Test func reportsMalformedValueWithoutDroppingTheRestOfTheFile() throws {
    let json = """
    { "color": { "$type": "color",
      "good": { "$value": "#112233" },
      "bad": { "$value": "definitely not hex" } } }
    """
    let document = try DesignTokenDocument(data: Data(json.utf8), fallbackName: "test")
    #expect(document.tokens["color.good"] != nil)
    #expect(document.tokens["color.bad"] == nil)
    #expect(document.problems.count == 1)
    #expect(document.problems[0].contains("color.bad"))
}

@Test func rejectsNonObjectRoot() {
    #expect(throws: DesignTokenDocument.ParseError.self) {
        _ = try DesignTokenDocument(data: Data("[1, 2, 3]".utf8), fallbackName: "test")
    }
}

// MARK: - Bundled themes

/// The load-bearing test of M0: if a bundled theme is missing a token, every view
/// asking for it silently gets the emergency palette instead. That must fail here,
/// in CI, not on screen.
@Test func bundledThemesDefineEveryToken() throws {
    for id in ["pergamenum-light", "pergamenum-dark"] {
        let url = try #require(
            Bundle.pergamenumResources.tokenFileURL(named: id),
            "\(id).json is not in the bundle"
        )
        let document = try DesignTokenDocument(data: try Data(contentsOf: url), fallbackName: id)
        #expect(document.problems.isEmpty, "\(id): \(document.problems)")

        let theme = Theme(document: document, id: id, inheriting: .emergency)
        #expect(theme.inheritedTokens.isEmpty, "\(id) is missing: \(theme.inheritedTokens)")

        // ADR-0030: the three page tokens are expected here explicitly, not only
        // through `inheritedTokens.isEmpty` above - named individually so a red run
        // says which of the three is still missing rather than requiring the reader
        // to diff `FontToken`/`SpacingToken` against the JSON by hand. Red until the
        // coder adds `font.prose`, `font.proseTitle` and `spacing.readable` to both
        // bundled theme files.
        #expect(!theme.inheritedTokens.contains("font.prose"), "\(id) should define font.prose")
        #expect(!theme.inheritedTokens.contains("font.proseTitle"), "\(id) should define font.proseTitle")
        #expect(!theme.inheritedTokens.contains("spacing.readable"), "\(id) should define spacing.readable")
        #expect(theme.spacing(.readable) == 720, "\(id): spacing.readable should resolve to 720")

        // ADR-0036 (Pratiche) §D16, plan Task 6 - R-39: the timeline's three surface
        // tokens must be defined by both bundled themes, not inherited from
        // `Theme.emergency`'s placeholder. Red until the coder adds `color.surface.
        // received`, `.sent` and `.entry` to both theme JSON files.
        #expect(!theme.inheritedTokens.contains("color.surface.received"), "\(id) should define color.surface.received")
        #expect(!theme.inheritedTokens.contains("color.surface.sent"), "\(id) should define color.surface.sent")
        #expect(!theme.inheritedTokens.contains("color.surface.entry"), "\(id) should define color.surface.entry")

        // The category dot's own saturated palette, distinct from `color.sticky.*`
        // (`CategoryColor+Token.swift`). Both bundled themes must define all five.
        #expect(!theme.inheritedTokens.contains("color.category.yellow"), "\(id) should define color.category.yellow")
        #expect(!theme.inheritedTokens.contains("color.category.green"), "\(id) should define color.category.green")
        #expect(!theme.inheritedTokens.contains("color.category.blue"), "\(id) should define color.category.blue")
        #expect(!theme.inheritedTokens.contains("color.category.pink"), "\(id) should define color.category.pink")
        #expect(!theme.inheritedTokens.contains("color.category.grey"), "\(id) should define color.category.grey")
    }
}

@MainActor
@Test func bundledThemesDeclareOppositeAppearances() {
    let engine = ThemeEngine(defaults: isolatedDefaults())
    #expect(Set(engine.themes.map(\.appearance)) == [.light, .dark])
}

@MainActor
@Test func engineLoadsWithoutProblems() {
    let engine = ThemeEngine(defaults: isolatedDefaults())
    #expect(engine.problems.isEmpty, "\(engine.problems)")
}

// MARK: - Theme selection

@MainActor
@Test func selectionSwitchesTheRenderedTheme() {
    let engine = ThemeEngine(defaults: isolatedDefaults())
    engine.systemAppearance = .light

    engine.selection = .followSystem
    #expect(engine.current.appearance == .light)

    engine.systemAppearance = .dark
    #expect(engine.current.appearance == .dark)

    // An explicit choice must win over the system, otherwise "forza chiaro" in
    // Settings would be silently ignored at night.
    engine.selection = .light
    #expect(engine.current.appearance == .light)
}

@MainActor
@Test func unknownNamedThemeFallsBackInsteadOfFailing() {
    let engine = ThemeEngine(defaults: isolatedDefaults())
    engine.systemAppearance = .dark
    engine.selection = .named("a-theme-the-user-deleted")
    #expect(engine.current.appearance == .dark)
}

@MainActor
@Test func selectionSurvivesRelaunch() {
    let defaults = isolatedDefaults()
    let first = ThemeEngine(defaults: defaults)
    first.selection = .dark

    let second = ThemeEngine(defaults: defaults)
    #expect(second.selection == .dark)
}

// MARK: - User themes

@MainActor
@Test func partialUserThemeInheritsTheRest() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pergamenum-themes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let partial = """
    {
      "meta": { "name": { "$type": "string", "$value": "Solo accento" },
                "appearance": { "$type": "string", "$value": "light" } },
      "color": { "$type": "color", "accent": { "primary": { "$value": "#FF0000" } } }
    }
    """
    try Data(partial.utf8).write(to: directory.appendingPathComponent("solo-accento.json"))

    let engine = ThemeEngine(defaults: isolatedDefaults())
    engine.loadUserThemes(in: directory)

    let custom = try #require(engine.themes.first { $0.id == "solo-accento" })
    #expect(custom.name == "Solo accento")
    // Everything it did not define came from the bundled light theme, so the count
    // of inherited tokens is large and, crucially, the theme is still complete.
    #expect(custom.inheritedTokens.contains("color.text.primary"))
    #expect(!custom.inheritedTokens.contains("color.accent.primary"))

    engine.selection = .named("solo-accento")
    #expect(engine.current.id == "solo-accento")
}

@MainActor
@Test func thePickerListsOnlyVaultThemesNeverTheTwoBundledOnes() throws {
    // `SettingsView.swift`'s `Picker("Tema")` does not read `selectableThemes` bare -
    // it filters `!$0.id.hasPrefix("pergamenum-")` first, the same predicate
    // `detachVault` and `loadUserThemes` already use to tell a bundled theme apart
    // from a vault one. `selectableThemes` alone (`ThemeCustomizationTests.swift`'s
    // `aVaultThemeReachesTheEngineOnceTheVaultIsAttached`) is not what the control on
    // screen shows.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pergamenum-themes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let engine = ThemeEngine(defaults: isolatedDefaults())
    // Before any vault theme loads, the filtered list is empty: both bundled themes
    // carry the `pergamenum-` prefix and neither belongs in the custom section.
    #expect(engine.selectableThemes.filter { !$0.id.hasPrefix("pergamenum-") }.isEmpty)

    let vaultTheme = """
    {
      "meta": { "name": { "$type": "string", "$value": "Notte Vibrofer" },
                "appearance": { "$type": "string", "$value": "dark" } }
    }
    """
    try Data(vaultTheme.utf8).write(to: directory.appendingPathComponent("notte-vibrofer.json"))
    engine.loadUserThemes(in: directory)

    #expect(engine.selectableThemes.filter { !$0.id.hasPrefix("pergamenum-") }.map(\.id) == ["notte-vibrofer"])
}

@MainActor
@Test func unreadableUserThemeIsReportedNotFatal() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pergamenum-themes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("{ not json".utf8).write(to: directory.appendingPathComponent("broken.json"))

    let engine = ThemeEngine(defaults: isolatedDefaults())
    engine.loadUserThemes(in: directory)

    #expect(engine.problems.contains { $0.contains("broken") })
    // The app still renders: a broken user file never takes the bundled themes down.
    #expect(engine.current.inheritedTokens.isEmpty)
}

// MARK: - Font weight ladder

@Test(arguments: [
    (100, FontWeightStop.ultraLight), (149, .ultraLight),
    (150, .thin), (249, .thin),
    (250, .light), (349, .light),
    (350, .regular), (400, .regular), (449, .regular),
    (450, .medium), (549, .medium),
    (550, .semibold), (649, .semibold),
    (650, .bold), (700, .bold), (749, .bold),
    (750, .heavy), (849, .heavy),
    (850, .black), (900, .black),
])
func weightThresholdsRoundDownToTheLighterStop(weight: Int, stop: FontWeightStop) {
    #expect(FontWeightStop(dtcg: weight) == stop)
}

@Test func everyWeightStopIsDistinctAndOrderedInBothFrameworks() {
    let stops = FontWeightStop.allCases
    #expect(Set(stops.map(\.swiftUI)).count == stops.count)
    #expect(Set(stops.map(\.appKit)).count == stops.count)
    // AppKit's weights are CGFloats, so the ladder's order is checkable: a stop mapped to
    // the wrong AppKit weight would break the ascending run that the thresholds imply.
    let appKit = stops.map(\.appKit.rawValue)
    #expect(appKit == appKit.sorted())
}

// MARK: - Helpers

/// Each test gets its own defaults suite so persisted selections cannot leak between
/// tests running in parallel.
private func isolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "pergamenum.tests.\(UUID().uuidString)")!
}
