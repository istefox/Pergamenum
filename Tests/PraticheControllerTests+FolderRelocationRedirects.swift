import Foundation
import Testing
@testable import Pergamenum

// Split out of `PraticheControllerTests.swift` under PG-293 (#638) to clear its SwiftLint
// `file_length` warning: a pure move, no test changed.

// The same suite as `PraticheControllerTests+FolderRelocation.swift`, in an extension so the
// struct body stays under SwiftLint's `type_body_length`.
extension PraticaLedgerFolderRelocationTests {
    // MARK: - Review round 2: two MINORs in `praticaPathRedirects` itself

    /// MINOR 1: the old `remapKeys` inserted a `praticaPathRedirects` entry for EVERY
    /// relocated key unconditionally, even when nothing was mid-sync/mid-regeneration
    /// for it - and nothing ever pruned an entry nobody was ever going to read. Fixed
    /// by gating the insert on `syncingPraticaPath`/`regeneratingPraticaPaths`: a
    /// relocation with nothing in flight for this pratica must leave no redirect at
    /// all, not just an eventually-pruned one.
    @Test func moveLedgerStateLeavesNoRedirectWhenNothingIsInFlight() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let oldPath = "01 Progetti/Tifone/X"
        let newPath = "Calendar/01 Progetti/Tifone/X"
        controller.updateLedger(.live(nil)) { $0.byPraticaPath[oldPath] = .empty }
        let vault = VaultController()

        controller.moveLedgerState(from: oldPath, to: newPath, in: vault)

        #expect(controller.ledger.byPraticaPath[newPath] != nil, "the remap itself must still happen")
        #expect(
            controller.praticaPathRedirects.isEmpty,
            "nothing was syncing or regenerating this pratica, so the relocation must not leave a redirect entry nothing will ever read"
        )
    }

    /// MINOR 2's exact shape: an ordinary sync AND a "Rigenera…" commit both captured
    /// `oldPath` before the SAME relocation ran - `PraticaLiveSync`'s `SyncRunQueue`
    /// only serializes ordinary syncs against each other, never against a
    /// regeneration for the same pratica. The old `resolveAndConsumePraticaPathRedirect`
    /// destructively removed the entry on its first read, so the first of the two
    /// callers to land would consume it and the second fell through to the stale key,
    /// resurrecting it exactly as before the whole fix. Both must now resolve to the
    /// relocated path, and neither may resurrect `oldPath`.
    @Test func recordSyncOutcomeResolvesForTwoConcurrentInFlightCallersOfTheSamePath() throws {
        let vault = try TemporaryVault()
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let oldPath = "01 Progetti/Tifone/X"
        let newPath = "Calendar/01 Progetti/Tifone/X"
        controller.updateLedger(.live(nil)) { $0.byPraticaPath[oldPath] = .empty }
        // Both callers captured `oldPath` before the relocation below, exactly like
        // `beginSync` (`runExclusive`) and `beginRegeneration` (`prepareRegeneration`)
        // do in production, before either one's own `await`s.
        controller.beginSync(oldPath)
        controller.beginRegeneration(oldPath)
        let vaultController = VaultController()

        controller.followFolderRelocations([MovedNote(old: oldPath, new: newPath)], in: vaultController)
        #expect(controller.ledger.byPraticaPath[oldPath] == nil, "the relocation itself must not leave the old key behind")
        #expect(
            controller.praticaPathRedirects[oldPath] == newPath,
            "with two in-flight callers claiming this path, the relocation must leave a redirect for it (MINOR 1's other side)"
        )

        // The ordinary sync's own outcome lands first, still keyed by the pre-move path.
        controller.recordSyncOutcome(
            PraticaSyncEngine.SyncOutcome(
                writtenFiles: [], importedMessageIDs: ["<a@rossi-spa.it>"],
                noLongerInMail: [], regeneratedPendingFiles: [], cancelled: false, bridge: []
            ),
            for: oldPath, session: session, isCurrentVault: true
        )
        #expect(
            controller.ledger.byPraticaPath[oldPath] == nil,
            "the first of two concurrent callers must not resurrect the old key"
        )
        #expect(controller.ledger.byPraticaPath[newPath]?.importedMessageIDs == ["<a@rossi-spa.it>"])

        // The regeneration's own outcome lands second, carrying the SAME pre-move path -
        // MINOR 2's actual race, since the old code would have already consumed the
        // redirect above and left nothing for this second caller to resolve through.
        controller.recordSyncOutcome(
            PraticaSyncEngine.SyncOutcome(
                writtenFiles: [], importedMessageIDs: ["<b@rossi-spa.it>"],
                noLongerInMail: [], regeneratedPendingFiles: ["<b@rossi-spa.it>"], cancelled: false, bridge: []
            ),
            for: oldPath, session: session, isCurrentVault: true
        )

        #expect(
            controller.ledger.byPraticaPath[oldPath] == nil,
            "the second of two concurrent callers must not resurrect the old key either"
        )
        #expect(
            controller.ledger.byPraticaPath[newPath]?.importedMessageIDs.sorted() == ["<a@rossi-spa.it>", "<b@rossi-spa.it>"],
            "both callers' outcomes must fold into the SAME relocated key"
        )

        // Once both callers actually finish (their own `defer`/completion path in
        // production), the redirect this relocation left is safe to drop - proving the
        // chosen "prune once idle" design, not just that resolution itself is safe.
        controller.endSync()
        #expect(
            controller.praticaPathRedirects[oldPath] != nil,
            "the regeneration is still claimed, so the redirect must not be pruned yet"
        )
        controller.endRegeneration(oldPath)
        #expect(
            controller.praticaPathRedirects.isEmpty,
            "once nothing anywhere is still in flight, the redirect this relocation left must be pruned"
        )
    }

    // MARK: - Round-4 review, §1: `praticaPath(continuing:)`, the one door
    // `PraticaLiveSync+Run.swift`'s `RunContext.livePraticaPath(in:)` goes through -
    // after this, there is no way to spell a pratica path inside that pipeline other
    // than through this resolver.

    @Test func praticaPathContinuingReturnsTheCapturedPathWhenNothingRelocated() throws {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })

        let resolved = try controller.praticaPath(continuing: "01 Progetti/Tifone/X")

        #expect(resolved == "01 Progetti/Tifone/X", "nothing relocated it, so the captured path is still the live one")
    }

    @Test func praticaPathContinuingRefusesAndNamesWhereThePraticaWent() throws {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let oldPath = "01 Progetti/Tifone/X"
        let newPath = "Calendar/01 Progetti/Tifone/X"
        controller.praticaPathRedirects[oldPath] = newPath

        do {
            _ = try controller.praticaPath(continuing: oldPath)
            Issue.record("expected praticaPath(continuing:) to throw .praticaRelocated")
        } catch let stop as PraticaRunStop {
            #expect(stop == .praticaRelocated(from: oldPath, to: newPath))
        } catch {
            Issue.record("expected PraticaRunStop, got \(error)")
        }

        // The two-hop chain: relocated twice before this caller ever asked - the same
        // multi-hop walk `destination(of:)` already does for
        // `recordSyncOutcome`, reused here rather than forked.
        let secondPath = "Calendar/02 Progetti/Tifone/X"
        controller.praticaPathRedirects[newPath] = secondPath

        do {
            _ = try controller.praticaPath(continuing: oldPath)
            Issue.record("expected praticaPath(continuing:) to throw .praticaRelocated across both hops")
        } catch let stop as PraticaRunStop {
            #expect(
                stop == .praticaRelocated(from: oldPath, to: secondPath),
                "the caller must be told where the pratica lives NOW, not the first hop"
            )
        } catch {
            Issue.record("expected PraticaRunStop, got \(error)")
        }
    }

    @Test func praticaPathContinuingIsOnlyMeaningfulWhileARunHoldsItsClaim() throws {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let oldPath = "01 Progetti/Tifone/X"
        let newPath = "Calendar/01 Progetti/Tifone/X"
        controller.updateLedger(.live(nil)) { $0.byPraticaPath[oldPath] = .empty }
        controller.beginSync(oldPath)
        let vault = VaultController()

        controller.followFolderRelocations([MovedNote(old: oldPath, new: newPath)], in: vault)
        #expect(controller.praticaPathRedirects[oldPath] == newPath, "a claimed path in flight must leave a redirect")

        // The claim ends (the run's own `defer { controller.endSync() }`), and with
        // nothing else in flight `pruneRedirectsIfIdle` wipes the whole map - documents
        // why `beginSync`/`endSync` must bracket the WHOLE of `runExclusive`: the
        // resolver is only meaningful while a run still holds its claim.
        controller.endSync()
        #expect(controller.praticaPathRedirects.isEmpty)

        let resolved = try controller.praticaPath(continuing: oldPath)
        #expect(
            resolved == oldPath,
            "once nothing is left to redirect through, the resolver returns its input rather than throwing"
        )
    }
}
