import AppKit
import CoreGraphics
import CryptoKit
import Testing
@testable import Pergamenum

// ADR-0020 Task 2: the grammar, clamping and geometry of `CanvasCrop`, tested as the pure
// value type it is - no controller, no canvas document, no disk. `Tests/CanvasCropProbeTests`
// is the aspect-fidelity gate this depends on; `Tests/CanvasTests.swift` and
// `Tests/CanvasCropTests` (MARK: - Task 7, added later) cover the round-trip and
// non-destructiveness halves.
@Suite struct CanvasCropTests {
    // MARK: Parse / format round trip

    @Test func aWellFormedValueParsesAndReformatsToTheSameFourDecimals() {
        let crop = CanvasCrop.parse("0.1200 0.0800 0.5500 0.6000")
        #expect(crop == CanvasCrop(x: 0.12, y: 0.08, width: 0.55, height: 0.6))
        #expect(crop?.formatted == "0.1200 0.0800 0.5500 0.6000")
    }

    @Test func formattingAlwaysProducesFourSpaceSeparatedDecimals() {
        let crop = CanvasCrop(x: 0, y: 0, width: 1, height: 1)
        #expect(crop.formatted == "0.0000 0.0000 1.0000 1.0000")
    }

    // MARK: Malformed and out-of-range input is rejected, not corrected

    @Test func aStringWithTheWrongNumberOfPartsIsRejected() {
        #expect(CanvasCrop.parse("0.1 0.2 0.3") == nil)
        #expect(CanvasCrop.parse("0.1 0.2 0.3 0.4 0.5") == nil)
    }

    @Test func nonNumericPartsAreRejectedWithoutThrowing() {
        #expect(CanvasCrop.parse("banana 0.2 0.3 0.4") == nil)
        #expect(CanvasCrop.parse("") == nil)
    }

    @Test func negativeOriginOrNonPositiveSizeIsRejected() {
        #expect(CanvasCrop.parse("-0.1 0.2 0.3 0.4") == nil)
        #expect(CanvasCrop.parse("0.1 -0.2 0.3 0.4") == nil)
        #expect(CanvasCrop.parse("0.1 0.2 0 0.4") == nil)
        #expect(CanvasCrop.parse("0.1 0.2 0.3 0") == nil)
    }

    @Test func aRectangleReachingPastTheUnitSquareIsRejected() {
        #expect(CanvasCrop.parse("0.8 0.1 0.5 0.2") == nil)
        #expect(CanvasCrop.parse("0.1 0.9 0.2 0.5") == nil)
    }

    @Test func aRectangleExactlyFillingTheUnitSquareIsAccepted() {
        #expect(CanvasCrop.parse("0 0 1 1") != nil)
    }

    // MARK: The 2% floor

    @Test func clampingRaisesAWidthOrHeightBelowTheMinimumFraction() {
        let tooNarrow = CanvasCrop(x: 0.5, y: 0.5, width: 0.001, height: 0.3)
        let clamped = tooNarrow.clamped
        #expect(clamped.width == CanvasCrop.minimumFraction)
        #expect(clamped.height == 0.3)
    }

    @Test func clampingKeepsTheRectangleInsideTheUnitSquareWhenItStartsPastTheFarEdge() {
        let overflowing = CanvasCrop(x: 0.95, y: 0.95, width: 0.3, height: 0.3)
        let clamped = overflowing.clamped
        #expect(clamped.x + clamped.width <= 1.0001)
        #expect(clamped.y + clamped.height <= 1.0001)
        #expect(clamped.width >= CanvasCrop.minimumFraction)
        #expect(clamped.height >= CanvasCrop.minimumFraction)
    }

    @Test func clampingLeavesAnAlreadyValidRectangleUnchanged() {
        let valid = CanvasCrop(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        #expect(valid.clamped == valid)
    }

    // MARK: isWhole (D6's no-op-removal rule)

    @Test func theFullUnitSquareIsWhole() {
        #expect(CanvasCrop(x: 0, y: 0, width: 1, height: 1).isWhole)
    }

    @Test func aValueOneEpsilonInsideTheFullSquareIsStillWhole() {
        let epsilon = CanvasCrop.wholeEpsilon * 0.5
        let almostWhole = CanvasCrop(x: epsilon, y: epsilon, width: 1 - epsilon, height: 1 - epsilon)
        #expect(almostWhole.isWhole)
    }

    @Test func aValueClearlyCroppedIsNotWhole() {
        #expect(!CanvasCrop(x: 0.1, y: 0.1, width: 0.5, height: 0.5).isWhole)
    }

    // MARK: Point-space conversion

    @Test func rectInDrawnSizeAndNormalizedAreInverses() {
        let crop = CanvasCrop(x: 0.25, y: 0.1, width: 0.5, height: 0.6)
        let drawnSize = CGSize(width: 800, height: 400)
        let pointRect = crop.rect(in: drawnSize)
        let roundTripped = CanvasCrop.normalized(pointRect, in: drawnSize)
        #expect(abs(roundTripped.x - crop.x) < 0.0001)
        #expect(abs(roundTripped.y - crop.y) < 0.0001)
        #expect(abs(roundTripped.width - crop.width) < 0.0001)
        #expect(abs(roundTripped.height - crop.height) < 0.0001)
    }

    // MARK: isCroppable (D8)

    @Test func rasterImageExtensionsAreCroppable() {
        for path in ["foto.png", "foto.jpg", "foto.jpeg", "foto.heic", "foto.gif", "FOTO.PNG"] {
            #expect(CanvasCrop.isCroppable(path: path), "\(path) should be croppable")
        }
    }

    @Test func svgPdfAndOtherExtensionsAreNotCroppable() {
        for path in ["disegno.svg", "documento.pdf", "nota.md", "email.eml"] {
            #expect(!CanvasCrop.isCroppable(path: path), "\(path) should not be croppable")
        }
    }
}

// MARK: - Task 7: non-destructiveness and round-trip (principle 1, principle 4, SPEC §6.2)

@MainActor
@Suite struct CanvasCropRoundTripTests {
    private static func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-crop-roundtrip-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A real PNG on disk - the file the SHA-256 check below reads, the same way
    /// `EmbedResolutionTests.writeImage` writes one for the embed renderer.
    private static func writeImage(named name: String, in root: URL) throws -> URL {
        let image = NSImage(size: CGSize(width: 40, height: 30))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 40, height: 30)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        let url = root.appending(path: name, directoryHint: .notDirectory)
        try png.write(to: url)
        return url
    }

    private static func sha256(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    /// SPEC's "crop non distruttivo" made literal: the source image's own bytes never
    /// change, through a crop and through removing it again.
    @Test func theSourceFileIsNeverTouchedByACropOrByRemovingOne() throws {
        let root = try Self.makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = try Self.writeImage(named: "foto.png", in: root)
        let beforeCrop = try Self.sha256(of: imageURL)

        let controller = WorkspaceController()
        controller.attach(to: CanvasStore(root: root))
        let id = controller.placeFile("foto.png", at: .zero)
        controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
        controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
        controller.endCrop(confirm: true)
        controller.flushPendingSave()
        #expect(try Self.sha256(of: imageURL) == beforeCrop)

        controller.removeCrop(nodeIDs: [id])
        controller.flushPendingSave()
        #expect(try Self.sha256(of: imageURL) == beforeCrop)
        controller.detach()
    }

    @Test func aCropSurvivesSaveAndLoadWithEveryOtherPropertyUnchanged() throws {
        let root = try Self.makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try Self.writeImage(named: "foto.png", in: root)
        let store = CanvasStore(root: root)
        let controller = WorkspaceController()
        controller.attach(to: store)
        // ADR-0025 §D4: `attach` opens nothing, so the root board must be created and
        // opened explicitly before the controller has anywhere to write to.
        let board = try store.createBoard(named: root.lastPathComponent, in: "")
        controller.open(board: board)
        let id = controller.placeFile("foto.png", at: CGPoint(x: 30, y: 40))
        controller.setColor(.preset(4), forNodeIDs: [id])

        controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
        controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
        controller.endCrop(confirm: true)
        let croppedNode = try #require(controller.document.node(id: id))
        let expectedCrop = try #require(CanvasCrop.read(from: croppedNode))
        controller.flushPendingSave()
        controller.detach()

        // Addressed by its own path (ADR-0025 §D1): the root board is the `.canvas`
        // named after the vault, which is the path the controller opened.
        let reloaded = try store.load(board: "\(root.lastPathComponent).canvas")
        let node = try #require(reloaded.node(id: id))
        #expect(CanvasCrop.read(from: node) == expectedCrop)
        #expect(node.x == 30)
        #expect(node.y == 40)
        #expect(node.width == 260)
        #expect(node.height == 180)
        #expect(node.color == .preset(4))
        #expect(node.kind == .file(path: "foto.png", subpath: nil))
    }

    @Test func aForeignKeySurvivesACropAndItsRemoval() throws {
        let canvas = """
        {"nodes":[{"id":"a","type":"file","x":0,"y":0,"width":260,"height":180,
                   "file":"foto.png","someOtherApp.flag":true}],"edges":[]}
        """
        let root = try Self.makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try Self.writeImage(named: "foto.png", in: root)
        let store = CanvasStore(root: root)
        try store.save(
            try CanvasDocument(data: Data(canvas.utf8)), board: "\(root.lastPathComponent).canvas"
        )

        let controller = WorkspaceController()
        controller.attach(to: store)
        // ADR-0025 §D4: `attach` opens nothing, so the board just saved above must be
        // opened explicitly before `controller.document` reflects its contents.
        controller.open(board: "\(root.lastPathComponent).canvas")
        controller.beginCrop(nodeID: "a", drawnSize: CGSize(width: 800, height: 400))
        controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
        controller.endCrop(confirm: true)
        var node = try #require(controller.document.node(id: "a"))
        #expect(CanvasCrop.read(from: node) != nil)
        #expect(node.unknown["someOtherApp.flag"] == .bool(true))

        controller.removeCrop(nodeIDs: ["a"])
        node = try #require(controller.document.node(id: "a"))
        #expect(CanvasCrop.read(from: node) == nil)
        #expect(node.unknown["someOtherApp.flag"] == .bool(true))
        controller.detach()
    }

    /// The Obsidian corruption class named in ADR-0020's Context: a non-scalar custom
    /// property on a file node is what broke a canvas in v1.6.5. Asserted here as the
    /// raw JSON type after encoding, not just as `JSONValue.string(_:)` on this app's own
    /// side of the round trip.
    @Test func theEncodedCropValueIsAJSONStringNeverAnObjectOrAList() throws {
        let root = try Self.makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try Self.writeImage(named: "foto.png", in: root)
        let controller = WorkspaceController()
        controller.attach(to: CanvasStore(root: root))
        let id = controller.placeFile("foto.png", at: .zero)
        controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
        controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
        controller.endCrop(confirm: true)

        let encoded = try controller.document.encoded()
        let written = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let node = (written?["nodes"] as? [[String: Any]])?.first { $0["id"] as? String == id }
        #expect(node?["pergamenum-crop"] is String)
        controller.detach()
    }
}
