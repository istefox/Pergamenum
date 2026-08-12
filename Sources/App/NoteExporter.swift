import AppKit
import Foundation

/// Writes an exported note to a file the user picks (SPEC §10, File › Esporta nota).
@MainActor
enum NoteExporter {
    enum Format: String, CaseIterable, Identifiable {
        case markdown, html, pdf

        var id: String { rawValue }
        var title: String {
            switch self {
            case .markdown: "Markdown (.md)"
            case .html: "HTML (.html)"
            case .pdf: "PDF (.pdf)"
            }
        }
        var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .html: "html"
            case .pdf: "pdf"
            }
        }
    }

    /// Asks where to save, then writes. Returns the problem to report, or nil.
    static func export(
        title: String,
        text: String,
        as format: Format
    ) -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(title).\(format.fileExtension)"
        panel.title = "Esporta nota"
        panel.message = "Frontmatter e «Note correlate» non vengono esportati."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            switch format {
            case .markdown:
                try Data(NoteExport.markdown(from: text).utf8).write(to: url, options: .atomic)
            case .html:
                try Data(NoteExport.html(from: text, title: title).utf8)
                    .write(to: url, options: .atomic)
            case .pdf:
                try writePDF(html: NoteExport.html(from: text, title: title), to: url)
            }
            return nil
        } catch {
            return "esportazione: \(error.localizedDescription)"
        }
    }

    /// Renders the HTML through AppKit's own text system and prints it to a file.
    ///
    /// The print machinery rather than a hand-rolled PDF context: it already paginates
    /// a long note, and a PDF whose second page is missing is the kind of failure an
    /// export must not have.
    static func writePDF(html: String, to url: URL) throws {
        guard let data = html.data(using: .utf8),
              let attributed = NSAttributedString(
                  html: data,
                  options: [.documentType: NSAttributedString.DocumentType.html],
                  documentAttributes: nil
              )
        else { throw ExportError.unrenderable }

        let pageSize = NSSize(width: 595, height: 842)   // A4 in points
        let margin: CGFloat = 56
        let textView = NSTextView(frame: NSRect(
            origin: .zero,
            size: NSSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        ))
        textView.textStorage?.setAttributedString(attributed)
        textView.isVerticallyResizable = true
        textView.sizeToFit()

        let printInfo = NSPrintInfo()
        printInfo.paperSize = pageSize
        printInfo.topMargin = margin
        printInfo.bottomMargin = margin
        printInfo.leftMargin = margin
        printInfo.rightMargin = margin
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw ExportError.printFailed }
    }

    enum ExportError: Error, CustomStringConvertible {
        case unrenderable
        case printFailed

        var description: String {
            switch self {
            case .unrenderable: "la nota non è convertibile in testo formattato"
            case .printFailed: "la scrittura del PDF non è riuscita"
            }
        }
    }
}
