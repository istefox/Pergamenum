import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0030 §D1, plan 2026-09-04-editor-page-typography-noteplan, Task 2 (R-03, R-06, R-07).
//
// Scope of this file: `ProseTypography` only - the one place `Sources/Features/Editor` +
// `Sources/Features/Workspace` scope is allowed to construct an `NSFont` (ADR §D1). Every
// function below is a `fatalError` stub until the coder fills it in
// (`Sources/DesignSystem/ProseTypography.swift`), so every `@Test` in this file is expected to
// crash the run, not merely fail an assertion, until then - the same TDD shape
// `Tests/CardTextViewTests.swift` documents for the card's own attribute table.
//
// PLAN DEVIATION (ADR-0073 §D2): both the dispatch brief and this plan's Task 2 cell claim
// `Tests/CardTextViewTests.swift`'s italic assertion is the regression guard for R-06. As of this
// dispatch that file (read in full before writing this suite) has no italic test at all - its
// two `@Test`s cover only `.bold` (the monospace regression) and the To-Do-prefix independence
// rule (R-09). There is therefore no existing italic assertion to regress against; this file's
// own `proseItalicAttributes` tests below are the first coverage of that rule anywhere in the
// suite, mirroring `CardTextAttributes.italicAttributes`'s current body (read directly,
// `Sources/Features/Workspace/CardTextAttributes.swift:162-171`) rather than the plan's claim
// about where it already lives. Reported rather than silently written around, per instructions;
// not a reason to skip the assertions themselves.
@Suite struct ProseTypographyTests {
    // MARK: - Fixtures

    /// Builds a `Theme` inheriting everything from `.emergency` except the two page-face tokens,
    /// which are declared explicitly so a test controls exactly what `prose`/`proseTitle` say -
    /// this is what makes the R-03 "changing the theme changes the levels" assertion real rather
    /// than incidental to whatever `Theme.emergency` happens to carry today.
    private static func theme(
        proseFamily: String = "Avenir Next",
        proseSize: CGFloat = 16,
        proseWeight: Int = 400,
        proseLineHeight: Double = 1.4,
        proseTitleFamily: String = "Avenir Next",
        proseTitleSize: CGFloat = 24,
        proseTitleWeight: Int = 700
    ) throws -> Theme {
        let json = """
        {
          "font": {
            "prose": {
              "$type": "typography",
              "$value": {
                "fontFamily": "\(proseFamily)",
                "fontSize": \(proseSize),
                "fontWeight": \(proseWeight),
                "lineHeight": \(proseLineHeight)
              }
            },
            "proseTitle": {
              "$type": "typography",
              "$value": {
                "fontFamily": "\(proseTitleFamily)",
                "fontSize": \(proseTitleSize),
                "fontWeight": \(proseTitleWeight),
                "lineHeight": 1.2
              }
            }
          }
        }
        """
        let document = try DesignTokenDocument(data: Data(json.utf8), fallbackName: "prose-typography-test")
        return Theme(document: document, id: "prose-typography-test", inheriting: .emergency)
    }

    /// A family installed on every machine this suite runs on (verified directly: `find
    /// /System/Library/Fonts -iname '*avenir*'` lists `Avenir Next.ttc`) with a real bold face
    /// (`AvenirNext-Bold`) and a real italic face (`AvenirNext-Italic`) - confirmed with a
    /// throwaway AppKit probe before writing this file, not assumed.
    private static let familyWithBoldAndItalic = "Avenir Next"

    /// A family installed on every macOS machine (`/System/Library/Fonts/Papyrus.ttc`) that
    /// genuinely has neither a bold nor an italic face - also confirmed with the same probe:
    /// `NSFont(descriptor:size:)` on a `.bold`/`.italic`-augmented `Papyrus` descriptor returns
    /// `nil`, not a font merely lacking the trait. This is the real "no bold/italic face" case
    /// the brief asks for, not a documented-but-unverified fallback path.
    private static let familyWithNeitherBoldNorItalic = "Papyrus"

    // MARK: - prose(_:) / proseBold(_:) (R-06)

    @Test func proseIsThemeNsFontProse() throws {
        let theme = try Self.theme()
        #expect(ProseTypography.prose(theme).fontName == theme.nsFont(.prose).fontName)
    }

    @Test func proseBoldIsTheSameFamilysBoldFaceAndNeverMonospaced() throws {
        let theme = try Self.theme(proseFamily: Self.familyWithBoldAndItalic)
        let bold = ProseTypography.proseBold(theme)
        let traits = bold.fontDescriptor.symbolicTraits

        #expect(!traits.contains(.monoSpace), "proseBold must never fall back to a monospaced face")
        #expect(traits.contains(.bold), "a family with a real bold face must produce a genuinely bold font")
        #expect(
            bold.familyName == ProseTypography.prose(theme).familyName,
            "R-06: falls back to the regular face rather than to a monospaced one - and stays in the same family"
        )
    }

    @Test func proseBoldOnAFamilyWithNoBoldFaceReturnsTheRegularFaceNeverNilNeverASystemSubstitute() throws {
        let theme = try Self.theme(proseFamily: Self.familyWithNeitherBoldNorItalic, proseWeight: 700)
        let bold = ProseTypography.proseBold(theme)
        let regular = ProseTypography.prose(theme)

        // `NSFont` is non-optional in the signature, so "never nil" is enforced by the type
        // system; what this test pins down is that the *value* returned is the regular face of
        // the same family, not a system font substituted in when the bold descriptor fails.
        #expect(bold.fontName == regular.fontName)
        #expect(bold.familyName == Self.familyWithNeitherBoldNorItalic)
        #expect(!bold.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    // MARK: - proseItalicAttributes(_:) (R-06)
    //
    // `CardTextAttributes.italicAttributes`'s rule, read directly from
    // `Sources/Features/Workspace/CardTextAttributes.swift:162-171` rather than assumed: a real
    // italic face when the family has one, `[.obliqueness: 0.2]` on the upright face otherwise.
    // See the PLAN DEVIATION note at the top of this file for why this is not, in fact, a moved
    // assertion from `Tests/CardTextViewTests.swift`.

    @Test func italicAttributesCarryTheRealItalicFaceWhenTheFamilyHasOne() throws {
        let theme = try Self.theme(proseFamily: Self.familyWithBoldAndItalic)
        let attributes = ProseTypography.proseItalicAttributes(theme)
        let font = try #require(attributes[.font] as? NSFont, "an italic face must be carried under .font")
        #expect(font.fontDescriptor.symbolicTraits.contains(.italic))
        #expect(attributes[.obliqueness] == nil, "a real italic face must not also carry an obliqueness fallback")
    }

    @Test func italicAttributesFallBackToObliquenessWhenTheFamilyHasNoItalicFace() throws {
        let theme = try Self.theme(proseFamily: Self.familyWithNeitherBoldNorItalic)
        let attributes = ProseTypography.proseItalicAttributes(theme)
        // Read through `NSNumber` rather than `as? CGFloat`/`as? Double` directly: the boxed
        // numeric type an implementation happens to use (`Double` vs `CGFloat`) is an
        // implementation detail neither this test nor `CardTextAttributes.italicAttributes`'s
        // own `[.obliqueness: 0.2]` literal commits to.
        let obliqueness = try #require(attributes[.obliqueness] as? NSNumber)
        #expect(obliqueness.doubleValue == 0.2)
        #expect(attributes[.font] == nil, "the fallback case must not also carry a substituted .font")
    }

    // MARK: - heading(level:_:) (R-03)

    /// `max(prose + 1, proseTitle − (level − 1) × 2)` for prose 16 / proseTitle 24 (ADR §D1's
    /// worked example): 24, 22, 20, 18, 17, 17.
    @Test func headingSizesForTheDocumentedExample() throws {
        let theme = try Self.theme(proseSize: 16, proseTitleSize: 24)
        let sizes = (1...6).map { ProseTypography.heading(level: $0, theme).pointSize }
        #expect(sizes == [24, 22, 20, 18, 17, 17])
    }

    /// R-03's actual claim: changing `font.proseTitle` in the theme changes every level with no
    /// code change. A second, independent `Theme` with `proseTitle` raised to 30 must move all
    /// six sizes - this is the assertion that makes R-03 real rather than incidentally true of
    /// one theme.
    @Test func headingSizesTrackANewProseTitleWithNoCodeChange() throws {
        let theme = try Self.theme(proseSize: 16, proseTitleSize: 30)
        let sizes = (1...6).map { ProseTypography.heading(level: $0, theme).pointSize }
        #expect(sizes == [30, 28, 26, 24, 22, 20])
    }

    /// The floor: no level may render smaller than `prose + 1`, even when `proseTitle` is close
    /// to or below `prose`'s own size.
    @Test func headingSizeNeverDropsBelowProsePlusOne() throws {
        let theme = try Self.theme(proseSize: 16, proseTitleSize: 10)
        let sizes = (1...6).map { ProseTypography.heading(level: $0, theme).pointSize }
        #expect(sizes.allSatisfy { $0 >= 17 })
        // At this prose/proseTitle pairing every level actually hits the floor.
        #expect(sizes == [17, 17, 17, 17, 17, 17])
    }

    @Test func headingLevelOutOfRangeIsClampedRatherThanCrashing() throws {
        let theme = try Self.theme(proseSize: 16, proseTitleSize: 24)
        let level1 = ProseTypography.heading(level: 1, theme).pointSize
        let level6 = ProseTypography.heading(level: 6, theme).pointSize

        #expect(ProseTypography.heading(level: 0, theme).pointSize == level1)
        #expect(ProseTypography.heading(level: -5, theme).pointSize == level1)
        #expect(ProseTypography.heading(level: 99, theme).pointSize == level6)
    }

    // MARK: - paragraphStyle(_:basedOn:) (R-07)

    @Test func paragraphStyleCarriesTheProseTokensLineHeightAndNoSpacing() throws {
        let theme = try Self.theme(proseLineHeight: 1.4)
        let style = ProseTypography.paragraphStyle(theme)
        #expect(style.lineHeightMultiple == 1.4)
        #expect(style.paragraphSpacing == 0, "R-07: no paragraphSpacing is added to a plain paragraph")
    }

    @Test func paragraphStyleTracksTheThemesOwnLineHeightToken() throws {
        let theme = try Self.theme(proseLineHeight: 1.8)
        let style = ProseTypography.paragraphStyle(theme)
        #expect(style.lineHeightMultiple == 1.8)
    }

    /// The composition assertion Tasks 3/4 depend on: an existing style's own `paragraphSpacing`
    /// and `firstLineHeadIndent` (list markers, transclusion `reservedHeight`, card alignment all
    /// build one of these) must survive, with only the line-height multiple added on top.
    @Test func paragraphStyleComposesOntoAnExistingStyleWithoutDroppingItsOwnProperties() throws {
        let theme = try Self.theme(proseLineHeight: 1.4)
        let base = NSMutableParagraphStyle()
        base.paragraphSpacing = 44
        base.firstLineHeadIndent = 24
        base.alignment = .center

        let composed = ProseTypography.paragraphStyle(theme, basedOn: base)

        #expect(composed.paragraphSpacing == 44, "an existing paragraphSpacing must not be overwritten")
        #expect(composed.firstLineHeadIndent == 24, "an existing indentation must not be overwritten")
        #expect(composed.alignment == .center, "an unrelated existing property must survive composition")
        #expect(composed.lineHeightMultiple == 1.4, "the theme's own line height must still be added")
    }

    // MARK: - mono(_:size:) (chrome/code face, unaffected by prose tokens)

    @Test func monoIsThemeNsFontMono() throws {
        let theme = try Self.theme()
        #expect(ProseTypography.mono(theme).fontName == theme.nsFont(.mono).fontName)
    }

    @Test func monoAtAnExplicitSizeIsTheSameFamilyAtThatSize() throws {
        let theme = try Self.theme()
        let resized = ProseTypography.mono(theme, size: 10)
        #expect(resized.pointSize == 10)
        #expect(resized.familyName == theme.nsFont(.mono).familyName)
        #expect(resized.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }
}
