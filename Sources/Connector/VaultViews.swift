import Foundation

/// Running a view from outside the app (ADR-0009 §D4).
///
/// This is the point of putting the query engine in `Core`: a model asking for the open-client
/// board gets the rows the window draws, from the same parser and the same evaluator. It is
/// also the first thing in this project that lets an assistant ask a question about the vault
/// rather than about a note.
///
/// **Listing reads every note.** A view lives in a fenced block and the index records structure,
/// not fences, so finding them is a full-vault text scan - the same work `search` does, and the
/// same trade §D7 states as a rule rather than a number. It is a listing, asked for on purpose,
/// not something that happens when a note opens.
extension VaultAPI {
    @MainActor
    static func views(_ session: VaultSession) -> [ViewSummary] {
        session.index.allNotes
            .sorted { $0.relativePath < $1.relativePath }
            .flatMap { record -> [ViewSummary] in
                guard let text = try? session.read(record.relativePath).text else { return [] }
                let blocks = ViewBlock.blocks(in: NoteDocument.parse(text).body)
                return blocks.enumerated().map { ordinal, block in
                    ViewSummary(record: record, ordinal: ordinal, block: block)
                }
            }
    }

    /// Evaluates one view and hands back its rows.
    ///
    /// `ordinal` picks the block when a note carries more than one; without it the note must
    /// carry exactly one, because guessing which of three boards was meant is the kind of
    /// answer that looks right and is not.
    @MainActor
    static func runView(_ session: VaultSession, at path: String, ordinal: Int?) throws -> ViewRun {
        guard let (record, text) = try? session.read(path) else {
            throw ConnectorError("nessuna nota a «\(path)»")
        }
        let blocks = ViewBlock.blocks(in: NoteDocument.parse(text).body)
        guard !blocks.isEmpty else {
            throw ConnectorError("«\(path)» non contiene blocchi \(ViewBlock.language)")
        }
        let index = try resolveOrdinal(ordinal, of: blocks.count, in: path)

        let block: ViewBlock
        do {
            block = try blocks[index].get()
        } catch let failure as ViewBlockError {
            throw ConnectorError("«\(path)», vista \(index): \(failure.description)")
        }

        let result = ViewEvaluator.evaluate(block, over: session.index) { candidate in
            try? session.read(candidate.relativePath).text
        }
        return ViewRun(
            view: ViewSummary(record: record, ordinal: index, block: .success(block)),
            block: block,
            result: result
        )
    }

    private static func resolveOrdinal(_ ordinal: Int?, of count: Int, in path: String) throws -> Int {
        guard let ordinal else {
            guard count == 1 else {
                throw ConnectorError(
                    "«\(path)» contiene \(count) viste: indica quale con --ordinal (0-\(count - 1))",
                    usage: true
                )
            }
            return 0
        }
        guard ordinal >= 0, ordinal < count else {
            throw ConnectorError("«\(path)» ha \(count) viste, non una alla posizione \(ordinal)", usage: true)
        }
        return ordinal
    }
}
