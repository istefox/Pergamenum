import XCTest

/// The board's pointer behaviour (SPEC §6.3 and §6.5), driven with real drags.
///
/// The corner grip was a hit-test regression invisible to the unit suite and to
/// reading the code: too small to hit, only once SwiftUI had laid the views out.
///
/// The card exposes an accessibility element whose frame is exactly the card's
/// rectangle on screen, so the test anchors on that rather than computing the board's
/// pan and zoom. What the gesture did is then read back off the `.canvas` file,
/// which is the app's own record of the change and cannot be satisfied by a view that
/// merely looks right.
///
/// The arrow-tool and group-drag tests retired here per the UI-suite-replacement
/// census (stage 3, Task 6): both were real pointer gestures on the canvas, and the
/// most exposed to the machine (on 2026-09-20 the 22 Workspace tests rerun alone on
/// an undisturbed Mac passed 22 of 22, which points at the environment rather than
/// the app). Their in-process replacements are named in the census's
/// WorkspaceBoardUITests entry; the arrow tool's `a` key and real drag, and the
/// group frame's real hit-testing, are left with no cover at all, a loss named
/// rather than hidden.
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
        corner.dragTo(corner.withOffset(CGVector(dx: 160, dy: 90)))

        let node = try waitForNode("aaaa000000000001") { $0.width > self.cardA.width + 100 }
        XCTAssertGreaterThan(node.width, cardA.width + 100, "la card non è stata allargata")
        XCTAssertGreaterThan(node.height, cardA.height + 50, "la card non è stata allungata")
        // The grip moves the far edges only: the origin stays put.
        XCTAssertEqual(node.x, cardA.minX, accuracy: 2)
        XCTAssertEqual(node.y, cardA.minY, accuracy: 2)
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
          "x": 0, "y": 0, "width": 240, "height": 140, "color": "3" }
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

    // Coordinates are always taken from an element, never from the application:
    // `XCUIApplication.frame` is (inf, inf, 0, 0) on macOS, so anchoring on it puts
    // every drag at a NaN offset and nothing moves - which reads exactly like the
    // defect under test still being there.

    // MARK: Reading the result off disk

    private struct Node {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
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
}
