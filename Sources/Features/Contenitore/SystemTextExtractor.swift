import CoreGraphics
import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D8, plan
// docs/plans/contenitore.md, Task 5 - R-09.
//
// App-only (§D14). Everything runs on-device: PDFKit and Vision make no network call
// (principle 2).

/// The extractor the app uses, behind `TextExtracting` so the queue's tests use a fake.
///
/// - A PDF's text layer is read with PDFKit. A PDF with no non-whitespace character anywhere in
///   its text layer is rendered page by page and OCR'd; the decision is per document.
/// - An image is OCR'd with Vision's `RecognizeTextRequest`: `it-IT` then `en-US`, the
///   `.accurate` level, language correction on (Context 8). Property types checked against the
///   macOS 27 SDK's `Vision.swiftinterface`: `recognitionLanguages` is `[Locale.Language]`,
///   `recognitionLevel` is `RecognizeTextRequest.RecognitionLevel`, `usesLanguageCorrection` is
///   `Bool`, and `perform(on:orientation:)` returns `[RecognizedTextObservation]`.
/// - A file whose type conforms to `UTType.plainText` is read as text.
/// - Anything else is `none`.
struct SystemTextExtractor: TextExtracting {
    /// Rendering scale for OCR: 2 points per PDF point, about 144 dpi, enough for body text.
    private static let renderScale: CGFloat = 2

    func extract(_ url: URL, progress: @Sendable (Int, Int) -> Void) async throws -> ExtractedText {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)

        guard let type else { return ExtractedText(method: .none, status: .done, text: "") }
        if type.conforms(to: .pdf) {
            return try await extractPDF(url, progress: progress)
        }
        if type.conforms(to: .image) {
            progress(0, 1)
            let text = try await Self.recognize(url: url)
            progress(1, 1)
            return ExtractedText(method: .ocr, status: .done, text: text, pagesDone: 1, pageCount: 1)
        }
        if type.conforms(to: .plainText) {
            return ExtractedText(method: .plainText, status: .done, text: try Self.readText(url))
        }
        return ExtractedText(method: .none, status: .done, text: "")
    }

    // MARK: - PDF

    private func extractPDF(_ url: URL, progress: @Sendable (Int, Int) -> Void) async throws -> ExtractedText {
        guard let document = PDFDocument(url: url) else {
            throw FileOperationError.failed("PDF non leggibile: \(url.lastPathComponent)")
        }
        let count = document.pageCount

        var pages: [String] = []
        for index in 0..<count {
            pages.append(document.page(at: index)?.string ?? "")
            progress(index + 1, count)
        }
        if pages.contains(where: { $0.contains(where: { !$0.isWhitespace }) }) {
            return ExtractedText(
                method: .textLayer, status: .done, text: pages.joined(separator: "\n\n"),
                pagesDone: count, pageCount: count
            )
        }

        // No text layer anywhere: the whole document is a scan.
        var recognised: [String] = []
        progress(0, count)
        for index in 0..<count {
            try Task.checkCancellation()
            if let page = document.page(at: index), let image = Self.render(page) {
                recognised.append(try await Self.recognize(image: image))
            } else {
                recognised.append("")
            }
            progress(index + 1, count)
        }
        return ExtractedText(
            method: .ocr, status: .done, text: recognised.joined(separator: "\n\n"),
            pagesDone: count, pageCount: count
        )
    }

    /// One page drawn on white into a bitmap, or nil when the page has no area.
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int((bounds.width * renderScale).rounded())
        let height = Int((bounds.height * renderScale).rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: renderScale, y: renderScale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    // MARK: - OCR

    private static func request() -> RecognizeTextRequest {
        var request = RecognizeTextRequest()
        request.recognitionLanguages = [Locale.Language(identifier: "it-IT"), Locale.Language(identifier: "en-US")]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        return request
    }

    private static func recognize(image: CGImage) async throws -> String {
        lines(try await request().perform(on: image))
    }

    private static func recognize(url: URL) async throws -> String {
        lines(try await request().perform(on: url))
    }

    private static func lines(_ observations: [RecognizedTextObservation]) -> String {
        observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    // MARK: - Plain text

    /// UTF-8 first, then whatever encoding Foundation detects.
    private static func readText(_ url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding = String.Encoding.utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }
}
