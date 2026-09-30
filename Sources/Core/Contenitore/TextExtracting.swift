import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D8, plan
// docs/plans/contenitore.md, Task 2 - R-09, R-11.

/// How a document's text was obtained.
enum ExtractionMethod: String, Codable, Sendable {
    /// A PDF's own text layer, read with PDFKit.
    case textLayer
    /// On-device OCR of an image, or of a PDF with no text layer.
    case ocr
    /// A file whose type conforms to plain text, read as it is.
    case plainText
    /// A type nothing here extracts from, or a document with no recognisable text.
    case none
}

/// Where an extraction stands.
enum ExtractionStatus: String, Codable, Sendable {
    case pending
    case done
    case failed
}

/// A document's extracted text, derived state keyed by the file's SHA-256 (ADR-0071 §D8).
/// Renaming or moving the file does not invalidate it; deleting it loses only the time to
/// extract again.
struct ExtractedText: Codable, Equatable, Sendable {
    var method: ExtractionMethod
    var status: ExtractionStatus
    var text: String
    /// Pages processed so far, for the list's progress (R-09). A single-page source counts 1.
    var pagesDone: Int
    var pageCount: Int

    init(method: ExtractionMethod, status: ExtractionStatus, text: String, pagesDone: Int = 0, pageCount: Int = 0) {
        self.method = method
        self.status = status
        self.text = text
        self.pagesDone = pagesDone
        self.pageCount = pageCount
    }

    /// What the list shows for a document's extraction. `failed` and `none` both read «nessun
    /// testo» (R-11): to the person, a scan with nothing recognisable and an OCR that failed
    /// are the same fact, a document searchable only by its name, description and tags.
    static func displayLabel(_ extracted: ExtractedText?) -> String {
        guard let extracted else { return "in attesa" }
        switch extracted.status {
        case .pending: return "in estrazione"
        case .failed: return "nessun testo"
        case .done:
            switch extracted.method {
            case .textLayer, .plainText: return "testo"
            case .ocr: return "testo da OCR"
            case .none: return "nessun testo"
            }
        }
    }
}

/// Turns a file into text (ADR-0071 §D8). The app's implementation is `SystemTextExtractor`
/// (PDFKit, Vision); the tests use a fake.
///
/// `progress` is called with `(pagesDone, pageCount)` as pages are processed.
protocol TextExtracting: Sendable {
    func extract(_ url: URL, progress: @Sendable (Int, Int) -> Void) async throws -> ExtractedText
}
