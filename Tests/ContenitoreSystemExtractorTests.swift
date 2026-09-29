import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Pergamenum

// ADR-0071 (Contenitore) §D8, plan docs/plans/contenitore.md, Task 5 - R-09, with the real
// frameworks: every fixture is drawn by the test itself with CoreText, so nothing depends on a
// file checked into the repository.

private let phrase = "Preventivo fornitura guarnizioni"

private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-extractor-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func line(_ text: String, size: CGFloat) -> CTLine {
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
}

/// A one-page PDF whose text is real text, so it has a text layer.
private func textPDF(at url: URL) throws {
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    context.textPosition = CGPoint(x: 72, y: 700)
    CTLineDraw(line(phrase, size: 18), context)
    context.endPDFPage()
    context.closePDF()
}

/// The phrase drawn black on white into a bitmap: an image with no text anywhere but pixels.
private func phraseImage() throws -> CGImage {
    let width = 1600, height = 240
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.textPosition = CGPoint(x: 40, y: 90)
    CTLineDraw(line(phrase, size: 72), context)
    return try #require(context.makeImage())
}

private func png(_ image: CGImage, at url: URL) throws {
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

/// A one-page PDF holding only the bitmap: a scan, with no text layer.
private func imagePDF(_ image: CGImage, at url: URL) throws {
    var box = CGRect(x: 0, y: 0, width: 800, height: 120)
    let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    context.draw(image, in: box)
    context.endPDFPage()
    context.closePDF()
}

private func words(_ text: String) -> String {
    text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private final class PageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(Int, Int)] = []
    func append(_ done: Int, _ total: Int) { lock.withLock { entries.append((done, total)) } }
    var last: (Int, Int)? { lock.withLock { entries.last } }
}

@Test func aPDFWithATextLayerYieldsItsWordsByTextLayer() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "testo.pdf")
    try textPDF(at: url)
    let log = PageLog()

    let result = try await SystemTextExtractor().extract(url) { log.append($0, $1) }

    #expect(result.method == .textLayer)
    #expect(result.status == .done)
    #expect(words(result.text).contains(phrase.lowercased()))
    #expect(result.pageCount == 1)
    #expect(log.last?.0 == 1 && log.last?.1 == 1)
}

@Test func aBitmapYieldsItsWordsByOCR() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "scansione.png")
    try png(try phraseImage(), at: url)

    let result = try await SystemTextExtractor().extract(url) { _, _ in }

    #expect(result.method == .ocr)
    #expect(words(result.text).contains("guarnizioni"))
    #expect(words(result.text).contains("preventivo"))
}

@Test func anImageOnlyPDFYieldsOCR() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "scansione.pdf")
    try imagePDF(try phraseImage(), at: url)

    let result = try await SystemTextExtractor().extract(url) { _, _ in }

    #expect(result.method == .ocr)
    #expect(words(result.text).contains("guarnizioni"))
}

@Test func aTextFileYieldsPlainText() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "appunti.txt")
    try Data("Riga uno\n\(phrase)\n".utf8).write(to: url)

    let result = try await SystemTextExtractor().extract(url) { _, _ in }

    #expect(result.method == .plainText)
    #expect(result.text.contains(phrase))
}

@Test func anUnknownBinaryYieldsNone() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "archivio.pgbin")
    try Data([0x00, 0x01, 0xFE, 0xFF]).write(to: url)

    let result = try await SystemTextExtractor().extract(url) { _, _ in }

    #expect(result.method == .none)
    #expect(result.status == .done)
    #expect(ExtractedText.displayLabel(result) == "nessun testo")
}
