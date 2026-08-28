import Foundation
import Testing
@testable import Pergamenum

// `Navigation.revealFolder(_:)` (2026-08-28, Note-pane breadcrumb parity chain): the same
// "a click is a click" contract `OutlineJump` already carries (Navigation.swift:166-180) - two
// requests for the same folder are still two events, because `NoteListPane`'s `.onChange` only
// fires on a value that actually changed.

@MainActor
@Test func revealFolderStartsAtOneAndCarriesTheFolderAsked() {
    let navigation = Navigation()
    #expect(navigation.folderReveal == nil)

    navigation.revealFolder("01 Progetti")

    #expect(navigation.folderReveal?.id == 1)
    #expect(navigation.folderReveal?.folder == "01 Progetti")
}

@MainActor
@Test func revealingTheSameFolderTwiceProducesTwoDistinctEvents() {
    let navigation = Navigation()

    navigation.revealFolder("01 Progetti")
    let first = navigation.folderReveal

    navigation.revealFolder("01 Progetti")
    let second = navigation.folderReveal

    #expect(first?.folder == second?.folder)
    #expect(first?.id != second?.id)
}

@MainActor
@Test func revealingTheRootIsAnEmptyFolderNotANilEvent() {
    let navigation = Navigation()

    navigation.revealFolder("")

    #expect(navigation.folderReveal?.folder == "")
    #expect(navigation.folderReveal != nil)
}
