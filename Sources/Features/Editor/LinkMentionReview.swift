import Foundation
import Observation

// ADR-0084 §D3 (PG-386, N3 session C).

/// The model behind the «Collega» sheet: the diff the person is shown, and the one guarded write
/// of exactly those bytes.
///
/// The diff is planned when the model is made, so the sheet opens on it. «Collega» writes through
/// the session with the hash of the bytes the diff came from; a note that moved on since is
/// planned again and shown again with a notice, never written blind.
@MainActor
@Observable
final class LinkMentionReview {
    enum State: Equatable {
        case reviewing(diff: String, notice: String?)
        case linked
        case nothingToLink
        case failed(String)
    }

    static let changedNotice = "La nota è cambiata: il confronto è stato aggiornato"

    private(set) var state: State = .nothingToLink
    /// True while the write is in flight, so a second press cannot send a second one.
    private(set) var isConfirming = false

    @ObservationIgnored private let vault: VaultController
    let notePath: String
    let title: String
    /// The hash of the bytes the diff on screen was computed from.
    @ObservationIgnored private var hash: String?

    init(vault: VaultController, notePath: String, title: String) {
        self.vault = vault
        self.notePath = notePath
        self.title = title
        state = plan(notice: nil)
    }

    /// Writes the link the diff showed (ADR-0084 §D3). The answer is acted on as it comes back:
    /// the session re-read after its own `await`, so nothing read here before it is trusted.
    func confirm() async {
        guard case .reviewing = state, let hash, !isConfirming else { return }
        isConfirming = true
        defer { isConfirming = false }
        switch await vault.linkMention(in: notePath, to: title, expecting: hash) {
        case .linked:
            state = .linked
        case .noMention:
            state = .nothingToLink
        case .movedOn:
            state = plan(notice: Self.changedNotice)
        case .failed(let message):
            state = .failed(message)
        }
    }

    /// «Annulla»: the session forgets the plan it remembered for this diff.
    func cancel() {
        vault.session?.forgetLinkMentionPlan(in: notePath, to: title)
    }

    private func plan(notice: String?) -> State {
        guard let session = vault.session else { return .failed("nessun vault aperto") }
        guard let plan = session.planLinkMention(in: notePath, to: title) else {
            hash = nil
            return .nothingToLink
        }
        hash = plan.hash
        let diff = UnifiedDiff.between(plan.before, plan.after, path: notePath) ?? ""
        return .reviewing(diff: diff, notice: notice)
    }
}
