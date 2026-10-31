import AppKit
import Foundation
import Testing
@testable import Pergamenum

// `***x***`, `___x___` and a nested `**a *b* c**` draw bold-italic on every surface that styles
// prose. Each styling loop used to `addAttributes` the bold and the italic face in turn, so the
// second `.font` replaced the first and bold-italic never drew (G-hand-427's hand check).
// `ProseTypography.addEmphasis` lays each trait over the run's current face instead.

private func traits(at needle: String, in string: NSAttributedString) throws -> NSFontDescriptor.SymbolicTraits {
    let range = (string.string as NSString).range(of: needle)
    #expect(range.location != NSNotFound, "fixture: \(needle) not in \(string.string)")
    let font = try #require(string.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
    return font.fontDescriptor.symbolicTraits
}

@MainActor
@Suite struct BoldItalicEmphasisTests {
    // MARK: - ProseTypography.addEmphasis

    @Test func italicOverABoldRunKeepsTheBold() throws {
        let theme = Theme.emergency
        let storage = NSMutableAttributedString(string: "x", attributes: [.font: ProseTypography.proseBold(theme)])
        ProseTypography.addEmphasis(.italic, in: storage, range: NSRange(location: 0, length: 1), theme: theme)

        let result = try traits(at: "x", in: storage)
        #expect(result.contains(.bold))
        #expect(result.contains(.italic))
    }

    @Test func boldOverAPlainRunIsProseBold() throws {
        let theme = Theme.emergency
        let storage = NSMutableAttributedString(string: "x", attributes: [.font: ProseTypography.prose(theme)])
        ProseTypography.addEmphasis(.bold, in: storage, range: NSRange(location: 0, length: 1), theme: theme)

        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.fontName == ProseTypography.proseBold(theme).fontName)
    }

    @Test func italicOverAPlainRunIsTheProseItalicFace() throws {
        let theme = Theme.emergency
        let storage = NSMutableAttributedString(string: "x", attributes: [.font: ProseTypography.prose(theme)])
        ProseTypography.addEmphasis(.italic, in: storage, range: NSRange(location: 0, length: 1), theme: theme)

        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let expected = try #require(ProseTypography.proseItalicAttributes(theme)[.font] as? NSFont)
        #expect(font.fontName == expected.fontName)
        #expect(storage.attribute(.obliqueness, at: 0, effectiveRange: nil) == nil)
    }

    // MARK: - MarkdownAttributedText (transclusions)

    @Test(arguments: ["***entrambi***", "___entrambi___"])
    func aTripleDelimiterRunIsBoldItalicInTheTransclusionRenderer(_ text: String) throws {
        let result = try traits(at: "entrambi", in: MarkdownAttributedText.attributed(text, theme: .emergency))
        #expect(result.contains(.bold), "\(text)")
        #expect(result.contains(.italic), "\(text)")
    }

    @Test func aNestedItalicKeepsTheEnclosingBold() throws {
        let string = MarkdownAttributedText.attributed("**alfa *beta* gamma**", theme: .emergency)

        let outer = try traits(at: "alfa", in: string)
        #expect(outer.contains(.bold))
        #expect(!outer.contains(.italic))
        let inner = try traits(at: "beta", in: string)
        #expect(inner.contains(.bold))
        #expect(inner.contains(.italic))
    }

    // MARK: - Workspace text card

    @Test(arguments: ["***entrambi***", "___entrambi___"])
    func aTripleDelimiterRunIsBoldItalicOnACard(_ text: String) throws {
        let result = try traits(at: "entrambi", in: CardTextAttributes.attributed(text, theme: .emergency))
        #expect(result.contains(.bold), "\(text)")
        #expect(result.contains(.italic), "\(text)")
    }

    // MARK: - Note editor

    @Test(arguments: ["***entrambi***", "___entrambi___"])
    func aTripleDelimiterRunIsBoldItalicInTheNoteEditor(_ text: String) throws {
        let editor = ScrolledEditorFixture(text: text)
        let storage = try #require(editor.textView.textStorage)

        let result = try traits(at: "entrambi", in: storage)
        #expect(result.contains(.bold), "\(text)")
        #expect(result.contains(.italic), "\(text)")
    }
}
