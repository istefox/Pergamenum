import Foundation
import Testing
@testable import Pergamenum

// ADR-0083 §D7, review follow-ups to session B: the fade belongs to a body that was cut, and a
// board target is named rather than resolved.

@Suite struct LinkPreviewReviewFixesTests {
    private func note(lines count: Int) -> LinkPreviewContent? {
        let text = (1...count).map { "riga \($0)" }.joined(separator: "\n")
        return LinkPreviewContent.make(for: .note(path: "Nota.md"), section: nil, noteText: { _ in text })
    }

    private func lineCount(_ content: LinkPreviewContent?) -> Int? {
        guard case .note(_, let lines, _)? = content?.kind else { return nil }
        return lines.count
    }

    @Test func aBodyOfExactlyTwelveLinesShowsAllOfThemAndIsNotCut() {
        let content = note(lines: LinkPreviewContent.lineLimit)
        #expect(lineCount(content) == LinkPreviewContent.lineLimit)
        #expect(content?.isCut == false)
    }

    @Test func aBodyPastTwelveLinesIsCut() {
        let content = note(lines: LinkPreviewContent.lineLimit + 1)
        #expect(lineCount(content) == LinkPreviewContent.lineLimit)
        #expect(content?.isCut == true)
    }

    @Test func aShortBodyIsNotCut() {
        #expect(note(lines: 3)?.isCut == false)
    }

    /// No board exists here, and the preview still names it: resolving a board walks the whole
    /// vault, and a hover is not worth that walk (ADR-0072 §D7).
    @MainActor @Test func aBoardTargetIsNamedWithoutResolvingIt() async throws {
        let vault = try TemporaryVault()
        try vault.write("Corpo", to: "Altra.md")
        let controller = await LinkFixtures.controller(root: vault.root)

        let content = controller.linkPreviewContent(for: "Q4.canvas", section: nil)
        #expect(content?.kind == .board(name: "Q4"))
        controller.close()
    }
}
