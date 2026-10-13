import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D3 («Collega» writes the link the person was shown), SPEC R-26, plan
// docs/plans/note-workflow-n3.md Task 5.
//
// `LinkMentionReview` is the model behind the «Collega» sheet: it holds the diff on screen and
// confirms with one guarded write of the bytes that diff came from. The session's own refusals
// are pinned in `VaultLinkWritesTests`; what is pinned here is what the sheet's model does with
// each answer. A controller over a temporary vault, no timer, no sleep.

private func note(_ body: String, aliases: [String] = []) -> String {
    let aliasLines = aliases.isEmpty ? "" : "aliases:\n" + aliases.map { "  - \($0)\n" }.joined()
    return "---\ndate: 2026-10-07\ntags:\n  - type-note\n\(aliasLines)---\n\n\(body)\n"
}

private let changedNotice = "La nota è cambiata: il confronto è stato aggiornato"

@MainActor
private func openController(
    _ vault: borrowing TemporaryVault, mentioning body: String, aliases: [String] = []
) async throws -> VaultController {
    try vault.write(note("Corpo.", aliases: aliases), to: "Curva.md")
    try vault.write(note(body), to: "Altra.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

private func onDisk(_ vault: borrowing TemporaryVault, _ path: String) throws -> String {
    try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
}

/// The diff and the notice of a `.reviewing` state, or a recorded issue.
private func reviewing(_ state: LinkMentionReview.State) -> (diff: String, notice: String?)? {
    guard case .reviewing(let diff, let notice) = state else {
        Issue.record("atteso .reviewing, ottenuto \(state)")
        return nil
    }
    return (diff, notice)
}

@MainActor
@Test func anUnchangedNoteIsReviewedWithTheDiffAndConfirmWritesTheLink() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault, mentioning: "Si parla di Curva e di altro.")
    defer { controller.close() }
    let review = LinkMentionReview(vault: controller, notePath: "Altra.md", title: "Curva")

    let shown = try #require(reviewing(review.state))
    #expect(shown.notice == nil)
    #expect(shown.diff.contains("-Si parla di Curva e di altro."))
    #expect(shown.diff.contains("+Si parla di [[Curva]] e di altro."))
    #expect(!(try onDisk(vault, "Altra.md")).contains("[["), "nothing is written before the person confirms")

    await review.confirm()

    #expect(review.state == .linked)
    #expect(try onDisk(vault, "Altra.md").contains("Si parla di [[Curva]] e di altro."))
}

@MainActor
@Test func aNoteWrittenBetweenReviewAndConfirmIsRecomputedWithTheNoticeAndNothingIsWritten() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault, mentioning: "Si parla di Curva e di altro.")
    defer { controller.close() }
    let review = LinkMentionReview(vault: controller, notePath: "Altra.md", title: "Curva")
    let first = try #require(reviewing(review.state))
    let moved = note("Si parla di Curva, e anche di altro ancora.")
    try vault.write(moved, to: "Altra.md")

    await review.confirm()

    let second = try #require(reviewing(review.state))
    #expect(second.notice == changedNotice)
    #expect(second.diff != first.diff, "the diff is the one of the bytes now on disk")
    #expect(second.diff.contains("+Si parla di [[Curva]], e anche di altro ancora."))
    #expect(try onDisk(vault, "Altra.md") == moved, "the bounced confirm wrote nothing")
}

@MainActor
@Test func confirmingTheRecomputedDiffLinksTheNewBytes() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault, mentioning: "Si parla di Curva e di altro.")
    defer { controller.close() }
    let review = LinkMentionReview(vault: controller, notePath: "Altra.md", title: "Curva")
    try vault.write(note("Si parla di Curva, e anche di altro ancora."), to: "Altra.md")
    await review.confirm()
    try #require(reviewing(review.state)?.notice == changedNotice)

    await review.confirm()

    #expect(review.state == .linked)
    let after = try onDisk(vault, "Altra.md")
    #expect(after.contains("Si parla di [[Curva]], e anche di altro ancora."), "the external edit is kept")
}

@MainActor
@Test func aMentionThatWentIsNothingToLinkAndNothingIsWritten() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault, mentioning: "Si parla di Curva e di altro.")
    defer { controller.close() }
    let review = LinkMentionReview(vault: controller, notePath: "Altra.md", title: "Curva")
    let gone = note("Non si parla più di niente.")
    try vault.write(gone, to: "Altra.md")

    await review.confirm()

    #expect(review.state == .nothingToLink)
    #expect(try onDisk(vault, "Altra.md") == gone)
}

@MainActor
@Test func aMentionThatBecameALinkIsNothingToLinkToo() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault, mentioning: "Si parla di Curva e di altro.")
    defer { controller.close() }
    let review = LinkMentionReview(vault: controller, notePath: "Altra.md", title: "Curva")
    try vault.write(note("Si parla di [[Curva]] e di altro."), to: "Altra.md")

    await review.confirm()

    #expect(review.state == .nothingToLink, "a note that already links the title has no unlinked mention")
}

@MainActor
@Test func cancellingTheReviewForgetsThePlanTheSessionRemembered() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault, mentioning: "Si parla di Curva e di altro.")
    defer { controller.close() }
    let review = LinkMentionReview(vault: controller, notePath: "Altra.md", title: "Curva")
    let session = try #require(controller.session)
    try #require(session.shownMentionPlans.count == 1, "the diff on screen is remembered by the session")

    review.cancel()

    #expect(session.shownMentionPlans.isEmpty, "a cancelled diff is forgotten (ADR-0084 §D3)")
    #expect(!(try onDisk(vault, "Altra.md")).contains("[["), "«Annulla» writes nothing")
}

@MainActor
@Test func aSecondConfirmWhileTheFirstIsInFlightDoesNotWriteAgain() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault, mentioning: "Si parla di Curva e di altro.")
    defer { controller.close() }
    let review = LinkMentionReview(vault: controller, notePath: "Altra.md", title: "Curva")
    let first = Task { await review.confirm() }
    // The write suspends on the disk actor, so the first press is observably in flight.
    while !review.isConfirming && review.state != .linked { await Task.yield() }
    try #require(review.isConfirming, "the first confirm must still be in flight for the second press")

    await review.confirm()

    #expect(review.isConfirming, "the second press returned without waiting for a write of its own")
    await first.value
    #expect(review.state == .linked)
    let after = try onDisk(vault, "Altra.md")
    #expect(after.components(separatedBy: "[[Curva]]").count - 1 == 1, "the link is written once")
}

@MainActor
@Test func anAliasMentionShowsTheTitleWithTheMatchedTextAsDisplay() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(
        vault, mentioning: "Il tornante è stretto.", aliases: ["Tornante"]
    )
    defer { controller.close() }
    let review = LinkMentionReview(vault: controller, notePath: "Altra.md", title: "Curva")

    let shown = try #require(reviewing(review.state))
    #expect(shown.diff.contains("+Il [[Curva|tornante]] è stretto."), "`[[tornante]]` alone would dangle")

    await review.confirm()

    #expect(review.state == .linked)
    #expect(try onDisk(vault, "Altra.md").contains("Il [[Curva|tornante]] è stretto."))
}
