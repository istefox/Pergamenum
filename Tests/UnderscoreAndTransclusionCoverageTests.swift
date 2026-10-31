import AppKit
import Foundation
import Testing
@testable import Pergamenum

// (coverage) tests for plan docs/plans/pg-427-pg-428-underscore-concealment-daily-transclusions.md
// (PG-427, PG-428), beside the requirement tests of `UnderscoreEmphasisConcealmentTests.swift` and
// `DailySurfaceTransclusionsTests.swift`. They cover logic the diff touches that those leave
// unexercised, and assert only what ADR-0098 §D1/§D2/§D4 and the code's documented contract state:
// every delimiter of a run the parser accepts is a marker, the delegate re-check collapses nothing
// it cannot read as one or two copies of one delimiter, and `TransclusionSource.live(for:)` is the
// column's old lookup (a path when the reference ends in `.md`, else the index's titles in order,
// skipping a path that no longer reads).

private func markerSpellings(_ text: String) -> [String] {
    MarkdownStyler.spans(in: text)
        .filter { $0.span == .emphasisMarker }
        .sorted { $0.range.lowerBound < $1.range.lowerBound }
        .map { String(text[$0.range]) }
}

// MARK: - The styler, mixed spellings

@MainActor
@Suite struct UnderscoreEmphasisMixedCoverage {
    // (coverage) A `_` run nested in a `**` run: all four delimiters are markers, each spelled as written.
    @Test func anUnderscoreRunInsideAStarRunMarksAllFourDelimiters() {
        #expect(markerSpellings("**a _b_ c**") == ["**", "_", "_", "**"])
    }

    // (coverage) And the other way round: `*` inside `__`.
    @Test func aStarRunInsideADoubleUnderscoreRunMarksAllFourDelimiters() {
        #expect(markerSpellings("__a *b* c__") == ["__", "*", "*", "__"])
    }

    // (coverage) Two runs on one line, one of each spelling, each contributes its own pair.
    @Test func aStarRunAndAnUnderscoreRunOnOneLineEachContributeAPair() {
        #expect(markerSpellings("*uno* e _due_") == ["*", "*", "_", "_"])
    }

    // (coverage) A `_` run whose neighbours are accented letters is intraword to the parser's
    // flanking rule (ADR-0077 §D5), so it carries no marker, exactly as `nome_file_lungo`.
    @Test func anUnderscoreBetweenAccentedLettersCarriesNoMarker() {
        #expect(markerSpellings("città_è_qui").isEmpty)
    }
}

// MARK: - The delegate re-check, boundaries

@MainActor
@Suite struct UnderscoreEmphasisRecheckCoverage {
    // (coverage) A stale `.emphasis` entry whose range runs past the end of the text (the note
    // shrank under it) collapses nothing and does not trap.
    @Test func anEntryPastTheEndOfTheTextCollapsesNothing() {
        let text = "a _b_ c\n"
        let past = HiddenMarker(range: NSRange(location: (text as NSString).length, length: 1), kind: .emphasis)
        #expect(MarkupHidingFixture.displayedParagraph(text, markers: [past]) == nil)
    }

    // (coverage) A stale entry of length zero spells no delimiter.
    @Test func anEmptyEntryCollapsesNothing() {
        let text = "a _b_ c\n"
        let empty = HiddenMarker(range: NSRange(location: 2, length: 0), kind: .emphasis)
        #expect(MarkupHidingFixture.displayedParagraph(text, markers: [empty]) == nil)
    }

    // (coverage) The same two-character entry collapses when it spells `__` and does not once the
    // text under it changed to a letter pair: the per-entry re-check, not the table, decides.
    @Test func theSameEntryCollapsesOnlyWhileTheTextUnderItStillSpellsADelimiter() throws {
        let entry = HiddenMarker(range: NSRange(location: 2, length: 2), kind: .emphasis)
        let spelled = try #require(MarkupHidingFixture.displayedParagraph("a __b__ c\n", markers: [entry]))
        let font = spelled.attributedString.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(font == EditorDecorationDelegate.collapsedFont)
        #expect(MarkupHidingFixture.displayedParagraph("a xxb__ c\n", markers: [entry]) == nil)
    }
}

// MARK: - The delegate table, UTF-16 offsets

@MainActor
@Suite struct UnderscoreEmphasisOffsetsCoverage {
    // (coverage) The styler works in `String.Index`, the delegate in UTF-16 offsets: with an emoji
    // (two UTF-16 units) and an accented letter ahead of the run, the table still holds the
    // delimiters' own UTF-16 ranges.
    @Test func theTableHoldsUTF16RangesAfterAnEmojiAndAnAccent() {
        let text = "😀 è _corsivo_ __forte__\naltro\n"
        let editor = ScrolledEditorFixture(text: text)
        defer { editor.window.orderOut(nil) }

        let ns = text as NSString
        let single = ns.range(of: "_corsivo_")
        let double = ns.range(of: "__forte__")
        let expected = [
            NSRange(location: single.location, length: 1),
            NSRange(location: NSMaxRange(single) - 1, length: 1),
            NSRange(location: double.location, length: 2),
            NSRange(location: NSMaxRange(double) - 2, length: 2)
        ]
        let entries = (editor.coordinator.decorations.hiddenMarkers[0] ?? []).filter { $0.kind == .emphasis }
        #expect(entries.map(\.range).sorted { $0.location < $1.location } == expected, "\(entries)")
        for entry in entries {
            let spelled = ns.substring(with: entry.range)
            #expect(spelled == "_" || spelled == "__", "\(entry.range): \(spelled)")
        }
    }
}

// MARK: - TransclusionSource.live(for:)

@MainActor
@Suite(.serialized) struct TransclusionSourceLiveCoverage {
    private static let note = "---\ndate: 2026-10-06\ntags:\n  - type-note\n---\n\nCorpo della nota.\n"

    private func opened(_ vault: borrowing TemporaryVault, _ paths: String...) async throws -> VaultController {
        for path in paths { try vault.write(Self.note, to: path) }
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        return controller
    }

    // (coverage) The guard on the session: a vault that was never opened has none, so the source
    // answers nothing for a title and for a path alike.
    @Test(arguments: ["N", "Note/N.md"])
    func aControllerWithNoOpenVaultResolvesNothing(_ reference: String) {
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        defer { controller.close() }

        #expect(TransclusionSource.live(for: controller).resolve(reference) == nil)
    }

    // (coverage) A reference ending in `.md` is a path and nothing else: a path no file bears
    // resolves to nothing, and it is not retried as a title.
    @Test func aMarkdownPathNoFileBearsResolvesToNothing() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault, "Note/N.md")
        defer { controller.close() }

        #expect(TransclusionSource.live(for: controller).resolve("Note/Assente.md") == nil)
        #expect(TransclusionSource.live(for: controller).resolve("N.md") == nil)
    }

    // (coverage) A title is looked up case-insensitively, as the index's `resolve(title:)` does
    // for a `[[wikilink]]` ("the two cannot disagree", the factory's doc comment).
    @Test func aTitleResolvesWhateverItsCase() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault, "Note/N.md")
        defer { controller.close() }

        let resolved = try #require(TransclusionSource.live(for: controller).resolve("n"))
        #expect(resolved.relativePath == "Note/N.md")
    }

    // (coverage) Two notes bear the title: the first the index lists that still reads wins, and a
    // path the index lists but the disk has lost is skipped for the next one rather than ending
    // the lookup. The first-listed file is removed after the index was built.
    @Test func aTitlePathThatNoLongerReadsFallsThroughToTheNextOne() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault, "Note/N.md", "Altro/N.md")
        defer { controller.close() }

        let listed = controller.index.resolve(title: "N")
        try #require(listed.count == 2, "the index lists \(listed)")
        let survivor = listed[1]
        try vault.remove(listed[0])

        let resolved = try #require(TransclusionSource.live(for: controller).resolve("N"))
        #expect(resolved.relativePath == survivor)
        #expect(resolved.text == Self.note)
    }
}
