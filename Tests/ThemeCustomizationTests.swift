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

@MainActor
@Test func withoutAVaultAColourCannotBeSavedAndSaysSo() {
    let engine = ThemeEngine(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())")!)
    engine.setCustomColor(.accentPrimary, to: RGBA(hex: "#FF0000")!)
    // Silently doing nothing would look like a colour picker that ignores the user.
    #expect(engine.customizationProblem != nil)
    #expect(engine.customization == nil)
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
