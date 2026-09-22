import Testing
@testable import Pergamenum

// `CategoryEditor.proposedSlug(from:)` and `CategoryEditor.slugProblem(slug:isCreating:)`
// are both static and pure - the two rules a bug report against «Nuova categoria» traced
// back to here: an unfollowed proposal (the first) and an unexplained disabled «Crea»
// (the second).

@Test func proposedSlugFoldsAccentsAndPunctuationToHyphens() {
    #expect(CategoryEditor.proposedSlug(from: "Stampo Nexion") == "stampo-nexion")
    #expect(CategoryEditor.proposedSlug(from: "Città è bella!") == "citta-e-bella")
    #expect(CategoryEditor.proposedSlug(from: "  a---b  ") == "a-b")
}

@Test func proposedSlugFromAllPunctuationIsEmpty() {
    #expect(CategoryEditor.proposedSlug(from: "!!!") == "")
}

@Test func slugProblemIsNilOnlyForAWellFormedSlugWhileCreating() {
    #expect(CategoryEditor.slugProblem(slug: "stampo-nexion", isCreating: true) == nil)
    #expect(CategoryEditor.slugProblem(slug: "", isCreating: true) != nil)
    #expect(CategoryEditor.slugProblem(slug: "Stampo Nexion", isCreating: true) != nil)
    #expect(CategoryEditor.slugProblem(slug: "-x", isCreating: true) != nil)
    #expect(CategoryEditor.slugProblem(slug: "x-", isCreating: true) != nil)
    #expect(CategoryEditor.slugProblem(slug: "a--b", isCreating: true) != nil)
}

@Test func slugProblemIsAlwaysNilWhileEditing() {
    #expect(CategoryEditor.slugProblem(slug: "", isCreating: false) == nil)
    #expect(CategoryEditor.slugProblem(slug: "not valid", isCreating: false) == nil)
}

// `CategoryEditor.isSaveDisabled(name:slug:isCreating:)` (ADR-0053 §D2 seam #9): the
// defect it fixed was «Crea» staying enabled with an empty slug, so an empty name and a
// slug problem both have to disable it on their own, and neither should while editing.

@Test func isSaveDisabledOnAnEmptyNameEvenWithAFineSlug() {
    #expect(CategoryEditor.isSaveDisabled(name: "", slug: "stampo-nexion", isCreating: true))
    #expect(CategoryEditor.isSaveDisabled(name: "   ", slug: "stampo-nexion", isCreating: true))
}

@Test func isSaveDisabledOnASlugProblemEvenWithAName() {
    #expect(CategoryEditor.isSaveDisabled(name: "Stampo Nexion", slug: "", isCreating: true))
    #expect(CategoryEditor.isSaveDisabled(name: "Stampo Nexion", slug: "Not Valid", isCreating: true))
}

@Test func isSaveDisabledIsFalseOnlyWithBothAName() {
    #expect(!CategoryEditor.isSaveDisabled(name: "Stampo Nexion", slug: "stampo-nexion", isCreating: true))
    // While editing the slug field is disabled and already valid, so only the name matters.
    #expect(!CategoryEditor.isSaveDisabled(name: "Stampo Nexion", slug: "not valid", isCreating: false))
    #expect(CategoryEditor.isSaveDisabled(name: "", slug: "not valid", isCreating: false))
}
