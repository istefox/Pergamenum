import Foundation
import Observation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D8, plan
// docs/plans/contenitore.md, Task 5 - R-09, R-11.
//
// App-only (§D14): the connectors read the store through search and never extract.

/// Extracts the text of imported documents one at a time, in the background, and records each
/// result in the `ExtractedTextStore` under the document's hash.
///
/// Sequential on purpose: OCR of a long scan is the heaviest thing the app does, and two at once
/// would only make both slower. A job is recorded `pending` when it starts, so a document whose
/// extraction was interrupted (the app quit mid-way) is enqueued again at the next vault open by
/// the controller, which enqueues every hash with no `done` or `failed` record (Task 6). A failure
/// records `failed` and the queue moves on (R-11).
@MainActor
@Observable
final class ContenitoreExtractionQueue {
    /// Pages done and total per hash, for the document being extracted now (R-09). Published on
    /// the main actor; the entry leaves when its extraction ends.
    private(set) var progress: [String: (done: Int, total: Int)] = [:]

    /// Called with the document's URL when its extraction throws, so the controller can raise
    /// `ContenitoreNotice.extractionFailed` naming it.
    @ObservationIgnored var onFailed: ((URL) -> Void)?
    /// Called with the hash and the record each time the store took one: `pending` as a job
    /// starts, `done` or `failed` as it ends. The controller's extraction cache follows the
    /// store through it instead of reading the file back. A write that failed calls nothing.
    @ObservationIgnored var onRecorded: ((String, ExtractedText) -> Void)?

    @ObservationIgnored private let store: ExtractedTextStore
    @ObservationIgnored private let extractor: any TextExtracting
    @ObservationIgnored private var jobs: [(sha256: String, url: URL)] = []
    /// The hash being extracted now, so a progress report arriving after its job ended is dropped.
    @ObservationIgnored private var current: String?
    @ObservationIgnored private var isDraining = false

    init(store: ExtractedTextStore, extractor: any TextExtracting) {
        self.store = store
        self.extractor = extractor
    }

    /// Adds a document to the queue, unless the same hash is already waiting or being extracted.
    func enqueue(sha256: String, url: URL) {
        let key = sha256.lowercased()
        guard current != key, !jobs.contains(where: { $0.sha256 == key }) else { return }
        jobs.append((key, url))
    }

    /// Extracts every queued document in order, returning when the queue is empty. A second call
    /// while one is running returns at once: the running drain picks up what was enqueued since.
    func drain() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        while !jobs.isEmpty {
            let job = jobs.removeFirst()
            current = job.sha256
            progress[job.sha256] = (done: 0, total: 0)
            record(ExtractedText(method: .none, status: .pending, text: ""), sha256: job.sha256)

            let sha256 = job.sha256
            let result: ExtractedText
            do {
                result = try await extractor.extract(job.url) { done, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.current == sha256 else { return }
                        self.progress[sha256] = (done: done, total: total)
                    }
                }
            } catch {
                result = ExtractedText(method: .none, status: .failed, text: "")
                onFailed?(job.url)
            }
            record(result, sha256: job.sha256)
            current = nil
            progress.removeValue(forKey: job.sha256)
        }
    }

    /// Writes `text` for `sha256` and tells `onRecorded` when the store took it.
    private func record(_ text: ExtractedText, sha256: String) {
        guard (try? store.write(text, sha256: sha256)) != nil else { return }
        onRecorded?(sha256, text)
    }
}
