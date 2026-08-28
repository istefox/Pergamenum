import Foundation
import Testing
@testable import Pergamenum

// ADR-0027, plan `2026-08-28-unificare-nota-e-testo-in-un-solo-strume`, Task 2 (R-05).
//
// `LineFormat` is the pure line-prefix arithmetic for bullet/numbered/heading, sitting beside
// `InlineFormat` (bold/italic/strikethrough) but solving a different problem: it rewrites the
// start of every line a selection touches rather than wrapping a range of characters. These
// tests are red against the stub `fatalError` bodies in `Sources/Core/Editor/LineFormat.swift`;
// Task 5 fills in the real arithmetic.

private func range(of word: String, in text: String) -> NSRange {
    (text as NSString).range(of: word)
}

private func fullRange(_ text: String) -> NSRange {
    NSRange(location: 0, length: (text as NSString).length)
}

// MARK: Bullet

@Test func bulletAppliedToOneLineInsertsPrefixAndKeepsSelectionOnTheWords() {
    // The selection is a word inside the line, not the whole line, so the test can tell the
    // prefix insertion apart from the selection simply "growing" to match it.
    let text = "primo secondo terzo"
    let word = range(of: "secondo", in: text)
    let result = LineFormat.toggled(.bullet, in: text, over: word)
    #expect(result.text == "- primo secondo terzo")
    #expect((result.text as NSString).substring(with: result.selection) == "secondo")
}

@Test func bulletAppliedToThreeSelectedLinesPrefixesAllThree() {
    let text = "primo\nsecondo\nterzo"
    let result = LineFormat.toggled(.bullet, in: text, over: fullRange(text))
    #expect(result.text == "- primo\n- secondo\n- terzo")
}

@Test func bulletOnLinesThatAlreadyCarryItRemovesIt() {
    // Toggle round-trips: applying the same format to lines that already have it takes it away.
    let text = "- primo\n- secondo\n- terzo"
    let result = LineFormat.toggled(.bullet, in: text, over: fullRange(text))
    #expect(result.text == "primo\nsecondo\nterzo")
}

// MARK: Numbered

@Test func numberedListOverThreeLinesWritesSequentialNumbersStartingFromOneRegardlessOfPosition() {
    // "Regardless of what preceded the run": these three lines are the 4th-6th lines of the
    // document, not the 1st-3rd. If numbering tracked absolute line position it would write
    // "4. "/"5. "/"6. "; it must not - the touched run always starts its own count at 1.
    let text = "zero\nuno\ndue\nprimo\nsecondo\nterzo"
    let target = range(of: "primo\nsecondo\nterzo", in: text)
    let result = LineFormat.toggled(.numbered, in: text, over: target)
    #expect(result.text == "zero\nuno\ndue\n1. primo\n2. secondo\n3. terzo")
}

@Test func numberedOnLinesThatAlreadyCarryItRemovesIt() {
    // The negative control for the test above: without it, a `toggled` that always *added* a
    // numbered prefix, never removing one, would still pass.
    let text = "1. primo\n2. secondo\n3. terzo"
    let result = LineFormat.toggled(.numbered, in: text, over: fullRange(text))
    #expect(result.text == "primo\nsecondo\nterzo")
}

// MARK: Heading

@Test func headingLevelTwoOverAnExistingLevelOneReplacesRatherThanStacks() {
    let text = "# Titolo"
    let result = LineFormat.toggled(.heading(level: 2), in: text, over: fullRange(text))
    #expect(result.text == "## Titolo")
    // And critically, not "### Titolo" - the old marker is replaced, not extended.
    #expect(!result.text.hasPrefix("###"))
}

@Test func headingAppliedTwiceAtTheSameLevelRemovesThePrefix() {
    let text = "Titolo"
    let once = LineFormat.toggled(.heading(level: 2), in: text, over: fullRange(text))
    #expect(once.text == "## Titolo")
    let twice = LineFormat.toggled(.heading(level: 2), in: once.text, over: once.selection)
    #expect(twice.text == "Titolo")
}

@Test func isAppliedForAHeadingLevelIsFalseWhenALineIsAtADifferentLevel() {
    // `# Titolo` is a heading, but not a *level-2* heading - the button for level 2 must not
    // light, or a second press at level 2 would look like a no-op removal instead of a replace.
    let text = "# Titolo"
    #expect(!LineFormat.isApplied(.heading(level: 2), in: text, over: fullRange(text)))
    #expect(LineFormat.isApplied(.heading(level: 1), in: text, over: fullRange(text)))
}

// MARK: Mixed selection

@Test func mixedSelectionAppliesRatherThanRemoves() {
    // One line already a bullet, one not: `isApplied` must be false (not every touched line
    // carries it), so the next press adds the prefix to both instead of removing the one that
    // already has it.
    let text = "- primo\nsecondo"
    #expect(!LineFormat.isApplied(.bullet, in: text, over: fullRange(text)))
    let result = LineFormat.toggled(.bullet, in: text, over: fullRange(text))
    #expect(result.text == "- primo\n- secondo")
}

// MARK: Empty selection

@Test func emptySelectionAppliesToTheCaretsOwnLine() {
    // Deliberately different from `InlineFormat.toggled`'s empty-selection rule (a total no-op,
    // `InlineFormat.swift:47-50`): there, nothing is selected to wrap markers *around*, and
    // wrapping would leave a bare, stray pair like `****`. There is no equivalent trap for a
    // line format - the caret sits on a real line whether or not any of it is selected, and
    // that is the line every other editor's list/heading command acts on with a bare caret. So
    // a bare caret still counts as one line touched, not a no-op.
    let text = "primo\nsecondo"
    let caret = NSRange(location: 2, length: 0) // inside "primo"
    let result = LineFormat.toggled(.bullet, in: text, over: caret)
    #expect(result.text == "- primo\nsecondo")
}

// MARK: The interaction that matters - inline markup survives the line toggle

@Test func toggleOnALineWithInlineMarkupLeavesTheMarkupUntouched() {
    let text = "- **bold** item"
    let result = LineFormat.toggled(.bullet, in: text, over: fullRange(text))
    #expect(result.text == "**bold** item")
}

@Test func addingABulletToALineWithInlineMarkupLeavesTheMarkupUntouched() {
    let text = "**bold** item"
    let result = LineFormat.toggled(.bullet, in: text, over: fullRange(text))
    #expect(result.text == "- **bold** item")
}

// MARK: isApplied and toggled agree with each other

@Test func isAppliedAndToggledAgreeAcrossFormatsAndStartingStates() {
    // `isApplied` is what lights the format bar's button; `toggled` is what a press does. If
    // they disagreed, the button would show the wrong state after its own press. Assert the
    // pair as one round-trip rather than testing either in isolation.
    let cases: [(LineFormat, String)] = [
        (.bullet, "primo\nsecondo"),
        (.bullet, "- primo\n- secondo"),
        (.numbered, "primo\nsecondo\nterzo"),
        (.numbered, "1. primo\n2. secondo\n3. terzo"),
        (.heading(level: 1), "Titolo"),
        (.heading(level: 1), "# Titolo"),
        (.heading(level: 2), "# Titolo"),
    ]
    for (format, text) in cases {
        let range = fullRange(text)
        let wasApplied = LineFormat.isApplied(format, in: text, over: range)
        let result = LineFormat.toggled(format, in: text, over: range)
        let isAppliedAfter = LineFormat.isApplied(format, in: result.text, over: result.selection)
        // Toggling flips the state exactly once: what was applied no longer is, and vice versa.
        #expect(isAppliedAfter == !wasApplied)
    }
}
