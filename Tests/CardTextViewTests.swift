import AppKit
import Testing
@testable import Pergamenum

// ADR-0027 §D1, plan 2026-08-28-unificare-nota-e-testo-in-un-solo-strume, Task 4 (R-08, R-09).
//
// Scope of this file: only `CardTextAttributes`, per the tester's dispatch for Task 4 - "the
// ONLY part of Task 4 that is testable without a real window". `FormattingTextView`,
// `CardTextView` and `StickyTextCard` are the coder's own files in a later dispatch, with no
// unit tests of their own by design: step 4a's geometry probe and Task 8's manual pass are
// where caret placement, selection rectangles and focus are actually verified. The plan's third
// listed test for this task ("read-only and editing configurations produce the same attributed
// string") belongs to `CardTextView`, which needs a real window to instantiate, and is
// deliberately not written here.
//
// RED: `CardTextAttributes.attributes(for:theme:)` and `.attributed(_:theme:)` are both
// `fatalError` stubs until the coder fills them in (`CardTextAttributes.swift`), so every
// `@Test` below is expected to crash the run, not merely fail an assertion, until then - the
// same TDD shape `Tests/CardTextStyleTests.swift` documents for Task 3.
@Suite struct CardTextViewTests {
    private let theme = Theme.emergency

    // MARK: - R-08: the card's base font is the page's prose face, not the interface's body face

    /// `CardTextAttributes.base(theme:)` used to read `.body` (`Theme.emergency`: System, 13pt) -
    /// the same face the interface's chrome uses. ADR-0030 §D1/Task 5 moves the card onto
    /// `.prose` (Avenir Next, 16pt) through `ProseTypography`, the same helper the note editor's
    /// page already reads, so a card's plain text stops looking like chrome copy.
    @Test func baseFontIsTheProsePageFontNotTheBodyChromeFont() throws {
        let attributes = CardTextAttributes.base(theme: theme)
        let font = try #require(attributes[.font] as? NSFont, "base(theme:) must set an NSFont")
        let expected = ProseTypography.prose(theme)

        #expect(
            font.fontName == expected.fontName,
            "base(theme:) must resolve through ProseTypography.prose(theme), not theme.nsFont(.body)"
        )
        #expect(font.pointSize == expected.pointSize)
    }

    // MARK: - R-08: heading sizes come from the one shared scale

    /// The card must not compute its own heading scale independently of the note editor's - both
    /// must read `ProseTypography.heading(level:_:)`, or the two surfaces silently drift apart.
    /// In `Theme.emergency` every one of the six levels lands on a different point size between
    /// the card's own `headingSize` (interpolating `.title`/`.body`) and `ProseTypography.heading`
    /// (interpolating `.proseTitle`/`.prose`), so this is red at every level, not only some.
    @Test func headingSizesMatchProseTypographyForEveryLevel() throws {
        for level in 1...6 {
            let attributes = CardTextAttributes.attributes(for: .heading(level: level), theme: theme)
            let font = try #require(
                attributes[.font] as? NSFont,
                "a .heading(level: \(level)) span must set an NSFont"
            )
            let expectedSize = ProseTypography.heading(level: level, theme).pointSize
            #expect(
                font.pointSize == expectedSize,
                "heading level \(level) must match ProseTypography.heading(level:_:)'s scale, not CardTextAttributes' own headingSize"
            )
        }
    }

    // MARK: - The regression this task exists to prevent (ADR §D1)

    /// `MarkdownAttributedText`'s `.bold` arm now resolves through `ProseTypography.proseBold`
    /// (Avenir Next, non-monospaced) rather than `NSFont.monospacedSystemFont(ofSize: 13, weight:
    /// .bold)` - the note editor's own bold stopped being typewriter-bold in an earlier task of
    /// this same chain. The comparison below is kept anyway, unweakened: a canvas card's bold
    /// must never be monospaced regardless of what the note editor currently does, and comparing
    /// against a literal monospaced-bold font (rather than against whatever the editor happens to
    /// return today) is what keeps this assertion meaningful even as the editor's own font changes
    /// again later.
    @Test func boldSpanIsAGenuinelyNonMonospacedBoldFont() throws {
        let attributes = CardTextAttributes.attributes(for: .bold, theme: theme)
        let font = try #require(attributes[.font] as? NSFont, "a .bold span must set an NSFont")

        let traits = font.fontDescriptor.symbolicTraits
        #expect(!traits.contains(.monoSpace), "a card's bold span must not be drawn in a monospaced font")
        #expect(traits.contains(.bold), "a card's bold span must actually render bold")

        // The exact regression named in the ADR and this task's brief: the note editor's own
        // monospaced bold choice, compared by font name rather than by trait alone, so a future
        // implementation cannot satisfy this test by returning a monospaced font that merely
        // lacks the `.bold` symbolic trait bit.
        let noteEditorBold = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        #expect(font.fontName != noteEditorBold.fontName, "must not equal the note editor's monospaced bold font")
        #expect(font.familyName != noteEditorBold.familyName, "must not share the monospaced font family")
    }

    // MARK: - R-09: no special-casing that excludes a To Do card

    /// A To Do card's `"- [ ] "` prefix must not change how a `**bold**` span elsewhere on the
    /// line is attributed. Compares the actual attribute run TextKit would draw for the word
    /// "bold" in a plain `.text` card against the same word in a To Do card, rather than
    /// asserting the claim in a comment.
    @Test func aTodoCardsPrefixDoesNotChangeTheBoldSpansAttributes() {
        let plainCard = "**bold**"
        let todoCard = "- [ ] **bold**"

        let plainAttributed = CardTextAttributes.attributed(plainCard, theme: theme)
        let todoAttributed = CardTextAttributes.attributed(todoCard, theme: theme)

        // The word itself, not the `**` markers, so this does not depend on how markers are
        // merged on top of the run - only on whether the `.bold` span's own attributes differ
        // depending on what precedes it on the line.
        let plainRange = (plainCard as NSString).range(of: "bold")
        let todoRange = (todoCard as NSString).range(of: "bold")
        #expect(plainRange.location != NSNotFound)
        #expect(todoRange.location != NSNotFound)

        let plainRun = plainAttributed.attributes(at: plainRange.location, effectiveRange: nil)
        let todoRun = todoAttributed.attributes(at: todoRange.location, effectiveRange: nil)

        #expect(
            NSDictionary(dictionary: plainRun) == NSDictionary(dictionary: todoRun),
            "a bold span must attribute identically whether or not the line carries a To Do prefix"
        )
    }

    // MARK: - R-08: italic moves to the prose face too

    /// PLAN DEVIATION (ADR-0073 §D2): the plan's Task 5 brief claims an existing ".italic is
    /// still oblique-or-italic (the existing assertion, kept verbatim)" test to preserve - no
    /// such assertion exists anywhere in the suite. `Tests/CardFormattingTests.swift` has italic
    /// tests, but they cover `InlineFormat`'s markdown-wrapping toggle (source text mutation),
    /// never `CardTextAttributes.italicAttributes`/`.attributes(for: .italic, theme:)`. This is a
    /// new test, not a kept one, mirroring `italicAttributes(theme)`'s own two-path shape (a real
    /// italic face on the font key, or `.obliqueness` on the upright face otherwise) the same way
    /// `boldSpanIsAGenuinelyNonMonospacedBoldFont` above mirrors `.bold`'s shape - and then, since
    /// `italicAttributes` is being replaced by a call to `ProseTypography.proseItalicAttributes`
    /// wholesale (plan: "replaces headingSize and italicAttributes with helper calls"), pins the
    /// exact output to that helper rather than only to the oblique/italic property, which today's
    /// `.body`-based implementation already happens to satisfy and would leave this test green
    /// for the wrong reason.
    @Test func italicSpanMatchesProseTypographysItalicFace() {
        let attributes = CardTextAttributes.attributes(for: .italic, theme: theme)

        if let font = attributes[.font] as? NSFont {
            #expect(
                font.fontDescriptor.symbolicTraits.contains(.italic),
                "a card's italic span with a real italic face must actually render italic"
            )
        } else {
            #expect(
                attributes[.obliqueness] != nil,
                "a card's italic span with no real italic face must fall back to .obliqueness"
            )
        }

        let expected = ProseTypography.proseItalicAttributes(theme)
        #expect(
            NSDictionary(dictionary: attributes) == NSDictionary(dictionary: expected),
            "a card's italic span must resolve through ProseTypography.proseItalicAttributes(theme) exactly, not its own body-token-based italicAttributes"
        )
    }

    // MARK: - R-08: code faces stay monospaced, but move to the prose size

    /// `.code`'s size used to track `bodyFont(theme)` (`.body`, 13pt in `Theme.emergency`). It
    /// must now track `ProseTypography.mono(theme, size:)` sized off `.prose` (16pt) - a real
    /// behavior change, not a rename, since the two tokens carry different point sizes.
    @Test func codeSpanIsMonospacedAtTheProseSize() throws {
        let attributes = CardTextAttributes.attributes(for: .code, theme: theme)
        let font = try #require(attributes[.font] as? NSFont, "a .code span must set an NSFont")
        let expected = ProseTypography.mono(theme, size: ProseTypography.prose(theme).pointSize)

        #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace), "a .code span must stay monospaced")
        #expect(
            font.pointSize == expected.pointSize,
            "a .code span's size must track ProseTypography.prose(theme), not .body"
        )
    }

    /// Same rule as `.code`, for the whole-block variant.
    @Test func codeBlockSpanIsMonospacedAtTheProseSize() throws {
        let attributes = CardTextAttributes.attributes(for: .codeBlock, theme: theme)
        let font = try #require(attributes[.font] as? NSFont, "a .codeBlock span must set an NSFont")
        let expected = ProseTypography.mono(theme, size: ProseTypography.prose(theme).pointSize)

        #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace), "a .codeBlock span must stay monospaced")
        #expect(
            font.pointSize == expected.pointSize,
            "a .codeBlock span's size must track ProseTypography.prose(theme), not .body"
        )
    }

    // MARK: - R-06 (issue #188): a card's links become clickable, reopening ADR-0027 §D1

    @Test func linkTargetCarriesLinkAndCursorForAResolvableTarget() throws {
        let attributes = CardTextAttributes.attributes(for: .linkTarget("Nota"), theme: theme)
        let url = try #require(attributes[.link] as? URL, ".linkTarget must now carry .link (R-06)")
        #expect(MarkdownAttributedText.clickTarget(for: url) == .note(title: "Nota"))
        #expect(attributes[.cursor] != nil, ".linkTarget must now carry .cursor (R-06)")
    }

    @Test func embedTargetCarriesLinkAndCursorForAFileReference() {
        let attributes = CardTextAttributes.attributes(for: .embedTarget("foto.png"), theme: theme)
        #expect(attributes[.link] as? URL == MarkdownAttributedText.embedURL(for: "foto.png"))
        #expect(attributes[.cursor] != nil, ".embedTarget must now carry .cursor (R-06)")
    }

    /// An empty CommonMark href (`[testo]()`) never reaches `.linkTarget` at all
    /// (`MarkdownStyler.markdownLinkSpans`'s own empty-target guard), but a `.linkTarget`
    /// whose raw string cannot resolve to any URL still must not crash or promise a
    /// navigation it cannot perform.
    @Test func linkTargetWithAnEmptyStringStillReturnsAttributesWithoutCrashing() {
        let attributes = CardTextAttributes.attributes(for: .linkTarget(""), theme: theme)
        #expect(attributes[.foregroundColor] != nil)
    }
}
