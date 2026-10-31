import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0098 §D4, closing ADR-0082 §D8's named gap; plan
// docs/plans/pg-427-pg-428-underscore-concealment-daily-transclusions.md, Task 3 (PG-428).
//
// A `![[nota]]` transclusion renders in the Oggi and Diario panes as it does in a note's editor:
// the source `EditorColumnView.transclusionSource` builds moves into one factory,
// `TransclusionSource.live(for:)`, and the three hosts pass it: the note's editor, `TodayView`
// and `DiaryView`.

private let note = "---\ndate: 2026-10-06\ntags:\n  - type-note\n---\n\nCorpo della nota.\n\n## Sezione\n\nTesto della sezione.\n"
private let prose = "prima\n![[N]]\ndopo\n"

@MainActor
@Suite(.serialized) struct DailySurfaceTransclusions {
    private func opened(_ vault: borrowing TemporaryVault) async throws -> VaultController {
        try vault.write(note, to: "Note/N.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        return controller
    }

    /// The inputs a daily pane passes (`TodayView`/`DiaryView`), with the transclusion source the
    /// factory builds.
    private func paneInputs(_ controller: VaultController) -> NoteTextView.VaultInputs {
        NoteTextView.VaultInputs(
            vaultRoot: controller.root, notePath: "Diario/2026-10-11.md", thumbnails: controller.thumbnails,
            transclusions: .live(for: controller), queries: .live(for: controller),
            onOpenTag: { _ in }, onOpenDay: { _ in }
        )
    }

    // MARK: The generation

    // The factory's generation is the editor's own, and it moves when the index does.
    @Test func theLiveSourceCarriesTheEditorsGenerationAndFollowsTheIndex() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        defer { controller.close() }

        let before = TransclusionSource.live(for: controller).generation
        #expect(before == EditorColumnView.transclusionGeneration(for: controller))

        try vault.write(note + "\nAltro.\n", to: "Note/N.md")
        await controller.reconcile(["Note/N.md"])
        let after = TransclusionSource.live(for: controller).generation

        #expect(after == EditorColumnView.transclusionGeneration(for: controller))
        #expect(after != before, "the generation did not move with the index")
    }

    // MARK: The lookup

    // A title and a vault-relative path both resolve to the note, with its full text.
    @Test(arguments: ["N", "Note/N.md"])
    func aTitleAndAPathBothResolveToTheNote(_ reference: String) async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        defer { controller.close() }

        let resolved = try #require(TransclusionSource.live(for: controller).resolve(reference), "\(reference) did not resolve")
        #expect(resolved.relativePath == "Note/N.md")
        #expect(resolved.text == note)
    }

    // A name no note bears resolves to nothing.
    @Test func aNameNoNoteBearsResolvesToNothing() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        defer { controller.close() }

        #expect(TransclusionSource.live(for: controller).resolve("Assente") == nil)
    }

    // MARK: A hosted editor draws it

    // A hosted editor given the pane's inputs draws one rendition, at the `![[N]]` line.
    @Test func aHostedEditorDrawsTheTransclusionLine() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        defer { controller.close() }

        let editor = ScrolledEditorFixture(text: prose, vault: paneInputs(controller))
        defer { editor.window.orderOut(nil) }
        editor.runPasses()

        let lineStart = (prose as NSString).range(of: "![[N]]").location
        let renditions = editor.coordinator.transclusion.lastRenditions
        #expect(renditions.count == 1, "\(renditions.keys.sorted())")
        #expect(renditions[lineStart]?.title == "N", "\(renditions.mapValues(\.title))")
    }

    // The section form's rendition is titled with the note and the section.
    @Test func aSectionTransclusionIsTitledWithItsSection() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        defer { controller.close() }
        let text = "prima\n![[N#Sezione]]\ndopo\n"

        let editor = ScrolledEditorFixture(text: text, vault: paneInputs(controller))
        defer { editor.window.orderOut(nil) }
        editor.runPasses()

        let lineStart = (text as NSString).range(of: "![[N#Sezione]]").location
        let renditions = editor.coordinator.transclusion.lastRenditions
        #expect(renditions[lineStart]?.title == "N › Sezione", "\(renditions.mapValues(\.title))")
    }

    // The same source feeds `[[Nota#` completion: an editor given the pane's inputs lists the
    // target note's sections through the closure `NoteTextView.wire(_:to:)` installs.
    @Test func aHostedEditorListsTheNotesSectionsForHeadingCompletion() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        defer { controller.close() }

        let editor = ScrolledEditorFixture(text: prose, vault: paneInputs(controller))
        defer { editor.window.orderOut(nil) }

        #expect(editor.textView.noteSections?("N") == ["Sezione"])
        #expect(editor.textView.noteSections?("Assente") == [])
    }

    // MARK: The incremental path

    // A prose keystroke is one incremental restyle, the rendition stays drawn, and the editor
    // equals its full-restyle twin.
    @Test func aProseKeystrokeKeepsTheRenditionAndTheIncrementalPath() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        defer { controller.close() }
        let inputs = paneInputs(controller)

        let incremental = ScrolledEditorFixture(text: prose, vault: inputs, forcesFullRestyle: nil)
        let full = ScrolledEditorFixture(text: prose, vault: inputs, forcesFullRestyle: true)
        let twin = RestyleTwin(incremental: incremental, full: full)
        defer { twin.tearDown() }
        twin.both { $0.runPasses() }
        let lineStart = (prose as NSString).range(of: "![[N]]").location
        #expect(incremental.coordinator.transclusion.lastRenditions[lineStart]?.title == "N", "no rendition before the keystroke")
        try #require(!incremental.coordinator.forcesFullRestyle, "the kill switch is on in this test process")

        let before = incremental.coordinator.restyleLog
        twin.type("x", at: 3)

        let after = incremental.coordinator.restyleLog
        #expect(after.incremental == before.incremental + 1, "not one incremental restyle: \(before) then \(after)")
        #expect(after.full == before.full, "a prose keystroke was restyled in full: \(before) then \(after)")
        // The keystroke inserts one character before the `![[N]]` line, so the rendition moves with it:
        // read the line's offset from the edited text rather than reuse the one measured before.
        let typedLineStart = (incremental.textView.string as NSString).range(of: "![[N]]").location
        #expect(typedLineStart == lineStart + 1, "the keystroke did not land before the transclusion line")
        let renditions = incremental.coordinator.transclusion.lastRenditions
        #expect(renditions.count == 1 && renditions[typedLineStart]?.title == "N", "the rendition was lost: \(renditions.mapValues(\.title)), line at \(typedLineStart)")
        #expect(twin.differences().isEmpty, "\(twin.differences())")
    }

    // MARK: A caret crossing a view fence

    // A caret crossing a `pergamenum-view` fence restyles the note from the selection handler, and
    // that restyle rewrites every paragraph style - the one buying a transclusion's height
    // included. The reservation is bought back in the same handler, not left for a SwiftUI update
    // the daily panes never send on a bare caret move (found by hand in Oggi and Diario).
    @Test func aCaretCrossingAViewFenceKeepsTheTransclusionsHeight() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        defer { controller.close() }
        let text = "prima\n![[N]]\n\n```pergamenum-view\nrender: list\n```\n\nfine\n"

        let editor = ScrolledEditorFixture(text: text, vault: paneInputs(controller))
        defer { editor.window.orderOut(nil) }
        editor.runPasses()
        let lineStart = (text as NSString).range(of: "![[N]]").location
        let reserved = try #require(editor.coordinator.transclusion.lastRenditions[lineStart]?.reservedHeight)
        func spacing() -> CGFloat? {
            (editor.textView.textStorage?.attribute(.paragraphStyle, at: lineStart, effectiveRange: nil)
                as? NSParagraphStyle)?.paragraphSpacing
        }
        #expect(spacing() == reserved, "no reservation before the caret moved")

        let inside = (text as NSString).range(of: "render: list").location
        editor.textView.setSelectedRange(NSRange(location: inside, length: 0))
        #expect(spacing() == reserved, "entering the fence dropped the reservation: \(String(describing: spacing()))")

        let after = (text as NSString).range(of: "fine").location
        editor.textView.setSelectedRange(NSRange(location: after, length: 0))
        #expect(spacing() == reserved, "leaving the fence dropped the reservation: \(String(describing: spacing()))")
    }

    // MARK: Source guards

    // Each pane passes the factory.
    @Test(arguments: ["Sources/Features/Today/TodayView.swift", "Sources/Features/Diary/DiaryView.swift"])
    func theDailyPanesPassTheLiveTransclusionSource(_ relativePath: String) throws {
        let root = try resolvedRepoRoot()
        let source = try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)

        #expect(source.contains("transclusions: .live(for: vault)"), "\(relativePath) does not pass `transclusions: .live(for: vault)`")
    }

    // The lookup lives in the factory only. A call-site check, not a symbol check,
    // so a factory nothing calls fails here.
    @Test func theColumnNoLongerCarriesTheLookupItself() throws {
        let root = try resolvedRepoRoot()
        let source = try String(
            contentsOf: root.appending(path: "Sources/Features/Editor/EditorColumn+Text.swift"), encoding: .utf8
        )

        #expect(!source.contains("vault.index.resolve(title:"), "EditorColumn+Text.swift still holds the lookup")
    }
}
