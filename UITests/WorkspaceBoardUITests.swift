import XCTest

/// The board's pointer behaviour (SPEC §6.3 and §6.5), driven with real drags.
///
/// These three defects were all invisible to the unit suite and to reading the code:
/// a grip too small to hit, a tool wired to nothing, and a container that swallowed
/// every click inside it. All three are hit testing and gesture priority, which exist
/// only once SwiftUI has laid the views out.
///
/// Every card exposes an accessibility element whose frame is exactly the card's
/// rectangle on screen, so the tests anchor on that rather than computing the board's
/// pan and zoom. What each gesture did is then read back off the `.canvas` file,
/// which is the app's own record of the change and cannot be satisfied by a view that
/// merely looks right.
final class WorkspaceBoardUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var boardFile: URL!
    private var app: XCUIApplication!

    // Board coordinates of the fixture, mirrored here so a test can say what it
    // expects in the same units the file uses.
    private let cardA = CGRect(x: 0, y: 0, width: 240, height: 140)

    override func setUpWithError() throws {
        continueAfterFailure = false
        try makeVault()

        // Nothing is snapshotted or restored here. `-recentVaults` below lands in the
        // argument domain, and `RecentVaults.remember` refuses to persist a list that
        // arrived that way, so this run cannot reach the user's own recents at all.
        // A guard on this side could not have worked: the XCUITest runner is sandboxed
        // and its `UserDefaults(suiteName:)` is a private copy in its own container.

        app = XCUIApplication()
        // NSUserDefaults reads the argument domain, so the app reopens this vault at
        // launch without any test-only code inside the app itself.
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        mailStoreRoot = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-mailstore", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: mailStoreRoot, withIntermediateDirectories: true)
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-mailStoreRoot", mailStoreRoot.path(percentEncoded: false),
                               "-disablePlaud", "YES",
                               "-disableUpdater", "YES",
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
        try openWorkspace()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    // MARK: 1. A corner grip can be grabbed and resizes the card

    func testACornerGripResizesTheCard() throws {
        let card = try element(labelled: "CARD A")
        card.click()

        // The grip is centred on the corner, so half of it lies outside the card:
        // this is the exact point that could not be hit before.
        let corner = card.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
        corner.press(
            forDuration: 0.4,
            thenDragTo: corner.withOffset(CGVector(dx: 160, dy: 90))
        )

        let node = try waitForNode("aaaa000000000001") { $0.width > self.cardA.width + 100 }
        XCTAssertGreaterThan(node.width, cardA.width + 100, "la card non è stata allargata")
        XCTAssertGreaterThan(node.height, cardA.height + 50, "la card non è stata allungata")
        // The grip moves the far edges only: the origin stays put.
        XCTAssertEqual(node.x, cardA.minX, accuracy: 2)
        XCTAssertEqual(node.y, cardA.minY, accuracy: 2)
    }

    /// The same grip, with the board zoomed out. This is the regression: the grip
    /// used to be sized in board units, so at a small zoom it was two points across
    /// and the pointer could not land on it.
    func testACornerGripCanStillBeGrabbedWhenZoomedOut() throws {
        zoomOutBelowPlaceholder()

        // Below `BoardGeometry.placeholderZoom` the card draws no Text at all (perf:
        // see `BoardContentLayer.cardBody`), so it can no longer be found by its label.
        let card = try element(nodeID: "aaaa000000000001")
        card.click()
        let corner = card.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
        corner.press(
            forDuration: 0.4,
            thenDragTo: corner.withOffset(CGVector(dx: 60, dy: 40))
        )

        let node = try waitForNode("aaaa000000000001") { $0.width > self.cardA.width + 20 }
        XCTAssertGreaterThan(node.width, cardA.width + 20, "grip non afferrabile da zoomata")
    }

    /// PG-041: below `BoardGeometry.placeholderZoom` the card draws no Text, but its
    /// accessibility label must still say what the card holds.
    func testAZoomedOutCardStillHasAReadableAccessibilityLabel() throws {
        zoomOutBelowPlaceholder()
        // Proves the test actually reached the placeholder branch it names, rather than
        // passing trivially because the card still rendered its own Text (PG-108).
        XCTAssertFalse(app.staticTexts["CARD A"].exists, "il ramo placeholder non è stato raggiunto")
        let card = try element(nodeID: "aaaa000000000001")
        XCTAssertEqual(card.label, "CARD A", "la card senza testo non ha una label accessibile")
    }

    // MARK: 2. The Freccia tool draws an edge

    func testTheArrowToolConnectsTwoCards() throws {
        let from = try element(labelled: "CARD A")
        let to = try element(labelled: "CARD B")

        app.typeKey("a", modifierFlags: [])
        from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.4,
                thenDragTo: to.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            )

        let edges = try waitForEdges { $0.count == 1 }
        XCTAssertEqual(edges.first?["fromNode"] as? String, "aaaa000000000001")
        XCTAssertEqual(edges.first?["toNode"] as? String, "bbbb000000000002")

        // The cards themselves must not have moved: with the arrow tool the drag
        // draws a connector, it does not carry the card along with it.
        let node = try node("aaaa000000000001")
        XCTAssertEqual(node.x, cardA.minX, accuracy: 2)
        XCTAssertEqual(node.y, cardA.minY, accuracy: 2)
    }

    // MARK: 3. A group is dragged by its frame, not by its middle

    func testDraggingTheMiddleOfAGroupLeavesItWhereItIs() throws {
        let group = try element(labelled: "GRUPPO")
        // Well inside the middle and clear of the card the group holds.
        let middle = group.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        middle.press(
            forDuration: 0.4,
            thenDragTo: middle.withOffset(CGVector(dx: 150, dy: 90))
        )

        // Past the autosave delay before looking, or this test passes on a board that
        // did move and simply had not been written yet - which is what it did against
        // the unfixed code, silently.
        settle()
        let moved = try node("gggg000000000003")
        XCTAssertEqual(moved.x, 0, accuracy: 2, "il gruppo si è trascinato dal centro")
        XCTAssertEqual(moved.y, 320, accuracy: 2, "il gruppo si è trascinato dal centro")
    }

    func testAGroupStillMovesWhenDraggedByItsFrameAndCarriesWhatItHolds() throws {
        let group = try element(labelled: "GRUPPO")
        // On the left band of the frame, which is the only part that answers.
        let band = group.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 4, dy: 0))
        band.press(
            forDuration: 0.4,
            thenDragTo: band.withOffset(CGVector(dx: 200, dy: 0))
        )

        let moved = try waitForNode("gggg000000000003") { $0.x > 100 }
        XCTAssertGreaterThan(moved.x, 100, "il gruppo non si muove nemmeno dalla cornice")
        // Moving a group moves what it holds (SPEC §6.5).
        let inside = try node("cccc000000000004")
        XCTAssertGreaterThan(inside.x, 400, "la card dentro il gruppo è rimasta indietro")
    }

    func testACardInsideAGroupCanBeSelected() throws {
        let inside = try element(labelled: "CARD C dentro il gruppo")
        inside.click()

        // Selected means grips, and grips mean the card grew when one is dragged.
        // Asserting on the outcome rather than on a highlight keeps this test about
        // behaviour: a selection the pointer cannot act on is not a selection.
        let corner = inside.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
        corner.press(
            forDuration: 0.4,
            thenDragTo: corner.withOffset(CGVector(dx: 120, dy: 70))
        )

        let node = try waitForNode("cccc000000000004") { $0.width > 320 }
        XCTAssertGreaterThan(node.width, 320, "la card dentro il gruppo non è raggiungibile")
    }

    // MARK: Fixture and helpers

    private func makeVault() throws {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "BoardUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // One `.canvas` in the vault root, named after the vault only because this fixture
        // writes it that way: no rule derives a board from a folder's name any more
        // (ADR-0025 §D1 deleted `CanvasStore.boardPath(forFolder:)`), and no board opens at
        // launch - `openWorkspace()` below clicks its row, which is what this file has
        // actually done since ADR-0024 made `attach` load-not-select.
        let board = root.appending(path: "\(root.lastPathComponent).canvas")
        try Self.fixture.write(to: board, atomically: true, encoding: .utf8)
        vault = root
        boardFile = board
    }

    private static let fixture = """
    {
      "nodes": [
        { "id": "aaaa000000000001", "type": "text", "text": "CARD A",
          "x": 0, "y": 0, "width": 240, "height": 140, "color": "3" },
        { "id": "bbbb000000000002", "type": "text", "text": "CARD B",
          "x": 700, "y": 0, "width": 240, "height": 140, "color": "5" },
        { "id": "gggg000000000003", "type": "group", "label": "GRUPPO",
          "x": 0, "y": 320, "width": 900, "height": 460 },
        { "id": "cccc000000000004", "type": "text", "text": "CARD C dentro il gruppo",
          "x": 320, "y": 470, "width": 260, "height": 150, "color": "4" }
      ],
      "edges": []
    }
    """

    /// Brings the Workspace pane up, whichever pane the app happened to open on,
    /// then explicitly selects the vault's root board. Since ADR-0024 (and 5041d5c
    /// before it) no board opens on its own - the pane lands on the browser/tree and
    /// a row must be clicked, so this can no longer assume `CARD A` appears for free.
    private func openWorkspace() throws {
        let board = app.staticTexts["CARD A"]
        if board.waitForExistence(timeout: 5) { return }

        for candidate in [app.buttons["Workspace"], app.staticTexts["Workspace"], app.cells["Workspace"]]
        where candidate.exists {
            candidate.click()
            break
        }

        let rootBoardID = "workspace-board-\(vault.lastPathComponent).canvas"
        let row = app.descendants(matching: .any).matching(identifier: rootBoardID).firstMatch
        if row.waitForExistence(timeout: 10) {
            row.click()
        }

        XCTAssertTrue(board.waitForExistence(timeout: 10), "la board non si è aperta")
    }

    /// Every card draws an accessibility element the size of the card itself, which
    /// is what lets a test aim at a corner without knowing the pan and the zoom.
    private func element(labelled label: String) throws -> XCUIElement {
        let element = app.staticTexts[label]
        XCTAssertTrue(element.waitForExistence(timeout: 10), "elemento «\(label)» assente")
        return element
    }

    /// Same as `element(labelled:)`, anchored on the card's `accessibilityIdentifier`
    /// instead of its visible label - the only lookup that still works once the card
    /// is below `BoardGeometry.placeholderZoom` and draws no Text.
    private func element(nodeID: String) throws -> XCUIElement {
        let element = app.descendants(matching: .any)
            .matching(identifier: "canvas-node-\(nodeID)").firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "elemento con id «\(nodeID)» assente")
        return element
    }

    // Coordinates are always taken from an element, never from the application:
    // `XCUIApplication.frame` is (inf, inf, 0, 0) on macOS, so anchoring on it puts
    // every drag at a NaN offset and nothing moves - which reads exactly like the
    // defect under test still being there.

    /// Clicks «riduci» until the board is below `BoardGeometry.placeholderZoom`, whatever
    /// zoom `zoomToFit` picked for this window (PG-108: `times: 6` only worked when the
    /// window happened to be wide enough that `zoomToFit` landed near 1.0). Fails loudly
    /// instead of the old helper's silent `guard … return` - that silence is how this
    /// regression hid.
    @discardableResult
    private func zoomOutBelowPlaceholder(cap: Int = 24) -> Int {
        let minus = app.buttons["board-zoom-out"]
        let readout = app.buttons["board-zoom-level"]
        XCTAssertTrue(minus.waitForExistence(timeout: 10), "il controllo dello zoom non è sulla board")
        XCTAssertTrue(readout.waitForExistence(timeout: 5), "manca la percentuale dello zoom")

        var lastPercent = -1
        for click in 0..<cap {
            guard let percent = Int(readout.value as? String ?? "") else {
                XCTFail("la percentuale dello zoom non è leggibile: \(String(describing: readout.value))")
                return click
            }
            // `Int(zoom * 100)` truncates, so a displayed value below 25 guarantees
            // zoom < 0.25 - the same boundary `BoardGeometry.drawsPlaceholder(at:)` uses.
            if percent < 25 { return click }
            if percent == lastPercent {
                XCTFail("lo zoom è fermo a \(percent)% dopo \(click) click - il pulsante non risponde")
                return click
            }
            lastPercent = percent
            minus.click()
        }
        XCTFail("lo zoom non è sceso sotto il 25% in \(cap) click (fermo a \(lastPercent)%)")
        return cap
    }

    // MARK: Reading the result off disk

    private struct Node {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    /// Waits past the board's autosave delay, for the tests that assert something did
    /// *not* happen. A negative assertion read too early is satisfied by a file that
    /// simply has not been written yet.
    private func settle() {
        Thread.sleep(forTimeInterval: 3)
    }

    private func document() throws -> [String: Any] {
        let data = try Data(contentsOf: boardFile)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw XCTSkip("board illeggibile")
        }
        return object
    }

    private func node(_ id: String) throws -> Node {
        let nodes = try document()["nodes"] as? [[String: Any]] ?? []
        guard let raw = nodes.first(where: { $0["id"] as? String == id }) else {
            XCTFail("nodo \(id) assente dal file")
            return Node(x: 0, y: 0, width: 0, height: 0)
        }
        return Node(
            x: raw["x"] as? CGFloat ?? 0,
            y: raw["y"] as? CGFloat ?? 0,
            width: raw["width"] as? CGFloat ?? 0,
            height: raw["height"] as? CGFloat ?? 0
        )
    }

    /// Polls the file until the change lands. The board autosaves a second after a
    /// gesture ends, so reading once would race it.
    private func waitForNode(
        _ id: String,
        timeout: TimeInterval = 6,
        until predicate: (Node) -> Bool
    ) throws -> Node {
        let deadline = Date().addingTimeInterval(timeout)
        var last = try node(id)
        while Date() < deadline {
            last = try node(id)
            if predicate(last) { return last }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return last
    }

    private func waitForEdges(
        timeout: TimeInterval = 6,
        until predicate: ([[String: Any]]) -> Bool
    ) throws -> [[String: Any]] {
        let deadline = Date().addingTimeInterval(timeout)
        var last: [[String: Any]] = []
        while Date() < deadline {
            last = try document()["edges"] as? [[String: Any]] ?? []
            if predicate(last) { return last }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return last
    }
}
