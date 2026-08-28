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

    // MARK: - The regression this task exists to prevent (ADR §D1)

    /// `MarkdownAttributedText`'s `.bold` arm returns
    /// `NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)` - the note editor's source-mode
    /// look. A canvas card must never draw bold that way: bold is bold, not typewriter-bold.
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
}
