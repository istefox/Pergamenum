import AppKit
import Foundation
import Testing
@testable import Pergamenum

// MARK: The setting

@Test(arguments: [
    (SpellCheck.off, "\"off\""),
    (SpellCheck.automatic, "\"auto\""),
    (SpellCheck.language("it_IT"), "\"it_IT\"")
])
func spellCheckEncodesAsABareString(_ value: SpellCheck, _ expected: String) throws {
    // A bare string and not an object: `settings.json` is meant to be edited by hand.
    let encoded = try JSONEncoder().encode(value)
    #expect(String(bytes: encoded, encoding: .utf8) == expected)
}

@Test(arguments: [
    ("\"off\"", SpellCheck.off),
    ("\"auto\"", SpellCheck.automatic),
    ("\"it_IT\"", SpellCheck.language("it_IT")),
    ("\"\"", SpellCheck.off)
])
func spellCheckDecodesFromItsKeyword(_ json: String, _ expected: SpellCheck) throws {
    let decoded = try JSONDecoder().decode(SpellCheck.self, from: Data(json.utf8))
    #expect(decoded == expected)
}

@Test func aSettingsFileWrittenBeforeTheKeyExistedStillLoads() throws {
    // The whole point of `VaultSettings.init(from:)`: one absent key must not cost the
    // vault its daily folder. Written the way an older build would have written it.
    let json = """
    {"dailyFolder":"Calendar","diaryFolder":"Diario","copyDroppedFiles":true,
     "boardShowsGrid":true,"boardSnapsToGrid":false,"blockMinutes":30}
    """
    let settings = try JSONDecoder().decode(VaultSettings.self, from: Data(json.utf8))
    #expect(settings.spellCheck == .off)
    #expect(settings.dailyFolder == "Calendar")
    #expect(settings.blockMinutes == 30)
}

@Test func anUnreadableSpellCheckKeywordIsTreatedAsALanguage() throws {
    // A hand-edited `settings.json` holding a language the system has no dictionary for
    // must still decode: `NSSpellChecker` ignores an unknown identifier, and losing the
    // rest of the file over one word would be far worse.
    let json = #"{"dailyFolder":"Calendar","spellCheck":"xx_XX"}"#
    let settings = try JSONDecoder().decode(VaultSettings.self, from: Data(json.utf8))
    #expect(settings.spellCheck == .language("xx_XX"))
    #expect(settings.spellCheck.fixedLanguage == "xx_XX")
}

@Test func theCheckerIsOffUntilItIsAskedFor() {
    #expect(VaultSettings.default.spellCheck == .off)
    #expect(!SpellCheck.off.isEnabled)
    #expect(SpellCheck.automatic.isEnabled)
    #expect(SpellCheck.automatic.fixedLanguage == nil)
}

// MARK: What is not spell-checked

/// The spans of `note` that the editor keeps the spelling underline off, as the strings
/// they cover - the form a failure is readable in.
private func unspellable(in note: String) -> [String] {
    MarkdownStyler.spans(in: note)
        .filter { MarkdownStyler.suppressesSpellCheck($0.span) }
        .map { String(note[$0.range]) }
}

@Test func markdownSyntaxIsNotSpellChecked() {
    let note = """
    ---
    date: 2026-08-18
    ---
    Un paragrafo con un [[Wikilink]] e un #project-pergamenum.

    - [ ] fare qualcosa >2026-08-20 !2026-08-25

    ```sh
    grep --recursive parola .
    ```
    """
    let suppressed = unspellable(in: note)
    #expect(suppressed.contains("---\ndate: 2026-08-18\n---"))
    #expect(suppressed.contains("Wikilink"))
    #expect(suppressed.contains("#project-pergamenum"))
    #expect(suppressed.contains(">2026-08-20"))
    #expect(suppressed.contains("!2026-08-25"))
    #expect(suppressed.contains { $0.hasPrefix("```sh") })
}

@Test func proseIsStillSpellChecked() {
    // The words a checker exists for: a heading's text and an emphasised word are prose,
    // and a span covering them would make the whole feature pointless.
    let note = "# Un titolo sbagliatto\n\nuna parola *enfatizzata*."
    let suppressed = unspellable(in: note)
    #expect(!suppressed.contains { $0.contains("sbagliatto") })
    #expect(!suppressed.contains { $0.contains("enfatizzata") })
    #expect(!MarkdownStyler.suppressesSpellCheck(.heading(level: 1)))
    #expect(!MarkdownStyler.suppressesSpellCheck(.bold))
    #expect(!MarkdownStyler.suppressesSpellCheck(.italic))
    // Punctuation, not prose - unlike the run it wraps (ADR-0018 §D1, slice 2).
    #expect(MarkdownStyler.suppressesSpellCheck(.emphasisMarker))
}

@Test func anEmbeddedFileNameIsNotSpellChecked() {
    #expect(unspellable(in: "vedi ![[schema-di-flusso.png]]").contains("schema-di-flusso.png"))
}

// MARK: Merging

@Test func overlappingAndTouchingRangesMerge() {
    // `spans(in:)` nests by design - a wikilink inside a heading - so the delegate is
    // handed one range per region and not one per span.
    let merged = MarkdownStyler.merged([
        NSRange(location: 10, length: 5),
        NSRange(location: 0, length: 4),
        NSRange(location: 12, length: 8),
        NSRange(location: 4, length: 2)
    ])
    #expect(merged == [NSRange(location: 0, length: 6), NSRange(location: 10, length: 10)])
}

@Test func mergingKeepsRangesThatDoNotMeet() {
    let merged = MarkdownStyler.merged([NSRange(location: 0, length: 3), NSRange(location: 5, length: 3)])
    #expect(merged.count == 2)
}

@Test func mergingAnEmptyListGivesAnEmptyList() {
    #expect(MarkdownStyler.merged([]).isEmpty)
}

// MARK: The delegate

/// Whether AppKit honours the coordinator's refusal.
///
/// `setSpellingState(_:range:)` is the funnel every spelling indicator goes through, and
/// its documentation says it asks the delegate first. This drives it by hand, so it proves
/// the delegate is wired and that a zero suppresses the underline. That the *continuous*
/// checker uses the same funnel is the one thing it cannot prove, and it was answered on
/// screen on 2026-08-18 rather than here.
///
/// The first version of this read the state back from `textStorage` and both tests passed -
/// including the one asserting an underline is *present*, which cannot be true of a store
/// that never held it. Under TextKit 2 the spelling state is a rendering attribute of the
/// layout manager, so the negative control below is the only reason this file measures
/// anything at all.
@MainActor
private func spellingState(over marker: String, in note: String) -> Int {
    let view = NoteTextView(
        text: .constant(note), theme: .emergency, noteTitles: [], tagSuggestions: [],
        onFollowLink: { _ in }
    )
    let coordinator = view.makeCoordinator()
    let textView = NSTextView(usingTextLayoutManager: true)
    textView.delegate = coordinator
    textView.isContinuousSpellCheckingEnabled = true
    textView.string = note
    coordinator.applyStyling(to: textView, theme: .emergency)

    let range = (note as NSString).range(of: marker)
    textView.setSpellingState(NSAttributedString.SpellingState.spelling.rawValue, range: range)

    // Read back where TextKit 2 keeps it. The underline is a *rendering* attribute on the
    // layout manager, not an attribute of the text: looking for it in `textStorage` finds
    // nothing whatever the delegate answered, which is a test that passes by being blind.
    guard let layout = textView.textLayoutManager,
          let content = layout.textContentManager,
          let start = content.location(content.documentRange.location, offsetBy: range.location)
    else { return 0 }
    var state = 0
    layout.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, _ in
        state = attributes[.spellingState] as? Int ?? 0
        return false
    }
    return state
}

@MainActor
@Test func theEditorRefusesAnUnderlineOverATag() {
    let note = "una parolla e un #project-pergamenum."
    #expect(spellingState(over: "#project-pergamenum", in: note) == 0)
}

@MainActor
@Test func theEditorLetsAnUnderlineThroughOverProse() {
    // The negative control: without it the test above passes on a coordinator that
    // suppresses everything, which is the same as having no spell checker at all.
    let note = "una parolla e un #project-pergamenum."
    #expect(spellingState(over: "parolla", in: note) == NSAttributedString.SpellingState.spelling.rawValue)
}
