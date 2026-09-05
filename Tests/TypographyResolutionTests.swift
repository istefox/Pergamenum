import AppKit
import Foundation
import Testing
@testable import Pergamenum

/// ADR-0030 §D3: a named font family is a fourth `TypographyValue.Family` case, and a
/// theme resolves it to an installed `NSFont` (falling back to the system face when it
/// is not installed), never to `nil` and never silently to a monospaced substitute.
///
/// Several assertions here are expected to stay red until the coder fills
/// `Theme.nsFont(_:)`'s `.named` arm and `Theme.font(_:)`/`asDesign`'s - see the
/// `TESTER STUB` comments in `Theme.swift` and `DesignTokenDocument.swift`. Task 1's
/// budget does not include implementing that resolution.

// MARK: - Family: rawValue round-trip

@Test func familyRawValueGivesTheThreeKnownCases() {
    #expect(TypographyValue.Family(rawValue: "system") == .system)
    #expect(TypographyValue.Family(rawValue: "monospace") == .monospace)
    #expect(TypographyValue.Family(rawValue: "serif") == .serif)
}

@Test(arguments: ["Avenir Next", "Helvetica Neue", "", "Totally Not A Font"])
func familyRawValueGivesNamedForAnythingElse(_ raw: String) {
    #expect(TypographyValue.Family(rawValue: raw) == .named(raw))
}

/// Protects the hand-written conformance: a case whose `rawValue` does not feed
/// `init(rawValue:)` back to itself would silently break "the family name a theme
/// file stores is the family name it reads back", `.named` included.
///
/// `.named("system")` is deliberately not one of the arguments: the three built-in
/// keywords are reserved, so a family that happens to be spelled exactly like one of
/// them cannot round-trip as `.named` by construction, not by a defect in this
/// conformance - `Family(rawValue: "system")` has to mean the design keyword.
@Test(arguments: [
    TypographyValue.Family.system,
    .monospace,
    .serif,
    .named("Avenir Next"),
    .named("Helvetica Neue"),
])
func familyRawValueRoundTripsEveryCaseVerbatim(_ family: TypographyValue.Family) {
    #expect(TypographyValue.Family(rawValue: family.rawValue) == family)
}

// MARK: - DTCG parsing

@Test func typographyTokenWithNamedFontFamilyParsesToTheNamedCase() throws {
    let json = """
    { "font": { "prose": { "$type": "typography",
        "$value": { "fontFamily": "Avenir Next", "fontSize": 16, "fontWeight": 400, "lineHeight": 1.4 } } } }
    """
    let document = try DesignTokenDocument(data: Data(json.utf8), fallbackName: "test")
    #expect(document.tokens["font.prose"] == .typography(
        TypographyValue(family: .named("Avenir Next"), size: 16, weight: 400, lineHeight: 1.4)
    ))
}

@Test func typographyTokenWithoutFontFamilyStillDefaultsToSystem() throws {
    let json = """
    { "font": { "prose": { "$type": "typography",
        "$value": { "fontSize": 16, "fontWeight": 400, "lineHeight": 1.4 } } } }
    """
    let document = try DesignTokenDocument(data: Data(json.utf8), fallbackName: "test")
    #expect(document.tokens["font.prose"] == .typography(
        TypographyValue(family: .system, size: 16, weight: 400, lineHeight: 1.4)
    ))
}

// MARK: - Theme resolution

@Test func nsFontOnAnInstalledNamedFamilyResolvesToThatFamily() throws {
    let theme = try themeNamingProse(family: "Avenir Next")
    #expect(theme.nsFont(.prose).familyName == "Avenir Next")
}

@Test func nsFontBoldWeightOnANamedFamilyResolvesToTheBoldFace() throws {
    let regular = try themeNamingProse(family: "Avenir Next", weight: 400).nsFont(.prose)
    let bold = try themeNamingProse(family: "Avenir Next", weight: 700).nsFont(.prose)

    #expect(bold.fontDescriptor.symbolicTraits.contains(.bold))
    // A weight-trait-only route can silently return the regular face for a named
    // family (ADR §Context probe) - comparing the two resolved names is what a
    // trait-only check alone would miss.
    #expect(bold.fontName != regular.fontName)
    // Measured against the current `.named` stub (`NSFont.systemFont(weight:)`):
    // that call alone already satisfies both assertions above, because a bold
    // *system* weight also carries the `.bold` trait and a different font name from
    // the regular system weight. Only this exact-name check actually requires the
    // family to have resolved to Avenir Next, so it is the one that stays red until
    // the coder implements the real `.named` arm.
    #expect(bold.fontName == "AvenirNext-Bold")
}

@Test func nsFontOnAnUninstalledNamedFamilyFallsBackToSystemFontAtTheTokensOwnSizeAndWeight() throws {
    let theme = try themeNamingProse(family: "Totally Not A Font", weight: 400, size: 16)
    let font = theme.nsFont(.prose)
    let expected = NSFont.systemFont(ofSize: 16, weight: .regular)
    #expect(font.fontName == expected.fontName)
    #expect(font.pointSize == 16)
}

/// `theme.font(_:)` (SwiftUI) has to be built from the same resolved face
/// `theme.nsFont(_:)` uses, or the editor's page and its own font picker would
/// disagree about what "Avenir Next" looks like. SwiftUI's `Font` cannot be
/// inspected for a custom font name, so this pins the internal resolver
/// (`Theme.resolvedFontName(_:)`) instead of asserting nothing.
@Test func resolvedFontNameMatchesTheActuallyResolvedFace() throws {
    let theme = try themeNamingProse(family: "Avenir Next", weight: 400)
    #expect(theme.resolvedFontName(.prose) == "AvenirNext-Regular")
}

// MARK: - Helpers

private func themeNamingProse(
    family: String,
    weight: Int = 400,
    size: CGFloat = 16,
    lineHeight: Double = 1.4
) throws -> Theme {
    let json = """
    { "font": { "prose": { "$type": "typography",
        "$value": { "fontFamily": "\(family)", "fontSize": \(size), "fontWeight": \(weight), "lineHeight": \(lineHeight) } } } }
    """
    let document = try DesignTokenDocument(data: Data(json.utf8), fallbackName: "test")
    return Theme(document: document, id: "test", inheriting: .emergency)
}
