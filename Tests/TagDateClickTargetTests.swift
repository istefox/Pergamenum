import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// A `#client-acme` and a valid `>2026-10-12` / `!2026-10-12` are click targets (n1-seams R-12,
/// R-13): the styled run carries the editor's own `.editorLink`, Cmd+click routes it to
/// `onOpenTag` / `onOpenDay`, and a plain click only places the caret. The same on a Workspace
/// card.
///
/// `MarkdownStyler.Span.tag` carries its source *with* the `#` (`MarkdownStyler.swift`, the
/// `.tag(String(characters[index..<(index + length)]))` arm), while the plan writes
/// `.tag("client-acme")`; `Pergamenum.Tag(_:)` accepts both, so both spellings are asserted below.

private let tagText = "#client-acme"
private let dayText = ">2026-10-12"
private let dueText = "!2026-10-12"

private func acme() -> Pergamenum.Tag { Pergamenum.Tag("#client-acme")! }
private func october12() -> CalendarDate { CalendarDate(iso: "2026-10-12")! }

// MARK: - Which spans become click URLs

@Suite struct ClickURLForSpans {
    @Test func aTagSpanGivesATagURLInBothSpellings() { // (n1-seams R-12)
        let withHash = MarkdownAttributedText.clickURL(for: .tag("#client-acme"), source: "#client-acme")
        let bare = MarkdownAttributedText.clickURL(for: .tag("client-acme"), source: "client-acme")

        #expect(withHash == MarkdownAttributedText.tagURL(for: acme()))
        #expect(bare == MarkdownAttributedText.tagURL(for: acme()))
        #expect(withHash != nil)
    }

    @Test func aTagThatIsNotInAKnownNamespaceIsNotAClickTarget() { // (n1-seams R-12)
        // `Pergamenum.Tag(_:)` is the one door; a `#word` that is no tag of the closed schema opens nothing.
        let url = MarkdownAttributedText.clickURL(for: .tag("#semplice"), source: "#semplice")
        #expect(url == nil)
    }

    @Test func aScheduledAndADueSpanGiveTheSameDayURL() { // (n1-seams R-13)
        let scheduled = MarkdownAttributedText.clickURL(for: .scheduled, source: ">2026-10-12")
        let due = MarkdownAttributedText.clickURL(for: .due, source: "!2026-10-12")

        #expect(scheduled == MarkdownAttributedText.dayURL(for: october12()))
        #expect(due == MarkdownAttributedText.dayURL(for: october12()))
        #expect(scheduled != nil)
    }

    @Test func anImpossibleDateIsNotAClickTarget() { // (n1-seams R-13)
        #expect(MarkdownAttributedText.clickURL(for: .scheduled, source: ">2026-02-31") == nil)
        #expect(MarkdownAttributedText.clickURL(for: .due, source: "!2026-13-01") == nil)
    }

    @Test func anAnnotationIsNeverAClickTarget() { // (n1-seams R-13)
        for source in ["@done(2026-10-01)", "@remind(2026-10-12)", "@repeat(2026-10-12)"] {
            #expect(
                MarkdownAttributedText.clickURL(for: .annotation, source: Substring(source)) == nil,
                "\(source)"
            )
        }
    }

    @Test func noOtherSpanIsAClickTarget() { // (n1-seams R-12)
        let others: [MarkdownStyler.Span] = [
            .bold, .italic, .code, .strikethrough, .heading(level: 2), .headingMarker,
            .linkSyntax, .embedRun, .codeBlock, .frontmatter,
        ]
        for span in others {
            #expect(
                MarkdownAttributedText.clickURL(for: span, source: "#client-acme") == nil,
                "\(span)"
            )
        }
    }
}

// MARK: - The round trip

@Suite struct ClickTargetRoundTrip {
    @Test func aTagURLDecodesBackToTheTag() { // (n1-seams R-12)
        let url = MarkdownAttributedText.tagURL(for: acme())
        #expect(MarkdownAttributedText.clickTarget(for: url) == .tag(acme()))
    }

    @Test func aDayURLDecodesBackToTheDay() { // (n1-seams R-13)
        let url = MarkdownAttributedText.dayURL(for: october12())
        #expect(MarkdownAttributedText.clickTarget(for: url) == .day(october12()))
    }

    @Test func tagAndDayURLsDoNotCollideWithEachOtherOrWithANote() { // (n1-seams R-12, R-13)
        let tag = MarkdownAttributedText.tagURL(for: acme())
        let day = MarkdownAttributedText.dayURL(for: october12())
        #expect(tag != day)
        #expect(tag != MarkdownAttributedText.noteURL(for: "client-acme"))
        #expect(MarkdownAttributedText.clickTarget(for: MarkdownAttributedText.noteURL(for: "client-acme"))
            == .note(title: "client-acme"))
    }
}

// MARK: - The styled text

@MainActor
@Suite struct StyledTagAndDateRuns {
    private static func linkURL(
        in text: NSAttributedString, at index: Int
    ) -> URL? {
        text.attribute(.editorLink, at: index, effectiveRange: nil) as? URL
    }

    @Test func theComposedStringCarriesTheLinkAndKeepsItsTokenColour() { // (n1-seams R-12, R-13)
        let theme = Theme.emergency
        let text = "Vedi \(tagText) e - [ ] fare \(dayText) poi \(dueText)"
        let styled = MarkdownAttributedText.attributed(text, theme: theme)
        let nsText = text as NSString

        let tagAt = nsText.range(of: tagText).location
        let dayAt = nsText.range(of: dayText).location
        let dueAt = nsText.range(of: dueText).location

        #expect(Self.linkURL(in: styled, at: tagAt) == MarkdownAttributedText.tagURL(for: acme()))
        #expect(Self.linkURL(in: styled, at: dayAt) == MarkdownAttributedText.dayURL(for: october12()))
        #expect(Self.linkURL(in: styled, at: dueAt) == MarkdownAttributedText.dayURL(for: october12()))

        let tagColour = styled.attribute(.foregroundColor, at: tagAt, effectiveRange: nil) as? NSColor
        let dayColour = styled.attribute(.foregroundColor, at: dayAt, effectiveRange: nil) as? NSColor
        let dueColour = styled.attribute(.foregroundColor, at: dueAt, effectiveRange: nil) as? NSColor
        #expect(tagColour == NSColor(theme.color(.accentPrimary)))
        #expect(dayColour == NSColor(theme.color(.taskScheduled)))
        #expect(dueColour == NSColor(theme.color(.taskOverdue)))
    }

    @Test func withLinksOffNoneOfThemCarriesALink() { // (n1-seams R-12, R-13)
        // A transcluded note is a picture of another file: no click it could route.
        let theme = Theme.emergency
        let text = "Vedi \(tagText) e \(dayText) poi \(dueText)"
        let styled = MarkdownAttributedText.attributed(text, theme: theme, links: false)
        let nsText = text as NSString

        for run in [tagText, dayText, dueText] {
            let index = nsText.range(of: run).location
            #expect(Self.linkURL(in: styled, at: index) == nil, "\(run)")
        }
        // The colour is still the token's: only the click is withheld.
        let tagColour = styled.attribute(
            .foregroundColor, at: nsText.range(of: tagText).location, effectiveRange: nil
        ) as? NSColor
        #expect(tagColour == NSColor(theme.color(.accentPrimary)))
    }

    @Test func anImpossibleDateAndAnAnnotationCarryNoLink() { // (n1-seams R-13)
        let text = "- [ ] fare >2026-02-31 @done(2026-10-01)"
        let styled = MarkdownAttributedText.attributed(text, theme: .emergency)
        let nsText = text as NSString

        #expect(Self.linkURL(in: styled, at: nsText.range(of: ">2026-02-31").location) == nil)
        #expect(Self.linkURL(in: styled, at: nsText.range(of: "@done").location) == nil)
    }

    @Test func theNoteEditorsStyledStorageCarriesTheLinks() { // (n1-seams R-12, R-13)
        let theme = Theme.emergency
        let text = "Vedi \(tagText) e - [ ] fare \(dayText)"
        let fixture = EmbedEditorFixtures.editor(
            text: text, hidesMarkup: false, root: nil, thumbnails: nil
        )
        fixture.coordinator.applyStyling(to: fixture.textView, theme: theme)
        let storage = fixture.textView.textStorage
        let nsText = text as NSString
        let tagAt = nsText.range(of: tagText).location
        let dayAt = nsText.range(of: dayText).location

        #expect(storage?.attribute(.editorLink, at: tagAt, effectiveRange: nil) as? URL
            == MarkdownAttributedText.tagURL(for: acme()))
        #expect(storage?.attribute(.editorLink, at: dayAt, effectiveRange: nil) as? URL
            == MarkdownAttributedText.dayURL(for: october12()))
        let colour = storage?.attribute(.foregroundColor, at: tagAt, effectiveRange: nil) as? NSColor
        #expect(colour == NSColor(theme.color(.accentPrimary)))
        // And a word between them stays unlinked.
        #expect(storage?.attribute(.editorLink, at: 0, effectiveRange: nil) == nil)
    }

    @Test func aWorkspaceCardsStyledTextDoesTheSame() { // (n1-seams R-12, R-13)
        let theme = Theme.emergency
        let text = "Vedi \(tagText) e - [ ] fare \(dayText)"
        let styled = CardTextAttributes.attributed(text, theme: theme)
        let nsText = text as NSString
        let tagAt = nsText.range(of: tagText).location
        let dayAt = nsText.range(of: dayText).location

        #expect(Self.linkURL(in: styled, at: tagAt) == MarkdownAttributedText.tagURL(for: acme()))
        #expect(Self.linkURL(in: styled, at: dayAt) == MarkdownAttributedText.dayURL(for: october12()))
        let colour = styled.attribute(.foregroundColor, at: tagAt, effectiveRange: nil) as? NSColor
        #expect(colour == NSColor(theme.color(.accentPrimary)))
        #expect(Self.linkURL(in: styled, at: 0) == nil)
    }
}

// MARK: - Click behaviour, note editor

@MainActor
@Suite struct NoteEditorTagAndDateClicks {
    /// What the editor's two new callbacks were called with.
    @MainActor
    final class Spy {
        var tags: [Pergamenum.Tag] = []
        var days: [CalendarDate] = []
    }

    /// `EmbedEditorFixtures.editor`'s construction with `onOpenTag` / `onOpenDay` handed in,
    /// styled once so the run carries the attribute a click reads.
    private static func fixture(text: String, spy: Spy) -> EmbedEditorFixtures.Fixture {
        var inputs = NoteTextView.VaultInputs(vaultRoot: nil, notePath: "Nota.md", thumbnails: nil)
        inputs.onOpenTag = { spy.tags.append($0) }
        inputs.onOpenDay = { spy.days.append($0) }
        let view = NoteTextView(
            text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: false, onFollowLink: { _ in }, vault: inputs
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = text
        textView.delegate = coordinator
        let window = NSWindow(
            contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = textView
        coordinator.applyStyling(to: textView, theme: .emergency)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
        textView.layoutSubtreeIfNeeded()
        return EmbedEditorFixtures.Fixture(
            textView: textView, coordinator: coordinator, window: window,
            followedLinks: LinkFollowSpy()
        )
    }

    private static func pointInside(_ fixture: EmbedEditorFixtures.Fixture) -> CGPoint {
        let frame = EmbedEditorFixtures.fragmentFrame(at: 0, in: fixture.textView)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    @Test func cmdClickOnATagOpensItAndNothingElse() { // (n1-seams R-12)
        let spy = Spy()
        let fixture = Self.fixture(text: tagText, spy: spy)
        fixture.coordinator.modifierFlags = { .command }

        let followed = fixture.textView.followLinkIfPresent(at: Self.pointInside(fixture))

        #expect(followed)
        #expect(spy.tags == [acme()])
        #expect(spy.days.isEmpty)
    }

    @Test func aPlainClickOnATagCallsNothingAndPlacesTheCaret() { // (n1-seams R-12)
        let spy = Spy()
        let fixture = Self.fixture(text: tagText, spy: spy)
        fixture.coordinator.modifierFlags = { [] }
        let point = Self.pointInside(fixture)

        let followed = fixture.textView.followLinkIfPresent(at: point)
        #expect(!followed)
        #expect(spy.tags.isEmpty)

        // The tag run is a link now, so a plain click lands the caret through the same helper a
        // wikilink uses (issue #191) - and reveal-on-caret then has something to act on.
        let placed = fixture.textView.placeCaretForPlainClick(at: point)
        #expect(placed)
        #expect(fixture.textView.selectedRange().length == 0)
        #expect(spy.tags.isEmpty)
    }

    @Test func cmdClickOnAScheduledDateOpensItsDay() { // (n1-seams R-13)
        let spy = Spy()
        let fixture = Self.fixture(text: dayText, spy: spy)
        fixture.coordinator.modifierFlags = { .command }

        let followed = fixture.textView.followLinkIfPresent(at: Self.pointInside(fixture))

        #expect(followed)
        #expect(spy.days == [october12()])
        #expect(spy.tags.isEmpty)
    }

    @Test func cmdClickOnADueDateOpensItsDay() { // (n1-seams R-13)
        let spy = Spy()
        let fixture = Self.fixture(text: dueText, spy: spy)
        fixture.coordinator.modifierFlags = { .command }

        #expect(fixture.textView.followLinkIfPresent(at: Self.pointInside(fixture)))
        #expect(spy.days == [october12()])
    }

    @Test func aPlainClickOnADateCallsNothing() { // (n1-seams R-13)
        let spy = Spy()
        let fixture = Self.fixture(text: dayText, spy: spy)
        fixture.coordinator.modifierFlags = { [] }

        #expect(!fixture.textView.followLinkIfPresent(at: Self.pointInside(fixture)))
        #expect(spy.days.isEmpty)
    }

    @Test func cmdClickOnAnImpossibleDateOpensNothing() { // (n1-seams R-13)
        let spy = Spy()
        let fixture = Self.fixture(text: ">2026-02-31", spy: spy)
        fixture.coordinator.modifierFlags = { .command }

        #expect(!fixture.textView.followLinkIfPresent(at: Self.pointInside(fixture)))
        #expect(spy.days.isEmpty)
    }
}

// MARK: - Click behaviour, Workspace card

@MainActor
@Suite struct CardTagAndDateClicks {
    @MainActor
    final class Spy {
        var tags: [Pergamenum.Tag] = []
        var days: [CalendarDate] = []
    }

    private static func coordinator(spy: Spy) -> CardTextView.Coordinator {
        var view = CardTextView(
            text: .constant("Vedi \(tagText)"),
            theme: .emergency,
            style: CardTextStyle(color: nil, alignment: nil),
            isEditable: true,
            hidesMarkup: false
        )
        view.onOpenTag = { spy.tags.append($0) }
        view.onOpenDay = { spy.days.append($0) }
        return view.makeCoordinator()
    }

    @Test func cmdClickOnATagOpensIt() { // (n1-seams R-12)
        let spy = Spy()
        let coordinator = Self.coordinator(spy: spy)
        coordinator.modifierFlags = { .command }

        let followed = coordinator.textView(
            FormattingTextView(), clickedOnLink: MarkdownAttributedText.tagURL(for: acme()), at: 5
        )
        #expect(followed)
        #expect(spy.tags == [acme()])
    }

    @Test func aPlainClickOnATagOpensNothing() { // (n1-seams R-12)
        let spy = Spy()
        let coordinator = Self.coordinator(spy: spy)
        coordinator.modifierFlags = { [] }

        let followed = coordinator.textView(
            FormattingTextView(), clickedOnLink: MarkdownAttributedText.tagURL(for: acme()), at: 5
        )
        #expect(!followed)
        #expect(spy.tags.isEmpty)
    }

    @Test func cmdClickOnADateOpensItsDay() { // (n1-seams R-13)
        let spy = Spy()
        let coordinator = Self.coordinator(spy: spy)
        coordinator.modifierFlags = { .command }

        let followed = coordinator.textView(
            FormattingTextView(), clickedOnLink: MarkdownAttributedText.dayURL(for: october12()), at: 5
        )
        #expect(followed)
        #expect(spy.days == [october12()])
        #expect(spy.tags.isEmpty)
    }

    @Test func aPlainClickOnADateOpensNothing() { // (n1-seams R-13)
        let spy = Spy()
        let coordinator = Self.coordinator(spy: spy)
        coordinator.modifierFlags = { [] }

        #expect(!coordinator.textView(
            FormattingTextView(), clickedOnLink: MarkdownAttributedText.dayURL(for: october12()), at: 5
        ))
        #expect(spy.days.isEmpty)
    }
}
