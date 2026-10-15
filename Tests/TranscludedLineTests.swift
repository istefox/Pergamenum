import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// The editor's half of a transclusion, driven through a real `NSTextView` offscreen
// (ADR-0010 §D3).
//
// Written after the first version drew nothing at all on screen while every unit test was
// green: `applyStyling` rewrites every attribute of the note on each pass, the paragraph
// style that buys the space included, and `applyTransclusions` was skipping its work when
// the renditions had not changed. The space was bought once and wiped by the next update.
// A test that only checked the first call would have agreed with the broken version, so
// these call the pair twice, the way the app does.

@MainActor
@Suite struct TranscludedLine {
    private static let host = "# Ospite\n\n![[Prove]]\n\ncoda\n"

    private static func source() -> TransclusionSource {
        TransclusionSource(
            resolve: { reference in
                guard reference == "Prove" else { return nil }
                return TransclusionSource.Resolved(
                    title: "Prove",
                    relativePath: "Prove.md",
                    text: "# Prove\n\nTre serie di misure.\n"
                )
            },
            generation: 1
        )
    }

    /// The text view the app builds, minus SwiftUI.
    private static func editor(transclusions: TransclusionSource?) -> (NSTextView, NoteTextView.Coordinator) {
        let view = NoteTextView(
            text: .constant(host),
            theme: .emergency,
            noteTitles: [],
            tagSuggestions: [],
            onFollowLink: { _ in },
            vault: .init(transclusions: transclusions)
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = host
        return (textView, coordinator)
    }

    private static func spacing(in textView: NSTextView, atLineContaining needle: String) -> CGFloat? {
        let text = textView.string as NSString
        let line = text.range(of: needle)
        guard line.location != NSNotFound,
              let style = textView.textStorage?
                .attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle
        else { return nil }
        return style.paragraphSpacing
    }

    // PG-328: the rendition cache is keyed by generation, and the index generation moves on
    // every save, so a cache that kept older generations would grow by one entry per
    // transclusion per save. Observed through the coordinator's own cache, no window needed.
    private static func source(generation: Int, text: String) -> TransclusionSource {
        TransclusionSource(
            resolve: { reference in
                guard reference == "Prove" else { return nil }
                return TransclusionSource.Resolved(title: "Prove", relativePath: "Prove.md", text: text)
            },
            generation: generation
        )
    }

    @Test func aNewGenerationDropsTheRenditionsOfTheOldOne() {
        let (textView, coordinator) = Self.editor(transclusions: Self.source(generation: 1, text: "# Prove\n\nPrima.\n"))
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)
        #expect(coordinator.transclusion.renditionCache.count == 1)

        for generation in 2...4 {
            coordinator.parent.vault.transclusions = Self.source(generation: generation, text: "# Prove\n\nDopo \(generation).\n")
            coordinator.applyStyling(to: textView, theme: .emergency)
            coordinator.applyTransclusions(to: textView, theme: .emergency)
            #expect(coordinator.transclusion.renditionCache.count == 1)
            #expect(coordinator.transclusion.renditionCache.keys.allSatisfy { $0.contains("@\(generation)|") })
        }
    }

    @Test func theSameGenerationKeepsItsCachedRendition() {
        let (textView, coordinator) = Self.editor(transclusions: Self.source(generation: 5, text: "# Prove\n\nPrima.\n"))
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)
        let cached = coordinator.transclusion.renditionCache
        // Same generation, different text behind it: the cache answers, nothing is re-read.
        coordinator.parent.vault.transclusions = Self.source(generation: 5, text: "# Prove\n\nCambiata.\n")
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)
        #expect(coordinator.transclusion.renditionCache == cached)
    }

    @Test func theLineNamingANoteReservesSpaceUnderItself() {
        let (textView, coordinator) = Self.editor(transclusions: Self.source())
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)

        let reserved = Self.spacing(in: textView, atLineContaining: "![[Prove]]")
        #expect((reserved ?? 0) > 0)
        // (n1-seams R-14) Updated: this used to expect 0 for `coda`. A prose line now takes
        // `spacing.paragraph` (8 pt) after itself, and `coda` is prose, so 8 is the correct
        // value. The transcluded line keeps its own reserved height (asserted above), and
        // nobody else's line pays for that reservation: `coda` carries the paragraph gap only.
        let paragraph = Theme.emergency.spacing(.paragraph)
        #expect(paragraph == 8)
        #expect(Self.spacing(in: textView, atLineContaining: "coda") == paragraph)
        #expect(reserved != paragraph)
    }

    @Test func theSpaceSurvivesTheNextStylingPass() {
        // The regression. Styling runs on every keystroke and on every view update; a
        // reservation that only happened when the renditions changed lasted until the first
        // of those, which in practice was before the window ever appeared.
        let (textView, coordinator) = Self.editor(transclusions: Self.source())
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)
        let first = Self.spacing(in: textView, atLineContaining: "![[Prove]]")

        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)
        #expect(Self.spacing(in: textView, atLineContaining: "![[Prove]]") == first)
        #expect((first ?? 0) > 0)
    }

    @Test func theLineIsDrawnByAFragmentThatKnowsWhatItIsShowing() {
        let (textView, coordinator) = Self.editor(transclusions: Self.source())
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)

        guard let manager = textView.textLayoutManager else { return }
        manager.ensureLayout(for: manager.documentRange)

        var found: TranscludedLineFragment?
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) {
            if let fragment = $0 as? TranscludedLineFragment { found = fragment }
            return true
        }
        #expect(found?.rendition?.reference == "Prove")
        #expect(found?.rendition?.title == "Prove")
        // The drawn area has to be under the source line and inside the fragment, or the
        // click that opens the note has nothing to hit.
        #expect(found.map { $0.renditionFrame.height > 0 } == true)
    }

    @Test func aClickInsideTheDrawnNoteIsTakenAsAClickOnIt() {
        // The geometry on its own, away from AppKit's event routing: the click arrives in
        // the view's coordinates and the fragment answers in the container's, and between
        // them sits `textContainerInset`. Comparing the two directly is what the first
        // version did, and it could not hit anything anywhere on the page.
        var followed: String?
        let view = NoteTextView(
            text: .constant(Self.host),
            theme: .emergency,
            noteTitles: [],
            tagSuggestions: [],
            onFollowLink: { followed = $0 },
            vault: .init(transclusions: Self.source())
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = Self.host
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)

        guard let manager = textView.textLayoutManager else { return }
        manager.ensureLayout(for: manager.documentRange)
        var drawn: CGRect = .null
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) {
            if let fragment = $0 as? TranscludedLineFragment { drawn = fragment.renditionFrame }
            return true
        }
        #expect(drawn.height > 0)

        let origin = textView.textContainerOrigin
        let inside = CGPoint(x: drawn.midX + origin.x, y: drawn.midY + origin.y)
        #expect(coordinator.openTransclusion(at: inside, in: textView))
        #expect(followed == "Prove")

        // And a click on the source line above is not one: it belongs to the text, and
        // swallowing it would stop the caret being placed by a click.
        followed = nil
        let above = CGPoint(x: inside.x, y: drawn.minY + origin.y - 4)
        #expect(!coordinator.openTransclusion(at: above, in: textView))
        #expect(followed == nil)
    }

    @Test func clickingTheSourceLineOfATranscludedNoteOpensTheNoteAndNotTheFilePreview() {
        // The editor's half of PG-020. `![[nota]]` and `![[foto.png]]` share a span, so
        // both used to carry the embed URL and a click on a note asked Quick Look for a
        // file that does not exist.
        func url(of target: String) -> URL? {
            MarkdownAttributedText.attributes(for: .embedTarget(target), theme: .emergency)[.editorLink] as? URL
        }
        #expect(url(of: "Prove in laboratorio")?.host == "note")
        #expect(url(of: "foto.png")?.host == MarkdownAttributedText.embedHost)
    }

    /// G2 H8 (ADR-0074): `![[Nota#Sezione]]` reaches `TransclusionController.apply` with the
    /// occurrence's section, and the rendition drawn holds that section's text only - neither
    /// the sections around it nor the note's lead-in. A fresh coordinator, so the cache has no
    /// earlier generation to answer from.
    @Test func aSectionTransclusionRendersOnlyThatSectionsText() throws {
        let note = "# Prove\n\nIntro.\n\n## Prima\n\nTesto della prima.\n\n"
            + "## Seconda\n\nTesto della seconda.\n\n## Terza\n\nTesto della terza.\n"
        let source = TransclusionSource(
            resolve: { reference in
                guard reference == "Prove" else { return nil }
                return TransclusionSource.Resolved(title: "Prove", relativePath: "Prove.md", text: note)
            },
            generation: 1
        )
        let (textView, coordinator) = Self.editor(transclusions: source)
        let host = "# Ospite\n\n![[Prove#Seconda]]\n\ncoda\n"
        textView.string = host
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)

        let offset = (host as NSString).range(of: "![[Prove#Seconda]]").location
        let rendition = try #require(coordinator.transclusion.lastRenditions[offset])
        let drawn = rendition.body.string
        #expect(drawn.contains("Testo della seconda"))
        #expect(!drawn.contains("Testo della prima"))
        #expect(!drawn.contains("Testo della terza"))
        #expect(!drawn.contains("Intro."))
        #expect(rendition.title == "Prove › Seconda")
    }

    @Test func withoutAVaultBehindItTheLineStaysAnOrdinaryLine() {
        // The Diario's preview and the mockups have no vault to look anything up in, and
        // the honest behaviour there is to leave the text alone.
        let (textView, coordinator) = Self.editor(transclusions: nil)
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)
        // (n1-seams R-14) Updated: this used to expect 0. With no vault behind it `![[Prove]]`
        // is an ordinary prose line, and an ordinary prose line takes `spacing.paragraph`
        // (8 pt) after itself, so 8 is the correct value. What stays pinned is that no
        // transclusion height is reserved: the value is the paragraph gap and nothing more.
        #expect(Self.spacing(in: textView, atLineContaining: "![[Prove]]") == Theme.emergency.spacing(.paragraph))
    }
}

// MARK: - N5 Task 3 (ADR-0087 §D10, plan `note-workflow-n5.md`, R-40): the source line is the caption

// Off the caret the source line's own characters are collapsed and the fragment draws the caption
// `da «Nota» › Sezione` in their place; with the caret in the line the source shows raw; the rendition
// no longer reserves a header caption of its own. The caption's text is `TransclusionCaption.text` (Task 1); the fragment declares no accessor
// for it, so what is pinned here is the collapse, the reveal and the reserved height.

@MainActor
@Suite struct TranscludedCaption {
    private static let host = "# Ospite\n\n![[Prove]]\n\ncoda\n"
    private static let line = 10

    private static func source(resolving reference: String = "Prove") -> TransclusionSource {
        TransclusionSource(
            resolve: { requested in
                guard requested == reference else { return nil }
                return TransclusionSource.Resolved(
                    title: "Prove", relativePath: "Prove.md", text: "# Prove\n\nTre serie di misure.\n"
                )
            },
            generation: 1
        )
    }

    private static func editor(
        _ text: String = host, caret: Int, transclusions: TransclusionSource?
    ) -> N5Editor.Built {
        let built = N5Editor.build(text, caret: caret, vault: .init(transclusions: transclusions))
        built.coordinator.applyTransclusions(to: built.textView, theme: built.theme)
        built.textView.textLayoutManager?.ensureLayout(for: built.textView.textLayoutManager!.documentRange)
        return built
    }

    @Test func offTheCaretTheSourceLinesCharactersAreCollapsed() { // R-40
        let built = Self.editor(caret: 0, transclusions: Self.source())
        for offset in Self.line..<(Self.line + 10) {
            #expect(N5Editor.isConcealed(built, paragraph: Self.line, at: offset), "offset \(offset)")
        }
    }

    @Test func theCollapsedLineKeepsItsStoredLength() { // R-40
        for caret in [0, Self.line + 4] {
            let built = Self.editor(caret: caret, transclusions: Self.source())
            let lengths = N5Editor.lengths(built, at: Self.line)
            #expect(lengths.displayed == lengths.stored, "caret \(caret): \(lengths)")
        }
    }

    @Test func withTheCaretInTheLineTheSourceShowsRaw() { // R-40
        let built = Self.editor(caret: Self.line + 4, transclusions: Self.source())
        for offset in Self.line..<(Self.line + 10) {
            #expect(!N5Editor.isConcealed(built, paragraph: Self.line, at: offset), "offset \(offset)")
        }
    }

    @Test func anUnresolvedTransclusionIsDrawnAsToday() { // R-40
        let built = Self.editor(caret: 0, transclusions: Self.source(resolving: "Altra"))
        #expect(!N5Editor.isConcealed(built, paragraph: Self.line, at: Self.line + 4))
        let style = built.textView.textStorage?
            .attribute(.paragraphStyle, at: Self.line, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.paragraphSpacing == Theme.emergency.spacing(.paragraph))
        #expect(built.coordinator.transclusion.lastRenditions[Self.line] == nil)
    }

    /// Today the reservation is `padding * 2 + caption + body (+ caption when cut)`: the caption was the
    /// header the rendition drew. The source line is the caption now, so the header's height is gone.
    @Test func theReservedHeightHasNoHeaderCaption() throws { // R-40
        let built = Self.editor(caret: 0, transclusions: Self.source())
        let rendition = try #require(built.coordinator.transclusion.lastRenditions[Self.line])
        try #require(!rendition.isCut, "the fixture note must fit")

        let container = try #require(built.textView.textContainer)
        let style = built.textView.textStorage?
            .attribute(.paragraphStyle, at: Self.line, effectiveRange: nil) as? NSParagraphStyle
        let width = EditorGutter.columnSpan(
            containerWidth: container.size.width, padding: container.lineFragmentPadding, style: style
        ).width
        let body = TranscludedRendition.height(of: rendition.body, width: width)
        #expect(rendition.reservedHeight == TranscludedRendition.padding * 2 + body, "\(rendition.reservedHeight)")
    }

    @Test func aSectionTransclusionKeepsItsTitleForTheClickThrough() throws { // R-40
        let note = "# Prove\n\nIntro.\n\n## Seconda\n\nTesto.\n"
        let source = TransclusionSource(
            resolve: { reference in
                reference == "Prove"
                    ? TransclusionSource.Resolved(title: "Prove", relativePath: "Prove.md", text: note) : nil
            },
            generation: 1
        )
        let host = "# Ospite\n\n![[Prove#Seconda]]\n\ncoda\n"
        let built = Self.editor(host, caret: 0, transclusions: source)
        let rendition = try #require(built.coordinator.transclusion.lastRenditions[Self.line])
        #expect(rendition.title == "Prove › Seconda")
        #expect(N5Editor.isConcealed(built, paragraph: Self.line, at: Self.line + 5))
    }
}
