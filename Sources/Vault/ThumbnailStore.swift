import AppKit
import CryptoKit
import Foundation
import PDFKit
import QuickLookThumbnailing

/// Renders and caches card previews for files on a board.
///
/// PDFs go through PDFKit, which SPEC §6.5 names as the primary requirement;
/// everything else falls back to Quick Look's thumbnail generator, so an image, a
/// spreadsheet or a video still shows something recognisable rather than a generic
/// icon.
///
/// The cache lives beside the vault, under this vault's Application Support state
/// directory (ADR-0017), and is disposable like the index: deleting it costs a
/// re-render, never data.
actor ThumbnailStore {
    /// The only way this store turns a `.canvas` node's `file` property - ordinary JSON
    /// anybody can edit - into a URL it will read (ADR-0041 §D2).
    private let boundary: VaultBoundary
    private let directory: URL
    /// In-flight and completed renders, so a board with the same PDF on ten cards
    /// renders it once per size rather than ten times.
    private var tasks: [String: Task<NSImage?, Never>] = [:]

    /// `root` resolves the *source* file being thumbnailed; `directory` is where the
    /// rendered cache lives and is resolved by the caller from `VaultState.thumbnails`
    /// - only the cache moved out of the vault, not the files it renders.
    init(root: URL, directory: URL) {
        self.boundary = VaultBoundary(root: root)
        self.directory = directory
    }

    /// A thumbnail for a vault file at roughly the given point size.
    ///
    /// Sizes are quantised so that dragging a resize handle does not spawn a render
    /// per frame: SPEC §6.5 asks for a regenerated thumbnail at the end of a resize,
    /// not during it.
    func thumbnail(for relativePath: String, width: CGFloat) -> Task<NSImage?, Never> {
        let bucket = Self.bucket(for: width)
        let key = Self.cacheKey(relativePath: relativePath, bucket: bucket)

        if let existing = tasks[key] { return existing }

        // `nil` rather than a thrown error, per ADR-0041 §D2's decision for this site: a
        // thumbnail that cannot be drawn is not worth unwinding a view for, and a card
        // drawing its generic icon is the same outcome as a missing file. The refusal is
        // taken *before* the render task is built, so a path escaping the vault is never
        // read, never rendered and never memoised under a cache key.
        guard let fileURL = try? boundary.url(for: relativePath) else {
            return Task<NSImage?, Never> { nil }
        }
        let cacheURL = directory.appending(path: "\(key).png", directoryHint: .notDirectory)
        let task = Task<NSImage?, Never>.detached(priority: .utility) {
            await Self.render(fileURL: fileURL, cacheURL: cacheURL, width: CGFloat(bucket))
        }
        tasks[key] = task
        return task
    }

    /// Discards the memoised tasks, e.g. after "svuota cache". The files on disk are
    /// removed separately so a caller can do one without the other.
    func forgetAll() {
        tasks.removeAll()
    }

    func clearCacheOnDisk() throws {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: Rendering

    private static func render(fileURL: URL, cacheURL: URL, width: CGFloat) async -> NSImage? {
        if let cached = NSImage(contentsOf: cacheURL) { return cached }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }

        let image: NSImage? = if fileURL.pathExtension.lowercased() == "pdf" {
            renderPDF(fileURL, width: width)
        } else {
            await renderWithQuickLook(fileURL, width: width)
        }

        if let image, let data = pngData(from: image) {
            try? FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: cacheURL, options: .atomic)
        }
        return image
    }

    /// First page via `PDFPage.thumbnail(of:for:)`, the API SPEC §3 names.
    private static func renderPDF(_ fileURL: URL, width: CGFloat) -> NSImage? {
        guard let document = PDFDocument(url: fileURL), let page = document.page(at: 0) else { return nil }
        let pageSize = page.bounds(for: .mediaBox).size
        guard pageSize.width > 0 else { return nil }

        let scale = width / pageSize.width
        let target = CGSize(width: width, height: max(1, pageSize.height * scale))
        return page.thumbnail(of: target, for: .mediaBox)
    }

    private static func renderWithQuickLook(_ fileURL: URL, width: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: width, height: width),
            scale: 2,
            representationTypes: .thumbnail
        )
        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        return representation.map { NSImage(cgImage: $0.cgImage, size: $0.contentRect.size) }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: Cache keys

    /// Rounds a width up to the next power-of-two-ish step.
    ///
    /// Without this, every pixel of a resize drag would be its own cache entry and its
    /// own render; with it, a card has at most a handful of sizes over its life.
    static func bucket(for width: CGFloat) -> Int {
        let steps = [160, 240, 320, 480, 640, 960, 1280]
        return steps.first { CGFloat($0) >= width } ?? steps[steps.count - 1]
    }

    /// Path plus size, hashed so a name with slashes or accents is a valid file name.
    static func cacheKey(relativePath: String, bucket: Int) -> String {
        // The same lowercase hex `NoteStore.hash` writes, from the same helper - this key
        // names files already on disk, so its spelling cannot drift.
        let digest = NoteStore.hexString(SHA256.hash(data: Data(relativePath.utf8))).prefix(24)
        return "\(digest)@\(bucket)"
    }
}
