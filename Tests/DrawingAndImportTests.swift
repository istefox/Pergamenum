import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// MARK: - Drawing SVG

private let sampleDrawing = Drawing(strokes: [
    Drawing.Stroke(id: "s1", points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 25), CGPoint(x: 70, y: 10)],
                   color: "#9A5B1F", width: 3, opacity: 1),
    Drawing.Stroke(id: "s2", points: [CGPoint(x: 20, y: 60), CGPoint(x: 90, y: 60)],
                   color: "#FBF0C4", width: 12, opacity: 0.4),
])

@Test func roundTripsADrawingThroughSVG() throws {
    // SPEC §6.2 requires a stroke to stay editable, so the SVG is parsed back rather
    // than treated as a write-only export.
    let decoded = try #require(DrawingSVG.decode(DrawingSVG.encode(sampleDrawing)))
    // Required rather than expected: indexing into an empty array below would abort
    // the whole test run instead of reporting one failure.
    try #require(decoded.strokes.count == 2)

    #expect(decoded.strokes[0].id == "s1")
    #expect(decoded.strokes[0].points == sampleDrawing.strokes[0].points)
    #expect(decoded.strokes[0].color == "#9A5B1F")
    #expect(decoded.strokes[0].width == 3)
    #expect(decoded.strokes[1].opacity == 0.4)
}

@Test func writesAViewBoxCoveringTheStrokes() {
    let svg = DrawingSVG.encode(sampleDrawing)
    #expect(svg.contains("<svg"))
    #expect(svg.contains("viewBox="))
    // Self-contained: an SVG whose content sits outside its viewBox renders empty in
    // most viewers, including Obsidian's.
    let bounds = sampleDrawing.bounds
    #expect(bounds.minX <= 10)
    #expect(bounds.maxX >= 90)
    #expect(bounds.minY <= 10)
    #expect(bounds.maxY >= 60)
}

@Test func padsTheBoundsByHalfTheWidestStroke() {
    // A thick line centred on the edge would be clipped in half without this.
    let thick = Drawing(strokes: [
        Drawing.Stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)], color: "#000000", width: 20),
    ])
    #expect(thick.bounds.minX <= -10)
}

@Test func refusesAnSVGItDidNotWrite() {
    // An imported illustration is an image; offering to edit its paths as pen strokes
    // would mangle it.
    let foreign = """
    <?xml version="1.0"?>
    <svg xmlns="http://www.w3.org/2000/svg"><path d="M 0 0 L 10 10" stroke="#000"/></svg>
    """
    #expect(DrawingSVG.decode(foreign) == nil)
}

@Test func handlesAnEmptyDrawing() {
    let svg = DrawingSVG.encode(.empty)
    #expect(DrawingSVG.decode(svg)?.strokes.isEmpty == true)
    #expect(Drawing.empty.bounds == .zero)
}

@Test func parsesPathDataAndIgnoresStrayCommands() {
    #expect(DrawingSVG.parsePathData("M 10 20 L 30 40") == [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40)])
    // A dangling coordinate must not become a point with a missing axis.
    #expect(DrawingSVG.parsePathData("M 10 20 L 30") == [CGPoint(x: 10, y: 20)])
    #expect(DrawingSVG.parsePathData("").isEmpty)
}

@Test func namesDrawingsAsTheSpecPrescribes() {
    let date = CalendarDate(iso: "2026-08-11")!
    #expect(DrawingSVG.fileName(for: date, sequence: 1) == "disegno-20260811-001.svg")
    #expect(DrawingSVG.fileName(for: date, sequence: 42) == "disegno-20260811-042.svg")
}

// MARK: - Import naming

@Test func buildsTheEmailFileNameOfNamingMd() {
    let name = ImportNaming.emailFileName(
        date: CalendarDate(iso: "2026-08-04")!,
        counterparty: "Rossi Impianti Srl",
        subject: "Richiesta offerta supporti antivibranti"
    )
    #expect(name == "20260804_RossiImpianti_Email_richiesta-offerta-supporti-antivibranti.eml")
}

@Test(arguments: [
    ("Rossi Impianti Srl", "RossiImpianti"),
    ("Acme S.p.A.", "Acme"),
    ("Società Metalmeccanica", "SocietaMetalmeccanica"),
    ("Müller GmbH", "Muller"),
    ("", "Sconosciuto"),
])
func canonicalisesTheCounterparty(_ testCase: (raw: String, expected: String)) {
    // naming.md N-07: legal form dropped when it is a separate word, accents folded,
    // spaces and punctuation removed, capitals kept.
    #expect(ImportNaming.canonicalCounterparty(testCase.raw) == testCase.expected)
}

@Test func doesNotDropALegalFormThatIsPartOfTheName() {
    // "Sacchi" contains "sa" but is not a legal form; only whole words are dropped.
    #expect(ImportNaming.canonicalCounterparty("Sacchi Antivibranti") == "SacchiAntivibranti")
}

@Test func kebabCasesASubjectAndCapsItsLength() {
    #expect(ImportNaming.kebabCase("Richiesta offerta") == "richiesta-offerta")
    #expect(ImportNaming.kebabCase("Trasmissibilità: dati!") == "trasmissibilita-dati")
    #expect(ImportNaming.kebabCase("una due tre quattro cinque sei sette otto")
        == "una-due-tre-quattro-cinque-sei")
    #expect(ImportNaming.kebabCase("").isEmpty)
}

@Test func proposesTheNameFromTheMessageHeaders() {
    let headers = EmailHeaderParser.parse("""
    Date: Tue, 4 Aug 2026 09:15:00 +0200
    From: Niccolò Rossi <n.rossi@rossimpianti.test>
    Subject: Richiesta offerta

    corpo
    """)
    let proposed = ImportNaming.proposedEmailFileName(
        headers: headers, currentFileName: "messaggio.eml", today: .today
    )
    #expect(proposed == "20260804_NiccoloRossi_Email_richiesta-offerta.eml")
}

@Test func fallsBackToTheDomainWhenThereIsNoSenderName() {
    let headers = EmailHeaderParser.parse("Date: Tue, 4 Aug 2026 09:15:00 +0200\nFrom: <a@rossimpianti.test>\nSubject: x\n\ny")
    let proposed = ImportNaming.proposedEmailFileName(
        headers: headers, currentFileName: "m.eml", today: .today
    )
    #expect(proposed.contains("_rossimpiantitest_") || proposed.contains("_Rossimpiantitest_"))
}

@Test func avoidsOverwritingAnExistingImport() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-import-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let name = "20260804_Rossi_Email_offerta.eml"
    #expect(ImportNaming.uniqueFileName(name, in: directory) == name)

    try Data("x".utf8).write(to: directory.appending(path: name))
    // Two messages from the same sender on the same day about the same subject is an
    // ordinary occurrence, not a reason to destroy the first one.
    #expect(ImportNaming.uniqueFileName(name, in: directory) == "20260804_Rossi_Email_offerta-2.eml")
}

// MARK: - Drawing on a board

private struct DrawingRoot: ~Copyable {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-draw-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

@MainActor
@Test func writesADrawingAsAnSVGAndPlacesItsCard() throws {
    let root = try DrawingRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    controller.beginStroke(at: CGPoint(x: 10, y: 10), color: "#9A5B1F", width: 3, opacity: 1)
    controller.extendStroke(to: CGPoint(x: 60, y: 40))
    let id = try #require(controller.commitDrawing(date: CalendarDate(iso: "2026-08-11")!))

    let node = try #require(controller.document.node(id: id))
    guard case .file(let path, _) = node.kind else {
        Issue.record("il disegno non ha prodotto un nodo file")
        return
    }
    #expect(path == "disegno-20260811-001.svg")
    #expect(FileManager.default.fileExists(
        atPath: root.url.appending(path: path).path(percentEncoded: false)
    ))
    // The buffer is cleared, so the next stroke starts a new drawing.
    #expect(controller.activeDrawing.strokes.isEmpty)
    controller.detach()
}

@MainActor
@Test func reopensItsOwnDrawingForEditingWithoutDuplicatingTheCard() throws {
    let root = try DrawingRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    controller.beginStroke(at: .zero, color: "#000000", width: 2, opacity: 1)
    controller.extendStroke(to: CGPoint(x: 50, y: 50))
    let id = try #require(controller.commitDrawing(date: CalendarDate(iso: "2026-08-11")!))

    #expect(controller.editDrawing(nodeID: id))
    #expect(controller.activeDrawing.strokes.count == 1)

    controller.beginStroke(at: CGPoint(x: 0, y: 60), color: "#000000", width: 2, opacity: 1)
    controller.extendStroke(to: CGPoint(x: 50, y: 60))
    #expect(controller.commitDrawing(date: CalendarDate(iso: "2026-08-11")!) == id)

    // Editing ink must not leave the old card beside the new one.
    #expect(controller.document.nodes.count == 1)
    let text = try String(contentsOf: root.url.appending(path: "disegno-20260811-001.svg"), encoding: .utf8)
    #expect(DrawingSVG.decode(text)?.strokes.count == 2)
    controller.detach()
}

@MainActor
@Test func refusesToEditAnSVGItDidNotWrite() throws {
    let root = try DrawingRoot()
    try Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M 0 0\"/></svg>".utf8)
        .write(to: root.url.appending(path: "importato.svg"))

    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    let id = controller.placeFile("importato.svg", at: .zero)

    #expect(!controller.editDrawing(nodeID: id))
    #expect(controller.activeDrawing.strokes.isEmpty)
    controller.detach()
}

@MainActor
@Test func erasesOnlyTheStrokesUnderThePointer() throws {
    let root = try DrawingRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    controller.beginStroke(at: CGPoint(x: 0, y: 0), color: "#000000", width: 2, opacity: 1)
    controller.extendStroke(to: CGPoint(x: 10, y: 0))
    controller.beginStroke(at: CGPoint(x: 200, y: 200), color: "#000000", width: 2, opacity: 1)
    controller.extendStroke(to: CGPoint(x: 210, y: 200))

    controller.eraseStrokes(near: CGPoint(x: 5, y: 2), radius: 8)
    #expect(controller.activeDrawing.strokes.count == 1)
    #expect(controller.activeDrawing.strokes[0].points[0] == CGPoint(x: 200, y: 200))
    controller.detach()
}

@MainActor
@Test func numbersDrawingsSequentiallyInAFolder() throws {
    let root = try DrawingRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    let date = CalendarDate(iso: "2026-08-11")!

    for _ in 0..<3 {
        controller.beginStroke(at: .zero, color: "#000000", width: 2, opacity: 1)
        controller.extendStroke(to: CGPoint(x: 10, y: 10))
        _ = controller.commitDrawing(date: date)
    }
    let names = controller.document.nodes.compactMap { node -> String? in
        if case .file(let path, _) = node.kind { return path } else { return nil }
    }
    #expect(Set(names) == ["disegno-20260811-001.svg", "disegno-20260811-002.svg", "disegno-20260811-003.svg"])
    controller.detach()
}

// MARK: - Import

@MainActor
@Test func proposesTheAssistedNameForAnImportedMessage() throws {
    let root = try DrawingRoot()
    let source = FileManager.default.temporaryDirectory
        .appending(path: "scaricato-\(UUID().uuidString).eml")
    try Data("""
    Date: Tue, 4 Aug 2026 09:15:00 +0200
    From: Rossi Impianti Srl <info@rossimpianti.test>
    Subject: Richiesta offerta

    corpo
    """.utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }

    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    let proposals = controller.importFiles([source], at: .zero)
    #expect(proposals.count == 1)
    #expect(proposals[0].proposedName == "20260804_RossiImpianti_Email_richiesta-offerta.eml")

    // Nothing is copied until the proposal is confirmed.
    #expect(!FileManager.default.fileExists(
        atPath: root.url.appending(path: proposals[0].proposedName).path(percentEncoded: false)
    ))

    _ = controller.commitImport(proposals[0])
    #expect(FileManager.default.fileExists(
        atPath: root.url.appending(path: proposals[0].proposedName).path(percentEncoded: false)
    ))
    // Copied, not moved: the source may live outside the vault.
    #expect(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
    controller.detach()
}

@MainActor
@Test func keepsTheNameOfANonEmailImport() throws {
    let root = try DrawingRoot()
    let source = FileManager.default.temporaryDirectory
        .appending(path: "schema-\(UUID().uuidString).png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }

    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    let proposals = controller.importFiles([source], at: .zero)
    #expect(proposals[0].proposedName == source.lastPathComponent)
    controller.detach()
}

@MainActor
@Test func cascadesSeveralFilesImportedAtOnce() throws {
    let root = try DrawingRoot()
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-src-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    var sources: [URL] = []
    for index in 0..<3 {
        let url = directory.appending(path: "file\(index).png")
        try Data([0x89]).write(to: url)
        sources.append(url)
    }

    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    let proposals = controller.importFiles(sources, at: CGPoint(x: 100, y: 100))

    // Dropped together, they must not land exactly on top of each other.
    #expect(Set(proposals.map(\.point.x)).count == 3)
    controller.detach()
}
