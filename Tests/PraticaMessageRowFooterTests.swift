import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// ADR-0076 implementation notes (PR #761): the message footer closes the row in both states,
// collapsed as well as expanded, so its verbs are reachable without opening the message first.
//
// The in-process accessibility tree is one childless group (`HostedViewSupport.swift`), so the
// footer's identifier cannot be looked up here. What can be read is the row's fitting height:
// a collapsed row given the pane's command runner against the same row with nothing to draw in
// the footer (`actions: nil` and no Mail link, which is `footer`'s empty branch). The footer is
// one line of caption-sized verbs, so the first must be taller by at least one caption line, and
// the two are the same height if `footer` moves back inside `expanded`.
//
// `.serialized`: each test builds its own window and reads `NSApp` state around it
// (`HostedViewPrototypeTests`' reason).
@MainActor
@Suite(.serialized)
struct PraticaMessageRowFooterTests {
    /// About a received lane's width in a timeline beside the list column.
    private static let width: CGFloat = 640

    /// Not in Mail, so `subjectLink` has no URL and `footer` without actions draws nothing.
    private static let entry = PraticaTimelineEntry(
        id: "email/messaggio.md", kind: .message, date: Date(timeIntervalSince1970: 1_788_000_000),
        direction: .received, senderDisplayName: "Mario Rossi", subject: "Offerta 118",
        bodyPreview: "Buongiorno", hasAttachments: false, messageID: "<footer@example.com>", isInMail: false
    )

    private static let detail = PraticaRowDetail(
        notePath: "email/messaggio.md", body: "Buongiorno", quotedHistory: nil, signature: nil,
        attachments: [], storeReferences: [], isPending: false, senderAddress: nil,
        pendingAttachments: [], linkedNote: nil
    )

    /// The fitting height of `content` laid out at `width`, in a window never shown.
    private func fittingHeight(of content: some View) async -> CGFloat {
        let host = HostedView(
            content.frame(width: Self.width).environment(\.theme, .emergency),
            size: CGSize(width: Self.width, height: 240)
        )
        defer { host.tearDown() }
        await host.settle()
        #expect(host.neverShown)
        #expect(host.refusals.isEmpty)
        return host.hosting.fittingSize.height
    }

    private func collapsedRowHeight(actions: PraticaCommandActions?) async -> CGFloat {
        await fittingHeight(of: PraticaMessageRow(
            entry: Self.entry, detail: Self.detail, isExpanded: false,
            onToggle: { _ in }, onQuickLook: { _ in }, actions: actions
        ))
    }

    @Test func aCollapsedRowWithActionsDrawsTheFooter() async throws {
        let vault = try TemporaryVault()
        let root = vault.root
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let actions = PraticaCommandActions(pratiche: pratiche, vault: controller, navigation: Navigation())
        #expect(!actions.commands(for: Self.detail).isEmpty, "the footer has verbs to draw")

        let captionLine = await fittingHeight(of: Text("Apri in Mail").themedText(.caption))
        let withoutFooter = await collapsedRowHeight(actions: nil)
        let withFooter = await collapsedRowHeight(actions: actions)

        #expect(captionLine > 0)
        #expect(withoutFooter > 0)
        #expect(
            withFooter - withoutFooter >= captionLine,
            "collapsed row: \(withFooter)pt with actions, \(withoutFooter)pt without, caption line \(captionLine)pt"
        )
    }
}
