import Foundation
import Testing
@testable import Pergamenum

// PG-292 (#637): ADR-0068 §D15's per-pratica throttle on the pane's appearance.
// `paneAppeared(in:)` runs `syncAll(in:kind: .windowKey)`, so two appearances inside the
// 60-second window sync each pratica once, while a manual refresh is never held back.

@MainActor
@Suite(.serialized) struct PraticaWindowKeyThrottleTests {
    // `trigger(_:kind:eligibility:)` is what `syncAll(in:kind: .windowKey)` runs per pratica
    // (and `paneAppeared(in:)` runs `syncAll`). Driven directly, because `syncAll` ends in
    // `load(from:)`, which on a controller with no vault open resets the vault-scoped state
    // - the pratiche list included - and a second pass would then iterate nothing.
    private static func controller(recording calls: @escaping @MainActor (String) -> Void) -> PraticheController {
        PraticheController(probe: { .granted }, performSync: { path, _ in calls(path) })
    }

    @Test func twoAppearancesInsideTheWindowSyncAPraticaOnce() async {
        var calls: [String] = []
        let controller = Self.controller { calls.append($0) }

        await controller.trigger("P1", kind: .windowKey, eligibility: .automatic)
        await controller.trigger("P1", kind: .windowKey, eligibility: .automatic)

        #expect(calls == ["P1"])
        #expect(controller.watchersByPraticaPath["P1"]?.lastWindowKeySyncAt != nil)
    }

    @Test func theMarkIsPerPraticaSoASecondPraticaStillSyncs() async {
        var calls: [String] = []
        let controller = Self.controller { calls.append($0) }

        await controller.trigger("P1", kind: .windowKey, eligibility: .automatic)
        await controller.trigger("P2", kind: .windowKey, eligibility: .automatic)

        #expect(calls == ["P1", "P2"])
    }

    @Test func aManualRefreshIsNotHeldBackByTheWindowKeyMark() async {
        var calls: [String] = []
        let controller = Self.controller { calls.append($0) }
        await controller.trigger("P1", kind: .windowKey, eligibility: .automatic)

        await controller.trigger("P1", kind: .manualRefresh, eligibility: .automatic)

        #expect(calls == ["P1", "P1"])
    }
}
