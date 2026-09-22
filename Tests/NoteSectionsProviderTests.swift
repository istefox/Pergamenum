import AppKit
import Testing
@testable import Pergamenum

/// The real `[[Nota#` heading provider, exercised through the production door.
///
/// The census found no test of this (ui-suite-replacement plan §2 row 2): the three
/// `CompletionPanelTests` `noteSections` stubs and `EditorCompletionTests:189`'s
/// `headings(of:)` all hand `CompletingTextView.noteSections` a literal closure written
/// by the test, never `NoteTextView.wire(_:to:)`'s own (`NoteTextView.swift:259-265`) -
/// `coordinator.parent.transclusions?.resolve(reference)` then `NoteOutline.entries`
/// filtered to `.heading`, mapped to `entry.title`. A bug in that wiring - the wrong
/// `transclusions` read, a filter that let an embed row through - would have shipped
/// green through every one of those. This drives the real closure `wire` installs,
/// the same way `Tests/NoteListEditingTests.swift`'s fixture drives a real Return key
/// through the same method rather than a copy of it.
@MainActor
@Test func theRealNoteSectionsProviderResolvesTheTargetNoteAndListsOnlyItsHeadings() {
    let target = """
    # Prove in laboratorio

    Testo qui, non un titolo.

    ## Campioni

    ![[foto.png]]

    ### Durezza
    """
    let source = TransclusionSource(resolve: { reference in
        guard reference == "Prove" else { return nil }
        return TransclusionSource.Resolved(title: "Prove", relativePath: "Prove.md", text: target)
    })
    var view = NoteTextView(
        text: .constant(""), theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: true, onFollowLink: { _ in }
    )
    view.transclusions = source
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(usingTextLayoutManager: true)
    view.wire(textView, to: coordinator)

    // Headings only, in document order - the embedded picture between the second and
    // third heading is `NoteOutline`'s own `.embed` kind and must not appear.
    #expect(textView.noteSections?("Prove") == ["Prove in laboratorio", "Campioni", "Durezza"])
    // A reference the source cannot resolve answers empty, matching the production
    // `guard let resolved = ... else { return [] }` for a note that does not exist.
    #expect(textView.noteSections?("Sconosciuta") == [])
}
