import Testing
@testable import Pergamenum

// ADR-0073 §D10, plan Task 6 (R-14): a dirty note is «Non salvato», never «Salvataggio…» -
// nothing is saving a note until somebody saves it.

@Test func aDirtyNoteReadsNonSalvato() {
    let indicator = NoteSaveIndicator(hasUnsavedChanges: true)

    #expect(indicator.label == "Non salvato")
    #expect(indicator.symbol == "arrow.triangle.2.circlepath")
}

@Test func aCleanNoteReadsSalvato() {
    let indicator = NoteSaveIndicator(hasUnsavedChanges: false)

    #expect(indicator.label == "Salvato")
    #expect(indicator.symbol == "checkmark.circle")
}
