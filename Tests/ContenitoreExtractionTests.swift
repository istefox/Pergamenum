import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D8/§D9, plan docs/plans/contenitore.md, Task 5 - R-09, R-10, R-11,
// R-12. The queue runs on a fake `TextExtracting`; the real frameworks are exercised in
// `ContenitoreSystemExtractorTests.swift`.

private let hashA = String(repeating: "a", count: 64)
private let hashB = String(repeating: "b", count: 64)

/// Answers from a table by file name, reporting every page, and throws for a name it lists as
/// failing.
private struct FakeExtractor: TextExtracting {
    var results: [String: ExtractedText] = [:]
    var failing: Set<String> = []

    struct Failure: Error {}

    func extract(_ url: URL, progress: @Sendable (Int, Int) -> Void) async throws -> ExtractedText {
        let name = url.lastPathComponent
        if failing.contains(name) { throw Failure() }
        let result = results[name] ?? ExtractedText(method: .none, status: .done, text: "")
        for page in 0...result.pageCount { progress(page, result.pageCount) }
        return result
    }
}

/// Reports a three-page document one page at a time: after each page it tells the test which
/// page it reported, then waits for the test to let it read the next, so the test can look at
/// the queue while the extraction is mid-way. No sleeps: both hand-offs are streams.
private struct SteppedExtractor: TextExtracting {
    static let pageCount = 3
    let reported: AsyncStream<Int>.Continuation
    let nextPage: AsyncStream<Void>

    func extract(_ url: URL, progress: @Sendable (Int, Int) -> Void) async throws -> ExtractedText {
        var permits = nextPage.makeAsyncIterator()
        for page in 1...Self.pageCount {
            progress(page, Self.pageCount)
            reported.yield(page)
            if page < Self.pageCount { _ = await permits.next() }
        }
        return ExtractedText(
            method: .ocr, status: .done, text: "Pagine", pagesDone: Self.pageCount, pageCount: Self.pageCount
        )
    }
}

private func temporaryStore() -> ExtractedTextStore {
    ExtractedTextStore(
        directory: FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-extracted-\(UUID().uuidString)", directoryHint: .isDirectory)
    )
}

// MARK: - The store

@Test func theStoreRoundTripsOneRecordPerHashAndClearsThemAll() throws {
    let store = temporaryStore()
    defer { try? store.removeAll() }
    let record = ExtractedText(method: .ocr, status: .done, text: "Preventivo", pagesDone: 2, pageCount: 2)

    try store.write(record, sha256: hashA.uppercased())

    #expect(store.read(sha256: hashA) == record)
    #expect(store.read(sha256: hashB) == nil)
    #expect(FileManager.default.fileExists(atPath: store.directory.appending(path: "\(hashA).json").path(percentEncoded: false)))

    try store.removeAll()
    #expect(store.read(sha256: hashA) == nil)
}

@Test func theStoreRefusesAKeyThatIsNotAHash() {
    let store = temporaryStore()
    defer { try? store.removeAll() }

    #expect(throws: FileOperationError.self) {
        try store.write(ExtractedText(method: .none, status: .done, text: ""), sha256: "../fuori")
    }
    #expect(store.read(sha256: "../fuori") == nil)
}

// MARK: - The queue (R-09, R-11)

@MainActor
@Test func theQueueRecordsDoneWithTheMethod() async {
    let store = temporaryStore()
    defer { try? store.removeAll() }
    let extracted = ExtractedText(method: .textLayer, status: .done, text: "Offerta", pagesDone: 3, pageCount: 3)
    let queue = ContenitoreExtractionQueue(store: store, extractor: FakeExtractor(results: ["a.pdf": extracted]))

    queue.enqueue(sha256: hashA, url: URL(filePath: "/tmp/a.pdf"))
    await queue.drain()

    #expect(store.read(sha256: hashA) == extracted)
    #expect(queue.progress.isEmpty)
}

@MainActor
@Test func aFailingExtractionRecordsFailedAndTheNextStillRuns() async {
    let store = temporaryStore()
    defer { try? store.removeAll() }
    let extracted = ExtractedText(method: .plainText, status: .done, text: "Nota")
    let queue = ContenitoreExtractionQueue(
        store: store, extractor: FakeExtractor(results: ["b.txt": extracted], failing: ["a.pdf"])
    )
    var failed: [String] = []
    queue.onFailed = { failed.append($0.lastPathComponent) }

    queue.enqueue(sha256: hashA, url: URL(filePath: "/tmp/a.pdf"))
    queue.enqueue(sha256: hashB, url: URL(filePath: "/tmp/b.txt"))
    await queue.drain()

    #expect(store.read(sha256: hashA)?.status == .failed)
    #expect(store.read(sha256: hashB) == extracted)
    #expect(failed == ["a.pdf"])
}

@MainActor
@Test func theSameHashIsQueuedOnce() async {
    let store = temporaryStore()
    defer { try? store.removeAll() }
    let queue = ContenitoreExtractionQueue(store: store, extractor: FakeExtractor(failing: ["a.pdf"]))
    var failures = 0
    queue.onFailed = { _ in failures += 1 }

    queue.enqueue(sha256: hashA, url: URL(filePath: "/tmp/a.pdf"))
    queue.enqueue(sha256: hashA.uppercased(), url: URL(filePath: "/tmp/a.pdf"))
    await queue.drain()

    #expect(failures == 1)
}

/// R-09: progress is published per page while the extraction runs, not only at its end. The
/// queue publishes through a main-actor hop, so the test yields (a bounded number of times, no
/// clock) until that hop has run before reading it.
@MainActor
@Test func progressIsPublishedPerPageWhileTheExtractionRuns() async {
    let store = temporaryStore()
    defer { try? store.removeAll() }
    let (reports, reported) = AsyncStream<Int>.makeStream()
    let (nextPage, permit) = AsyncStream<Void>.makeStream()
    let queue = ContenitoreExtractionQueue(
        store: store, extractor: SteppedExtractor(reported: reported, nextPage: nextPage)
    )

    func published(page: Int) async -> [Int]? {
        for _ in 0..<1_000 where queue.progress[hashA]?.done != page { await Task.yield() }
        return queue.progress[hashA].map { [$0.done, $0.total] }
    }

    queue.enqueue(sha256: hashA, url: URL(filePath: "/tmp/scansione.pdf"))
    let drained = Task { await queue.drain() }
    var pages = reports.makeAsyncIterator()

    let first = await pages.next()
    #expect(first == 1)
    #expect(await published(page: 1) == [1, 3])
    #expect(store.read(sha256: hashA)?.status == .pending)

    permit.yield()
    let second = await pages.next()
    #expect(second == 2)
    #expect(await published(page: 2) == [2, 3])

    permit.yield()
    await drained.value

    #expect(queue.progress[hashA] == nil)
    #expect(store.read(sha256: hashA)?.status == .done)
}

@Test func failedAndNoneBothReadNessunTesto() {
    #expect(ExtractedText.displayLabel(ExtractedText(method: .none, status: .failed, text: "")) == "nessun testo")
    #expect(ExtractedText.displayLabel(ExtractedText(method: .none, status: .done, text: "")) == "nessun testo")
    #expect(ExtractedText.displayLabel(ExtractedText(method: .ocr, status: .done, text: "x")) == "testo da OCR")
    #expect(ExtractedText.displayLabel(nil) == "in attesa")
}

// MARK: - Search (R-10, R-12)

@MainActor
@Test func searchFindsASchedaByItsExtractedTextAndExcerptsThatLine() async throws {
    let vault = try TemporaryVault()
    let day = try #require(CalendarDate(year: 2026, month: 9, day: 29))
    try vault.write(
        ContenitoreScheda.render(date: day, fileName: "20260929 scansione.pdf", originalName: "scansione.pdf", sha256: hashA),
        to: "Contenitore/2026/20260929 scansione.md"
    )
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    try session.extractedTexts.write(
        ExtractedText(method: .ocr, status: .done, text: "Intestazione\nPreventivo fornitura guarnizioni\nFine"),
        sha256: hashA
    )

    let results = session.search(SearchQuery("guarnizioni"))

    #expect(results.map(\.path) == ["Contenitore/2026/20260929 scansione.md"])
    #expect(results.first?.excerpt == "Preventivo fornitura guarnizioni")
}

@MainActor
@Test func clearingTheStoreRemovesNoVaultFileAndTheHitGoesAway() async throws {
    let vault = try TemporaryVault()
    let day = try #require(CalendarDate(year: 2026, month: 9, day: 29))
    let scheda = "Contenitore/2026/20260929 scansione.md"
    try vault.write(
        ContenitoreScheda.render(date: day, fileName: "20260929 scansione.pdf", originalName: "scansione.pdf", sha256: hashA),
        to: scheda
    )
    try vault.write("pdf", to: "Contenitore/2026/20260929 scansione.pdf")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    try session.extractedTexts.write(ExtractedText(method: .textLayer, status: .done, text: "guarnizioni"), sha256: hashA)

    try session.extractedTexts.removeAll()

    #expect(session.search(SearchQuery("guarnizioni")).isEmpty)
    #expect(session.exists(scheda))
    #expect(session.exists("Contenitore/2026/20260929 scansione.pdf"))
    #expect(session.extractedTexts.directory.path(percentEncoded: false).hasPrefix(vault.stateBase.path(percentEncoded: false)))
}

// MARK: - «Svuota cache» (§D8)

@MainActor
@Test func clearCacheAlsoRemovesTheExtractedText() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ndate: 2026-09-29\ntags:\n  - type-note\n---\n\nCorpo.\n", to: "Nota.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    // `VaultController.open` resolves the process-wide test base, not `TemporaryVault.stateBase`
    // (`VaultControllerCacheCleanupTests`' own note).
    let state = try #require(VaultState.resolve(root: vault.root, base: try VaultState.processDefaultBase()))
    let store = ExtractedTextStore(directory: state.extractedText)
    try store.write(ExtractedText(method: .ocr, status: .done, text: "x"), sha256: hashA)

    await controller.clearCache()

    #expect(store.read(sha256: hashA) == nil)
    #expect(!FileManager.default.fileExists(atPath: state.extractedText.path(percentEncoded: false)))
    #expect(FileManager.default.fileExists(atPath: vault.root.appending(path: "Nota.md").path(percentEncoded: false)))
}
