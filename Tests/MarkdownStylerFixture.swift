import Foundation
@testable import Pergamenum

/// Shared helpers for the MarkdownStyler suites (moved out of `MarkdownStylerTests.swift`
/// when it was split; PG-144 Task 1).
enum MarkdownStylerFixture {
    static func spans(_ text: String) -> [MarkdownStyler.Span] {
        MarkdownStyler.spans(in: text).map(\.span)
    }

    static func styled(_ text: String, _ span: MarkdownStyler.Span) -> String? {
        guard let match = MarkdownStyler.spans(in: text).first(where: { $0.span == span }) else { return nil }
        return String(text[match.range])
    }
}
