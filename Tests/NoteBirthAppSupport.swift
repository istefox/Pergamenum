import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Pergamenum

// PG-387 (N4), plan docs/plans/pg-387-n4-birth-of-note.md, Task 4: what the app-layer behaviour
// suites of the note's birth share (ADR-0051: one helper, not seven copies). It builds on the
// Contenitore harness, which already owns a temporary state base, an isolated `ContenitoreController`
// and the app's `CommandActions` wiring, and adds the environment a hosted view of this feature
// is given. Nothing here shows a window or sends an event.

/// A capture: a note born without a topic, carrying `status-inbox`.
func captureNote(_ body: String = "Pensiero.", date: String = "2026-10-01") -> String {
    "---\ndate: \(date)\ntags:\n  - type-note\n  - status-inbox\n---\n\n\(body)\n"
}

/// A note that is already classified.
func classifiedNote(_ body: String = "Corpo.", date: String = "2026-10-01") -> String {
    "---\ndate: \(date)\ntags:\n  - type-note\n  - topic-x\n---\n\n\(body)\n"
}

@MainActor
struct NoteBirthApp {
    let harness: ContenitoreHarness
    let actions: CommandActions
    let shortcuts: ShortcutStore

    var vault: VaultController { harness.vault }
    var navigation: Navigation { harness.navigation }
    var contenitore: ContenitoreController { harness.contenitore }

    static func make(_ vault: borrowing TemporaryVault) async throws -> NoteBirthApp {
        let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
        let name = "NoteBirthApp-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return NoteBirthApp(
            harness: harness,
            actions: harness.commandActions(),
            shortcuts: ShortcutStore(defaults: defaults, isOverridden: false)
        )
    }

    /// `view` built for real in a window that is never shown, with the environment the app gives
    /// every pane.
    func hosted<V: View>(_ view: V, size: CGSize) -> HostedView<some View> {
        HostedView(
            view
                .environment(\.theme, .emergency)
                .environment(vault)
                .environment(navigation)
                .environment(contenitore)
                .environment(actions)
                .environment(shortcuts),
            size: size
        )
    }
}

/// Every `NSTableView` under `view`, with its frame in `view`'s coordinates.
@MainActor
func tables(under view: NSView) -> [(table: NSTableView, frame: CGRect)] {
    func collect(_ subview: NSView) -> [NSTableView] {
        ((subview as? NSTableView).map { [$0] } ?? []) + subview.subviews.flatMap(collect)
    }
    return collect(view).map { ($0, $0.convert($0.bounds, to: view)) }
}
