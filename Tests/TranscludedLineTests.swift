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
            transclusions: transclusions
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

    @Test func theLineNamingANoteReservesSpaceUnderItself() {
        let (textView, coordinator) = Self.editor(transclusions: Self.source())
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)

        let reserved = Self.spacing(in: textView, atLineContaining: "![[Prove]]")
        #expect((reserved ?? 0) > 0)
        // And nobody else's line pays for it.
        #expect(Self.spacing(in: textView, atLineContaining: "coda") ?? 0 == 0)
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
            transclusions: Self.source()
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
            MarkdownAttributedText.attributes(for: .embedTarget(target), theme: .emergency)[.link] as? URL
        }
        #expect(url(of: "Prove in laboratorio")?.host == "note")
        #expect(url(of: "foto.png")?.host == MarkdownAttributedText.embedHost)
    }

    @Test func withoutAVaultBehindItTheLineStaysAnOrdinaryLine() {
        // The Diario's preview and the mockups have no vault to look anything up in, and
        // the honest behaviour there is to leave the text alone.
        let (textView, coordinator) = Self.editor(transclusions: nil)
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)
        #expect(Self.spacing(in: textView, atLineContaining: "![[Prove]]") ?? 0 == 0)
    }
}
