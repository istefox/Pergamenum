import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0030 §D1/§D2, plan 2026-09-04-editor-page-typography-noteplan, Task 3 (R-01, R-02, R-07).
//
// Scope of this file: `MarkdownAttributedText.base(theme:)` and `.attributes(for:theme:links:)`
// read through `ProseTypography` and `theme.nsFont(.mono)` rather than the three literal
// `NSFont.` constructions the file has today (`:18` monospaced base, `:52` system heading,
// `:56` monospaced bold). Every assertion below is checked against the file as read in full
// before writing this suite (`Sources/Features/Editor/MarkdownAttributedText.swift`), not
// against the plan's paraphrase of it.
//
// PLAN DEVIATION (ADR-0073 §D2): the plan's Task 3 cell says "a `.code` span inside a heading
// keeps the mono face at the heading's size (SPEC §8)". `docs/20260811_Pergamenum_SpecApp.md`
// §8 is "Calendario e integrazione Apple" - unrelated - and the roadmap document ADR-0030
// itself cites for this feature, `docs/20260904_Editor_Page_Roadmap.md`, does not exist in
// this tree. There is no document anywhere in the repo that states an exact expected point
// size for this case. Tracing the mechanism directly (`MarkdownStyler.spans(in:)`: a line's
// `.heading` span is appended before that same line's inline spans, `attributed(_:theme:)`
// applies `addAttributes(range:)` in that order, and a later span's `.font` replaces rather
// than composes with an earlier one within the overlapping range) shows the natural
// consequence of Task 3's own instruction ("`.code` ... resolve to `theme.nsFont(.mono)`") is
// that the code substring lands at `font.mono`'s own configured size, not resized to the
// heading's - nothing in this task's coder instructions ("rewrites the three `NSFont.` sites
// ... adds `.paragraphStyle` to `base(theme:)`") describes the context-aware resizing that
// would be needed to make the two sizes equal. Rather than inventing a size the SPEC never
// declared, `codeInsideAHeadingStaysMonospacedRatherThanInheritingTheHeadingsFace` below
// asserts the part that is actually load-bearing and traceable to the mechanism: the mono
// face wins over the heading's face for that nested range. Flagged for the coder/architect to
// confirm rather than silently asserting an unverifiable number.
@MainActor
@Suite struct MarkdownAttributedTextTests {
    // MARK: - Fixtures

    /// A theme identical to `.emergency` except for `font.prose`, so the italic-fallback test
    /// can name a family with no italic face without touching anything else `.emergency`
    /// carries. Mirrors `ProseTypographyTests`' own fixture builder (`Tests/ProseTypographyTests.swift`).
    private static func theme(proseFamily: String) throws -> Theme {
        let json = """
        {
          "font": {
            "prose": {
              "$type": "typography",
              "$value": {
                "fontFamily": "\(proseFamily)",
                "fontSize": 16,
                "fontWeight": 400,
                "lineHeight": 1.4
              }
            }
          }
        }
        """
        let document = try DesignTokenDocument(data: Data(json.utf8), fallbackName: "markdown-attributed-text-test")
        return Theme(document: document, id: "markdown-attributed-text-test", inheriting: .emergency)
    }

    /// `/System/Library/Fonts/Papyrus.ttc` - verified by `ProseTypographyTests` to have
    /// neither a bold nor an italic face.
    private static let familyWithNoItalic = "Papyrus"

    // MARK: - base(theme:) (R-02, R-07)

    @Test func baseFontIsProseTypographyProseNeverMonospaced() throws {
        let theme = Theme.emergency
        let font = try #require(MarkdownAttributedText.base(theme: theme)[.font] as? NSFont)
        let expected = ProseTypography.prose(theme)

        #expect(font.familyName == expected.familyName)
        #expect(font.pointSize == expected.pointSize)
        #expect(
            !font.fontDescriptor.symbolicTraits.contains(.monoSpace),
            "R-02: the editor's base body face must not be the monospaced 13pt literal"
        )
    }

    @Test func baseParagraphStyleCarriesTheProseLineHeightAndNoSpacing() throws {
        let theme = Theme.emergency
        let style = try #require(MarkdownAttributedText.base(theme: theme)[.paragraphStyle] as? NSParagraphStyle)

        #expect(style.lineHeightMultiple == ProseTypography.paragraphStyle(theme).lineHeightMultiple)
        #expect(style.paragraphSpacing == 0, "R-07: a plain base style adds no paragraphSpacing")
    }

    // MARK: - .heading(level:) (R-01)

    @Test func headingAttributesMatchProseTypographyHeadingForEveryLevel() {
        let theme = Theme.emergency
        for level in 1...6 {
            let font = MarkdownAttributedText.attributes(for: .heading(level: level), theme: theme)[.font] as? NSFont
            let expected = ProseTypography.heading(level: level, theme)

            #expect(font?.pointSize == expected.pointSize, "level \(level)")
            #expect(font?.fontName == expected.fontName, "level \(level)")
        }
    }

    /// Regression for the bug reported against this file (attributes(for: .heading(level:)),
    /// ~lines 57-61): a heading run's `.font`/`.foregroundColor` are set, but `.paragraphStyle`
    /// is left unset entirely, so `NSMutableAttributedString.addAttributes(range:)` never
    /// overwrites the single `base(theme:)`-supplied style every paragraph starts with. That
    /// base style's `lineHeightMultiple` is computed from `font.prose`'s 16pt size
    /// (`ProseTypography.lineHeightMultiple`), never from the actual heading font, which can be
    /// as large as `font.proseTitle`'s 24pt at H1 (`ProseTypography.heading(level:_:)`). The
    /// laid-out line box for a heading is therefore body-sized regardless of level, and the
    /// extra space that should scale with the heading's own font does not — this is what pushes
    /// `FoldedHeadingFragment`'s badge (centered on `typographicBounds`) out of alignment with
    /// the heading glyphs at H1/H2, though the badge's own centering math is correct and out of
    /// scope for this fix (do not touch `FoldedHeadingFragment.badgeFrame`).
    ///
    /// This asserts the invariant the coder must restore: an H1 heading's effective paragraph
    /// line height must differ from (be proportionately taller than) the plain-body paragraph
    /// style's line height, tracking the H1/prose font-size ratio — not merely be non-nil, and
    /// not merely be present, since a `.paragraphStyle` equal to the body's would still keep the
    /// bug (it is the not-scaling that is wrong, not the absence of a key). The `1` sentinel
    /// check on `bodyStyle.lineHeightMultiple` guards against a body style that already reads as
    /// "no line height applied" making this comparison vacuous.
    @Test func headingParagraphStyleLineHeightScalesWithTheHeadingsOwnFontSize() throws {
        let theme = Theme.emergency

        let bodyStyle = try #require(MarkdownAttributedText.base(theme: theme)[.paragraphStyle] as? NSParagraphStyle)
        #expect(bodyStyle.lineHeightMultiple != 1, "fixture sanity: the body style must carry a real line height")

        let headingAttributes = MarkdownAttributedText.attributes(for: .heading(level: 1), theme: theme)
        let headingStyle = try #require(
            headingAttributes[.paragraphStyle] as? NSParagraphStyle,
            "a heading run must carry its own .paragraphStyle, scaled to the heading's font size, not silently inherit the body-sized style base(theme:) already applied to the paragraph"
        )

        let proseSize = ProseTypography.prose(theme).pointSize
        let headingSize = ProseTypography.heading(level: 1, theme).pointSize
        let expectedMultiple = bodyStyle.lineHeightMultiple * (headingSize / proseSize)

        #expect(
            headingStyle.lineHeightMultiple != bodyStyle.lineHeightMultiple,
            "H1's line height must not be identical to the body's — it must scale with the larger heading font"
        )
        #expect(
            abs(headingStyle.lineHeightMultiple - expectedMultiple) < 0.01,
            "H1's lineHeightMultiple (\(headingStyle.lineHeightMultiple)) must track the heading/prose font-size ratio (expected ~\(expectedMultiple))"
        )
    }

    // MARK: - .bold (R-01, R-02)

    @Test func boldIsTheProseFamilysBoldFaceAndNeverMonospaced() throws {
        let theme = Theme.emergency
        let font = try #require(MarkdownAttributedText.attributes(for: .bold, theme: theme)[.font] as? NSFont)
        let expected = ProseTypography.proseBold(theme)

        #expect(font.fontName == expected.fontName)
        #expect(
            !font.fontDescriptor.symbolicTraits.contains(.monoSpace),
            "R-02's explicit clause: .bold must not stay the monospaced 13pt bold literal"
        )
    }

    // MARK: - .italic (R-06)

    @Test func italicCarriesARealItalicFaceForAFamilyThatHasOne() throws {
        let theme = Theme.emergency
        let attributes = MarkdownAttributedText.attributes(for: .italic, theme: theme)
        let font = try #require(attributes[.font] as? NSFont, "an italic face must be carried under .font")

        #expect(font.fontDescriptor.symbolicTraits.contains(.italic))
        #expect(attributes[.obliqueness] == nil, "a real italic face must not also carry an obliqueness fallback")
    }

    @Test func italicFallsBackToObliquenessForAFamilyWithNoItalicFace() throws {
        let theme = try Self.theme(proseFamily: Self.familyWithNoItalic)
        let attributes = MarkdownAttributedText.attributes(for: .italic, theme: theme)
        let obliqueness = try #require(attributes[.obliqueness] as? NSNumber)

        #expect(obliqueness.doubleValue == 0.2)
        #expect(attributes[.font] == nil, "the fallback case must not also carry a substituted .font")
    }

    // MARK: - .code / .codeBlock / .codeToken / .frontmatter (R-02)

    @Test func codeCodeBlockCodeTokenAndFrontmatterAllResolveToTheThemesMonoFace() throws {
        let theme = Theme.emergency
        let mono = theme.nsFont(.mono)
        let spans: [MarkdownStyler.Span] = [.code, .codeBlock, .frontmatter, .codeToken(.keyword)]

        for span in spans {
            let font = try #require(
                MarkdownAttributedText.attributes(for: span, theme: theme)[.font] as? NSFont,
                "\(span) must carry an explicit .font, not fall through to `default`'s colour-only case"
            )
            #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace), "\(span) must be monospaced")
            #expect(
                font.pointSize == mono.pointSize,
                "\(span) must sit at font.mono's own size, not the editor base's incidental 13pt"
            )
            #expect(font.familyName == mono.familyName, "\(span)")
        }
    }

    /// See the PLAN DEVIATION note at the top of this file: only the traceable half of the
    /// plan's claim is asserted here, not an unverifiable exact point size.
    @Test func codeInsideAHeadingStaysMonospacedRatherThanInheritingTheHeadingsFace() throws {
        let theme = Theme.emergency
        let text = "# Titolo `codice`"
        let attributed = MarkdownAttributedText.attributed(text, theme: theme)
        let codeRange = try #require((text as NSString).range(of: "codice") as NSRange?)
        #expect(codeRange.location != NSNotFound)

        let font = try #require(
            attributed.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
        )
        let headingFont = try #require(
            attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        #expect(font.familyName == theme.nsFont(.mono).familyName)
        #expect(
            font.familyName != headingFont.familyName,
            "the nested code run must not keep reading as the heading's own face"
        )
    }

    // MARK: - attributed(_:theme:) composed (R-01, R-02)

    @Test func aWholeNoteWithHeadingBoldItalicAFenceAndALinkUsesOnlyProseOrMonoFamilies() {
        let theme = Theme.emergency
        let text = """
        # Titolo

        Testo con **grassetto** e *corsivo*.

        ```swift
        func demo() {}
        ```

        Vedi [[Nota collegata]].
        """
        let attributed = MarkdownAttributedText.attributed(text, theme: theme)
        let proseFamily = ProseTypography.prose(theme).familyName
        let monoFamily = theme.nsFont(.mono).familyName

        var offenders: [String] = []
        attributed.enumerateAttribute(
            .font, in: NSRange(location: 0, length: attributed.length)
        ) { value, range, _ in
            guard let font = value as? NSFont else { return }
            guard font.familyName == proseFamily || font.familyName == monoFamily else {
                offenders.append("\(font.familyName ?? font.fontName) at \(range)")
                return
            }
        }
        #expect(offenders.isEmpty, "unexpected font families in the composed note: \(offenders)")
    }

    // MARK: - Link resolution (issue #188, R-01…R-04, R-14)
    //
    // Pure resolution from a clicked link/wikilink target to its navigation target, independent
    // of any AppKit click simulation - `targetURL(for:)` builds the `.link` attribute's URL at
    // styling time, `clickTarget(for:)` decodes it back at click time, and every case here
    // round-trips one through the other.

    @Test func targetURLForAWikilinkTitleEncodesItAsANoteReference() throws {
        let url = try #require(MarkdownAttributedText.targetURL(for: "Nota collegata"))
        #expect(MarkdownAttributedText.clickTarget(for: url) == .note(title: "Nota collegata"))
    }

    @Test func targetURLForACanvasMarkerEncodesTheWholeTargetIncludingTheExtension() throws {
        // `^[[board.canvas]]` styles through the same `.linkTarget` span as an ordinary
        // wikilink - deciding that a `.canvas` suffix means a board is `CommandActions.
        // open(link:)`'s job (ADR-0039 reuse), not this decoder's, so it round-trips as a
        // plain `.note` target here.
        let url = try #require(MarkdownAttributedText.targetURL(for: "Progetti/board.canvas"))
        #expect(MarkdownAttributedText.clickTarget(for: url) == .note(title: "Progetti/board.canvas"))
    }

    @Test func targetURLForAVaultRelativeMarkdownLinkStripsTheExtensionBeforeEncoding() throws {
        let url = try #require(MarkdownAttributedText.targetURL(for: "Nota.md"))
        #expect(MarkdownAttributedText.clickTarget(for: url) == .note(title: "Nota"))
    }

    @Test func targetURLForAnExternalHTTPSHrefIsTheURLItself() throws {
        let url = try #require(MarkdownAttributedText.targetURL(for: "https://example.com/page"))
        #expect(url.absoluteString == "https://example.com/page")
        #expect(MarkdownAttributedText.clickTarget(for: url) == .external(url))
    }

    @Test func targetURLForAnExternalHTTPHrefIsTheURLItself() throws {
        let url = try #require(MarkdownAttributedText.targetURL(for: "http://example.com"))
        #expect(MarkdownAttributedText.clickTarget(for: url) == .external(url))
    }

    @Test func clickTargetDecodesAnEmbedURLAsTheEmbedCase() {
        let url = MarkdownAttributedText.embedURL(for: "foto.png")
        #expect(MarkdownAttributedText.clickTarget(for: url) == .embed(name: "foto.png"))
    }

    @Test func clickTargetReturnsNilForAURLItDoesNotRecognize() {
        // Neither `http(s)` nor this app's own `pergamenum://` scheme with a `note`/`embed`
        // host: nothing to navigate to, and the click should fall through untouched.
        let url = URL(string: "file:///Users/x/y.txt")!
        #expect(MarkdownAttributedText.clickTarget(for: url) == nil)
    }

    // MARK: - CommonMark links get a real clickable target (issue #188)

    @Test func aCommonMarkLinkLabelCarriesLinkAndCursorForAnExternalURL() {
        let theme = Theme.emergency
        let attributed = MarkdownAttributedText.attributed("[apri](https://example.com)", theme: theme)
        let labelRange = ("[apri](https://example.com)" as NSString).range(of: "apri")
        let link = attributed.attribute(.editorLink, at: labelRange.location, effectiveRange: nil) as? URL
        #expect(link?.absoluteString == "https://example.com")
        #expect(attributed.attribute(.cursor, at: labelRange.location, effectiveRange: nil) != nil)
    }

    @Test func aCommonMarkLinkLabelCarriesLinkAndCursorForAVaultRelativeNote() throws {
        let theme = Theme.emergency
        let attributed = MarkdownAttributedText.attributed("[vedi](Nota.md)", theme: theme)
        let labelRange = ("[vedi](Nota.md)" as NSString).range(of: "vedi")
        let link = try #require(
            attributed.attribute(.editorLink, at: labelRange.location, effectiveRange: nil) as? URL
        )
        #expect(MarkdownAttributedText.clickTarget(for: link) == .note(title: "Nota"))
    }

    // MARK: - StyleContext (Task 2, PG-139/#239)
    //
    // `attributes(for:theme:links:)` is now a two-line wrapper over a fresh `StyleContext` -
    // these pin that the wrapper and the context it builds never drift apart, one span kind
    // at a time, and that the memoised heading dictionary answers the same thing twice.

    /// Structural equality for two attribute dictionaries - `[NSAttributedString.Key: Any]`
    /// is not itself `Equatable`, so this bridges both sides to `NSDictionary`, whose
    /// `isEqual` deep-compares every value (`NSFont`/`NSColor`/`NSParagraphStyle`/`NSCursor`/
    /// `URL`/`NSNumber` all support it).
    private static func attributesMatch(
        _ lhs: [NSAttributedString.Key: Any], _ rhs: [NSAttributedString.Key: Any]
    ) -> Bool {
        let left = Dictionary(uniqueKeysWithValues: lhs.map { ($0.key.rawValue, $0.value) })
        let right = Dictionary(uniqueKeysWithValues: rhs.map { ($0.key.rawValue, $0.value) })
        return NSDictionary(dictionary: left).isEqual(NSDictionary(dictionary: right))
    }

    /// One example of every `MarkdownStyler.Span` case - the exhaustive list this suite must
    /// keep in step with the enum, the same discipline `colorToken(for:)`'s own switch (no
    /// `default`) already enforces in production.
    private static let everySpanKind: [MarkdownStyler.Span] = [
        .frontmatter,
        .heading(level: 3),
        .headingMarker,
        .bold,
        .italic,
        .emphasisMarker,
        .strikethrough,
        .code,
        .linkSyntax,
        .linkTarget("Nota"),
        .embedTarget("foto.png"),
        .embedRun,
        .tag("#project-pergamenum"),
        .codeBlock,
        .codeToken(.keyword),
        .taskMarker(state: .open),
        .scheduled,
        .due,
        .annotation,
        .listMarker(kind: .bullet, level: 2),
        .blockquoteMarker(level: 1),
        .strikethroughMarker,
        .horizontalRule,
        .tableRun,
        .viewBlockRun,
    ]

    @Test func styleContextAttributesMatchTheStaticWrapperForEverySpanKind() {
        let theme = Theme.emergency
        for span in Self.everySpanKind {
            var context = MarkdownAttributedText.StyleContext(theme: theme, links: true)
            let fromContext = context.attributes(for: span)
            let fromWrapper = MarkdownAttributedText.attributes(for: span, theme: theme)
            #expect(Self.attributesMatch(fromContext, fromWrapper), "\(span)")
        }
    }

    @Test func aRepeatedHeadingLevelReturnsEqualAttributesTwice() {
        let theme = Theme.emergency
        var context = MarkdownAttributedText.StyleContext(theme: theme, links: true)
        let first = context.attributes(for: .heading(level: 2))
        let second = context.attributes(for: .heading(level: 2))
        #expect(Self.attributesMatch(first, second))
    }
}
