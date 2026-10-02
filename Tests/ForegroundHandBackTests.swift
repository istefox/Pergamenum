import Foundation
import Testing
@testable import Pergamenum

// PG-132: SPEC §9's "capture must not raise the app" was described by
// `PergamenumRoute.raisesApp` and consulted by nothing. The decision of whether a batch of
// links hands the foreground back is pure and pinned here; the activation itself goes
// through AppKit's cooperative `activate(from:options:)` and is checked by hand.

private func route(_ string: String) -> PergamenumRoute {
    guard let url = URL(string: string), let route = PergamenumRoute(url) else {
        Issue.record("\(string) is not a route")
        return .today
    }
    return route
}

@Test func aBatchMadeOnlyOfCapturesHandsTheForegroundBack() {
    let routes = [route("pergamenum://capture?text=uno"), route("pergamenum://capture?text=due")]
    #expect(ForegroundHandBack.handsBackActivation(after: routes))
}

@Test func aBatchWithALinkThePersonWantsToLookAtKeepsTheApp() {
    let routes = [route("pergamenum://capture?text=uno"), route("pergamenum://today")]
    #expect(!ForegroundHandBack.handsBackActivation(after: routes))
}

@Test func anEmptyBatchHandsNothingBack() {
    #expect(!ForegroundHandBack.handsBackActivation(after: []))
}

@Test func onlyTheCaptureRouteDeclinesToRaiseTheApp() {
    // The rule `handsBackActivation` rests on, pinned beside it so a new route case that
    // should not raise the app is added here, not inferred.
    #expect(!route("pergamenum://capture?text=uno").raisesApp)
    for raising in ["pergamenum://today", "pergamenum://search?q=a", "pergamenum://note?file=A.md"] {
        #expect(route(raising).raisesApp, "\(raising)")
    }
}
