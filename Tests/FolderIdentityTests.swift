import Testing
@testable import Pergamenum

// PG-050: `FolderName`/`FolderPath` replace bare same-typed `String` pairs at the
// Workspace folder-verb boundary (`WorkspaceFolderActions`, `WorkspaceNameField`, both
// sheets) so a swapped argument no longer compiles silently. This file checks the two
// wrapper types themselves behave correctly - construction, equality, hashing,
// `FolderPath.isEmpty` - not any feature behavior, which is unchanged by this refactor.

@Test func folderNameConstructsFromAStringLiteralAndFromInit() {
    let literal: FolderName = "Nuova"
    let explicit = FolderName("Nuova")

    #expect(literal == explicit)
    #expect(literal.value == "Nuova")
}

@Test func folderPathConstructsFromAStringLiteralAndFromInit() {
    let literal: FolderPath = "01 Progetti"
    let explicit = FolderPath("01 Progetti")

    #expect(literal == explicit)
    #expect(literal.value == "01 Progetti")
}

@Test func folderNameIsEquatableAndHashableOnValue() {
    #expect(FolderName("a") == FolderName("a"))
    #expect(FolderName("a") != FolderName("b"))
    #expect(Set([FolderName("a"), FolderName("a"), FolderName("b")]).count == 2)
}

@Test func folderPathIsEquatableAndHashableOnValue() {
    #expect(FolderPath("a") == FolderPath("a"))
    #expect(FolderPath("a") != FolderPath("b"))
    #expect(Set([FolderPath("a"), FolderPath("a"), FolderPath("b")]).count == 2)
}

@Test func folderPathIsEmptyOnlyForTheVaultRoot() {
    #expect(FolderPath("").isEmpty)
    #expect(!FolderPath("01 Progetti").isEmpty)
}
