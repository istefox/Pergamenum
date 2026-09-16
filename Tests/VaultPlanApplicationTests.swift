import Foundation
import Testing
@testable import Pergamenum

// MARK: - Task 5 (R-03): `VaultPlanApplication.apply`, the one loop meant to replace six
//
// Drives the coder's refactor (ADR-0041 §D4/§D5): `VaultPlanApplication.apply` is currently a
// stub that ignores its `changes` argument (see `Sources/Core/Vault/VaultPlanApplication.swift`),
// so every assertion below that checks a real change was applied is expected to be RED until the
// coder fills in the loop. The failure-string format (`"\(change.path): \(error)"`) is fixed by
// the six existing copies this loop replaces and must match them character for character, since
// no caller's own assertion is meant to change when it switches over.

private struct WriterFailure: Error, CustomStringConvertible {
    var description: String { "scrittura fallita" }
}

@Test func applyingAnEmptyChangeListYieldsAnEmptyOutcome() {
    let outcome = VaultPlanApplication.apply([]) { _ in }
    #expect(outcome == VaultPlanApplication.Outcome())
}

@Test func applyingThreeSucceedingChangesRewritesAllThreeInOrderWithNoFailures() {
    var written: [String] = []
    let changes = [
        VaultFileChange(path: "A.md", before: "a", after: "A"),
        VaultFileChange(path: "B.md", before: "b", after: "B"),
        VaultFileChange(path: "C.md", before: "c", after: "C"),
    ]

    let outcome = VaultPlanApplication.apply(changes) { change in
        written.append(change.path)
    }

    #expect(outcome.rewrittenPaths == ["A.md", "B.md", "C.md"])
    #expect(outcome.failures.isEmpty)
    // The writer really did run for each change, not just the outcome's bookkeeping.
    #expect(written == ["A.md", "B.md", "C.md"])
}

@Test func aThrowingMiddleChangeIsRecordedAsAFailureAndTheThirdIsStillAttempted() {
    var attempted: [String] = []
    let changes = [
        VaultFileChange(path: "A.md", before: "a", after: "A"),
        VaultFileChange(path: "B.md", before: "b", after: "B"),
        VaultFileChange(path: "C.md", before: "c", after: "C"),
    ]

    let outcome = VaultPlanApplication.apply(changes) { change in
        attempted.append(change.path)
        if change.path == "B.md" { throw WriterFailure() }
    }

    // The middle change failed and is absent from `rewrittenPaths`; the other two still
    // succeeded, and crucially C was attempted even though B threw (this is the shape R-06,
    // Task 7, leans on).
    #expect(outcome.rewrittenPaths == ["A.md", "C.md"])
    #expect(outcome.failures == ["B.md: scrittura fallita"])
    #expect(attempted == ["A.md", "B.md", "C.md"])
}

@Test func theFailureStringFormatMatchesTheSixExistingCopiesCharacterForCharacter() {
    let changes = [VaultFileChange(path: "01 Progetti/Nota.md", before: "x", after: "y")]

    let outcome = VaultPlanApplication.apply(changes) { _ in throw WriterFailure() }

    // `"\(change.path): \(error)"` - the exact interpolation every one of the six originals
    // uses (`NoteFileOperations.swift:247`, `FolderFileOperations.swift:322,330`,
    // `BoardFileOperations.swift:164,174,288`), not a rephrased or localized message.
    #expect(outcome.failures == ["01 Progetti/Nota.md: scrittura fallita"])
}

@Test func multipleFailuresArePreservedInEncounterOrder() {
    let changes = [
        VaultFileChange(path: "A.md", before: "a", after: "A"),
        VaultFileChange(path: "B.md", before: "b", after: "B"),
    ]

    let outcome = VaultPlanApplication.apply(changes) { _ in throw WriterFailure() }

    #expect(outcome.rewrittenPaths.isEmpty)
    #expect(outcome.failures == ["A.md: scrittura fallita", "B.md: scrittura fallita"])
}

// MARK: - Task 1 (R-01, R-02, R-04, R-08): a `VaultWriteRefusal` is its own channel
//
// `VaultWriteRefusal` (`Sources/Core/Vault/VaultWriteRefusal.swift`) is the type both loops
// below classify apart from an ordinary `failures` entry (ADR-0046 §D4).

@Test func aRefusalPutsTheBarePathInRefusalsAndNothingElsewhere() {
    let changes = [VaultFileChange(path: "Stale.md", before: "a", after: "A")]

    let outcome = VaultPlanApplication.apply(changes) { _ in throw VaultWriteRefusal.movedOn("Stale.md") }

    #expect(outcome.refusals == ["Stale.md"])
    #expect(outcome.failures.isEmpty)
    #expect(outcome.rewrittenPaths.isEmpty)
}

@Test func theChangeAfterARefusalIsStillAttempted() {
    var attempted: [String] = []
    let changes = [
        VaultFileChange(path: "A.md", before: "a", after: "A"),
        VaultFileChange(path: "Stale.md", before: "b", after: "B"),
        VaultFileChange(path: "C.md", before: "c", after: "C"),
    ]

    let outcome = VaultPlanApplication.apply(changes) { change in
        attempted.append(change.path)
        if change.path == "Stale.md" { throw VaultWriteRefusal.movedOn("Stale.md") }
    }

    #expect(outcome.rewrittenPaths == ["A.md", "C.md"])
    #expect(outcome.refusals == ["Stale.md"])
    #expect(attempted == ["A.md", "Stale.md", "C.md"])
}

@Test func aRefusalAndADiskFailureLandInTheirOwnCollectionsInEncounterOrder() {
    let changes = [
        VaultFileChange(path: "Stale.md", before: "a", after: "A"),
        VaultFileChange(path: "Broken.md", before: "b", after: "B"),
        VaultFileChange(path: "Fine.md", before: "c", after: "C"),
    ]

    let outcome = VaultPlanApplication.apply(changes) { change in
        switch change.path {
        case "Stale.md": throw VaultWriteRefusal.movedOn("Stale.md")
        case "Broken.md": throw WriterFailure()
        default: break
        }
    }

    #expect(outcome.rewrittenPaths == ["Fine.md"])
    #expect(outcome.refusals == ["Stale.md"])
    #expect(outcome.failures == ["Broken.md: scrittura fallita"])
}

@Test func theDefaultedOutcomeStillCompilesAndCompares() {
    #expect(VaultPlanApplication.Outcome() == VaultPlanApplication.Outcome(rewrittenPaths: [], failures: []))
}

@Test func theAsynchronousOverloadClassifiesARefusalIdentically() async {
    var attempted: [String] = []
    let changes = [
        VaultFileChange(path: "A.md", before: "a", after: "A"),
        VaultFileChange(path: "Stale.md", before: "b", after: "B"),
        VaultFileChange(path: "Broken.md", before: "c", after: "C"),
    ]

    let outcome = await VaultPlanApplication.apply(changes) { change in
        attempted.append(change.path)
        switch change.path {
        case "Stale.md": throw VaultWriteRefusal.movedOn("Stale.md")
        case "Broken.md": throw WriterFailure()
        default: break
        }
    }

    #expect(outcome.rewrittenPaths == ["A.md"])
    #expect(outcome.refusals == ["Stale.md"])
    #expect(outcome.failures == ["Broken.md: scrittura fallita"])
    #expect(attempted == ["A.md", "Stale.md", "Broken.md"])
}
