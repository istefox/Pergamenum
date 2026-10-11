import AppKit
import Testing
@testable import Pergamenum

/// R-21 (ADR-0083 §D2): the click variants, read in the Coordinator through the `modifierFlags`
/// seam and handed to `links.follow` as one `LinkRequest`. The protected file is never involved:
/// these drive the delegate method and `performLinkNavigation`, the two things it calls.
private func acmeTag() -> Pergamenum.Tag? { Pergamenum.Tag("#client-acme") }

@MainActor
@Suite struct WikilinkClickVariants {
    private static func editor() -> (EmbedEditorFixtures.Fixture, LinkInputsSpy) {
        let fixture = EmbedEditorFixtures.editor(
            text: "Vedi Destinazione qui", hidesMarkup: false, root: nil, thumbnails: nil
        )
        let spy = LinkInputsSpy()
        spy.install(on: fixture.coordinator)
        return (fixture, spy)
    }

    private static let url = MarkdownAttributedText.noteURL(for: "Destinazione")

    @Test(arguments: [
        (NSEvent.ModifierFlags.command, LinkOpening.replace),
        ([.command, .shift], .newTab),
        ([.command, .option], .otherColumn),
        ([.command, .shift, .option], .otherColumn),
    ] as [(NSEvent.ModifierFlags, LinkOpening)])
    func aCommandClickReachesFollowWithItsHow(flags: NSEvent.ModifierFlags, how: LinkOpening) {
        let (fixture, spy) = Self.editor()
        fixture.coordinator.modifierFlags = { flags }

        let followed = fixture.coordinator.textView(fixture.textView, clickedOnLink: Self.url, at: 5)

        #expect(followed)
        #expect(spy.requests.count == 1)
        #expect(spy.requests.first?.target == "Destinazione")
        #expect(spy.requests.first?.how == how)
        #expect(spy.requests.first?.fromClick == true)
        #expect(spy.requests.first?.sourcePath == nil || spy.requests.first?.sourcePath == "Nota.md")
        #expect(fixture.followedLinks.titles.isEmpty)
    }

    @Test func aClickWithoutCommandStillFollowsNothing() {
        let (fixture, spy) = Self.editor()
        fixture.coordinator.modifierFlags = { .shift }

        let followed = fixture.coordinator.textView(fixture.textView, clickedOnLink: Self.url, at: 5)

        #expect(!followed)
        #expect(spy.requests.isEmpty)
    }

    @Test func theMenuPathReachesFollowWithReplaceAndNotFromAClick() {
        let (fixture, spy) = Self.editor()

        let handled = fixture.coordinator.performLinkNavigation(Self.url)

        #expect(handled)
        #expect(spy.requests.count == 1)
        #expect(spy.requests.first?.how == .replace)
        #expect(spy.requests.first?.fromClick == false)
    }

    @Test func withNoFollowInputCommandStillCallsOnFollowLink() {
        let fixture = EmbedEditorFixtures.editor(
            text: "Vedi Destinazione qui", hidesMarkup: false, root: nil, thumbnails: nil
        )
        #expect(fixture.coordinator.parent.links.follow == nil)
        fixture.coordinator.modifierFlags = { .command }

        _ = fixture.coordinator.textView(fixture.textView, clickedOnLink: Self.url, at: 5)

        #expect(fixture.followedLinks.titles == ["Destinazione"])
    }

    @Test(arguments: [
        NSEvent.ModifierFlags([.command, .shift]),
        NSEvent.ModifierFlags([.command, .option]),
    ])
    func withNoFollowInputTheVariantsDoNothing(flags: NSEvent.ModifierFlags) {
        let fixture = EmbedEditorFixtures.editor(
            text: "Vedi Destinazione qui", hidesMarkup: false, root: nil, thumbnails: nil
        )
        fixture.coordinator.modifierFlags = { flags }

        _ = fixture.coordinator.textView(fixture.textView, clickedOnLink: Self.url, at: 5)

        #expect(fixture.followedLinks.titles.isEmpty)
    }

    // MARK: The choice at the click

    private static let sharedChoices = LinkChoice.entries(for: .ambiguous(
        title: "Riunione", paths: ["Clienti/Riunione.md", "Progetti/Riunione.md"]
    ))

    @Test func aChooseOutcomeHandsThePresenterAMenuWithADisabledHeaderAndTheFolderLabels() throws {
        let (fixture, spy) = Self.editor()
        let menus = LinkChoiceMenuSpy()
        fixture.coordinator.linkChoiceMenus = menus
        spy.outcome = .choose(Self.sharedChoices)
        fixture.coordinator.modifierFlags = { .command }

        _ = fixture.coordinator.textView(
            fixture.textView, clickedOnLink: MarkdownAttributedText.noteURL(for: "Riunione"), at: 5
        )

        let presented = try #require(menus.presented.last)
        #expect(presented.view === fixture.textView)
        let header = try #require(presented.menu.items.first)
        #expect(!header.isEnabled)
        #expect(menus.itemTitles == ["Clienti", "Progetti"])
        for row in menus.rows(of: presented.menu) { #expect(row.isEnabled) }
    }

    @Test func invokingARowCallsChooseWithThatChoiceAndTheClicksHow() throws {
        let (fixture, spy) = Self.editor()
        let menus = LinkChoiceMenuSpy()
        fixture.coordinator.linkChoiceMenus = menus
        spy.outcome = .choose(Self.sharedChoices)
        fixture.coordinator.modifierFlags = { [.command, .shift] }

        _ = fixture.coordinator.textView(
            fixture.textView, clickedOnLink: MarkdownAttributedText.noteURL(for: "Riunione"), at: 5
        )
        menus.invoke(row: 1)

        #expect(spy.chosen.count == 1)
        #expect(spy.chosen.first?.choice == Self.sharedChoices[1])
        #expect(spy.chosen.first?.how == .newTab)
    }

    @Test func aDoneOutcomePresentsNoMenu() {
        let (fixture, spy) = Self.editor()
        let menus = LinkChoiceMenuSpy()
        fixture.coordinator.linkChoiceMenus = menus
        spy.outcome = .done
        fixture.coordinator.modifierFlags = { .command }

        _ = fixture.coordinator.textView(fixture.textView, clickedOnLink: Self.url, at: 5)

        #expect(menus.presented.isEmpty)
    }

    @Test func theMenuPathNeverPresentsAMenuAtAPointItDoesNotHave() {
        let (fixture, spy) = Self.editor()
        let menus = LinkChoiceMenuSpy()
        fixture.coordinator.linkChoiceMenus = menus
        spy.outcome = .choose(Self.sharedChoices)

        _ = fixture.coordinator.performLinkNavigation(MarkdownAttributedText.noteURL(for: "Riunione"))

        // Not from a click: the sheet is the surface, so `follow` was asked and no menu appeared.
        #expect(spy.requests.first?.fromClick == false)
        #expect(menus.presented.isEmpty)
    }

    // MARK: Tags and days keep N1's routing

    @Test(arguments: [
        NSEvent.ModifierFlags.command,
        [.command, .shift],
        [.command, .option],
    ] as [NSEvent.ModifierFlags])
    func aTagOrDayTargetKeepsItsRoutingWhateverModifiersAreHeld(flags: NSEvent.ModifierFlags) throws {
        let (fixture, spy) = Self.editor()
        var tags: [Pergamenum.Tag] = []
        var days: [CalendarDate] = []
        fixture.coordinator.parent.vault.onOpenTag = { tags.append($0) }
        fixture.coordinator.parent.vault.onOpenDay = { days.append($0) }
        fixture.coordinator.modifierFlags = { flags }
        let tag = try #require(acmeTag())
        let day = try #require(CalendarDate(iso: "2026-10-12"))

        let tagFollowed = fixture.coordinator.textView(
            fixture.textView, clickedOnLink: MarkdownAttributedText.tagURL(for: tag), at: 0
        )
        let dayFollowed = fixture.coordinator.textView(
            fixture.textView, clickedOnLink: MarkdownAttributedText.dayURL(for: day), at: 0
        )

        #expect(tagFollowed && dayFollowed)
        #expect(tags == [tag])
        #expect(days == [day])
        #expect(spy.requests.isEmpty)
    }
}
