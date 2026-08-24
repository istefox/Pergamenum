import AppKit
import Testing
@testable import Pergamenum

// ADR-0020 D probe 1 (docs/adr/0020-image-card-crop.md, Task 1): whether
// `ThumbnailStore.renderWithQuickLook` preserves the source image's aspect ratio through
// `QLThumbnailGenerator`, whose request is a **square** (`CGSize(width: width, height:
// width)`, `ThumbnailStore.swift:98`). If a wide or tall photograph came back padded into
// that square, a crop rectangle expressed as a fraction of the *returned* image would not
// be a fraction of the *file*, and every crop would be offset by the pad. This is a gate
// (ADR-0020 Task 1): failing sends D1 and D7 back for revision before anything else in the
// plan is written.
//
// Driven through the real actor, never stubbed - `EmbedResolutionTests` and
// `EmbedCaretTests` already establish that pattern for this store.
@MainActor
@Suite struct CanvasCropProbeTests {
    private static func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-crop-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A real PNG at an exact pixel size, written to disk - `QLThumbnailGenerator` reads a
    /// file, not an in-memory image, so the probe needs one on disk the same way
    /// `EmbedResolutionTests.writeImage` does for the embed renderer.
    private static func writeImage(named name: String, size: CGSize, in root: URL) throws {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: root.appending(path: name, directoryHint: .notDirectory))
    }

    private func assertAspectRatioPreserved(
        sourceSize: CGSize, sourceLabel: String, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let root = try Self.makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "\(sourceLabel).png"
        try Self.writeImage(named: name, size: sourceSize, in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )

        let rendered = try #require(
            await thumbnails.thumbnail(for: name, width: 640).value, sourceLocation: sourceLocation
        )
        let sourceRatio = sourceSize.width / sourceSize.height
        let renderedRatio = rendered.size.width / rendered.size.height
        let deviation = abs(renderedRatio - sourceRatio) / sourceRatio
        #expect(deviation < 0.01, "expected \(sourceLabel) aspect ratio within 1%, got \(renderedRatio) vs \(sourceRatio)", sourceLocation: sourceLocation)
    }

    @Test func aWideImageKeepsItsAspectRatioThroughQuickLook() async throws {
        try await assertAspectRatioPreserved(sourceSize: CGSize(width: 1200, height: 400), sourceLabel: "wide")
    }

    @Test func aTallImageKeepsItsAspectRatioThroughQuickLook() async throws {
        try await assertAspectRatioPreserved(sourceSize: CGSize(width: 400, height: 1200), sourceLabel: "tall")
    }

    @Test func aSquareImageKeepsItsAspectRatioThroughQuickLook() async throws {
        try await assertAspectRatioPreserved(sourceSize: CGSize(width: 600, height: 600), sourceLabel: "square")
    }
}
