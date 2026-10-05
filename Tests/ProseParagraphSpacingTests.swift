import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// Paragraph spacing for prose (n1-seams R-14): the gap between two paragraphs is drawn as
/// `spacing.paragraph` on the paragraph style of every prose and heading line, and on nothing
/// else. Two layers: which source lines `ProseParagraphSpacing.paragraphRanges` returns, and what
/// a hosted `NoteTextView`'s storage then carries.
///
/// The ranges are asserted by containment and non-intersection and not by exact `NSRange`
/// equality, so the suite does not depend on whether a returned range includes its line's
/// newline (the plan does not say; either reading satisfies R-14).

private let sample = """
---
date: 2026-10-05
tags:
  - type-note
---
# Titolo della nota
Una riga di prosa.

Seconda riga di prosa con **grassetto**.
Vedi [[Altra nota]] e #client-acme in prosa.
- voce di elenco
1. voce numerata
- [ ] compito aperto
> citazione di prova

***

```swift
let codice = 1
```

| Colonna A | Colonna B |
| --- | --- |
| cella uno | cella due |

```pergamenum-view
render: table
```

<!-- pergamenum-message: <abc123@example.com> -->
![[foto.png]]
Ultima riga di prosa.
"""

/// The line holding `needle`, without its newline.
private func contentRange(of needle: String, in text: String) -> NSRange {
    let nsText = text as NSString
    let found = nsText.range(of: needle)
    guard found.location != NSNotFound else { return NSRange(location: NSNotFound, length: 0) }
    var line = nsText.lineRange(for: found)
    while line.length > 0, nsText.character(at: NSMaxRange(line) - 1) == 10 { line.length -= 1 }
    return line
}

private func spanRanges(in text: String) -> [MarkdownStyler.StyledRange] {
    MarkdownStyler.spans(in: text)
}

private func covers(_ line: NSRange, by ranges: [NSRange]) -> Bool {
    ranges.contains { NSIntersectionRange($0, line).length == line.length }
}

private func touches(_ line: NSRange, by ranges: [NSRange]) -> Bool {
    ranges.contains { NSIntersectionRange($0, line).length > 0 }
}

// MARK: - Which lines

@Suite struct ParagraphRangesOfProse {
    private static func ranges(_ text: String = sample) -> [NSRange] {
        ProseParagraphSpacing.paragraphRanges(in: text, spans: spanRanges(in: text))
    }

    @Test func everyProseLineIsCovered() { // (n1-seams R-14)
        let ranges = Self.ranges()
        for needle in [
            "Una riga di prosa.", "Seconda riga di prosa con", "Vedi [[Altra nota]]", "Ultima riga di prosa.",
        ] {
            let line = contentRange(of: needle, in: sample)
            #expect(line.location != NSNotFound, "sample has no line with \(needle)")
            #expect(covers(line, by: ranges), "\(needle) is a prose line and should be covered")
        }
    }

    @Test func aHeadingLineIsCovered() { // (n1-seams R-14)
        let line = contentRange(of: "# Titolo della nota", in: sample)
        #expect(covers(line, by: Self.ranges()))
    }

    @Test func aBlankLineIsNeverCovered() { // (n1-seams R-14)
        let nsText = sample as NSString
        let ranges = Self.ranges()
        var blankLines = 0
        var cursor = 0
        while cursor < nsText.length {
            let line = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            if nsText.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blankLines += 1
                // A blank line is its newline alone: no returned range may contain it.
                let contained = ranges.contains { NSLocationInRange(line.location, $0) }
                #expect(!contained, "blank line at \(line.location) is covered")
            }
            cursor = NSMaxRange(line)
        }
        #expect(blankLines >= 4, "the sample is meant to hold several blank lines")
    }

    /// The span kinds the plan names, one sample line each, and the predicate that proves the
    /// styler really did mark that line - so a sample that stopped producing a span fails here
    /// instead of passing vacuously.
    @Test(arguments: [
        ("date: 2026-10-05", "frontmatter"),
        ("  - type-note", "frontmatter"),
        ("let codice = 1", "codeBlock"),
        ("```swift", "codeBlock"),
        ("| Colonna A |", "tableRun"),
        ("| cella uno |", "tableRun"),
        ("render: table", "viewBlockRun"),
        ("- voce di elenco", "listMarker"),
        ("1. voce numerata", "listMarker"),
        ("- [ ] compito aperto", "taskMarker"),
        ("> citazione di prova", "blockquoteMarker"),
        ("***", "horizontalRule"),
        ("<!-- pergamenum-message:", "messageAnchor"),
        ("![[foto.png]]", "embedRun"),
    ])
    func aNonProseLineIsNotCovered(_ needle: String, _ kind: String) { // (n1-seams R-14)
        let line = contentRange(of: needle, in: sample)
        #expect(line.location != NSNotFound, "sample has no line with \(needle)")

        let marked = spanRanges(in: sample).contains { styled in
            let range = NSRange(styled.range, in: sample)
            guard NSIntersectionRange(range, line).length > 0 else { return false }
            return Self.name(of: styled.span) == kind
        }
        #expect(marked, "the styler no longer marks \(needle) as \(kind): fix the sample")

        #expect(
            !touches(line, by: Self.ranges()),
            "\(needle) is \(kind) and must not take paragraph spacing"
        )
    }

    @Test func aNoteWithNoProseHasNoRanges() { // (n1-seams R-14)
        let text = "- uno\n- due\n"
        #expect(ProseParagraphSpacing.paragraphRanges(in: text, spans: spanRanges(in: text)).isEmpty)
    }

    @Test func anEmptyNoteHasNoRanges() { // (n1-seams R-14)
        #expect(ProseParagraphSpacing.paragraphRanges(in: "", spans: []).isEmpty)
    }

    @Test func aLastLineWithoutANewlineIsStillCovered() { // (n1-seams R-14)
        let text = "Prima.\nUltima senza a capo"
        let ranges = ProseParagraphSpacing.paragraphRanges(in: text, spans: spanRanges(in: text))
        #expect(covers(contentRange(of: "Ultima", in: text), by: ranges))
        #expect(covers(contentRange(of: "Prima.", in: text), by: ranges))
    }

    private static func name(of span: MarkdownStyler.Span) -> String {
        switch span {
        case .frontmatter: "frontmatter"
        case .codeBlock: "codeBlock"
        case .tableRun: "tableRun"
        case .viewBlockRun: "viewBlockRun"
        case .listMarker: "listMarker"
        case .taskMarker: "taskMarker"
        case .blockquoteMarker: "blockquoteMarker"
        case .horizontalRule: "horizontalRule"
        case .messageAnchor: "messageAnchor"
        case .embedRun: "embedRun"
        default: "other"
        }
    }
}

// MARK: - What the editor then carries

@MainActor
@Suite struct ParagraphSpacingInTheEditor {
    private static let host = "# Ospite\n\nUna riga di prosa.\n\n- voce di elenco\n\n![[Prove]]\n\ncoda\n"

    private static func source() -> TransclusionSource {
        TransclusionSource(
            resolve: { reference in
                guard reference == "Prove" else { return nil }
                return TransclusionSource.Resolved(
                    title: "Prove", relativePath: "Prove.md",
                    text: "# Prove\n\nTre serie di misure.\n"
                )
            },
            generation: 1
        )
    }

    /// `TranscludedLine.editor`'s construction: the text view the app builds, minus SwiftUI.
    private static func styledEditor() -> (NSTextView, NoteTextView.Coordinator) {
        let view = NoteTextView(
            text: .constant(host), theme: .emergency, noteTitles: [], tagSuggestions: [],
            onFollowLink: { _ in }, vault: .init(transclusions: source())
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = host
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)
        return (textView, coordinator)
    }

    private static func style(in textView: NSTextView, atLineContaining needle: String) -> NSParagraphStyle? {
        let line = (textView.string as NSString).range(of: needle)
        guard line.location != NSNotFound else { return nil }
        return textView.textStorage?
            .attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle
    }

    @Test func aProseLineCarriesTheParagraphSpacing() { // (n1-seams R-14)
        let (textView, _) = Self.styledEditor()
        #expect(Self.style(in: textView, atLineContaining: "Una riga di prosa.")?.paragraphSpacing == 8)
        #expect(Self.style(in: textView, atLineContaining: "coda")?.paragraphSpacing == 8)
    }

    @Test func aHeadingLineCarriesItToo() { // (n1-seams R-14)
        let (textView, _) = Self.styledEditor()
        #expect(Self.style(in: textView, atLineContaining: "# Ospite")?.paragraphSpacing == 8)
    }

    @Test func aListLineKeepsItsOwnSpacing() { // (n1-seams R-14)
        let (textView, _) = Self.styledEditor()
        #expect(Self.style(in: textView, atLineContaining: "- voce di elenco")?.paragraphSpacing == 0)
    }

    @Test func aTransclusionLineKeepsItsReservedHeight() { // (n1-seams R-14)
        let (textView, coordinator) = Self.styledEditor()
        let reserved = coordinator.transclusion.renditionCache.values.first?.reservedHeight
        #expect(reserved != nil)
        #expect((reserved ?? 0) > 8)
        #expect(Self.style(in: textView, atLineContaining: "![[Prove]]")?.paragraphSpacing == reserved)
    }

    @Test func theSpacingSurvivesTheNextStylingPass() { // (n1-seams R-14)
        // `applyStyling` rewrites every attribute on each keystroke; a spacing applied once and
        // wiped by the next pass would be invisible on screen and green in a one-call test.
        let (textView, coordinator) = Self.styledEditor()
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)

        #expect(Self.style(in: textView, atLineContaining: "Una riga di prosa.")?.paragraphSpacing == 8)
        #expect(Self.style(in: textView, atLineContaining: "- voce di elenco")?.paragraphSpacing == 0)
    }

    @Test func theSpacingIsAddedToTheLineHeightAndNeverReplacesIt() { // (n1-seams R-14)
        // Merged into the existing style (ADR-0030 §D5): the page's own line-height multiple stays.
        let (textView, _) = Self.styledEditor()
        let style = Self.style(in: textView, atLineContaining: "Una riga di prosa.")
        let plain = ProseTypography.paragraphStyle(.emergency)
        #expect(style?.lineHeightMultiple == plain.lineHeightMultiple)
        #expect(style?.minimumLineHeight == plain.minimumLineHeight)
    }
}

// MARK: - Everything else keeps today's text

@Suite struct ParagraphSpacingElsewhere {
    @Test func theTransclusionPictureAndTheCardAreNotChanged() { // (n1-seams R-14)
        // The plan leaves `MarkdownAttributedText.attributed` (the transcluded note's picture) and
        // the card's styled text alone: no paragraph spacing is added to a plain paragraph there.
        let theme = Theme.emergency
        let picture = MarkdownAttributedText.attributed("Una riga di prosa.", theme: theme)
        let card = CardTextAttributes.attributed("Una riga di prosa.", theme: theme)

        let pictureStyle = picture.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(pictureStyle?.paragraphSpacing == 0)
        let cardStyle = card.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect((cardStyle?.paragraphSpacing ?? 0) == 0)
    }
}
