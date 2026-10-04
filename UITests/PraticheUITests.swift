import XCTest

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 10 -
// R-18, R-33, R-39; UX-BLUEPRINT's own accessibility-identifier checklist. Every
// assertion below reaches a control by its `accessibilityIdentifier`, never by the
// words on it (CLAUDE.md's own rule, paid for twice already).
//
// Four tests retired here per the UI-suite-replacement census (stage 3, Task 6): the
// pane/list/actions, filter-row, add-note/add-call and wizard-fields checks were all
// existence-of-identifier assertions with no production seam behind them, the same
// shape the census retired throughout this pass. What is left is the one real
// selection-wiring path this pane still needs a window for: a click on a list row
// driving the timeline and its inspector toggle.
//
// PG-298, ADR-0070 (`docs/plans/pg-298-timeline-backspace-exclude.md`, Task 4) added the
// fixture's two message files and the two Backspace tests below - R-01, R-02, R-08. A real
// key delivered to a live `List`'s focus and responder chain is observable nowhere in-process
// (ADR-0070 F10), so this is the only place either is witnessed; `Tests/PraticaDeleteKeyTests
// .swift` pins the pure target rule the key calls into. `UITests/AttachmentChipContextMenuUITests
// .swift` is not touched (R-07).
//
// PG-306 turned most of that plan's hand checks (M1-M10) into assertions on the same two tests,
// so the GUI suite does not grow: the held key (M3), the filter field (M4), a text selection in
// an expanded body (M6), «Annulla» after an exclusion (M7), forward delete and Modifica ▸ Elimina
// (M10). M9 is `AttachmentChipContextMenuUITests`'s own; M5 has no subject, since the inspector
// renders `pratica.md` read-only; the beep and the board's preview (M8) stay by hand.
//
// The fixture builder and the helpers live in `PraticheUITests+Support.swift` (PG-364).
final class PraticheUITests: PergamenumUITestCase {
    /// One conformant pratica, seeded on disk before `launch()`, so the list column
    /// has a row and the timeline/inspector/add-note/add-call surfaces - all gated on
    /// `pratiche.selection != nil` (`PratichePane.swift`'s `content`) - have something
    /// to open. `01 Progetti` is `PraticheSettings.defaultRootFolder`; `Acme` is the
    /// client folder `PraticheController.clientName(ofPraticaFolder:rootFolder:)` reads
    /// off the folder's parent.
    ///
    /// Not `private`, like the two ids below: `PraticheUITests+Support.swift` reads them.
    static let praticaFolder = "01 Progetti/Acme/Offerta 118"
    /// PG-298 fixture messages: one carries a placed attachment (for the Quick Look
    /// preview R-08 needs), one carries none (the row both Backspace tests exclude).
    static let messageWithAttachmentID = "<pg298-attachment@example.com>"
    static let messageWithoutAttachmentID = "<pg298-plain@example.com>"

    override func setUpWithError() throws {
        try super.setUpWithError()
        try makeTemporaryVault(prefix: "PraticheUITest")
        try seedFixturePratica()

        // R-19/ADR §D7: `launchApp()`'s Mail store is a per-test fixture root, never the real
        // `~/Library/Mail`, left empty - `FullDiskAccessProbe.state()` reads `ENOENT` on an
        // empty store as `.granted`, same as it would a real one (`FullDiskAccessProbe.swift`'s
        // own doc comment).
        launchApp()
        waitForMainWindow()
        showPratiche()
    }

    // MARK: - R-18: the pane itself, the list, and the Full Disk Access banner

    func testTheTimelineAndInspectorToggleAreAddressable() throws {
        selectFirstPratica()
        XCTAssertTrue(element("pratiche-timeline").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-inspector-toggle").waitForExistence(timeout: 5))
    }

    // MARK: - PG-298, ADR-0070: Backspace excludes the selected message (R-01, R-02, R-08)

    /// R-01, R-02: Backspace on a collapsed row, then on an expanded one, each runs
    /// «Escludi dalla pratica» on the selected row and no other. PG-306: Backspace edits the
    /// filter field instead (M4), a held key excludes one message only (M3), and Backspace
    /// after selecting a word in an expanded body excludes nothing (M6).
    func testBackspaceExcludesTheSelectedMessageCollapsedAndExpanded() throws {
        selectFirstPratica()

        // M4: the attachment row is selected, so a Backspace that leaked out of the field
        // would have a message to exclude.
        clickTrailingHeaderArea(ofMessage: Self.messageWithAttachmentID)
        let filter = element("pratiche-filter")
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "il campo filtro non è comparso")
        filter.click()
        filter.typeText("zz")
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(filter.value as? String, "z", "Backspace non ha cancellato un carattere del filtro")
        app.typeKey(.delete, modifierFlags: [])
        assertStillInPratica(Self.messageWithAttachmentID, noteFile: "con-allegato.md")

        // M1, M3: three presses on a collapsed row exclude that row and leave the next one.
        clickTrailingHeaderArea(ofMessage: Self.messageWithoutAttachmentID)
        for _ in 0..<3 { app.typeKey(.delete, modifierFlags: []) }
        assertExcluded(Self.messageWithoutAttachmentID, noteFile: "senza-allegato.md")
        assertStillInPratica(Self.messageWithAttachmentID, noteFile: "con-allegato.md")

        let chevron = element("pratiche-message-chevron-\(Self.hash(Self.messageWithAttachmentID))")
        XCTAssertTrue(chevron.waitForExistence(timeout: 5), "lo chevron del messaggio non è comparso")
        chevron.click()

        // M6: a word selected in the expanded body is text, not a message to exclude. The body is
        // found by its `pratiche-message-body-<hash>` identifier, not by its words (PG-265).
        let body = element("pratiche-message-body-\(Self.hash(Self.messageWithAttachmentID))")
        XCTAssertTrue(body.waitForExistence(timeout: 5), "il corpo del messaggio espanso non è comparso")
        body.doubleClick()
        app.typeKey(.delete, modifierFlags: [])
        assertStillInPratica(Self.messageWithAttachmentID, noteFile: "con-allegato.md")

        clickTrailingHeaderArea(ofMessage: Self.messageWithAttachmentID)
        app.typeKey(.delete, modifierFlags: [])
        assertExcluded(Self.messageWithAttachmentID, noteFile: "con-allegato.md")
    }

    /// R-08: keyboard focus survives a Quick Look preview. After a chip click opened the
    /// panel and Esc closed it, a click on a message row followed by Backspace still
    /// excludes that message - the one focus hand-off between the Quick Look host and the
    /// timeline's `List` that no other test observes (ADR-0070 §D5).
    func testBackspaceStillExcludesAfterAQuickLookPreview() throws {
        selectFirstPratica()

        let chip = element("pratiche-attachment-\(Self.hash(Self.messageWithAttachmentID))-0")
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "il chip dell'allegato non è comparso")
        chip.click()
        // The panel's own AX window title is "Quick Look", never the previewed file's name -
        // "nota.txt" is a `StaticText` label drawn inside the panel, not the window's title
        // (confirmed from a captured AX hierarchy on this exact failure).
        let panel = app.windows["Quick Look"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "il pannello Quick Look non è comparso")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(panel.waitForExistence(timeout: 5), "il pannello Quick Look non si è chiuso")

        // PG-307: the focus handed back to the timeline still reopens the last attachment on
        // a bare space, as it did while the host held the keyboard.
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "la barra spaziatrice non ha riaperto il pannello")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(panel.waitForExistence(timeout: 5), "il pannello Quick Look non si è richiuso")

        clickTrailingHeaderArea(ofMessage: Self.messageWithoutAttachmentID)
        app.typeKey(.delete, modifierFlags: [])
        assertExcluded(Self.messageWithoutAttachmentID, noteFile: "senza-allegato.md")

        // PG-306, M7: «Annulla» puts the excluded message back.
        app.typeKey("z", modifierFlags: .command)
        assertRestored(Self.messageWithoutAttachmentID, noteFile: "senza-allegato.md")

        // PG-306, M10: forward delete and Modifica ▸ Elimina take the same route. The menu
        // item is found by its action, `delete:`, never by the words on it.
        clickTrailingHeaderArea(ofMessage: Self.messageWithoutAttachmentID)
        app.typeKey(.forwardDelete, modifierFlags: [])
        assertExcluded(Self.messageWithoutAttachmentID, noteFile: "senza-allegato.md")

        clickTrailingHeaderArea(ofMessage: Self.messageWithAttachmentID)
        app.menuBars.menuItems["delete:"].firstMatch.click()
        assertExcluded(Self.messageWithAttachmentID, noteFile: "con-allegato.md")
    }

    // MARK: - ADR-0076 implementation notes: a double-click opens or closes a row

    /// The timeline `List`'s own `primaryAction` toggles the double-clicked row, on a target the
    /// size of the card rather than the chevron alone. A double-click delivered to a live `List`
    /// reaches nothing in-process (`Tests/HostedViewSupport.swift`), so this is its one witness.
    func testDoubleClickTogglesMessageRow() throws {
        selectFirstPratica()
        let messageID = Self.messageWithoutAttachmentID
        // The expanded body only: the collapsed row's one-line preview carries no identifier.
        let body = element("pratiche-message-body-\(Self.hash(messageID))")
        XCTAssertTrue(waitForChevron(ofMessage: messageID, label: "Espandi"), "la riga non parte compressa")
        XCTAssertFalse(body.exists, "il corpo è visibile con la riga compressa")

        doubleClickTrailingHeaderArea(ofMessage: messageID)
        XCTAssertTrue(body.waitForExistence(timeout: 5), "il doppio clic non ha espanso la riga")
        XCTAssertTrue(waitForChevron(ofMessage: messageID, label: "Comprimi"), "lo chevron non dice «Comprimi»")

        doubleClickTrailingHeaderArea(ofMessage: messageID)
        XCTAssertTrue(
            body.waitForNonExistence(timeout: 5), "il secondo doppio clic non ha compresso la riga"
        )
        XCTAssertTrue(waitForChevron(ofMessage: messageID, label: "Espandi"), "lo chevron non dice «Espandi»")
    }
}
