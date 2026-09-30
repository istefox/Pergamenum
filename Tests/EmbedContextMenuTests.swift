import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0023: A command is named once and rendered twice.
// Plan: docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md, Task 8.
//
// `EmbedContextMenu` is the pure catalogue for the drawn embed's own context menu
// (ADR-0023 §D9, R-08): its delete **is** the Backspace path, so the equality tests below
// compare directly against a real call to `EmbedNavigation.deletionRange` rather than
// restating its rule as a separate assertion.
//
// RED (Task 8): `EmbedContextMenu.items()` is a placeholder that always returns `[]`, and
// `deletionRange(forRun:textLength:)` is a placeholder that always returns `nil` - so every
// assertion below fails on its assertion, not on a build error.
//
// Fixtures beside `EmbedNavigationTests.swift`, reusing its own text and offsets: the
// thirteen-character embed run `"![[foto.png]]"` (never the trailing newline) placed at
// the start, the middle, and the very end of a small fixture text.

// MARK: - The menu's delete is the Backspace path (R-08)

@Test func theMenusDeleteForARunAtTheStartOfTheTextMatchesBackspacesOwnRange() {
    // "![[foto.png]]\ndopo\n" - the run starts at offset 0, the whole text is nineteen
    // characters (13 + "\n" + "dopo" + "\n").
    let run = NSRange(location: 0, length: 13)
    let textLength = 19
    #expect(
        EmbedContextMenu.deletionRange(forRun: run, textLength: textLength)
            == EmbedNavigation.deletionRange(
                selection: NSRange(location: NSMaxRange(run), length: 0),
                direction: .backward, drawnRuns: [run], textLength: textLength
            )
    )
}

@Test func theMenusDeleteForARunInTheMiddleOfTheTextMatchesBackspacesOwnRange() {
    // "prima\n![[foto.png]]\ndopo\n" - `EmbedNavigationTests`'s own fixture: the run starts
    // at offset 6, the whole text is twenty-five characters.
    let run = NSRange(location: 6, length: 13)
    let textLength = 25
    #expect(
        EmbedContextMenu.deletionRange(forRun: run, textLength: textLength)
            == EmbedNavigation.deletionRange(
                selection: NSRange(location: NSMaxRange(run), length: 0),
                direction: .backward, drawnRuns: [run], textLength: textLength
            )
    )
}

@Test func theMenusDeleteForARunAtTheVeryEndOfTheTextWithNoTrailingNewlineMatchesBackspacesOwnRange() {
    // "prima\n![[foto.png]]" - the run is the note's very last line, with nothing after it
    // to eat: `textLength` is the run's own far edge.
    let run = NSRange(location: 6, length: 13)
    let textLength = NSMaxRange(run)
    #expect(
        EmbedContextMenu.deletionRange(forRun: run, textLength: textLength)
            == EmbedNavigation.deletionRange(
                selection: NSRange(location: NSMaxRange(run), length: 0),
                direction: .backward, drawnRuns: [run], textLength: textLength
            )
    )
}

// MARK: - Catalogue shape (R-08)

@Test func itemsReturnsExactlyOneEntryTitledElimina() {
    #expect(EmbedContextMenu.items() == ["Elimina"])
}

// MARK: - The stale-range refusal (R-08)

@Test func deletionRangeRefusesARunWhoseEndExceedsTheCurrentTextLength() {
    // The document has since shrunk to exactly where this run used to begin - the same
    // stale-range guard `replaceAtomically` already applies, refused one step earlier so
    // the menu never asks for a bad write.
    let staleRun = NSRange(location: 6, length: 13)
    #expect(EmbedContextMenu.deletionRange(forRun: staleRun, textLength: 6) == nil)
}

// MARK: - The wired menu hook (ADR-0074 G2 H7)

/// A right click at `point` (the text view's own flipped coordinates, what
/// `EmbedEditorFixtures` returns), built the way `WikilinkClickNavigationTests` builds one and
/// handed straight to `menu(for:)` - never sent through a window.
@MainActor
private func rightClick(at point: CGPoint, in fixture: EmbedEditorFixtures.Fixture) -> NSEvent {
    NSEvent.mouseEvent(
        with: .rightMouseDown, location: fixture.textView.convert(point, to: nil),
        modifierFlags: [], timestamp: 0, windowNumber: fixture.window.windowNumber,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1
    )!
}

/// The fixture's `claimsCommand`-only wiring plus the rest of `NoteTextView.wire(_:to:)`, so
/// `onEmbedMenu` is the app's own closure and not a copy.
@MainActor
private func wired(_ fixture: EmbedEditorFixtures.Fixture) {
    NoteTextView(
        text: .constant(""), theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: true, onFollowLink: { _ in }
    ).wire(fixture.textView, to: fixture.coordinator)
}

/// G2 H7: a secondary click on a drawn picture reaches `CompletingTextView.menu(for:)`, which
/// asks `onEmbedMenu` first, so the menu is the embed's own catalogue and nothing else.
@MainActor
@Test func aRightClickOnADrawnEmbedYieldsTheEmbedMenu() async throws {
    let root = try EmbedEditorFixtures.makeTempVaultRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
    defer { fixture.window.orderOut(nil) }
    #expect(box.width > 0)
    wired(fixture)

    let menu = fixture.textView.menu(for: rightClick(at: CGPoint(x: box.midX, y: box.midY), in: fixture))

    #expect(menu?.items.map(\.title) == EmbedContextMenu.items())
    // The menu's action is the coordinator's, and the click selected the run it acts on.
    #expect(menu?.items.first?.target === fixture.coordinator)
    #expect(
        fixture.textView.selectedRange()
            == NSRange(location: EmbedEditorFixtures.embedOffset, length: EmbedEditorFixtures.runLength)
    )
}

/// G2 H7: away from the picture `onEmbedMenu` answers nil and the click falls through to
/// `super.menu(for:)` - the system contextual menu, present and without the embed's entry.
@MainActor
@Test func aRightClickOutsideAnEmbedFallsThroughToTheSystemMenu() async throws {
    let root = try EmbedEditorFixtures.makeTempVaultRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let (fixture, _) = try await EmbedEditorFixtures.landedEmbed(root: root)
    defer { fixture.window.orderOut(nil) }
    wired(fixture)
    let frame = EmbedEditorFixtures.fragmentFrame(at: 0, in: fixture.textView)
    #expect(frame.width > 0)

    let menu = fixture.textView.menu(for: rightClick(at: CGPoint(x: frame.midX, y: frame.midY), in: fixture))

    #expect(menu != nil, "il menu di sistema dell'editor non deve sparire fuori da un embed")
    #expect(menu?.items.contains { $0.title == "Elimina" } != true)
}
