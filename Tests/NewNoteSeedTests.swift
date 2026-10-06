import Testing
@testable import Pergamenum

// Which folder Cmd+N points the composer at, from what the Note pane's tree has selected
// (n1-seams R-11). The tree's selection ids are vault-relative paths: a folder's own path, or a
// note's `.md` path.

private let folders: Set<String> = ["Progetti", "Progetti/Alfa", "Archivio"]

@Test func aSelectedFolderIsTheSeed() { // (n1-seams R-11)
    #expect(NewNoteSeed.folder(forSelection: ["Progetti/Alfa"], knownFolders: folders) == "Progetti/Alfa")
}

@Test func aTopLevelFolderIsTheSeedToo() { // (n1-seams R-11)
    #expect(NewNoteSeed.folder(forSelection: ["Archivio"], knownFolders: folders) == "Archivio")
}

@Test func aSelectedNoteSeedsItsFolder() { // (n1-seams R-11)
    #expect(
        NewNoteSeed.folder(forSelection: ["Progetti/Alfa/Nota.md"], knownFolders: folders)
            == "Progetti/Alfa"
    )
}

@Test func aNoteAtTheVaultRootSeedsTheRoot() { // (n1-seams R-11)
    #expect(NewNoteSeed.folder(forSelection: ["Nota.md"], knownFolders: folders) == "")
}

@Test func anEmptySelectionSeedsTheRoot() { // (n1-seams R-11)
    #expect(NewNoteSeed.folder(forSelection: [], knownFolders: folders) == "")
}

@Test func twoSelectedItemsSeedTheRoot() { // (n1-seams R-11)
    #expect(
        NewNoteSeed.folder(forSelection: ["Progetti/Alfa", "Archivio"], knownFolders: folders) == ""
    )
    #expect(
        NewNoteSeed.folder(forSelection: ["Progetti/Alfa/Nota.md", "Nota.md"], knownFolders: folders) == ""
    )
}

@Test func anIdThatIsNeitherAKnownFolderNorANoteSeedsTheRoot() { // (n1-seams R-11)
    // The plan says «an unknown id» without a path; this is the one with no parent, which cannot
    // be read two ways. «Progetti/Fantasma» (a parent that is known) is left to the coder.
    #expect(NewNoteSeed.folder(forSelection: ["Fantasma"], knownFolders: folders) == "")
}

@Test func aSelectedNoteWhoseFolderIsUnknownSeedsTheRoot() { // (n1-seams R-11)
    // A selection left over from another vault: its parent is no folder of this one, so Cmd+N must
    // not seed it (createNote would build `Progetti/Fantasma` here).
    #expect(NewNoteSeed.folder(forSelection: ["Progetti/Fantasma/Nota.md"], knownFolders: folders) == "")
    #expect(NewNoteSeed.folder(forSelection: ["Progetti/Alfa/Nota.md"], knownFolders: []) == "")
}

@Test func aSelectedFolderWithNoNoteIsTheSeedOnceItIsKnown() { // (n1-seams R-11)
    // A folder just created, or holding only PDFs or boards: no note path names it, so only the
    // tree's own disk list (the caller's `knownFolders`) can say it is a folder.
    let known = folders.union(["Vuota", "Progetti/Senza note"])
    #expect(NewNoteSeed.folder(forSelection: ["Vuota"], knownFolders: known) == "Vuota")
    #expect(
        NewNoteSeed.folder(forSelection: ["Progetti/Senza note"], knownFolders: known)
            == "Progetti/Senza note"
    )
}

@Test func aDottedEmptyFolderIsTheSeedNotItsParent() { // (n1-seams R-11)
    // `2026.10` has a path extension, so it reads as a file unless it is a known folder.
    let known = folders.union(["Progetti/2026.10"])
    #expect(
        NewNoteSeed.folder(forSelection: ["Progetti/2026.10"], knownFolders: known)
            == "Progetti/2026.10"
    )
    // Unknown, the same id is a file: it seeds its parent.
    #expect(NewNoteSeed.folder(forSelection: ["Progetti/2026.10"], knownFolders: folders) == "Progetti")
}

@Test func theSeedIsStableWhateverTheKnownFoldersHoldBeyondTheSelection() { // (n1-seams R-11)
    #expect(NewNoteSeed.folder(forSelection: ["Progetti/Alfa"], knownFolders: []) == "")
    #expect(
        NewNoteSeed.folder(forSelection: ["Progetti/Alfa"], knownFolders: ["Progetti/Alfa"])
            == "Progetti/Alfa"
    )
}
