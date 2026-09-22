import Foundation
import Testing
@testable import Pergamenum

private struct TemporaryDirectory: ~Copyable {
    let url: URL

    init() throws {
        url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "pergamenum-themes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

@Test func aChosenColourIsWrittenAsANestedTokenFile() throws {
    let directory = try TemporaryDirectory()
    let draft = ThemeCustomization.Draft(
        appearance: .dark,
        colors: [.accentPrimary: RGBA(hex: "#123456")!]
    )
    try ThemeCustomization.write(draft, to: directory.url)

    let data = try Data(contentsOf: ThemeCustomization.url(in: directory.url))
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    // The nesting is what a DTCG reader walks: a flat "color.accent.primary" key
    // would parse as a token literally named that, and nothing would resolve.
    let color = try #require(root["color"] as? [String: Any])
    let accent = try #require(color["accent"] as? [String: Any])
    let primary = try #require(accent["primary"] as? [String: Any])
    #expect(primary["$value"] as? String == "#123456")
    #expect(primary["$type"] as? String == "color")
    // `meta` is written as tokens too: as a bare string the reader treats it as a
    // malformed group, ignores the declared appearance and inherits from the light
    // base whatever the user chose.
    let meta = try #require(root["meta"] as? [String: Any])
    let appearance = try #require(meta["appearance"] as? [String: Any])
    #expect(appearance["$value"] as? String == "dark")
}

@Test func onlyTheChosenColoursAreWrittenSoTheRestKeepsInheriting() throws {
    let directory = try TemporaryDirectory()
    try ThemeCustomization.write(
        ThemeCustomization.Draft(appearance: .light, colors: [.textPrimary: RGBA(hex: "#000000")!]),
        to: directory.url
    )
    let data = try Data(contentsOf: ThemeCustomization.url(in: directory.url))
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let color = try #require(root["color"] as? [String: Any])
    #expect(color.keys.sorted() == ["text"])
}

@Test func whatWasWrittenReadsBackAsTheSameDraft() throws {
    let directory = try TemporaryDirectory()
    let draft = ThemeCustomization.Draft(
        appearance: .dark,
        colors: [
            .accentPrimary: RGBA(hex: "#9A5B1F")!,
            .backgroundPrimary: RGBA(hex: "#101010")!,
        ]
    )
    try ThemeCustomization.write(draft, to: directory.url)
    #expect(ThemeCustomization.load(from: directory.url) == draft)
}

@Test func aColourWithTransparencyKeepsItsAlphaThroughTheRoundTrip() throws {
    let directory = try TemporaryDirectory()
    let translucent = RGBA(red: 1, green: 0, blue: 0, alpha: 0.5)
    try ThemeCustomization.write(
        ThemeCustomization.Draft(appearance: .light, colors: [.canvasGrid: translucent]),
        to: directory.url
    )
    let reloaded = try #require(ThemeCustomization.load(from: directory.url))
    let colour = try #require(reloaded.colors[.canvasGrid])
    #expect(colour.hexString == "#FF000080")
    #expect(abs(colour.alpha - 0.5) < 0.01)
}

@Test func theSameChoicesProduceTheSameFileByteForByte() throws {
    let first = try TemporaryDirectory()
    let second = try TemporaryDirectory()
    let draft = ThemeCustomization.Draft(
        appearance: .light,
        colors: [.accentPrimary: RGBA(hex: "#AABBCC")!, .textPrimary: RGBA(hex: "#111111")!]
    )
    try ThemeCustomization.write(draft, to: first.url)
    try ThemeCustomization.write(draft, to: second.url)
    // A vault under version control must not show a diff for a save that changed
    // nothing, the same rule the canvas writer follows.
    #expect(
        try Data(contentsOf: ThemeCustomization.url(in: first.url))
            == (try Data(contentsOf: ThemeCustomization.url(in: second.url)))
    )
}

@Test func removingTheFileIsHowACustomisationIsUndone() throws {
    let directory = try TemporaryDirectory()
    try ThemeCustomization.write(
        ThemeCustomization.Draft(appearance: .light, colors: [.accentPrimary: RGBA(hex: "#AABBCC")!]),
        to: directory.url
    )
    try ThemeCustomization.remove(from: directory.url)
    #expect(ThemeCustomization.load(from: directory.url) == nil)
    // Removing again is not an error: the reset button must not fail on a second press.
    try ThemeCustomization.remove(from: directory.url)
}

@MainActor
@Test func aVaultThemeReachesTheEngineOnceTheVaultIsAttached() throws {
    let vault = try TemporaryDirectory()
    let themes = vault.url
        .appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
        .appending(path: VaultLayout.themesDirectory, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
    try """
    { "meta": {
        "name": { "$type": "string", "$value": "Notte" },
        "appearance": { "$type": "string", "$value": "dark" } },
      "color": { "accent": { "primary": { "$type": "color", "$value": "#00FF00" } } } }
    """.write(to: themes.appending(path: "notte.json"), atomically: true, encoding: .utf8)

    let engine = ThemeEngine(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())")!)
    #expect(engine.selectableThemes.count == 2)

    engine.attach(vaultRoot: vault.url)
    // This is the wiring that was missing: the file existed, the loader existed, and
    // nothing in the app ever put the two together.
    #expect(engine.selectableThemes.contains { $0.id == "notte" })

    engine.selection = .named("notte")
    #expect(engine.current.rawColor(.accentPrimary) == RGBA(hex: "#00FF00")!)
    // The rest of the theme still comes from the bundled dark base.
    #expect(engine.current.appearance == .dark)

    engine.detachVault()
    #expect(!engine.selectableThemes.contains { $0.id == "notte" })
    #expect(engine.selection == .followSystem)
}

@MainActor
@Test func choosingAColourWritesItIntoTheVaultAndSelectsIt() throws {
    let vault = try TemporaryDirectory()
    let engine = ThemeEngine(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())")!)
    engine.attach(vaultRoot: vault.url)

    engine.setCustomColor(.accentPrimary, to: RGBA(hex: "#FF0000")!)

    #expect(engine.customizationProblem == nil)
    #expect(engine.selection == .named(ThemeCustomization.id))
    #expect(engine.current.rawColor(.accentPrimary) == RGBA(hex: "#FF0000")!)
    // On disk, not in memory: this is what makes it survive a relaunch and travel
    // with the vault.
    let directory = try #require(engine.userThemesDirectory)
    #expect(ThemeCustomization.load(from: directory)?.colors[.accentPrimary] == RGBA(hex: "#FF0000")!)

    engine.clearCustomColor(.accentPrimary)
    #expect(engine.customization == nil)
    #expect(engine.selection == .followSystem)
}

/// `ThemeEngine.resetCustomization()` on its own, not through `clearCustomColor`'s
/// empty-draft branch above: it deletes the file, clears `customizationProblem`,
/// drops `selection == .named(ThemeCustomization.id)` back to `.followSystem`, and
/// reloads the vault's themes - none of which the branch above exercises with a
/// stale problem or a second theme file waiting to be picked up.
@MainActor
@Test func resetCustomizationRemovesTheFileClearsTheProblemDropsTheSelectionAndReloads() throws {
    let vault = try TemporaryDirectory()
    let engine = ThemeEngine(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())")!)
    engine.attach(vaultRoot: vault.url)
    engine.setCustomColor(.accentPrimary, to: RGBA(hex: "#FF0000")!)

    let directory = try #require(engine.userThemesDirectory)
    let file = ThemeCustomization.url(in: directory)
    #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    #expect(engine.selection == .named(ThemeCustomization.id))

    // Dropped straight onto disk, after `attach`, so nothing has reloaded it into
    // `selectableThemes` yet - which is what proves the reload below is real.
    try """
    { "meta": { "name": { "$type": "string", "$value": "Secondo" },
        "appearance": { "$type": "string", "$value": "light" } } }
    """.write(to: directory.appending(path: "secondo.json"), atomically: true, encoding: .utf8)
    #expect(!engine.selectableThemes.contains { $0.id == "secondo" })

    // `chmod 555` on the directory blocks the removal (`PraticaSyncRepairTests.swift`'s
    // technique): the reset must report the failure rather than pretend it worked, and
    // leave the customisation and the selection exactly as they were.
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o555], ofItemAtPath: directory.path(percentEncoded: false)
    )
    defer {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: directory.path(percentEncoded: false)
        )
    }
    engine.resetCustomization()
    #expect(engine.customizationProblem != nil)
    #expect(engine.customization != nil)
    #expect(engine.selection == .named(ThemeCustomization.id))

    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: directory.path(percentEncoded: false)
    )
    engine.resetCustomization()

    #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    #expect(engine.customization == nil)
    // The stale problem from the failed attempt above does not survive a successful one.
    #expect(engine.customizationProblem == nil)
    #expect(engine.selection == .followSystem)
    // The reload is real: a file already on disk before this call is now visible.
    #expect(engine.selectableThemes.contains { $0.id == "secondo" })
}

@MainActor
@Test func withoutAVaultAColourCannotBeSavedAndSaysSo() {
    let engine = ThemeEngine(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())")!)
    engine.setCustomColor(.accentPrimary, to: RGBA(hex: "#FF0000")!)
    // Silently doing nothing would look like a colour picker that ignores the user.
    #expect(engine.customizationProblem != nil)
    #expect(engine.customization == nil)
}

// MARK: - Font customisation (ADR-0030 §D9, Task 7, R-11/R-12)

@Test func aFontOverrideRoundTripsByteForByteIncludingANamedFamilyWithASpace() throws {
    let directory = try TemporaryDirectory()
    // "Avenir Next" is the case `TypographyValue.Family.rawValue`'s round trip
    // (Task 1) exists to protect: a family name is carried verbatim, space and all,
    // never mistaken for the `system`/`monospace`/`serif` keywords.
    let draft = ThemeCustomization.Draft(
        appearance: .light,
        colors: [:],
        fonts: [.prose: TypographyValue(family: .named("Avenir Next"), size: 18, weight: 500, lineHeight: 1.45)]
    )
    try ThemeCustomization.write(draft, to: directory.url)
    #expect(ThemeCustomization.load(from: directory.url) == draft)
}

@Test func theSameFontDraftWrittenTwiceIsByteIdentical() throws {
    let first = try TemporaryDirectory()
    let second = try TemporaryDirectory()
    let draft = ThemeCustomization.Draft(
        appearance: .light,
        colors: [:],
        fonts: [
            .prose: TypographyValue(family: .named("Avenir Next"), size: 18, weight: 400, lineHeight: 1.4),
            .proseTitle: TypographyValue(family: .named("Avenir Next"), size: 26, weight: 700, lineHeight: 1.2),
        ]
    )
    try ThemeCustomization.write(draft, to: first.url)
    try ThemeCustomization.write(draft, to: second.url)
    // Same discipline `object(from:)`'s comment already states for colours, extended
    // to the second token type: a save that changed nothing must not diff.
    #expect(
        try Data(contentsOf: ThemeCustomization.url(in: first.url))
            == (try Data(contentsOf: ThemeCustomization.url(in: second.url)))
    )
}

@Test func loadOnAFileWithNoFontSectionReturnsEmptyFontsAndKeepsTheColours() throws {
    let directory = try TemporaryDirectory()
    // Hand-written, the shape a build before this chain would have produced: no
    // "font" key at all (R-12, "written by an older build").
    try """
    { "meta": {
        "name": { "$type": "string", "$value": "Personalizzato" },
        "appearance": { "$type": "string", "$value": "light" } },
      "color": { "accent": { "primary": { "$type": "color", "$value": "#123456" } } } }
    """.write(to: ThemeCustomization.url(in: directory.url), atomically: true, encoding: .utf8)

    let reloaded = try #require(ThemeCustomization.load(from: directory.url))
    #expect(reloaded.fonts.isEmpty)
    #expect(reloaded.colors[.accentPrimary] == RGBA(hex: "#123456")!)
}

@Test func loadOnAFileWithAFontSectionAndNoColoursReturnsTheFontsAndEmptyColours() throws {
    let directory = try TemporaryDirectory()
    try """
    { "meta": {
        "name": { "$type": "string", "$value": "Personalizzato" },
        "appearance": { "$type": "string", "$value": "light" } },
      "font": { "prose": { "$type": "typography", "$value": {
        "fontFamily": "Georgia", "fontSize": 20, "fontWeight": 400, "lineHeight": 1.4 } } } }
    """.write(to: ThemeCustomization.url(in: directory.url), atomically: true, encoding: .utf8)

    let reloaded = try #require(ThemeCustomization.load(from: directory.url))
    #expect(reloaded.colors.isEmpty)
    #expect(
        reloaded.fonts[.prose]
            == TypographyValue(family: .named("Georgia"), size: 20, weight: 400, lineHeight: 1.4)
    )
}

@Test func isEmptyIsFalseWithEitherFontsOrColoursAndTrueWithNeither() {
    let font = TypographyValue(family: .named("Georgia"), size: 20, weight: 400, lineHeight: 1.4)
    #expect(!ThemeCustomization.Draft(appearance: .light, colors: [:], fonts: [.prose: font]).isEmpty)
    #expect(!ThemeCustomization.Draft(appearance: .light, colors: [.accentPrimary: RGBA(hex: "#AABBCC")!], fonts: [:]).isEmpty)
    #expect(ThemeCustomization.Draft(appearance: .light, colors: [:], fonts: [:]).isEmpty)
}

@MainActor
@Test func clearingFontsRemovesTheFileWhenNoColourOverrideIsLeft() throws {
    let vault = try TemporaryDirectory()
    let engine = ThemeEngine(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())")!)
    engine.attach(vaultRoot: vault.url)
    let directory = try #require(engine.userThemesDirectory)

    // Written directly rather than through `setCustomFont` (itself under test
    // separately, and also a stub): this test only needs a font-only customisation
    // file already on disk before asking `clearCustomFonts()` to remove it, matching
    // what `clearCustomColor` already does through `resetCustomization()` (R-12).
    try ThemeCustomization.write(
        ThemeCustomization.Draft(
            appearance: .light,
            colors: [:],
            fonts: [.prose: TypographyValue(family: .named("Georgia"), size: 20, weight: 400, lineHeight: 1.4)]
        ),
        to: directory
    )
    #expect(FileManager.default.fileExists(atPath: ThemeCustomization.url(in: directory).path(percentEncoded: false)))

    engine.clearCustomFonts()

    #expect(!FileManager.default.fileExists(atPath: ThemeCustomization.url(in: directory).path(percentEncoded: false)))
}

@MainActor
@Test func withoutAVaultAFontCannotBeSavedAndSaysSo() {
    let engine = ThemeEngine(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())")!)
    engine.setCustomFont(.prose, to: TypographyValue(family: .named("Georgia"), size: 20, weight: 400, lineHeight: 1.4))
    // The same guard `setCustomColor` has: silently doing nothing would look like a
    // picker that ignores the user.
    #expect(engine.customizationProblem != nil)
    #expect(engine.customization == nil)
}

@MainActor
@Test func aWrittenFontOverrideReachesTheEngineAfterLoadUserThemes() throws {
    let vault = try TemporaryDirectory()
    let engine = ThemeEngine(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())")!)
    engine.attach(vaultRoot: vault.url)

    engine.setCustomFont(.prose, to: TypographyValue(family: .named("Georgia"), size: 20, weight: 400, lineHeight: 1.4))

    #expect(engine.customizationProblem == nil)
    #expect(engine.selection == .named(ThemeCustomization.id))
    // The assertion that proves the whole path rather than the file format: the
    // override has to reach the face an `NSTextView` actually draws with. The
    // bundled themes' `font.prose` is 16pt, so a mismatch here cannot pass by
    // accident.
    #expect(engine.current.nsFont(.prose).pointSize == 20)
}

// MARK: - Stale customisation appearance (bug: picking a font while dark silently
// switches the app to light, and "Ripristina" then reads as switching back)

@MainActor
@Test func choosingAFontWhileTheExplicitSelectionIsDarkKeepsTheCustomisationDark() throws {
    let vault = try TemporaryDirectory()
    let themes = vault.url
        .appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
        .appending(path: VaultLayout.themesDirectory, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
    // A `personalizzato.json` already on disk, declaring `light` - written in an
    // earlier session, or (as happened) by hand while testing a missing-font-family
    // fallback theme. Nothing about picking a font today should care which
    // appearance an old file on disk happens to declare.
    try ThemeCustomization.write(
        ThemeCustomization.Draft(appearance: .light, colors: [.accentPrimary: RGBA(hex: "#AABBCC")!]),
        to: themes
    )

    let engine = ThemeEngine(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())")!)
    engine.attach(vaultRoot: vault.url)
    // The explicit selection the person is actually looking at: dark, not the stale
    // file's light.
    engine.selection = .dark
    #expect(engine.current.appearance == .dark)

    engine.setCustomFont(.prose, to: TypographyValue(family: .named("Georgia"), size: 20, weight: 400, lineHeight: 1.4))

    // The bug: without a fix, `setCustomFont` reused the stale file's `.light` and
    // the app visibly flipped to the light theme the moment the font was picked.
    #expect(engine.current.appearance == .dark, "picking a font must not silently change the app's appearance")
    #expect(engine.customization?.appearance == .dark)
    let directory = try #require(engine.userThemesDirectory)
    #expect(ThemeCustomization.load(from: directory)?.appearance == .dark)
    // The colour chosen under the stale file survives the reconciliation - only the
    // appearance is corrected, nothing else about the customisation is discarded.
    #expect(engine.customization?.colors[.accentPrimary] == RGBA(hex: "#AABBCC")!)
}

@MainActor
@Test func choosingAColourWhileTheExplicitSelectionIsDarkKeepsTheCustomisationDark() throws {
    let vault = try TemporaryDirectory()
    let themes = vault.url
        .appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
        .appending(path: VaultLayout.themesDirectory, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
    try ThemeCustomization.write(
        ThemeCustomization.Draft(appearance: .light, colors: [:]),
        to: themes
    )

    let engine = ThemeEngine(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())")!)
    engine.attach(vaultRoot: vault.url)
    engine.selection = .dark

    engine.setCustomColor(.accentPrimary, to: RGBA(hex: "#112233")!)

    #expect(engine.current.appearance == .dark, "picking a colour must not silently change the app's appearance")
    #expect(engine.customization?.appearance == .dark)
}

@MainActor
@Test func choosingAFontWhileFollowingASystemDarkAppearanceKeepsTheCustomisationDark() throws {
    let vault = try TemporaryDirectory()
    let themes = vault.url
        .appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
        .appending(path: VaultLayout.themesDirectory, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
    try ThemeCustomization.write(
        ThemeCustomization.Draft(appearance: .light, colors: [:]),
        to: themes
    )

    let engine = ThemeEngine(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())")!)
    engine.attach(vaultRoot: vault.url)
    // `.followSystem` is the default selection; the system itself is in dark mode.
    engine.systemAppearance = .dark
    #expect(engine.selection == .followSystem)
    #expect(engine.current.appearance == .dark)

    engine.setCustomFont(.prose, to: TypographyValue(family: .named("Georgia"), size: 20, weight: 400, lineHeight: 1.4))

    #expect(engine.current.appearance == .dark)
}

@MainActor
@Test func aRememberedThemeThatThisVaultDoesNotHaveIsDropped() throws {
    let vault = try TemporaryDirectory()
    let defaults = UserDefaults(suiteName: "pergamenum.tests.\(UUID())")!
    defaults.set("named:tema-di-un-altro-vault", forKey: "theme.selection")

    let engine = ThemeEngine(defaults: defaults)
    #expect(engine.selection == .named("tema-di-un-altro-vault"))

    engine.attach(vaultRoot: vault.url)
    // The picker showed an empty selection otherwise, which reads as a broken
    // control rather than as a theme that belongs to another vault.
    #expect(engine.selection == .followSystem)
}
