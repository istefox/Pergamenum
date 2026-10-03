import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// ADR-0069 (the attachment chip's context menu is an AppKit menu), plan
// docs/plans/pg-285-attachment-chip-context-menu.md, Task 1 - R-01, R-02, R-04.
//
// Which menu a real right-click opens inside a real `List` stays a GUI test
// (`UITests/AttachmentChipContextMenuUITests.swift`): the in-process harness delivers no
// pointer event (`HostedViewSupport.swift`). What is pinned here is everything around it,
// through the production AppKit path: `AttachmentChipMenuView.menu(for:)` called directly with
// a synthesized right-mouse event - the `WikilinkContextMenu` precedent, never `sendEvent`
// (ADR-0053 R-15) - the predicate `hitTest` asks, and the view actually being there, one per
// chip, when the chip and its row are built for real.

@MainActor
@Suite struct AttachmentChipMenuViewTests {
    private static let entries: [AttachmentChipModel.MenuEntry] = [
        .init(command: .preview, title: "Anteprima allegato", isEnabled: true),
        .init(command: .open, title: "Apri", isEnabled: false),
        .init(command: .reveal, title: "Mostra nel Finder", isEnabled: true),
        .init(command: .copy, title: "Copia", isEnabled: true),
    ]

    private static func rightMouseDown() throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    @Test func theMenuCarriesEachEntryInOrderWithItsOwnEnablementAndIdentifier() throws {
        let view = AttachmentChipMenuView(frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        view.entries = { Self.entries }

        let menu = try #require(view.menu(for: try Self.rightMouseDown()))
        #expect(menu.autoenablesItems == false, "enablement comes from the catalogue, not from AppKit")
        #expect(menu.items.map(\.title) == Self.entries.map(\.title))
        #expect(menu.items.map(\.isEnabled) == Self.entries.map(\.isEnabled))
        #expect(menu.items.map { $0.identifier?.rawValue } == Self.entries.map(\.command.identifier))
    }

    @Test func eachItemDeliversExactlyItsOwnCommand() throws {
        var performed: [AttachmentChipModel.Command] = []
        let view = AttachmentChipMenuView(frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        view.entries = { Self.entries }
        view.perform = { performed.append($0) }

        let menu = try #require(view.menu(for: try Self.rightMouseDown()))
        for item in menu.items {
            let action = try #require(item.action)
            let target = try #require(item.target as? NSObject)
            _ = target.perform(action, with: item)
        }
        #expect(performed == Self.entries.map(\.command))
    }

    @Test func entriesAreReadWhenTheMenuOpensNotWhenTheViewIsBuilt() throws {
        var isUsable = false
        let view = AttachmentChipMenuView(frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        view.entries = { [.init(command: .preview, title: "Anteprima allegato", isEnabled: isUsable)] }

        isUsable = true
        let menu = try #require(view.menu(for: try Self.rightMouseDown()))
        #expect(menu.items.map(\.isEnabled) == [true])
    }

    // MARK: - §D2: the overlay claims the context click and nothing else

    @Test(arguments: [
        (NSEvent.EventType.rightMouseDown, NSEvent.ModifierFlags()),
        (NSEvent.EventType.rightMouseDown, NSEvent.ModifierFlags.control),
        (NSEvent.EventType.leftMouseDown, NSEvent.ModifierFlags.control),
        (NSEvent.EventType.leftMouseDown, NSEvent.ModifierFlags([.control, .shift])),
    ])
    func aContextClickIsClaimed(type: NSEvent.EventType, modifierFlags: NSEvent.ModifierFlags) {
        #expect(AttachmentChipMenuView.claimsContextClick(type: type, modifierFlags: modifierFlags))
    }

    @Test(arguments: [
        (NSEvent.EventType.leftMouseDown, NSEvent.ModifierFlags()),
        (NSEvent.EventType.leftMouseDown, NSEvent.ModifierFlags.command),
        (NSEvent.EventType.leftMouseUp, NSEvent.ModifierFlags()),
        (NSEvent.EventType.mouseMoved, NSEvent.ModifierFlags()),
        (NSEvent.EventType.otherMouseDown, NSEvent.ModifierFlags()),
        (NSEvent.EventType.rightMouseUp, NSEvent.ModifierFlags()),
        (NSEvent.EventType.leftMouseDragged, NSEvent.ModifierFlags()),
        (NSEvent.EventType.scrollWheel, NSEvent.ModifierFlags()),
    ])
    func everyOtherEventSeesNoOverlay(type: NSEvent.EventType, modifierFlags: NSEvent.ModifierFlags) {
        #expect(!AttachmentChipMenuView.claimsContextClick(type: type, modifierFlags: modifierFlags))
    }
}

/// The chip and its row built for real (`HostedView`), with the AppKit menu view looked up in the
/// hosting view's own subviews. This is the check that goes red if a SwiftUI `.contextMenu`
/// replaces the AppKit one (ADR-0069 §D6).
@MainActor
@Suite(.serialized)
struct AttachmentChipHostedMenuTests {
    private static func menuViews(in view: NSView) -> [AttachmentChipMenuView] {
        view.subviews.flatMap { subview -> [AttachmentChipMenuView] in
            if let menuView = subview as? AttachmentChipMenuView { return [menuView] }
            return menuViews(in: subview)
        }
    }

    private static func withAttachment(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-attachment-chip-menu-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // `.txt` has no signature in `AttachmentIntegrity`: any non-empty file reads `.usable`.
        let url = root.appending(path: "nota.txt", directoryHint: .notDirectory)
        try Data("contenuto".utf8).write(to: url)
        try await body(url)
    }

    private static func rightMouseDown() throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    @Test func aHostedChipCarriesOneAppKitMenuViewThatAnswersWithTheCatalogue() async throws {
        try await Self.withAttachment { url in
            var previewed: [URL] = []
            let content = AttachmentChip.Content.file(PraticaAttachmentRef(name: "nota.txt", url: url))
            let host = HostedView(
                AttachmentChip(
                    content: content, identifier: "pratiche-attachment-test-0", onQuickLook: { previewed.append($0) }
                )
                .environment(\.theme, .emergency),
                size: CGSize(width: 240, height: 40)
            )
            defer { host.tearDown() }
            await host.settle()

            let found = Self.menuViews(in: host.hosting)
            #expect(found.count == 1)
            let menuView = try #require(found.first)
            let menu = try #require(menuView.menu(for: try Self.rightMouseDown()))
            let expected = AttachmentChipModel.menuEntries(for: content) { _ in .usable }
            #expect(expected.filter { $0.isEnabled }.count == 4, "a usable .txt enables all four entries")
            #expect(menu.items.map(\.title) == expected.map(\.title))
            #expect(menu.items.map(\.isEnabled) == expected.map(\.isEnabled))

            let preview = try #require(menu.items.first {
                $0.identifier?.rawValue == AttachmentChipModel.Command.preview.identifier
            })
            let action = try #require(preview.action)
            _ = (preview.target as? NSObject)?.perform(action, with: preview)
            #expect(previewed == [url], "«Anteprima» hands the file to the timeline's Quick Look")

            #expect(host.neverShown)
            #expect(host.refusals.isEmpty)
        }
    }

    /// R-02's guard: one menu view per chip, each on its chip - never one stretched over the row,
    /// which would take the message menu's right-clicks away.
    @Test func aHostedRowCarriesOneNarrowMenuViewPerChip() async throws {
        try await Self.withAttachment { url in
            let entry = PraticaTimelineEntry(
                id: "email/messaggio.md", kind: .message, date: Date(timeIntervalSince1970: 1_788_000_000),
                direction: .received, senderDisplayName: "Mario Rossi", subject: "Offerta 118",
                bodyPreview: "Buongiorno", hasAttachments: true, messageID: "<row@example.com>", isInMail: true
            )
            let detail = PraticaRowDetail(
                notePath: "email/messaggio.md", body: "", quotedHistory: nil, signature: nil,
                attachments: [PraticaAttachmentRef(name: "nota.txt", url: url)],
                storeReferences: [MessageDocument.StoreReference(
                    name: "grande.zip", size: 400_000_000, storePath: "/Volumes/gone/grande.zip"
                )],
                isPending: false, senderAddress: nil, pendingAttachments: ["attesa.pdf"], linkedNote: nil
            )
            let width: CGFloat = 800
            let host = HostedView(
                PraticaMessageRow(
                    entry: entry, detail: detail, isExpanded: false, onToggle: { _ in }, onQuickLook: { _ in }
                )
                .environment(\.theme, .emergency),
                size: CGSize(width: width, height: 80)
            )
            defer { host.tearDown() }
            await host.settle()

            let found = Self.menuViews(in: host.hosting)
            #expect(found.count == 3)
            for menuView in found {
                #expect(menuView.bounds.width > 0)
                #expect(menuView.bounds.width < width / 2, "the overlay stays on its chip, never over the row")
            }
            #expect(host.neverShown)
            #expect(host.refusals.isEmpty)
        }
    }
}
